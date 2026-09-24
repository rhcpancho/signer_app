import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signer_app/src/ui/home/open_password_dialog.dart';
import 'package:signer_app/src/ui/home/overwrite_save_dialog.dart';

void main() {
  group('showOpenPasswordDialog', () {
    testWidgets('Cancelar devuelve null', (WidgetTester tester) async {
      late Future<String?> result;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (BuildContext context) {
            return FilledButton(
              onPressed: () => result = showOpenPasswordDialog(context),
              child: const Text('abrir'),
            );
          },
        ),
      ));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      expect(find.text('PDF protegido'), findsOneWidget);

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(await result, isNull);
    });

    testWidgets('Aceptar con contraseña devuelve el texto',
        (WidgetTester tester) async {
      late Future<String?> result;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (BuildContext context) {
            return FilledButton(
              onPressed: () => result = showOpenPasswordDialog(context),
              child: const Text('abrir'),
            );
          },
        ),
      ));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'secreta123');
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      expect(await result, 'secreta123');
    });

    testWidgets('Aceptar vacío muestra error y no cierra',
        (WidgetTester tester) async {
      late Future<String?> result;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (BuildContext context) {
            return FilledButton(
              onPressed: () => result = showOpenPasswordDialog(context),
              child: const Text('abrir'),
            );
          },
        ),
      ));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      expect(find.text('Introduce la contraseña.'), findsOneWidget);
      expect(find.text('PDF protegido'), findsOneWidget);
      // El futuro no debe completarse todavía.
      expect(tester.widget<FilledButton>(find.byType(FilledButton).last),
          isNotNull);
      // Cierra para no dejar el futuro colgado.
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(await result, isNull);
    });
  });

  group('showOverwriteSaveDialog', () {
    Future<OverwriteDecision?> pumpAndTap(
      WidgetTester tester,
      String button, {
      bool checkApplyToAll = false,
      bool showApplyToAll = false,
    }) async {
      late Future<OverwriteDecision?> result;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (BuildContext context) {
            return FilledButton(
              onPressed: () => result = showOverwriteSaveDialog(
                context,
                path: r'C:\docs\contrato_firmado.pdf',
                showApplyToAll: showApplyToAll,
              ),
              child: const Text('abrir'),
            );
          },
        ),
      ));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      if (checkApplyToAll) {
        await tester.tap(find.text('Aplicar a todo el lote'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text(button));
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('Sobrescribir devuelve overwrite sin applyToAll',
        (WidgetTester tester) async {
      final OverwriteDecision? d = await pumpAndTap(tester, 'Sobrescribir');
      expect(d, isNotNull);
      expect(d!.choice, OverwriteChoice.overwrite);
      expect(d.applyToAll, isFalse);
    });

    testWidgets('Renombrar devuelve rename', (WidgetTester tester) async {
      final OverwriteDecision? d = await pumpAndTap(tester, 'Renombrar');
      expect(d!.choice, OverwriteChoice.rename);
      expect(d.applyToAll, isFalse);
    });

    testWidgets('Cancelar devuelve cancel', (WidgetTester tester) async {
      final OverwriteDecision? d = await pumpAndTap(tester, 'Cancelar');
      expect(d!.choice, OverwriteChoice.cancel);
      expect(d.applyToAll, isFalse);
    });

    testWidgets('applyToAll en checkbox se propaga en overwrite',
        (WidgetTester tester) async {
      final OverwriteDecision? d = await pumpAndTap(
        tester,
        'Sobrescribir',
        checkApplyToAll: true,
        showApplyToAll: true,
      );
      expect(d!.choice, OverwriteChoice.overwrite);
      expect(d.applyToAll, isTrue);
    });

    testWidgets('applyToAll no se propaga en cancel',
        (WidgetTester tester) async {
      final OverwriteDecision? d = await pumpAndTap(
        tester,
        'Cancelar',
        checkApplyToAll: true,
        showApplyToAll: true,
      );
      expect(d!.choice, OverwriteChoice.cancel);
      expect(d.applyToAll, isFalse);
    });

    testWidgets('sin showApplyToAll no hay checkbox',
        (WidgetTester tester) async {
      late Future<OverwriteDecision?> result;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (BuildContext context) {
            return FilledButton(
              onPressed: () => result = showOverwriteSaveDialog(
                context,
                path: '/tmp/x_firmado.pdf',
              ),
              child: const Text('abrir'),
            );
          },
        ),
      ));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      expect(find.text('Aplicar a todo el lote'), findsNothing);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect((await result)!.choice, OverwriteChoice.cancel);
    });
  });
}
