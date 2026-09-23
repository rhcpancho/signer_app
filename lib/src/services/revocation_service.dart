import 'dart:convert';
import 'dart:typed_data';

import 'package:asn1lib/asn1lib.dart';
import 'package:crypto/crypto.dart' as cryptoutils;
import 'package:http/http.dart' as http;

import '../models/signature_chain.dart';

/// Revocación soft-fail: OCSP primero, CRL como fallback.
///
/// Si no hay red, URLs o la respuesta es ilegible → [CertValidity.unknown];
/// nunca devuelve `no` salvo un estado `revoked` explícito.
class RevocationService {
  RevocationService({http.Client? client, Duration? timeout})
      : _client = client ?? http.Client(),
        timeout = timeout ?? const Duration(seconds: 6);

  final http.Client _client;
  final Duration timeout;

  /// Comprueba revocación de [chain] (leaf primero). Raíces self-signed se
  /// omiten. Agrega: algún `revoked` → no; todos los comprobados good → yes;
  /// si no, unknown.
  Future<RevocationCheck> checkChain(List<CertChainNode> chain) async {
    if (chain.length < 2) {
      // Solo raíz (o vacío): nada que comprobar contra un emisor externo.
      return const RevocationCheck(
        status: CertValidity.unknown,
        note: 'Cadena insuficiente para OCSP/CRL',
      );
    }

    int good = 0;
    int revoked = 0;
    int skipped = 0;
    RevocationSource? source;
    final List<String> notes = <String>[];

    for (int i = 0; i < chain.length; i++) {
      final CertChainNode node = chain[i];
      // Raíz self-signed / último de cadena completa → trust anchor.
      if (node.isSelfSigned && (i == chain.length - 1 || chain.length == 1)) {
        skipped++;
        continue;
      }

      final CertChainNode? issuer = (i + 1 < chain.length) ? chain[i + 1] : null;
      final _NodeRevocation r = await _checkNode(node, issuer);
      switch (r.status.value) {
        case true:
          good++;
          source ??= r.source;
          break;
        case false:
          revoked++;
          source ??= r.source;
          break;
        default:
          if (r.skipped) {
            skipped++;
          } else {
            notes.add(r.note ?? 'sin respuesta');
          }
          break;
      }
    }

    final CertValidity status;
    if (revoked > 0) {
      status = CertValidity.no;
    } else if (good > 0 && revoked == 0 && (good + skipped) >= (chain.length - 1)) {
      // Al menos un nodo non-root good y ningún revoked → yes soft.
      // Si hubo fallos de red en algún non-root, preferimos unknown salvo
      // que todos los non-root hayan sido good.
      status = notes.isEmpty ? CertValidity.yes : CertValidity.unknown;
    } else if (good > 0 && notes.isEmpty) {
      status = CertValidity.yes;
    } else {
      status = CertValidity.unknown;
    }

    String? note;
    if (revoked > 0) {
      note = '$revoked certificado(s) revocado(s)';
    } else if (status.value == true) {
      note = 'OCSP/CRL sin incidencias';
    } else if (notes.isNotEmpty) {
      note = notes.join('; ');
    } else if (good == 0 && skipped >= chain.length - 1) {
      note = 'Sin URLs AIA/CRL';
    }

    return RevocationCheck(
      status: status,
      source: source,
      note: note,
      goodCount: good,
      revokedCount: revoked,
      skippedCount: skipped,
    );
  }

  Future<_NodeRevocation> _checkNode(
    CertChainNode node,
    CertChainNode? issuer,
  ) async {
    if (node.ocspUrls.isEmpty && node.crlUrls.isEmpty) {
      return const _NodeRevocation(
        status: CertValidity.unknown,
        skipped: true,
        note: 'sin URLs AIA/CRL',
      );
    }

    // OCSP primero
    for (final String url in node.ocspUrls) {
      try {
        final CertValidity? v = await _checkOcsp(node, issuer, url);
        if (v != null) {
          return _NodeRevocation(
            status: v,
            source: RevocationSource.ocsp,
            note: v.value == false ? 'Revocado (OCSP)' : null,
          );
        }
      } catch (_) {
        // soft-fail → probar siguiente / CRL
      }
    }

    // CRL fallback
    for (final String url in node.crlUrls) {
      try {
        final CertValidity? v = await _checkCrl(node, url);
        if (v != null) {
          return _NodeRevocation(
            status: v,
            source: RevocationSource.crl,
            note: v.value == false ? 'Revocado (CRL)' : null,
          );
        }
      } catch (_) {
        // soft-fail
      }
    }

    return const _NodeRevocation(
      status: CertValidity.unknown,
      note: 'OCSP/CRL no disponible',
    );
  }

