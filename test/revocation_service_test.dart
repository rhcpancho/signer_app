import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:signer_app/src/models/signature_chain.dart';
import 'package:signer_app/src/services/revocation_service.dart';

CertChainNode _node({
  String serialHex = 'ABCD',
  List<String> ocspUrls = const <String>[],
  List<String> crlUrls = const <String>[],
  List<int>? issuerNameDer,
  List<int>? spkiDer,
  bool isSelfSigned = false,
}) {
  return CertChainNode(
    subject: 'CN=Leaf',
    issuer: 'CN=CA',
    serialHex: serialHex,
    validFrom: DateTime.utc(2020),
    validTo: DateTime.utc(2030),
    isSelfSigned: isSelfSigned,
    isCa: false,
    basicConstraintsPresent: true,
    validityAtSigning: CertValidity.yes,
    rawDer: const <int>[0x30, 0x00],
    issuerNameDer: issuerNameDer,
    spkiDer: spkiDer,
    ocspUrls: ocspUrls,
    crlUrls: crlUrls,
  );
}

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

Uint8List _seq(List<int> c) => _tlv(0x30, c);

/// OCSPResponse minimal: successful + BasicOCSPResponse con certStatus good.
Uint8List _ocspGoodResponse() {
  final Uint8List certId = _seq(<int>[
    ..._oid('1.3.14.3.2.26'),
    ..._tlv(0x04, <int>[1, 2, 3]),
    ..._tlv(0x04, <int>[4, 5, 6]),
    // Serial 0xABCD como INTEGER DER positivo (prefijo 0x00 por bit alto)
    ..._tlv(0x02, <int>[0x00, 0xAB, 0xCD]),
  ]);
  final Uint8List single = _seq(<int>[
    ...certId,
    0x80, 0x00, // good [0] NULL
    ..._tlv(0x18, '20260101000000Z'.codeUnits),
  ]);
  final Uint8List responses = _seq(single);
  final Uint8List responderId = _tlv(0xa2, <int>[1, 2, 3]);
  final Uint8List tbs = _seq(<int>[
    ...responderId,
    ..._tlv(0x18, '20260101000000Z'.codeUnits),
    ...responses,
  ]);
  final Uint8List basic = _seq(<int>[
    ...tbs,
    ..._seq(<int>[
      ..._oid('1.2.840.113549.1.1.11'),
      0x05, 0x00,
    ]),
    ..._tlv(0x03, <int>[0x00, 0x00]),
  ]);
  final Uint8List respBytes = _seq(<int>[
    ..._oid('1.3.6.1.5.5.7.48.1.1'),
    ..._tlv(0x04, basic),
  ]);
  return _seq(<int>[
    0x0a, 0x01, 0x00, // ENUMERATED successful(0)
    ..._tlv(0xa0, respBytes),
  ]);
}

Uint8List _ocspRevokedResponse() {
  final Uint8List certId = _seq(<int>[
    ..._oid('1.3.14.3.2.26'),
    ..._tlv(0x04, <int>[1, 2, 3]),
    ..._tlv(0x04, <int>[4, 5, 6]),
    ..._tlv(0x02, <int>[0x00, 0xAB, 0xCD]),
  ]);
  // revoked [1] IMPLICIT RevokedInfo: GeneralizedTime thisRevocation
  final Uint8List certStatus = _tlv(0xa1, _tlv(0x18, '20260101000000Z'.codeUnits).toList());
  final Uint8List single = _seq(<int>[
    ...certId,
    ...certStatus,
    ..._tlv(0x18, '20260101000000Z'.codeUnits),
  ]);
  final Uint8List tbs = _seq(<int>[
    ..._tlv(0xa2, <int>[1, 2, 3]),
    ..._tlv(0x18, '20260101000000Z'.codeUnits),
    ..._seq(single),
  ]);
  final Uint8List basic = _seq(<int>[
    ...tbs,
    ..._seq(<int>[..._oid('1.2.840.113549.1.1.11'), 0x05, 0x00]),
    ..._tlv(0x03, <int>[0x00, 0x00]),
  ]);
  final Uint8List respBytes = _seq(<int>[
    ..._oid('1.3.6.1.5.5.7.48.1.1'),
    ..._tlv(0x04, basic),
  ]);
  return _seq(<int>[0x0a, 0x01, 0x00, ..._tlv(0xa0, respBytes)]);
}

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

