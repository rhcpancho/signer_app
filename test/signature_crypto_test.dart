import 'dart:typed_data';

import 'package:asn1lib/asn1lib.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signer_app/src/models/signature_chain.dart';
import 'package:signer_app/src/services/signature_crypto.dart';

Uint8List _tlv(int tag, List<int> value) {
  if (value.length < 0x80) {
    return Uint8List.fromList(<int>[tag, value.length, ...value]);
  }
  final List<int> lenBytes = <int>[];
  int n = value.length;
  while (n > 0) {
    lenBytes.insert(0, n & 0xff);
    n >>= 8;
  }
  return Uint8List.fromList(
    <int>[tag, 0x80 | lenBytes.length, ...lenBytes, ...value],
  );
}

Uint8List _seq(List<int> children) => _tlv(0x30, children);
Uint8List _set(List<int> children) => _tlv(0x31, children);

Uint8List _oid(String dotted) {
  final List<int> parts =
      dotted.split('.').map((String s) => int.parse(s)).toList();
  final List<int> body = <int>[parts[0] * 40 + parts[1]];
  for (int i = 2; i < parts.length; i++) {
    int v = parts[i];
    final List<int> tmp = <int>[v & 0x7f];
    v >>= 7;
    while (v > 0) {
      tmp.insert(0, 0x80 | (v & 0x7f));
      v >>= 7;
    }
    body.addAll(tmp);
  }
  return _tlv(0x06, body);
}

Uint8List _integer(BigInt v) {
  final List<int> bytes = <int>[];
  BigInt n = v;
  while (n > BigInt.zero) {
    bytes.insert(0, (n & BigInt.from(0xff)).toInt());
    n >>= 8;
  }
  if (bytes.isEmpty) bytes.add(0);
  if ((bytes.first & 0x80) != 0) bytes.insert(0, 0);
  return _tlv(0x02, bytes);
}

Uint8List _integerInt(int v) => _integer(BigInt.from(v));
Uint8List _octet(List<int> data) => _tlv(0x04, data);
Uint8List _bitString(List<int> data) => _tlv(0x03, <int>[0, ...data]);
Uint8List _null() => Uint8List.fromList(const <int>[0x05, 0x00]);
Uint8List _boolTrue() => Uint8List.fromList(const <int>[0x01, 0xff]);
Uint8List _utf8(String s) => _tlv(0x0c, s.codeUnits);
Uint8List _ctx0(List<int> inner) => _tlv(0xa0, inner);
Uint8List _ctx3(List<int> inner) => _tlv(0xa3, inner);
Uint8List _algId(String oid) => _seq(<int>[..._oid(oid), ..._null()]);

Uint8List _name(String cn) {
  final Uint8List atv = _seq(<int>[..._oid('2.5.4.3'), ..._utf8(cn)]);
  return _seq(<int>[..._tlv(0x31, atv)]);
}

String _utc(DateTime d) {
  final String y = d.year.toString().padLeft(4, '0').substring(2);
  final String mo = d.month.toString().padLeft(2, '0');
  final String da = d.day.toString().padLeft(2, '0');
  final String h = d.hour.toString().padLeft(2, '0');
  final String mi = d.minute.toString().padLeft(2, '0');
  final String s = d.second.toString().padLeft(2, '0');
  return '$y$mo$da$h$mi${s}Z';
}

Uint8List _validity({required DateTime from, required DateTime to}) =>
    _seq(<int>[
      ..._tlv(0x17, _utc(from).codeUnits),
      ..._tlv(0x17, _utc(to).codeUnits),
    ]);

Uint8List _spki(BigInt mod, BigInt exp) {
  final Uint8List alg =
      _seq(<int>[..._oid('1.2.840.113549.1.1.1'), ..._null()]);
  final Uint8List rsa = _seq(<int>[..._integer(mod), ..._integer(exp)]);
  return _seq(<int>[...alg, ..._bitString(rsa)]);
}

Uint8List _makeCert({
  required String subject,
  required String issuer,
  required int serial,
  required BigInt mod,
  required bool ca,
  DateTime? from,
  DateTime? to,
}) {
  final Uint8List tbs = _seq(<int>[
    ..._ctx0(_integerInt(2)),
    ..._integerInt(serial),
    ..._algId('2.16.840.1.101.3.4.2.1'),
    ..._name(issuer),
    ..._validity(
      from: from ?? DateTime.utc(2020, 1, 1),
      to: to ?? DateTime.utc(2048, 1, 1),
    ),
    ..._name(subject),
    ..._spki(mod, BigInt.from(65537)),
    ..._ctx3(_seq(<int>[
      ..._seq(<int>[
        ..._oid('2.5.29.19'),
        ..._octet(ca ? _seq(<int>[..._boolTrue()]) : _seq(<int>[])),
      ]),
    ])),
  ]);
  final Uint8List alg = _algId('1.2.840.113549.1.1.11');
  final Uint8List sig = _bitString(List<int>.filled(64, 0x11));
  return _seq(<int>[
    ...tbs,
    ...alg,
    ...sig,
  ]);
}

Uint8List _signedAttrs({required List<int> messageDigest, DateTime? signingTime}) {
  final Uint8List mdAttr = _seq(<int>[
    ..._oid('1.2.840.113549.1.9.4'),
    ..._octet(messageDigest),
  ]);
  final List<int> children = <int>[...mdAttr];
  if (signingTime != null) {
    children.addAll(_seq(<int>[
      ..._oid('1.2.840.113549.1.9.5'),
      ..._tlv(0x17, _utc(signingTime).codeUnits),
    ]));
  }
  return _set(children);
}

