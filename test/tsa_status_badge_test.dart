import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signer_app/src/services/tsa_service.dart';
import 'package:signer_app/src/ui/widgets/tsa_status_badge.dart';

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  testWidgets('notRequested no renderiza nada', (tester) async {
    await tester.pumpWidget(_wrap(
      const TsaStatusBadge(status: TsaStatus.notRequested),
    ));
    expect(find.byType(TsaStatusBadge), findsOneWidget);
    expect(find.textContaining('TSA'), findsNothing);
    expect(find.byIcon(Icons.schedule), findsNothing);
  });

  testWidgets('granted muestra chip verde con fecha y nombre',
      (tester) async {
    final TsaResult result = TsaResult(
      token: Uint8List.fromList(<int>[1]),
      genTime: DateTime.utc(2026, 9, 23, 14, 30),
      tsaName: 'DigiCert Timestamping Authority',
    );
    await tester.pumpWidget(_wrap(
      TsaStatusBadge(status: TsaStatus.granted, result: result),
    ));
    expect(find.byIcon(Icons.schedule), findsOneWidget);
    expect(find.textContaining('TSA 23/09/2026 14:30'), findsOneWidget);
    expect(find.textContaining('DigiCert'), findsOneWidget);
  });

  testWidgets('granted sin genTime muestra «ok»', (tester) async {
    final TsaResult result = TsaResult(token: Uint8List.fromList(<int>[1]));
    await tester.pumpWidget(_wrap(
      TsaStatusBadge(status: TsaStatus.granted, result: result),
    ));
    expect(find.textContaining('TSA ok'), findsOneWidget);
  });

  testWidgets('failed muestra chip ámbar de soft-fail', (tester) async {
    await tester.pumpWidget(_wrap(
      const TsaStatusBadge(status: TsaStatus.failed),
    ));
    expect(
      find.text('Sello de tiempo no obtenido (soft-fail)'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.schedule), findsOneWidget);
  });

  testWidgets('failed dense muestra texto corto', (tester) async {
    await tester.pumpWidget(_wrap(
      const TsaStatusBadge(status: TsaStatus.failed, dense: true),
    ));
    expect(find.text('TSA no obtenido'), findsOneWidget);
  });

  test('enum TsaStatus tiene los 3 estados', () {
    expect(TsaStatus.values, hasLength(3));
    expect(TsaStatus.values, contains(TsaStatus.notRequested));
    expect(TsaStatus.values, contains(TsaStatus.granted));
    expect(TsaStatus.values, contains(TsaStatus.failed));
  });
}
