// ignore_for_file: implementation_imports

import 'dart:typed_data';

import 'package:asn1lib/asn1lib.dart';
import 'package:crypto/crypto.dart' as cryptoutils;
import 'package:pointycastle/api.dart' as pc;
import 'package:pointycastle/asymmetric/api.dart';
import 'package:pointycastle/digests/sha1.dart';
import 'package:pointycastle/digests/sha224.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/digests/sha384.dart';
import 'package:pointycastle/digests/sha512.dart';
import 'package:pointycastle/signers/rsa_signer.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/forms/pdf_field.dart';
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/io/pdf_cross_table.dart';
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/primitives/pdf_array.dart';
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/primitives/pdf_dictionary.dart';
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/primitives/pdf_number.dart';
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/primitives/pdf_string.dart';
import 'package:syncfusion_flutter_pdf/src/pdf/interfaces/pdf_interface.dart';

import '../models/signature_chain.dart';

/// Análisis manual de CMS/PKCS#7 + X.509 embebidos en firmas PDF.
///
/// No usa el paquete `x509` (extensiones críticas con `UnimplementedError`).
/// Nunca lanza: los errores se devuelven en [SignatureChainInfo.error].
class SignatureCryptoService {
  /// Extrae Contents + ByteRange del campo y analiza la cadena.
  SignatureChainInfo? analyseSignature(
    PdfSignatureField field,
    Uint8List documentBytes,
  ) {
    try {
      final _RawSignature? raw = _extractRaw(field);
      if (raw == null) return null;
      return analyse(
        cmsBytes: raw.cms,
        documentBytes: documentBytes,
        byteRange: raw.byteRange,
      );
    } catch (e) {
      return SignatureChainInfo(
        documentIntegrityOk: null,
        signatureCryptographicOk: null,
        signatureValidates: null,
        chainComplete: false,
        chainNodes: const <CertChainNode>[],
        digestAlgorithmOid: null,
        signatureAlgorithmOid: null,
        signingTime: null,
        error: e.toString(),
      );
    }
  }