void main() {
  test('buildOcspRequest devuelve SEQUENCE no vacía cuando hay issuer', () {
    final CertChainNode leaf = _node(
      issuerNameDer: _seq(<int>[0x31, 0x00]),
      spkiDer: null,
    );
    final CertChainNode issuer = _node(
      spkiDer: _seq(<int>[
        ..._seq(<int>[0x06, 0x03, 0x2a, 0x03, 0x04]),
        ..._tlv(0x03, <int>[0x00, 0x30, 0x02, 0x01, 0x01]),
      ]),
    );
    final Uint8List? req =
        RevocationService.buildOcspRequest(node: leaf, issuer: issuer);
    expect(req, isNotNull);
    expect(req!.first, 0x30);
    expect(req.length, greaterThan(10));
  });

  test('buildOcspRequest null si falta spki del emisor', () {
    final CertChainNode leaf = _node(issuerNameDer: <int>[0x30]);
    expect(RevocationService.buildOcspRequest(node: leaf, issuer: null),
        isNull);
  });

  test('parseOcspResponse good → yes', () {
    final Uint8List resp = _ocspGoodResponse();
    final CertValidity? v =
        RevocationService.parseOcspResponse(resp, serialHex: 'abcd');
    expect(v, isNotNull);
    expect(v!.value, isTrue);
  });

  test('parseOcspResponse revoked → no', () {
    final Uint8List resp = _ocspRevokedResponse();
    final CertValidity? v =
        RevocationService.parseOcspResponse(resp, serialHex: 'ABCD');
    expect(v, isNotNull);
    expect(v!.value, isFalse);
  });

  test('parseOcspResponse garbage → null (soft-fail)', () {
    expect(
      RevocationService.parseOcspResponse(
        <int>[0x00, 0x01, 0x02],
        serialHex: 'AB',
      ),
      isNull,
    );
  });

  test('checkChain soft-fail offline → unknown', () async {
    final MockClient client = MockClient(
      (http.Request request) async => http.Response.bytes(
        <int>[0xde, 0xad],
        500,
      ),
    );
    final RevocationService svc =
        RevocationService(client: client, timeout: const Duration(seconds: 1));
    final RevocationCheck r = await svc.checkChain(<CertChainNode>[
      _node(
        ocspUrls: const <String>['http://ocsp.invalid'],
        issuerNameDer: _seq(<int>[0x31, 0x00]),
      ),
      _node(isSelfSigned: true, spkiDer: _seq(<int>[0x06, 0x01, 0x00])),
    ]);
    expect(r.status.value, isNull);
    expect(r.revokedCount, 0);
  });

  test('checkChain sin URLs → unknown con nota', () async {
    final RevocationService svc = RevocationService(
      client: MockClient((_) async => http.Response('', 500)),
    );
    final RevocationCheck r = await svc.checkChain(<CertChainNode>[
      _node(),
      _node(isSelfSigned: true),
    ]);
    expect(r.status.value, isNull);
    expect(r.note, contains('URLs'));
  });

  test('checkChain solo raíz → unknown', () async {
    final RevocationService svc = RevocationService();
    final RevocationCheck r =
        await svc.checkChain(<CertChainNode>[_node(isSelfSigned: true)]);
    expect(r.status.value, isNull);
  });

  test('RevocationCheck unknown const', () {
    expect(RevocationCheck.unknown.status.value, isNull);
  });
}
