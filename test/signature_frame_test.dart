import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signer_app/src/ui/widgets/signature_frame.dart';

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(body: Center(child: SizedBox(width: 200, height: 80, child: child))),
    );

void main() {
  testWidgets('SignatureFrame pending pinta sin anillo ni badge', (tester) async {
    await tester.pumpWidget(_wrap(const SignatureFrame(
      style: SignatureFrameStyle.pending,
      child: SizedBox.expand(),
    )));
    expect(find.byType(CustomPaint), findsWidgets);
    expect(find.text('Firmada'), findsNothing);
  });

  testWidgets('SignatureFrame signed muestra badge «Firmada»', (tester) async {
    await tester.pumpWidget(_wrap(const SignatureFrame(
      style: SignatureFrameStyle.signed,
      badge: 'Firmada',
      badgeColor: Colors.green,
      child: SizedBox.expand(),
    )));
    expect(find.text('Firmada'), findsOneWidget);
    expect(find.byIcon(Icons.verified), findsOneWidget);
  });

  testWidgets('SignatureFrame verify acepta badge de color', (tester) async {
    await tester.pumpWidget(_wrap(const SignatureFrame(
      style: SignatureFrameStyle.verify,
      badge: 'Inválida',
      badgeColor: Colors.red,
      child: SizedBox.expand(),
    )));
    expect(find.text('Inválida'), findsOneWidget);
  });

  test('Estilos tienen opacidades decrecientes coherentes', () {
    // Smoke: enum completo presente.
    expect(SignatureFrameStyle.values, hasLength(5));
    expect(SignatureFrameStyle.values, contains(SignatureFrameStyle.hover));
    expect(SignatureFrameStyle.values, contains(SignatureFrameStyle.selected));
  });
}
