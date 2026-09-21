import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signer_app/app.dart';

void main() {
  testWidgets('La app arranca y muestra el estado sin documento',
      (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: SignerApp()));

    expect(find.text('Signer App'), findsOneWidget);
    expect(find.text('Abrir PDF'), findsOneWidget);
    expect(find.text('Sin documento cargado'), findsOneWidget);
  });
}