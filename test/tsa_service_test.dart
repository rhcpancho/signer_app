import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:signer_app/src/services/tsa_service.dart';

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

/// TimeStampResp minimal granted + token dummy (SEQ con ContentInfo básico).
Uint8List _grantedResponse() {
  final Uint8List token = _seq(<int>[
    ..._oid('1.2.840.113549.1.7.2'), // signedData
    ..._tlv(0xa0, _seq(<int>[
      ..._tlv(0x02, <int>[1]), // version
      ..._seq(<int>[]), // digestAlgorithms empty
      ..._seq(<int>[
        ..._oid('1.2.840.113549.1.7.1'),
      ]),
      ..._seq(<int>[]), // signerInfos
    ])),
  ]);
  final Uint8List statusInfo = _seq(<int>[
    ..._tlv(0x02, <int>[0]), // granted
  ]);
  return _seq(<int>[
    ...statusInfo,
    ...token,
  ]);
}

Uint8List _rejectedResponse() {
  final Uint8List statusInfo = _seq(<int>[
    ..._tlv(0x02, <int>[1]), // rejection
  ]);
  return _seq(<int>[...statusInfo]);
}

void main() {
  test('buildTimeStampRequest es SEQUENCE con version 1 y SHA-256', () {
    final Uint8List req =
        TsaService.buildTimeStampRequest(<int>[1, 2, 3, 4]);
    expect(req.first, 0x30);
    expect(req.length, greaterThan(40));
    // OID sha-256 2.16.840.1.101.3.4.2.1 debe aparecer en el DER
    final List<int> der = req;
    final String hex = der
        .map((int b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    // 06 09 60 86 48 01 65 03 04 02 01 = SHA-256 OID
    expect(hex.contains('0609608648016503040201'), isTrue);
  });

  test('parseTimeStampResponse granted → TsaResult con token', () {
    final Uint8List resp = _grantedResponse();
    final TsaResult? r = TsaService.parseTimeStampResponse(resp);
    expect(r, isNotNull);
    expect(r!.token, isNotEmpty);
    expect(r.token.first, 0x30);
  });

  test('parseTimeStampResponse rejected → null (soft-fail)', () {
    final TsaResult? r =
        TsaService.parseTimeStampResponse(_rejectedResponse());
    expect(r, isNull);
  });

  test('parseTimeStampResponse garbage → null', () {
    expect(
      TsaService.parseTimeStampResponse(<int>[0x00, 0x01]),
      isNull,
    );
  });

  test('timestamp soft-fail red caída → null', () async {
    final TsaService svc = TsaService(
      client: MockClient(
        (http.Request request) async => throw http.ClientException('down'),
      ),
      timeout: const Duration(seconds: 1),
    );
    final TsaResult? r = await svc.timestamp(
      data: Uint8List.fromList(<int>[9, 9]),
      url: 'http://tsa.invalid',
    );
    expect(r, isNull);
  });

  test('timestamp soft-fail HTTP 500 → null', () async {
    final TsaService svc = TsaService(
      client: MockClient(
        (http.Request request) async => http.Response.bytes(
          <int>[0xde, 0xad],
          500,
        ),
      ),
      timeout: const Duration(seconds: 1),
    );
    final TsaResult? r = await svc.timestamp(
      data: Uint8List.fromList(<int>[1]),
      url: 'http://tsa.example',
    );
    expect(r, isNull);
  });

  test('timestamp OK devuelve granted', () async {
    final Uint8List body = _grantedResponse();
    final TsaService svc = TsaService(
      client: MockClient(
        (http.Request request) async {
          expect(request.headers['Content-Type'],
              'application/timestamp-query');
          expect(request.bodyBytes, isNotEmpty);
          return http.Response.bytes(body, 200);
        },
      ),
      timeout: const Duration(seconds: 1),
    );
    final TsaResult? r = await svc.timestamp(
      data: Uint8List.fromList(<int>[1, 2, 3]),
      url: 'http://tsa.example',
    );
    expect(r, isNotNull);
    expect(r!.token, isNotEmpty);
  });

  test('kDefaultTsaUrl es digicert', () {
    expect(kDefaultTsaUrl, contains('timestamp.digicert.com'));
  });
}