  /// Devuelve good/revoked, o null si la respuesta no es utilizable.
  Future<CertValidity?> _checkOcsp(
    CertChainNode node,
    CertChainNode? issuer,
    String url,
  ) async {
    final Uint8List? req = buildOcspRequest(node: node, issuer: issuer);
    if (req == null) return null;

    final http.Response resp = await _client
        .post(
          Uri.parse(url),
          headers: <String, String>{
            'Content-Type': 'application/ocsp-request',
            'Accept': 'application/ocsp-response',
          },
          body: req,
        )
        .timeout(timeout);

    if (resp.statusCode != 200 || resp.bodyBytes.isEmpty) return null;
    return parseOcspResponse(resp.bodyBytes, serialHex: node.serialHex);
  }

  Future<CertValidity?> _checkCrl(CertChainNode node, String url) async {
    final http.Response resp =
        await _client.get(Uri.parse(url)).timeout(timeout);
    if (resp.statusCode != 200 || resp.bodyBytes.isEmpty) return null;

    Uint8List der = resp.bodyBytes;
    if (looksLikePem(der)) {
      der = derFromPem(der);
    }
    return parseCrl(der, serialHex: node.serialHex);
  }

  // ---------------------------------------------------------------------------
  // OCSP request (RFC 6960, CertID SHA-1)
  // ---------------------------------------------------------------------------

  /// Construye OCSPRequest o null si faltan issuerName/spki del emisor.
  static Uint8List? buildOcspRequest({
    required CertChainNode node,
    required CertChainNode? issuer,
  }) {
    final List<int>? issuerName = node.issuerNameDer;
    final List<int>? issuerSpki = issuer?.spkiDer;
    if (issuerName == null || issuerSpki == null) return null;

    final BigInt? serial = BigInt.tryParse(node.serialHex, radix: 16);
    if (serial == null) return null;

    // issuerNameHash = SHA-1(DER del Name del issuer)
    final List<int> nameHash = cryptoutils.sha1.convert(issuerName).bytes;

    // issuerKeyHash = SHA-1(subjectPublicKey BIT STRING contents)
    final List<int>? keyBits = _spkiPublicKeyBits(issuerSpki);
    if (keyBits == null) return null;
    final List<int> keyHash = cryptoutils.sha1.convert(keyBits).bytes;

    return _encodeOcspRequest(
      nameHash: nameHash,
      keyHash: keyHash,
      serial: serial,
    );
  }

  static Uint8List _encodeOcspRequest({
    required List<int> nameHash,
    required List<int> keyHash,
    required BigInt serial,
  }) {
    // AlgorithmIdentifier ::= SEQUENCE { OID sha1, NULL }
    final ASN1Sequence algId = ASN1Sequence()
      ..add(ASN1ObjectIdentifier.fromComponentString(_kOidSha1))
      ..add(ASN1Null());

    // CertID ::= SEQUENCE { hashAlg, issuerNameHash, issuerKeyHash, serial }
    final ASN1Sequence certIdSeq = ASN1Sequence()
      ..add(algId)
      ..add(ASN1OctetString(Uint8List.fromList(nameHash)))
      ..add(ASN1OctetString(Uint8List.fromList(keyHash)))
      ..add(ASN1Integer(serial));

    // Request ::= SEQUENCE { reqCert CertID }
    final ASN1Sequence request = ASN1Sequence()..add(certIdSeq);
    // TBSRequest ::= SEQUENCE { requestList SEQUENCE OF Request }
    final ASN1Sequence requestList = ASN1Sequence()..add(request);
    final ASN1Sequence tbs = ASN1Sequence()..add(requestList);
    // OCSPRequest ::= SEQUENCE { tbsRequest }
    final ASN1Sequence ocsp = ASN1Sequence()..add(tbs);

    return Uint8List.fromList(ocsp.encodedBytes);
  }

