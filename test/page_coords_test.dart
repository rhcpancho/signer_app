import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:signer_app/src/models/page_coords.dart';

void main() {
  const Size unrotated = Size(612, 792);

  group('displaySize', () {
    test('rotación 0 y 180 mantienen el tamaño', () {
      expect(PageCoords.displaySize(unrotated, 0), unrotated);
      expect(PageCoords.displaySize(unrotated, 180), unrotated);
    });

    test('rotación 90 y 270 intercambian ancho/alto', () {
      expect(PageCoords.displaySize(unrotated, 90), const Size(792, 612));
      expect(PageCoords.displaySize(unrotated, 270), const Size(792, 612));
    });

    test('normaliza grados fuera de rango', () {
      expect(PageCoords.normalize(-90), 270);
      expect(PageCoords.normalize(450), 90);
    });
  });

  group('round-trip displayToUnrotated ↔ unrotatedToDisplay', () {
    const Rect sample = Rect.fromLTWH(50, 60, 220, 96);

    for (final int rotation in <int>[0, 90, 180, 270]) {
      test('rotación $rotation°', () {
        final Rect display = PageCoords.unrotatedToDisplay(
          rect: sample,
          unrotatedSize: unrotated,
          rotationDegrees: rotation,
        );
        final Rect back = PageCoords.displayToUnrotated(
          rect: display,
          unrotatedSize: unrotated,
          rotationDegrees: rotation,
        );
        expect(back.left, closeTo(sample.left, 1e-9));
        expect(back.top, closeTo(sample.top, 1e-9));
        expect(back.width, closeTo(sample.width, 1e-9));
        expect(back.height, closeTo(sample.height, 1e-9));
      });
    }
  });

  group('rotación 90° (página apaisada en display)', () {
    test('unrotatedToDisplay coloca el origen correctamente', () {
      // Página sin rotar 612×792; display 792×612.
      // Esquina superior-izquierda sin rotar → superior-derecha en display
      // (giro horario 90°).
      final Rect display = PageCoords.unrotatedToDisplay(
        rect: const Rect.fromLTWH(0, 0, 10, 20),
        unrotatedSize: unrotated,
        rotationDegrees: 90,
      );
      // left = Hu - top - h = 792 - 0 - 20 = 772; top = left = 0
      expect(display.left, 772);
      expect(display.top, 0);
      expect(display.width, 20);
      expect(display.height, 10);
    });

    test('displayToUnrotated invierte un rect en display', () {
      const Rect display = Rect.fromLTWH(772, 0, 20, 10);
      final Rect unrot = PageCoords.displayToUnrotated(
        rect: display,
        unrotatedSize: unrotated,
        rotationDegrees: 90,
      );
      expect(unrot.left, 0);
      expect(unrot.top, 0);
      expect(unrot.width, 10);
      expect(unrot.height, 20);
    });
  });

  group('rotación 180°', () {
    test('esquina superior-izquierda sin rotar → inferior-derecha', () {
      final Rect display = PageCoords.unrotatedToDisplay(
        rect: const Rect.fromLTWH(0, 0, 10, 20),
        unrotatedSize: unrotated,
        rotationDegrees: 180,
      );
      expect(display.left, 612 - 10);
      expect(display.top, 792 - 20);
      expect(display.width, 10);
      expect(display.height, 20);
    });
  });

  group('rotación 270°', () {
    test('unrotatedToDisplay', () {
      final Rect display = PageCoords.unrotatedToDisplay(
        rect: const Rect.fromLTWH(0, 0, 10, 20),
        unrotatedSize: unrotated,
        rotationDegrees: 270,
      );
      // left = top = 0; top = Wu - left - w = 612 - 0 - 10 = 602
      expect(display.left, 0);
      expect(display.top, 602);
      expect(display.width, 20);
      expect(display.height, 10);
    });
  });

  group('rotación 0°', () {
    test('identidad', () {
      const Rect sample = Rect.fromLTWH(1, 2, 3, 4);
      expect(
        PageCoords.displayToUnrotated(
          rect: sample,
          unrotatedSize: unrotated,
          rotationDegrees: 0,
        ),
        sample,
      );
      expect(
        PageCoords.unrotatedToDisplay(
          rect: sample,
          unrotatedSize: unrotated,
          rotationDegrees: 0,
        ),
        sample,
      );
    });
  });
}
