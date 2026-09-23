import 'dart:ui';

/// Conversión de coordenadas entre espacios de página.
///
/// pdfrx expone el tamaño **rotado** (`page.width`/`page.height`, visual) y
/// Syncfusion `PdfSignatureField.bounds` trabaja en el espacio **sin rotar**
/// (CropBox/MediaBox, y hacia abajo desde arriba-izquierda).
///
/// Todas las funciones son puras: `rotationDegrees` es 0, 90, 180 o 270
/// (cualquier otro valor se normaliza con módulo 360).
class PageCoords {
  const PageCoords._();

  /// Tamaño de la página en el espacio de visualización (rotado).
  static Size displaySize(Size unrotated, int rotationDegrees) {
    final int r = normalize(rotationDegrees);
    if (r == 90 || r == 270) {
      return Size(unrotated.height, unrotated.width);
    }
    return unrotated;
  }

  /// Normaliza grados al rango [0, 360).
  static int normalize(int degrees) {
    final int d = degrees % 360;
    return d < 0 ? d + 360 : d;
  }

  /// Convierte [rect] del espacio de visualización (rotado) al sin rotar.
  ///
  /// [unrotatedSize] es el tamaño de página en CropBox/MediaBox.
  static Rect displayToUnrotated({
    required Rect rect,
    required Size unrotatedSize,
    required int rotationDegrees,
  }) {
    switch (normalize(rotationDegrees)) {
      case 90:
        return Rect.fromLTWH(
          rect.top,
          unrotatedSize.height - rect.left - rect.width,
          rect.height,
          rect.width,
        );
      case 180:
        return Rect.fromLTWH(
          unrotatedSize.width - rect.left - rect.width,
          unrotatedSize.height - rect.top - rect.height,
          rect.width,
          rect.height,
        );
      case 270:
        return Rect.fromLTWH(
          unrotatedSize.width - rect.top - rect.height,
          rect.left,
          rect.height,
          rect.width,
        );
      case 0:
      default:
        return rect;
    }
  }

  /// Convierte [rect] del espacio sin rotar al de visualización (rotado).
  ///
  /// [unrotatedSize] es el tamaño de página en CropBox/MediaBox.
  static Rect unrotatedToDisplay({
    required Rect rect,
    required Size unrotatedSize,
    required int rotationDegrees,
  }) {
    switch (normalize(rotationDegrees)) {
      case 90:
        return Rect.fromLTWH(
          unrotatedSize.height - rect.top - rect.height,
          rect.left,
          rect.height,
          rect.width,
        );
      case 180:
        return Rect.fromLTWH(
          unrotatedSize.width - rect.left - rect.width,
          unrotatedSize.height - rect.top - rect.height,
          rect.width,
          rect.height,
        );
      case 270:
        return Rect.fromLTWH(
          rect.top,
          unrotatedSize.width - rect.left - rect.width,
          rect.height,
          rect.width,
        );
      case 0:
      default:
        return rect;
    }
  }
}