  /// Extrae subjectPublicKey del SPKI (sin unused-bits byte).
  static Uint8List? _spkiPublicKeyBits(List<int> spkiDer) {
    try {
      final ASN1Object spki =
          ASN1Parser(Uint8List.fromList(spkiDer)).nextObject();
      if (spki is! ASN1Sequence) return null;
      final List<ASN1Object> parts = spki.elements;
      if (parts.length < 2) return null;
      final ASN1Object bitStr = parts[1];
      if (bitStr.tag != BIT_STRING_TYPE) return null;
      return Uint8List.fromList(bitStr.contentBytes());
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // OCSP response (solo certStatus del certId; soft-fail sin verif. firma)
  // ---------------------------------------------------------------------------

  /// Parsea OCSPResponse DER. Devuelve null si inutilizable.
  static CertValidity? parseOcspResponse(
    List<int> der, {
    required String serialHex,
  }) {
    try {
      final ASN1Object root = ASN1Parser(Uint8List.fromList(der)).nextObject();
      if (root is! ASN1Sequence) return null;
      final List<ASN1Object> parts = root.elements;
      if (parts.isEmpty) return null;

      // responseStatus ENUMERATED (asn1lib puede devolverlo como ASN1Integer)
      final ASN1Object statusObj = parts[0];
      if (statusObj.tag != ENUMERATED_TYPE && statusObj.tag != INTEGER_TYPE) {
        return null;
      }
      final List<int> statusBytes = statusObj.valueBytes();
      final int status = statusBytes.isEmpty ? -1 : statusBytes[0];
      if (status != 0) return null; // successful(0) only

      if (parts.length < 2) return null;
      final ASN1Object respBytes = parts[1];
      // [0] EXPLICIT ResponseBytes
      final ASN1Object? respBytesInner = _firstChild(respBytes);
      if (respBytesInner == null || respBytesInner is! ASN1Sequence) return null;
      final List<ASN1Object> rb = respBytesInner.elements;
      if (rb.length < 2) return null;
      // rb[1] = OCTET STRING con BasicOCSPResponse
      if (rb[1].tag != OCTET_STRING_TYPE) return null;
      final ASN1Object basic = ASN1Parser(
        Uint8List.fromList(rb[1].contentBytes()),
      ).nextObject();
      if (basic is! ASN1Sequence) return null;
      final List<ASN1Object> basicParts = basic.elements;
      if (basicParts.isEmpty) return null;
      // tbsResponseData = basicParts[0]
      if (basicParts[0] is! ASN1Sequence) return null;
      final ASN1Sequence tbs = basicParts[0] as ASN1Sequence;

      final String want = _normalizeSerial(serialHex);
      return _findSingleResponse(tbs, want);
    } catch (_) {
      return null;
    }
  }

  /// Busca SingleResponse (recursivo: responses es SEQUENCE OF).
  static CertValidity? _findSingleResponse(ASN1Object node, String want) {
    if (node is ASN1Sequence) {
      final List<ASN1Object> e = node.elements;
      // SingleResponse: CertID (SEQ) + CertStatus (context tag 0x8x/0xAx) + Time
      if (e.length >= 3 && e[0] is ASN1Sequence && _isCertStatusTag(e[1].tag)) {
        final String? serial = _certIdSerial(e[0]);
        if (serial != null && _normalizeSerial(serial) == want) {
          return _certStatusToValidity(e[1]);
        }
      }
      for (final ASN1Object child in e) {
        final CertValidity? v = _findSingleResponse(child, want);
        if (v != null) return v;
      }
    }
    return null;
  }

  static bool _isCertStatusTag(int tag) {
    // good[0]=0x80/0xA0, revoked[1]=0x91/0xA1, unknown[2]=0x82/0xA2
    return tag == 0x80 ||
        tag == 0xA0 ||
        tag == 0x91 ||
        tag == 0xA1 ||
        tag == 0x82 ||
        tag == 0xA2;
  }

  static CertValidity? _certStatusToValidity(ASN1Object certStatus) {
    // good [0] IMPLICIT NULL → 0x80; revoked [1] → 0xA1; unknown [2] → 0x82
    final int tag = certStatus.tag;
    if (tag == 0xA0 || tag == 0x80) return CertValidity.yes;
    if (tag == 0xA1 || tag == 0x91) return CertValidity.no;
    if (tag == 0xA2 || tag == 0x82) return CertValidity.unknown;
    return null;
  }

  static String? _certIdSerial(ASN1Object certId) {
    if (certId is! ASN1Sequence) return null;
    final List<ASN1Object> c = certId.elements;
    if (c.length < 4) return null;
    if (c[3] is! ASN1Integer) return null;
    // Serial X.509: tratar como unsigned (evita signos por alto bit).
    return _unsignedHex((c[3] as ASN1Integer).valueBytes());
  }

  /// Convierte bytes big-endian a hex sin signo (mayúsculas, sin 0x).
  static String _unsignedHex(List<int> bytes) {
    int i = 0;
    // Quitar prefijo 0x00 de DER para enteros positivos con bit alto.
    while (i < bytes.length - 1 && bytes[i] == 0x00) {
      i++;
    }
    final StringBuffer sb = StringBuffer();
    for (int j = i; j < bytes.length; j++) {
      sb.write(bytes[j].toRadixString(16).padLeft(2, '0').toUpperCase());
    }
    final String s = sb.toString();
    return s.isEmpty ? '0' : _normalizeSerial(s);
  }

  // ---------------------------------------------------------------------------
  // CRL
  // ---------------------------------------------------------------------------

  static bool looksLikePem(List<int> bytes) {
    try {
      final String head = String.fromCharCodes(bytes.take(32));
      return head.contains('-----BEGIN');
    } catch (_) {
      return false;
    }
  }

  static Uint8List derFromPem(List<int> bytes) {
    final String text = String.fromCharCodes(bytes);
    final RegExp re = RegExp(r'-----BEGIN[^-]+-----(.*?)-----END', dotAll: true);
    final Match? m = re.firstMatch(text);
    if (m == null) return Uint8List.fromList(bytes);
    final String b64 = m.group(1)!.replaceAll(RegExp(r'\s'), '');
    return Uint8List.fromList(base64.decode(b64));
  }

  /// true si el serial está en revokedCertificates; false si la CRL es
  /// válida y no lo contiene; null si ilegible.
  static CertValidity? parseCrl(List<int> der, {required String serialHex}) {
    try {
      final ASN1Object certList = ASN1Parser(Uint8List.fromList(der)).nextObject();
      if (certList is! ASN1Sequence) return null;
      final List<ASN1Object> parts = certList.elements;
      if (parts.isEmpty || parts[0] is! ASN1Sequence) return null;
      final ASN1Sequence tbs = parts[0] as ASN1Sequence;
      final List<ASN1Object> t = tbs.elements;
      if (t.length < 4) return null;

      int idx = 0;
      // version OPTIONAL (INTEGER)
      if (t[idx].tag == INTEGER_TYPE) idx++;
      // signature AlgId, issuer, thisUpdate [ , nextUpdate ]
      idx += 3;
      if (idx < t.length && t[idx].tag == timeTypeUtcOrGen) {
        idx++; // nextUpdate optional when present as Time
      }
      // Algunas CRLs llevan nextUpdate como UTCTime(0x17)/GeneralizedTime(0x18)
      // ya cubierto arriba; buscar revokedCertificates SEQUENCE (tag 0x30)
      // a partir de idx.
      final String want = _normalizeSerial(serialHex);
      for (int j = idx; j < t.length; j++) {
        if (t[j].tag != CONSTRUCTED_SEQUENCE_TYPE) continue;
        final List<ASN1Object>? revs = _childrenList(t[j]);
        if (revs == null) continue;
        for (final ASN1Object entry in revs) {
          if (entry is! ASN1Sequence) continue;
          final List<ASN1Object> e = entry.elements;
          if (e.isEmpty || e[0] is! ASN1Integer) continue;
          final BigInt s = (e[0] as ASN1Integer).valueAsBigInteger;
          if (_normalizeSerial(s.toRadixString(16)) == want) {
            return CertValidity.no;
          }
        }
        // Primer SEQUENCE tras issuer/thisUpdate tratado como revoked list
        return CertValidity.yes;
      }
      // Sin revokedCertificates → nobody revoked
      return CertValidity.yes;
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // helpers ASN.1 (minimal, asn1lib 1.6.5)
  // ---------------------------------------------------------------------------

  static List<ASN1Object>? _childrenList(ASN1Object o) {
    if (o is ASN1Sequence) return o.elements;
    return null;
  }

  static ASN1Object? _firstChild(ASN1Object o) {
    if (o is ASN1Sequence) {
      return o.elements.isEmpty ? null : o.elements.first;
    }
    try {
      final ASN1Parser p = ASN1Parser(o.valueBytes());
      if (p.hasNext()) return p.nextObject();
    } catch (_) {}
    return null;
  }

  static String _normalizeSerial(String hex) {
    String s = hex.toUpperCase().replaceAll(RegExp(r'^0+'), '');
    if (s.isEmpty) s = '0';
    return s;
  }

  static const int timeTypeUtcOrGen = 0x17; // UTCTime; GenTime=0x18
  static const String _kOidSha1 = '1.3.14.3.2.26';
}

class _NodeRevocation {
  const _NodeRevocation({
    required this.status,
    this.source,
    this.note,
    this.skipped = false,
  });

  final CertValidity status;
  final RevocationSource? source;
  final String? note;
  final bool skipped;
}
