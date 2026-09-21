import 'dart:ui';

/// Ubicación de una firma dentro de una página del documento.
///
/// El rectángulo está expresado en **puntos PDF** (coordenadas canónicas
/// del documento, 1 punto = 1/72 de pulgada) y `pageIndex` es 0-based,
/// de forma que las coordenadas coincidan exactamente con las de
/// `PdfSignatureField.bounds` de Syncfusion.
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