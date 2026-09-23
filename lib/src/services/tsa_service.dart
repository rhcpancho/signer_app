import 'dart:typed_data';

import 'package:asn1lib/asn1lib.dart';
import 'package:crypto/crypto.dart' as cryptoutils;
import 'package:http/http.dart' as http;

/// URL pública por defecto del TSA (DigiCert RFC 3161).
const String kDefaultTsaUrl = 'http://timestamp.digicert.com';

/// Resultado de una petición TSA soft-fail.
///
/// `granted` solo si PKIStatusInfo = 0 y hay token legible.
/// Cualquier error de red/parseo → el llamador recibe `null` (soft-fail).
class TsaResult {
  const TsaResult({
    required this.token,
    this.genTime,
    this.tsaName,
  });

  /// TimeStampToken (ContentInfo/CMS DER) tal cual lo devolvió el TSA.
  final Uint8List token;

  /// genTime de TSTInfo, si se pudo extraer.
  final DateTime? genTime;

  /// CN/subject aproximado del TSA (si se localiza en certs del token).
  final String? tsaName;
}

/// Sello de tiempo RFC 3161 soft-fail: POST timestamp-query → parse resp.
///
/// Nunca lanza hacia arriba: [timestamp] devuelve `null` en cualquier fallo.
class TsaService {
  TsaService({http.Client? client, Duration? timeout})
      : _client = client ?? http.Client(),
        timeout = timeout ?? const Duration(seconds: 6);

  final http.Client _client;
  final Duration timeout;

  /// Construye TimeStampReq (v1, messageImprint SHA-256, certReq=false) de [data].
  static Uint8List buildTimeStampRequest(List<int> data) {
    final List<int> digest = cryptoutils.sha256.convert(data).bytes;

    // AlgorithmIdentifier ::= SEQUENCE { OID sha256, NULL }
    final ASN1Sequence algId = ASN1Sequence()
      ..add(ASN1ObjectIdentifier.fromComponentString(
          '2.16.840.1.101.3.4.2.1'))
      ..add(ASN1Null());

    // MessageImprint ::= SEQUENCE { hashAlgorithm, hashedMessage OCTET STRING }
    final ASN1Sequence imprint = ASN1Sequence()
      ..add(algId)
      ..add(ASN1OctetString(Uint8List.fromList(digest)));

    // TimeStampReq ::= SEQUENCE { version v1(1), messageImprint }
    final ASN1Sequence req = ASN1Sequence()
      ..add(ASN1Integer(BigInt.one))
      ..add(imprint);

    return Uint8List.fromList(req.encodedBytes);
  }

  /// Parsea TimeStampResp. Devuelve null si status != granted o sin token.
  static TsaResult? parseTimeStampResponse(List<int> der) {
    try {
      final ASN1Object root = ASN1Parser(Uint8List.fromList(der)).nextObject();
      if (root is! ASN1Sequence) return null;
      final List<ASN1Object> parts = root.elements;
      if (parts.isEmpty) return null;

      // PKIStatusInfo.status INTEGER (0 = granted)
      final ASN1Object statusObj = parts[0];
      if (statusObj is! ASN1Sequence) return null;
      final List<ASN1Object> st = statusObj.elements;
      if (st.isEmpty || st[0] is! ASN1Integer) return null;
      final BigInt status = (st[0] as ASN1Integer).valueAsBigInteger;
      if (status != BigInt.zero) return null;

      if (parts.length < 2) return null;
      // timeStampToken: ContentInfo SEQUENCE (tag 0x30)
      final ASN1Object tokenObj = parts[1];
      if (tokenObj.tag != CONSTRUCTED_SEQUENCE_TYPE) return null;
      final Uint8List token = Uint8List.fromList(tokenObj.encodedBytes);
      final DateTime? genTime = _extractGenTime(token);
      final String? tsaName = _extractTsaName(token);
      return TsaResult(token: token, genTime: genTime, tsaName: tsaName);
    } catch (_) {
      return null;
    }
 }

  /// Soft-fail: envía TimeStampReq a [url]. null en cualquier error.
  Future<TsaResult?> timestamp({
    required Uint8List data,
    String url = kDefaultTsaUrl,
  }) async {
    try {
      final Uint8List req = buildTimeStampRequest(data);
      final http.Response resp = await _client
          .post(
            Uri.parse(url),
            headers: <String, String>{
              'Content-Type': 'application/timestamp-query',
              'Accept': 'application/timestamp-reply',
            },
            body: req,
          )
          .timeout(timeout);
      if (resp.statusCode != 200 || resp.bodyBytes.isEmpty) return null;
      return parseTimeStampResponse(resp.bodyBytes);
    } catch (_) {
      return null;
    }
  }