Uint8List _buildCms({
  required Uint8List cert,
  required Uint8List signedAttrsSet,
  required List<int> signature,
  String digestOid = '2.16.840.1.101.3.4.2.1',
}) {
  final ASN1Object parsed = ASN1Parser(signedAttrsSet).nextObject();
  final Uint8List attrsValue = parsed.valueBytes();
  final Uint8List signedAttrsA0 = Uint8List.fromList(
    <int>[0xa0, ...ASN1Object.encodeLength(attrsValue.length), ...attrsValue],
  );

  final Uint8List signerInfo = _seq(<int>[
    ..._integerInt(1),
    ..._octet(List<int>.filled(20, 1)),
    ..._algId(digestOid),
    ...signedAttrsA0,
    ..._algId('1.2.840.113549.1.1.11'),
    ..._octet(signature),
  ]);

  // certificates [0] IMPLICIT: hijos = Certificate SEQUENCEs (sin SET wrapper)
  final Uint8List digestAlgs = _set(_algId(digestOid));
  final Uint8List eci = _seq(<int>[..._oid('1.2.840.113549.1.7.1')]);
  final Uint8List signerInfos = _set(signerInfo);
  final Uint8List signedData = _seq(<int>[
    ..._integerInt(1),
    ...digestAlgs,
    ...eci,
    ..._ctx0(cert),
    ...signerInfos,
  ]);

  final Uint8List contentType = _oid('1.2.840.113549.1.7.2');
  return _seq(<int>[
    ...contentType,
    ..._ctx0(signedData),
  ]);
}

void main() {
  final SignatureCryptoService svc = SignatureCryptoService();

  test('garbage CMS no lanza y devuelve error', () {
    final SignatureChainInfo info = svc.analyse(
      cmsBytes: Uint8List.fromList(const <int>[0x01, 0x02, 0x03, 0x04]),
      documentBytes: Uint8List.fromList(const <int>[0x00]),
      byteRange: <int>[0, 1, 1, 1],
    );
    expect(info.error, isNotNull);
    expect(info.signatureValidates, isNull);
    expect(info.chainComplete, isFalse);
    expect(info.chainNodes, isEmpty);
  });

  test('ByteRange inválido → integridad false', () {
    final Uint8List cert = _makeCert(
      subject: 'CN=Test',
      issuer: 'CN=Test',
      serial: 1,
      mod: BigInt.from(65537),
      ca: true,
    );
    final Uint8List cms = _buildCms(
      cert: cert,
      signedAttrsSet:
          _signedAttrs(messageDigest: List<int>.filled(32, 0)),
      signature: List<int>.filled(64, 0x22),
    );

    final SignatureChainInfo info = svc.analyse(
      cmsBytes: cms,
      documentBytes: Uint8List.fromList(List<int>.filled(32, 0x41)),
      byteRange: <int>[5, 10, 10, 20],
    );
    expect(info.documentIntegrityOk, isFalse);
    expect(info.signatureValidates, isFalse);
    expect(info.digestAlgorithmOid, '2.16.840.1.101.3.4.2.1');
  });

  test('cadena self-signed con CA=true se marca completa', () {
    final Uint8List cert = _makeCert(
      subject: 'CN=Root CA',
      issuer: 'CN=Root CA',
      serial: 10,
      mod: BigInt.parse(
        'c5548a919c9d7e0e1e3b4e4d1c0a9f8b7a6d5c4b3a29180706050403020100ff',
        radix: 16,
      ),
      ca: true,
    );
    final Uint8List cms = _buildCms(
      cert: cert,
      signedAttrsSet: _signedAttrs(
        messageDigest: List<int>.filled(32, 0xaa),
        signingTime: DateTime.utc(2024, 5, 1, 12, 0, 0),
      ),
      signature: List<int>.filled(64, 0x33),
    );

    final SignatureChainInfo info = svc.analyse(
      cmsBytes: cms,
      documentBytes: Uint8List.fromList(List<int>.filled(64, 0x42)),
      byteRange: <int>[0, 16, 48, 64],
    );

    expect(info.error, isNull);
    expect(info.chainNodes, hasLength(1));
    expect(info.chainComplete, isTrue);
    expect(info.chainNodes.single.subject, contains('Root CA'));
    expect(info.chainNodes.single.isCa, isTrue);
    expect(info.chainNodes.single.isSelfSigned, isTrue);
    expect(info.signingTime, isNotNull);
    expect(info.signatureCryptographicOk, isNot(true));
    expect(info.documentIntegrityOk, isFalse);
    expect(info.signatureValidates, isFalse);
  });

  test('integridad true cuando messageDigest coincide con ByteRange', () {
    final Uint8List cert = _makeCert(
      subject: 'CN=Leaf',
      issuer: 'CN=Leaf',
      serial: 2,
      mod: BigInt.from(0xdeadbeef),
      ca: false,
    );
    final Uint8List doc = Uint8List.fromList(List<int>.filled(80, 0x5a));
    final List<int> covered = <int>[
      ...doc.sublist(0, 20),
      ...doc.sublist(60, 80),
    ];
    final List<int> md = sha256.convert(covered).bytes;

    final Uint8List cms = _buildCms(
      cert: cert,
      signedAttrsSet: _signedAttrs(messageDigest: md),
      signature: List<int>.filled(64, 0x44),
    );

    final SignatureChainInfo info = svc.analyse(
      cmsBytes: cms,
      documentBytes: doc,
      byteRange: <int>[0, 20, 60, 80],
    );

    expect(info.documentIntegrityOk, isTrue);
    expect(info.chainNodes, hasLength(1));
    expect(info.chainNodes.single.isSelfSigned, isTrue);
    expect(info.signatureCryptographicOk, isNot(true));
    // Integridad ok + crypto no evaluado → tri-state null (no false).
    expect(info.signatureValidates, isNull);
  });
}