  /// API pura sobre bytes ya extraídos (testeable sin PDF).
  SignatureChainInfo analyse({
    required Uint8List cmsBytes,
    required Uint8List documentBytes,
    required List<int> byteRange,
  }) {
    try {
      final _CmsParsed cms = _parseCms(cmsBytes);
      final bool? integrity = _checkDocumentIntegrity(
        documentBytes,
        byteRange,
        cms.digestOid,
        cms.messageDigest,
      );
      final List<CertChainNode> chain =
          _buildChain(cms.certificates, cms.signingTime);
      final bool chainComplete = _isChainComplete(chain);
      final bool? cryptoOk = _verifySignature(cms);

      final bool? validates = (integrity == true && cryptoOk == true)
          ? true
          : (integrity == false || cryptoOk == false)
              ? false
              : null;

      return SignatureChainInfo(
        documentIntegrityOk: integrity,
        signatureCryptographicOk: cryptoOk,
        signatureValidates: validates,
        chainComplete: chainComplete,
        chainNodes: chain,
        digestAlgorithmOid: cms.digestOid,
        signatureAlgorithmOid: cms.sigAlgOid,
        signingTime: cms.signingTime,
        error: cms.parseWarning,
      );
    } catch (e) {
      return SignatureChainInfo(
        documentIntegrityOk: null,
        signatureCryptographicOk: null,
        signatureValidates: null,
        chainComplete: false,
        chainNodes: const <CertChainNode>[],
        digestAlgorithmOid: null,
        signatureAlgorithmOid: null,
        signingTime: null,
        error: e.toString(),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Extracción Syncfusion
  // ---------------------------------------------------------------------------

  static const String _kContents = 'Contents';
  static const String _kByteRange = 'ByteRange';

  _RawSignature? _extractRaw(PdfSignatureField field) {
    final PdfDictionary? dict = PdfFieldHelper.getHelper(field).dictionary;
    if (dict == null) return null;

    final IPdfPrimitive? contentsRaw =
        PdfCrossTable.dereference(dict[_kContents]);
    final IPdfPrimitive? rangeRaw =
        PdfCrossTable.dereference(dict[_kByteRange]);

    if (contentsRaw is! PdfString || rangeRaw is! PdfArray) return null;

    final Uint8List cms = _contentsToBytes(contentsRaw);
    if (cms.isEmpty) return null;

    final List<int> range = <int>[];
    for (final IPdfPrimitive? el in rangeRaw.elements) {
      final IPdfPrimitive? d = PdfCrossTable.dereference(el);
      if (d is PdfNumber && d.value != null) {
        range.add(d.value!.toInt());
      }
    }
    if (range.length < 4) return null;

    return _RawSignature(cms: cms, byteRange: range);
  }

  static Uint8List _contentsToBytes(PdfString s) {
    final List<int>? data = s.data;
    if (data != null && data.isNotEmpty) {
      return Uint8List.fromList(data);
    }
    final String? value = s.value;
    if (value == null || value.isEmpty) return Uint8List(0);
    return Uint8List.fromList(_hexToBytes(value));
  }

  static List<int> _hexToBytes(String hex) {
    final String clean = hex.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
    final int n = clean.length ~/ 2;
    final Uint8List out = Uint8List(n);
    for (int i = 0; i < n; i++) {
      out[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

  // ---------------------------------------------------------------------------
  // ASN.1 tag bytes (asn1lib 1.6.5 no expone ASN1Tags)
  // ---------------------------------------------------------------------------

  static const int _kTagBoolean = BOOLEAN_TYPE;
  static const int _kTagInteger = INTEGER_TYPE;
  static const int _kTagBitString = BIT_STRING_TYPE;
  static const int _kTagOctetString = OCTET_STRING_TYPE;
  static const int _kTagSequence = CONSTRUCTED_SEQUENCE_TYPE;
  static const int _kTagSet = CONSTRUCTED_SET_TYPE;
  static const int _kTagCtx0 = 0xA0;
  static const int _kTagCtx3 = 0xA3;
  static const int _kTagCtx0Prim = CONTEXT_SPECIFIC_CLASS;

  // ---------------------------------------------------------------------------
  // CMS
  // ---------------------------------------------------------------------------

  static const String _kOidSignedData = '1.2.840.113549.1.7.2';
  static const String _kOidMessageDigest = '1.2.840.113549.1.9.4';
  static const String _kOidSigningTime = '1.2.840.113549.1.9.5';
  static const String _kOidAia = '1.3.6.1.5.5.7.1.1';
  static const String _kOidCrlDp = '2.5.29.31';

  /// DigestIdentifier DER (hex) que espera [RSASigner].
  static const Map<String, String> _kDigestIdentHex = <String, String>{
    '1.3.14.3.2.26': '06052b0e03021a',
    '2.16.840.1.101.3.4.2.1': '0609608648016503040201',
    '2.16.840.1.101.3.4.2.2': '0609608648016503040202',
    '2.16.840.1.101.3.4.2.3': '0609608648016503040203',
    '2.16.840.1.101.3.4.2.4': '0609608648016503040204',
  };

  _CmsParsed _parseCms(Uint8List cmsBytes) {
    final ASN1Parser parser = ASN1Parser(cmsBytes);
    final ASN1Object contentInfo = parser.nextObject();
    if (contentInfo.tag != _kTagSequence) {
      throw const FormatException('CMS: ContentInfo no es SEQUENCE');
    }
    final List<ASN1Object>? ci = _children(contentInfo);
    if (ci == null || ci.length < 2) {
      throw const FormatException('CMS: ContentInfo incompleto');
    }
    final String? ctOid = _oidString(ci[0]);
    if (ctOid != _kOidSignedData) {
      throw FormatException('CMS: contentType $ctOid ≠ signedData');
    }

    // [0] EXPLICIT SignedData → reparsear value bytes (context tag sin hijos)
    final ASN1Object explicit0 = ci[1];
    if (explicit0.tag != _kTagCtx0) {
      throw const FormatException('CMS: falta [0] SignedData');
    }
    final ASN1Parser sdParser = ASN1Parser(explicit0.valueBytes());
    final ASN1Object signedData = sdParser.nextObject();
    final List<ASN1Object>? sd = _children(signedData);
    if (sd == null || sd.length < 4) {
      throw const FormatException('CMS: SignedData incompleto');
    }

    final List<Uint8List> certs = <Uint8List>[];
    ASN1Object? signerInfosSet;
    for (int i = 3; i < sd.length; i++) {
      final ASN1Object el = sd[i];
      if (el.tag == _kTagSet) {
        signerInfosSet = el;
      } else if (el.tag == _kTagCtx0) {
        // certificates [0] IMPLICIT SET OF Certificate
        final List<ASN1Object>? children = _children(el);
        if (children != null) {
          for (final ASN1Object c in children) {
            certs.add(Uint8List.fromList(c.encodedBytes));
          }
        }
      }
      // [1] crls se ignora
    }

    if (signerInfosSet == null) {
      throw const FormatException('CMS: sin signerInfos');
    }
    final List<ASN1Object>? signerInfos = _children(signerInfosSet);
    if (signerInfos == null || signerInfos.isEmpty) {
      throw const FormatException('CMS: signerInfos vacío');
    }

    return _parseSignerInfo(signerInfos.first, certs);
  }

  _CmsParsed _parseSignerInfo(ASN1Object signerInfo, List<Uint8List> certs) {
    if (signerInfo.tag != _kTagSequence) {
      throw const FormatException('CMS: SignerInfo no es SEQUENCE');
    }
    final List<ASN1Object>? si = _children(signerInfo);
    if (si == null || si.length < 4) {
      throw const FormatException('CMS: SignerInfo incompleto');
    }

    // [0] version, [1] sid, [2] digestAlgorithm,
    // [3] signedAttrs? [0], [4] sigAlg, [5] signature
    int idx = 2;
    final String digestOid = _algOid(si[idx]) ?? '';
    idx++;

    Uint8List? signedAttrsDer;
    if (idx < si.length && si[idx].tag == _kTagCtx0) {
      signedAttrsDer = Uint8List.fromList(si[idx].encodedBytes);
      if (signedAttrsDer.isNotEmpty && signedAttrsDer[0] == 0xA0) {
        signedAttrsDer[0] = 0x31;
      }
      idx++;
    }

    if (idx >= si.length) {
      throw const FormatException('CMS: falta signatureAlgorithm');
    }
    final String sigOid = _algOid(si[idx]) ?? '';
    idx++;

    if (idx >= si.length) {
      throw const FormatException('CMS: falta signature');
    }
    final Uint8List signature = Uint8List.fromList(si[idx].contentBytes());

    Uint8List? messageDigest;
    DateTime? signingTime;
    if (signedAttrsDer != null) {
      final _SignedAttrs attrs = _parseSignedAttrs(signedAttrsDer);
      messageDigest = attrs.messageDigest;
      signingTime = attrs.signingTime;
    }

    return _CmsParsed(
      digestOid: digestOid,
      sigAlgOid: sigOid,
      signature: signature,
      signedAttrsDer: signedAttrsDer,
      messageDigest: messageDigest,
      signingTime: signingTime,
      certificates: certs,
      parseWarning: null,
    );
  }

  static _SignedAttrs _parseSignedAttrs(Uint8List der) {
    final ASN1Object set = ASN1Parser(der).nextObject();
    final List<ASN1Object>? attrs = _children(set);
    Uint8List? md;
    DateTime? st;
    if (attrs == null) {
      return const _SignedAttrs(messageDigest: null, signingTime: null);
    }
    for (final ASN1Object attr in attrs) {
      if (attr.tag != _kTagSequence) continue;
      final List<ASN1Object>? parts = _children(attr);
      if (parts == null || parts.length < 2) continue;
      final String? oid = _oidString(parts[0]);
      if (oid == _kOidMessageDigest) {
        final ASN1Object inner = parts[1];
        if (inner.tag == _kTagOctetString) {
          md = Uint8List.fromList(inner.contentBytes());
        } else {
          final List<ASN1Object>? ic = _children(inner);
          if (ic != null && ic.isNotEmpty) {
            md = Uint8List.fromList(ic.first.contentBytes());
          }
        }
      } else if (oid == _kOidSigningTime) {
        st = _asDate(parts[1]);
      }
    }
    return _SignedAttrs(messageDigest: md, signingTime: st);
  }

  // ---------------------------------------------------------------------------
  // Integridad del documento (ByteRange + messageDigest)
  // ---------------------------------------------------------------------------

  bool? _checkDocumentIntegrity(
    Uint8List documentBytes,
    List<int> byteRange,
    String? digestOid,
    Uint8List? messageDigest,
  ) {
    if (byteRange.length < 4) return null;
    if (digestOid == null || digestOid.isEmpty) return null;
    if (messageDigest == null) return null;

    final int a0 = byteRange[0];
    final int a1 = byteRange[1];
    final int b0 = byteRange[2];
    final int b1 = byteRange[3];

    if (a0 != 0) return false;
    if (a1 < 0 || b0 < a1 || b1 > documentBytes.length) return false;
    if (b1 < documentBytes.length && b1 < documentBytes.length - 32) {
      return false;
    }

    final BytesBuilder builder = BytesBuilder();
    builder.add(documentBytes.sublist(a0, a1));
    builder.add(documentBytes.sublist(b0, b1));
    final List<int> covered = builder.takeBytes();

    final List<int>? expected = _digestBytes(digestOid, covered);
    if (expected == null) return null;
    if (expected.length != messageDigest.length) return false;
    for (int i = 0; i < expected.length; i++) {
      if (expected[i] != messageDigest[i]) return false;
    }
    return true;
  }

  // ---------------------------------------------------------------------------
  // Verificación criptográfica (RSA PKCS#1 v1.5 sobre signedAttrs)
  // ---------------------------------------------------------------------------

  bool? _verifySignature(_CmsParsed cms) {
    try {
      if (cms.certificates.isEmpty) return null;
      if (cms.signedAttrsDer == null) return null;
      if (cms.digestOid.isEmpty) return null;

      final String? identHex = _kDigestIdentHex[cms.digestOid];
      if (identHex == null) return null;

      final _ParsedCert cert = _parseCertFull(cms.certificates.first);
      final RSAPublicKey? pub = _rsaPublicKey(cert);
      if (pub == null) return null;

      final pc.Digest digest = _digestForOid(cms.digestOid);
      final RSASigner signer = RSASigner(digest, identHex)
        ..init(false, pc.PublicKeyParameter<RSAPublicKey>(pub));

      return signer.verifySignature(
        cms.signedAttrsDer!,
        RSASignature(cms.signature),
      );
    } catch (_) {
      return null;
    }
  }

  static pc.Digest _digestForOid(String oid) {
    switch (oid) {
      case '1.3.14.3.2.26':
        return SHA1Digest();
      case '2.16.840.1.101.3.4.2.1':
        return SHA256Digest();
      case '2.16.840.1.101.3.4.2.2':
        return SHA384Digest();
      case '2.16.840.1.101.3.4.2.3':
        return SHA512Digest();
      case '2.16.840.1.101.3.4.2.4':
        return SHA224Digest();
      default:
        return SHA256Digest();
    }
  }

  static List<int>? _digestBytes(String oid, List<int> data) {
    switch (oid) {
      case '1.3.14.3.2.26':
        return cryptoutils.sha1.convert(data).bytes;
      case '2.16.840.1.101.3.4.2.1':
        return cryptoutils.sha256.convert(data).bytes;
      case '2.16.840.1.101.3.4.2.2':
        return cryptoutils.sha384.convert(data).bytes;
      case '2.16.840.1.101.3.4.2.3':
        return cryptoutils.sha512.convert(data).bytes;
      case '2.16.840.1.101.3.4.2.4':
        return cryptoutils.sha224.convert(data).bytes;
      default:
        return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Cadena de certificados
  // ---------------------------------------------------------------------------

  List<CertChainNode> _buildChain(List<Uint8List> certs, DateTime? at) {
    if (certs.isEmpty) return const <CertChainNode>[];
    final DateTime ref = at ?? DateTime.now();

    final List<_ParsedCert> parsed = <_ParsedCert>[];
    for (final Uint8List der in certs) {
      try {
        parsed.add(_parseCertFull(der));
      } catch (_) {
        // cert ilegible → omitir
      }
    }
    if (parsed.isEmpty) return const <CertChainNode>[];

    _ParsedCert leaf = parsed.first;
    for (final _ParsedCert c in parsed) {
      final bool issues = parsed.any(
        (o) => !identical(o, c) && o.subject == c.issuer,
      );
      final bool isIssuedTo = parsed.any(
        (o) => !identical(o, c) && o.issuer == c.subject,
      );
      if (!isIssuedTo && issues) {
        leaf = c;
        break;
      }
    }

    final List<CertChainNode> chain = <CertChainNode>[];
    _ParsedCert? current = leaf;
    final Set<String> seen = <String>{};

    while (current != null) {
      final String key = '${current.subject}|${current.serialHex}';
      if (seen.contains(key)) break;
      seen.add(key);

      chain.add(current.toNode(ref));

      if (current.isSelfSigned) break;

      final String parentSubject = current.issuer;
      _ParsedCert? parent;
      for (final _ParsedCert c in parsed) {
        if (c.subject == parentSubject && !identical(c, current)) {
          parent = c;
          break;
        }
      }
      if (parent == null) break;
      current = parent;
    }

    return chain;
  }

  static bool _isChainComplete(List<CertChainNode> chain) {
    if (chain.isEmpty) return false;
    final CertChainNode last = chain.last;
    return last.isSelfSigned && last.isCa;
  }

  // ---------------------------------------------------------------------------
  // ASN.1 helpers
  // ---------------------------------------------------------------------------

  /// Hijos de un nodo: SEQUENCE/SET o reparseo de context-tag (0xA0…).
  static List<ASN1Object>? _children(ASN1Object o) {
    if (o is ASN1Sequence) return o.elements;
    if (o is ASN1Set) return o.elements.toList(growable: false);
    try {
      final ASN1Parser p = ASN1Parser(o.valueBytes());
      final List<ASN1Object> list = <ASN1Object>[];
      while (p.hasNext()) {
        list.add(p.nextObject());
      }
      return list;
    } catch (_) {
      return null;
    }
  }

  static String? _oidString(ASN1Object o) {
    if (o is ASN1ObjectIdentifier) return o.identifier;
    return null;
  }

  static String? _algOid(ASN1Object algId) {
    if (algId.tag != _kTagSequence) return null;
    final List<ASN1Object>? parts = _children(algId);
    if (parts == null || parts.isEmpty) return null;
    return _oidString(parts[0]);
  }

  static ASN1Object _parseCert(Uint8List der) {
    final ASN1Object cert = ASN1Parser(der).nextObject();
    if (cert.tag != _kTagSequence) {
      throw const FormatException('X.509: no es SEQUENCE');
    }
    return cert;
  }

  static _ParsedCert _parseCertFull(Uint8List der) {
    final ASN1Object cert = _parseCert(der);
    final List<ASN1Object>? parts = _children(cert);
    if (parts == null || parts.length < 3) {
      throw const FormatException('X.509: cert incompleto');
    }
    final ASN1Object tbs = parts[0];
    final List<ASN1Object>? t = _children(tbs);
    if (t == null || t.length < 7) {
      throw const FormatException('X.509: tbs incompleto');
    }

    int i = 0;
    if (t[i].tag == _kTagCtx0) {
      i++;
    }
    // serial
    if (t[i].tag != _kTagInteger) {
      throw const FormatException('X.509: sin serial');
    }
    final BigInt serial = (t[i] as ASN1Integer).valueAsBigInteger;
    final String serialHex = serial.toRadixString(16).toUpperCase();
    i++;
    // signature AlgId (skip)
    i++;
    // issuer
    final int issuerIdx = i;
    final String issuer = _dnToString(t[i]);
    i++;
    // validity
    DateTime? from;
    DateTime? to;
    try {
      final List<ASN1Object>? validity = _children(t[i]);
      if (validity != null && validity.length >= 2) {
        from = _asDate(validity[0]);
        to = _asDate(validity[1]);
      }
    } catch (_) {}
    i++;
    // subject
    final String subject = _dnToString(t[i]);
    i++;
    // SPKI (skip index; se busca por forma luego)
    i++;

    List<int>? ski;
    List<int>? aki;
    bool isCa = false;
    bool bcPresent = false;
    final List<String> ocspUrls = <String>[];
    final List<String> crlUrls = <String>[];
    for (; i < t.length; i++) {
      final ASN1Object el = t[i];
      if (el.tag != _kTagCtx3) continue;
      final List<ASN1Object>? extWrapper = _children(el);
      if (extWrapper == null || extWrapper.isEmpty) continue;
      final ASN1Object extSeq = extWrapper.first;
      if (extSeq.tag != _kTagSequence) continue;
      final List<ASN1Object>? exts = _children(extSeq);
      if (exts == null) continue;
      for (final ASN1Object ext in exts) {
        if (ext.tag != _kTagSequence) continue;
        final List<ASN1Object>? ep = _children(ext);
        if (ep == null || ep.length < 2) continue;
        final String? oid = _oidString(ep[0]);
        if (oid == null) continue;
        final ASN1Object val = ep[1];
        ASN1Object? inner;
        if (val.tag == _kTagOctetString) {
          try {
            inner = ASN1Parser(val.contentBytes()).nextObject();
          } catch (_) {}
        } else if (val.tag == _kTagCtx0) {
          final List<ASN1Object>? ic = _children(val);
          if (ic != null && ic.isNotEmpty && ic.first.tag == _kTagOctetString) {
            try {
              inner = ASN1Parser(ic.first.contentBytes()).nextObject();
            } catch (_) {}
          }
        }
        if (inner == null) continue;
        if (oid == '2.5.29.19') {
          bcPresent = true;
          isCa = _basicConstraintsIsCa(inner);
        } else if (oid == '2.5.29.14') {
          ski = Uint8List.fromList(inner.contentBytes());
        } else if (oid == '2.5.29.35') {
          final List<ASN1Object>? akiParts = _children(inner);
          if (akiParts != null && akiParts.isNotEmpty) {
            final ASN1Object k = akiParts[0];
            if (k.tag == _kTagCtx0 || k.tag == _kTagCtx0Prim) {
              aki = Uint8List.fromList(k.valueBytes());
            }
          }
        } else if (oid == _kOidAia) {
          _extractOcspUrls(inner, ocspUrls);
        } else if (oid == _kOidCrlDp) {
          _extractCrlUrls(inner, crlUrls);
        }
      }
    }

    final bool selfSigned =
        subject.isNotEmpty && subject == issuer;
    if (selfSigned && !bcPresent) {
      isCa = true;
    }

    return _ParsedCert(
      der: der,
      subject: subject,
      issuer: issuer,
      serialHex: serialHex,
      validFrom: from,
      validTo: to,
      isSelfSigned: selfSigned,
      isCa: isCa,
      basicConstraintsPresent: bcPresent,
      ski: ski,
      aki: aki,
      tbs: t,
      issuerNameDer: Uint8List.fromList(t[issuerIdx].encodedBytes),
      spkiDer: _tryFindSpkiDer(t),
      ocspUrls: ocspUrls,
      crlUrls: crlUrls,
    );
  }

  static List<int>? _tryFindSpkiDer(List<ASN1Object> tbs) {
    try {
      return Uint8List.fromList(_findSpki(tbs).encodedBytes);
    } catch (_) {
      return null;
    }
  }

  /// AIA (1.3.6.1.5.5.7.1.1) → URLs de id-ad-ocsp (…48.1).
  static void _extractOcspUrls(ASN1Object aia, List<String> out) {
    final List<ASN1Object>? descs = _children(aia);
    if (descs == null) return;
    for (final ASN1Object d in descs) {
      final List<ASN1Object>? p = _children(d);
      if (p == null || p.length < 2) continue;
      if (_oidString(p[0]) != '1.3.6.1.5.5.7.48.1') continue;
      final String? uri = _generalNameUri(p[1]);
      if (uri != null) out.add(uri);
    }
  }

  /// CRL Distribution Points (2.5.29.31) → cualquier URI GeneralName.
  static void _extractCrlUrls(ASN1Object dpSeq, List<String> out) {
    final List<ASN1Object>? dps = _children(dpSeq);
    if (dps == null) return;
    for (final ASN1Object dp in dps) {
      _collectUris(dp, out);
    }
  }

  static void _collectUris(ASN1Object o, List<String> out) {
    if (o.tag == 0x86) {
      // [6] uniformResourceIdentifier
      try {
        final String uri = String.fromCharCodes(o.valueBytes());
        if (uri.startsWith('http')) out.add(uri);
      } catch (_) {}
    }
    final List<ASN1Object>? kids = _children(o);
    if (kids == null) return;
    for (final ASN1Object k in kids) {
      _collectUris(k, out);
    }
  }

  static String? _generalNameUri(ASN1Object gn) {
    if (gn.tag == 0x86) {
      try {
        return String.fromCharCodes(gn.valueBytes());
      } catch (_) {
        return null;
      }
    }
    final List<ASN1Object>? kids = _children(gn);
    if (kids == null || kids.isEmpty) return null;
    for (final ASN1Object k in kids) {
      final String? u = _generalNameUri(k);
      if (u != null) return u;
    }
    return null;
  }

  static bool _basicConstraintsIsCa(ASN1Object inner) {
    if (inner.tag != _kTagSequence) return false;
    final List<ASN1Object>? parts = _children(inner);
    if (parts == null || parts.isEmpty) return false;
    if (parts.first.tag != _kTagBoolean) return false;
    return (parts.first as ASN1Boolean).booleanValue;
  }

  static RSAPublicKey? _rsaPublicKey(_ParsedCert cert) {
    try {
      final ASN1Object spki = _findSpki(cert.tbs);
      final List<ASN1Object>? sp = _children(spki);
      if (sp == null || sp.length < 2) return null;
      final ASN1Object bitStr = sp[1];
      if (bitStr.tag != _kTagBitString) return null;
      // contentBytes() de ASN1BitString ya omite el unused-bits byte
      final List<int> pkDer = bitStr.contentBytes();
      final ASN1Object rsa = ASN1Parser(Uint8List.fromList(pkDer)).nextObject();
      final List<ASN1Object>? rp = _children(rsa);
      if (rp == null || rp.length < 2) return null;
      final BigInt mod = (rp[0] as ASN1Integer).valueAsBigInteger;
      final BigInt exp = (rp[1] as ASN1Integer).valueAsBigInteger;
      return RSAPublicKey(mod, exp);
    } catch (_) {
      return null;
    }
  }

  static ASN1Object _findSpki(List<ASN1Object> tbs) {
    for (final ASN1Object el in tbs) {
      if (el.tag != _kTagSequence) continue;
      final List<ASN1Object>? kids = _children(el);
      if (kids == null || kids.length < 2) continue;
      if (kids[1].tag != _kTagBitString) continue;
      final List<int> c = kids[1].contentBytes();
      if (c.isNotEmpty && c[0] == 0x30) {
        return el;
      }
    }
    throw const FormatException('SPKI no encontrado');
  }

  static String _dnToString(ASN1Object name) {
    final List<ASN1Object>? rdns = _children(name);
    if (rdns == null) return '';
    final List<String> parts = <String>[];
    for (final ASN1Object rdn in rdns) {
      final List<ASN1Object>? setKids = _children(rdn);
      if (setKids == null || setKids.isEmpty) continue;
      final ASN1Object atv = setKids.first;
      if (atv.tag != _kTagSequence) continue;
      final List<ASN1Object>? ap = _children(atv);
      if (ap == null || ap.length < 2) continue;
      final String? oid = _oidString(ap[0]);
      final String? val = _stringValue(ap[1]);
      if (val == null || val.isEmpty) continue;
      final String label = _dnOidLabels[oid] ?? oid ?? '?';
      parts.add('$label=$val');
    }
    if (parts.isEmpty) return '';
    final int cn = parts.indexWhere((p) => p.startsWith('CN='));
    if (cn >= 0) {
      final String cnPart = parts[cn];
      final List<String> rest = [...parts]..removeAt(cn);
      return rest.isEmpty ? cnPart : '$cnPart (${rest.join(', ')})';
    }
    return parts.join(', ');
  }

  static String? _stringValue(ASN1Object o) {
    if (o is ASN1UTF8String) return o.utf8StringValue;
    if (o is ASN1PrintableString) return o.stringValue;
    if (o is ASN1IA5String) return o.stringValue;
    if (o is ASN1OctetString) {
      try {
        return o.utf8StringValue;
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  static const Map<String, String> _dnOidLabels = <String, String>{
    '2.5.4.3': 'CN',
    '2.5.4.6': 'C',
    '2.5.4.7': 'L',
    '2.5.4.8': 'ST',
    '2.5.4.10': 'O',
    '2.5.4.11': 'OU',
    '1.2.840.113549.1.9.1': 'emailAddress',
  };

  static DateTime? _asDate(ASN1Object o) {
    if (o is ASN1UtcTime) return o.dateTimeValue;
    if (o is ASN1GeneralizedTime) return o.dateTimeValue;
    return null;
  }
}

// ---------------------------------------------------------------------------
// Tipos internos
// ---------------------------------------------------------------------------

class _RawSignature {
  const _RawSignature({required this.cms, required this.byteRange});
  final Uint8List cms;
  final List<int> byteRange;
}

class _CmsParsed {
  const _CmsParsed({
    required this.digestOid,
    required this.sigAlgOid,
    required this.signature,
    required this.signedAttrsDer,
    required this.messageDigest,
    required this.signingTime,
    required this.certificates,
    required this.parseWarning,
  });

  final String digestOid;
  final String sigAlgOid;
  final Uint8List signature;
  final Uint8List? signedAttrsDer;
  final Uint8List? messageDigest;
  final DateTime? signingTime;
  final List<Uint8List> certificates;
  final String? parseWarning;
}

class _SignedAttrs {
  const _SignedAttrs({this.messageDigest, this.signingTime});
  final Uint8List? messageDigest;
  final DateTime? signingTime;
}

class _ParsedCert {
  const _ParsedCert({
    required this.der,
    required this.subject,
    required this.issuer,
    required this.serialHex,
    required this.validFrom,
    required this.validTo,
    required this.isSelfSigned,
    required this.isCa,
    required this.basicConstraintsPresent,
    required this.ski,
    required this.aki,
    required this.tbs,
    required this.issuerNameDer,
    this.spkiDer,
    this.ocspUrls = const <String>[],
    this.crlUrls = const <String>[],
  });

  final Uint8List der;
  final String subject;
  final String issuer;
  final String serialHex;
  final DateTime? validFrom;
  final DateTime? validTo;
  final bool isSelfSigned;
  final bool isCa;
  final bool basicConstraintsPresent;
  final List<int>? ski;
  final List<int>? aki;
  final List<ASN1Object> tbs;
  final List<int> issuerNameDer;
  final List<int>? spkiDer;
  final List<String> ocspUrls;
  final List<String> crlUrls;

  CertChainNode toNode(DateTime at) {
    final bool timeOk = validFrom != null &&
        validTo != null &&
        !at.isBefore(validFrom!) &&
        !at.isAfter(validTo!);
    return CertChainNode(
      subject: subject,
      issuer: issuer,
      serialHex: serialHex,
      validFrom: validFrom,
      validTo: validTo,
      isSelfSigned: isSelfSigned,
      isCa: isCa,
      basicConstraintsPresent: basicConstraintsPresent,
      validityAtSigning: (validFrom == null || validTo == null)
          ? CertValidity.unknown
          : timeOk
              ? CertValidity.yes
              : CertValidity.no,
      rawDer: der,
      subjectKeyIdentifier: ski,
      authorityKeyIdentifier: aki,
      issuerNameDer: issuerNameDer,
      spkiDer: spkiDer,
      ocspUrls: ocspUrls,
      crlUrls: crlUrls,
    );
  }
}