  // -------------------------------------------------------------------------
  // TSTInfo genTime + TSA CN (best-effort sobre CMS del token)
  // -------------------------------------------------------------------------

  static DateTime? _extractGenTime(Uint8List token) {
    try {
      final ASN1Object root = ASN1Parser(token).nextObject();
      final ASN1Object? tstInfo = _findTstInfo(root);
      if (tstInfo == null || tstInfo is! ASN1Sequence) return null;
      final List<ASN1Object> e = tstInfo.elements;
      // TSTInfo: version, policy, messageImprint, serial, genTime, ...
      // genTime es GeneralizedTime (0x18) tras serial (INTEGER).
      for (final ASN1Object o in e) {
        if (o.tag == 0x18) {
          final String s = String.fromCharCodes(o.valueBytes());
          return _parseGeneralizedTime(s);
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static ASN1Object? _findTstInfo(ASN1Object node, [int depth = 0]) {
    if (depth > 12) return null;
    if (node is ASN1Sequence) {
      final List<ASN1Object> e = node.elements;
      // eContent OCTET STRING a menudo llega como constructed [0] con inner SEQ
      for (final ASN1Object child in e) {
        if (child is ASN1Sequence) {
          final List<ASN1Object> ce = child.elements;
          // id-ct-TSTInfo = 1.2.840.113549.1.9.16.1.4
          if (ce.isNotEmpty &&
              ce[0] is ASN1ObjectIdentifier &&
              (ce[0] as ASN1ObjectIdentifier).identifier ==
                  '1.2.840.113549.1.9.16.1.4') {
            // Segundo elemento: [0] EXPLICIT OCTET STRING o OCTET STRING
            if (ce.length >= 2) {
              final ASN1Object? inner = _unwrapOctets(ce[1]);
              if (inner != null) return inner;
            }
          }
          final ASN1Object? found = _findTstInfo(child, depth + 1);
          if (found != null) return found;
        } else {
          final ASN1Object? found = _findTstInfo(child, depth + 1);
          if (found != null) return found;
        }
      }
    } else if (node.tag == OCTET_STRING_TYPE ||
        node.tag == 0xA0 ||
        node.tag == 0x04) {
      try {
        final ASN1Parser p = ASN1Parser(Uint8List.fromList(node.valueBytes()));
        if (p.hasNext()) {
          final ASN1Object o = p.nextObject();
          if (o is ASN1Sequence) return o;
        }
      } catch (_) {}
    }
    return null;
  }

  static ASN1Object? _unwrapOctets(ASN1Object o) {
    try {
      if (o.tag == OCTET_STRING_TYPE || o.tag == 0xA0 || o.tag == 0x04) {
        final ASN1Parser p = ASN1Parser(Uint8List.fromList(o.valueBytes()));
        if (p.hasNext()) return p.nextObject();
      }
    } catch (_) {}
    return null;
  }

  static String? _extractTsaName(Uint8List token) {
    try {
      final ASN1Object root = ASN1Parser(token).nextObject();
      return _searchCn(root, 0);
    } catch (_) {
      return null;
    }
  }

  static String? _searchCn(ASN1Object node, int depth) {
    if (depth > 14) return null;
    if (node is ASN1Sequence) {
      for (final ASN1Object child in node.elements) {
        if (child is ASN1Sequence) {
          final List<ASN1Object> e = child.elements;
          // RDN: SET OF AttributeTypeAndValue { OID 2.5.4.3, value }
          for (int i = 0; i + 1 < e.length; i++) {
            if (e[i] is ASN1ObjectIdentifier &&
                (e[i] as ASN1ObjectIdentifier).identifier == '2.5.4.3') {
              final ASN1Object v = e[i + 1];
              final String s = String.fromCharCodes(v.valueBytes());
              if (s.isNotEmpty) return s;
            }
          }
          final String? found = _searchCn(child, depth + 1);
          if (found != null) return found;
        } else {
          final String? found = _searchCn(child, depth + 1);
          if (found != null) return found;
        }
      }
    }
    return null;
  }

  static DateTime? _parseGeneralizedTime(String s) {
    // Formato: YYYYMMDDHHMMSSZ o YYYYMMDDHHMMSS.fffZ
    final RegExp re = RegExp(
      r'^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})(?:\.\d+)?Z$',
    );
    final Match? m = re.firstMatch(s.trim());
    if (m == null) return null;
    return DateTime.utc(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
      int.parse(m.group(4)!),
      int.parse(m.group(5)!),
      int.parse(m.group(6)!),
    );
  }
}
