import 'dart:ui';

/// Ubicación de una firma dentro de una página del documento.
///
/// El rectángulo está expresado en **puntos del espacio de visualización**
/// (tamaño rotado de la página de pdfrx, origen arriba-izquierda, y hacia
/// abajo) y `pageIndex` es 0-based. Al firmar se convierte al espacio sin
/// rotar con `PageCoords.displayToUnrotated` para `PdfSignatureField.bounds`.
class SignaturePlacement {
  const SignaturePlacement({
    required this.pageIndex,
    required this.rect,
    required this.profileId,
    this.signed = false,
  });

  SignaturePlacement copyWith({Rect? rect, bool? signed}) {
    return SignaturePlacement(
      pageIndex: pageIndex,
      rect: rect ?? this.rect,
      profileId: profileId,
      signed: signed ?? this.signed,
    );
  }

  final int pageIndex;
  final Rect rect;

  /// Identificador del certificado de firma que sella esta zona.
  final String profileId;
  final bool signed;
}