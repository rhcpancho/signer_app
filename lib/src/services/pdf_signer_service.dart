import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../models/batch_job.dart';
import '../models/certificate_profile.dart';
import '../models/page_coords.dart';
import '../models/signature_chain.dart';
import '../models/signature_placement.dart';
import 'revocation_service.dart';
import 'signature_crypto.dart';

/// Describe una firma a aplicar: certificado + zona + contraseña del PFX.
class SignRequest {
  const SignRequest({
    required this.placement,
    required this.profile,
    this.certificatePassword,
  });

  final SignaturePlacement placement;
  final CertificateProfile profile;
  final String? certificatePassword;
}

/// Resumen del estado de los campos de firma de un PDF.
class PdfSignatureReport {
  const PdfSignatureReport({required this.signed, required this.pending});

  final int signed;
  final int pending;
}

/// Estado individual de un campo de firma para verificación.
class PdfSignatureFieldInfo {
  const PdfSignatureFieldInfo({
    required this.name,
    required this.pageIndex,
    required this.hasSignature,
    this.signedDate,
    this.signedName,
    this.reason,
    this.locationInfo,
    this.certSubject,
    this.certIssuer,
    this.certValidFrom,
    this.certValidTo,
    this.digestAlgorithm,
    this.bounds,
    this.unrotatedPageSize,
    this.rotationDegrees = 0,
    this.chainInfo,
    this.contactInfo,
  });

  final String? name;
  final int? pageIndex;
  final bool hasSignature;
  final DateTime? signedDate;

  /// Nombre del firmante en la firma.
  final String? signedName;

  /// Motivo de la firma.
  final String? reason;

  /// Lugar de la firma.
  final String? locationInfo;

  /// Subject (CN) del certificado X.509.
  final String? certSubject;

  /// Emisor del certificado.
  final String? certIssuer;

  /// Fecha de inicio de validez del certificado.
  final DateTime? certValidFrom;

  /// Fecha de expiración del certificado.
  final DateTime? certValidTo;

  /// Algoritmo de digest (SHA256, SHA384...).
  final String? digestAlgorithm;

  /// Rectángulo del campo de firma en puntos PDF (para resaltado).
  final Rect? bounds;

  /// Tamaño de página sin rotar (Syncfusion `page.size`), si se conoce.
  final Size? unrotatedPageSize;

  /// Rotación de la página en grados (0, 90, 180, 270).
  final int rotationDegrees;

  /// Análisis CMS/X.509 de la firma (integridad, crypto, cadena).
  /// `null` si el campo no tiene CMS extraíble (p. ej. solo visual).
  final SignatureChainInfo? chainInfo;

  /// Contacto (`/ContactInfo`) del campo de firma, si se guardó al firmar.
  final String? contactInfo;
}

/// Detalle por campo de la verificación de firmas de un PDF.
class PdfSignatureDetailReport {
  const PdfSignatureDetailReport({
    required this.fields,
    required this.signed,
    required this.pending,
  });

  final List<PdfSignatureFieldInfo> fields;
  final int signed;
  final int pending;
}

/// Motor que incrusta firmas digitales (X.509) y visuales en un PDF.
class PdfSignerService {
  /// Devuelve el nombre (CN) del subject del PFX abrible con `password`.
  ///
  /// Si no se puede leer, devuelve `''`.
  String certificateSubject(String path, String password) {
    if (path.isEmpty) return '';
    final File file = File(path);
    if (!file.existsSync()) return '';
    try {
      return PdfCertificate(file.readAsBytesSync(), password).subjectName;
    } catch (_) {
      return '';
    }
  }

  /// Comprueba que `path` apunte a un PFX/P12 abrible con `password`.
  ///
  /// Devuelve `true` si el certificado se abre correctamente; en caso contrario
  /// lanza [ArgumentError] con un mensaje amigable.
  bool validateCertificate(String path, String password) {
    final File file = File(path);
    if (!file.existsSync()) {
      throw StateError('El certificado no existe: $path');
    }
    try {
      PdfCertificate(file.readAsBytesSync(), password);
    } catch (_) {
      throw ArgumentError(
          'Contraseña incorrecta o el archivo PFX/P12 no es válido.');
    }
    return true;
  }

  static int _syncfusionRotationDegrees(PdfPageRotateAngle rotation) {
    switch (rotation) {
      case PdfPageRotateAngle.rotateAngle90:
        return 90;
      case PdfPageRotateAngle.rotateAngle180:
        return 180;
      case PdfPageRotateAngle.rotateAngle270:
        return 270;
      case PdfPageRotateAngle.rotateAngle0:
        return 0;
    }
  }

  /// Firma `inputBytes` aplicando todas las [SignRequest].
  ///
  /// Devuelve los bytes del PDF firmado. El documento original no cambia.
  /// [openPassword] permite firmar PDFs cifrados con contraseña.
  ///
  /// El alto del campo en el PDF se adapta al contenido de la apariencia
  /// (filas de texto o aspecto de la rúbrica); el ancho y la posición
  /// superior-izquierda del [SignRequest.placement] se respetan y el
  /// resultado se recorta/ajusta para no salirse de la página.
  Future<Uint8List> sign({
    required Uint8List inputBytes,
    required List<SignRequest> requests,
    String? openPassword,
  }) async {
    assert(requests.isNotEmpty, 'No hay firmas que aplicar');

    final PdfDocument document = PdfDocument(
      inputBytes: inputBytes,
      password: openPassword,
    );

    try {
      for (int i = 0; i < requests.length; i++) {
        final SignRequest request = requests[i];
        final PdfPage page = document.pages[request.placement.pageIndex];
        final int rotation = _syncfusionRotationDegrees(page.rotation);
        final Size unrotatedSize = page.size;
        final Size displayPageSize =
            PageCoords.displaySize(unrotatedSize, rotation);

        final Rect displayRect = _contentFittedDisplayRect(
          placement: request.placement,
          profile: request.profile,
          pageDisplaySize: displayPageSize,
        );

        final Rect bounds = PageCoords.displayToUnrotated(
          rect: displayRect,
          unrotatedSize: unrotatedSize,
          rotationDegrees: rotation,
        );

        final PdfSignatureField field = PdfSignatureField(
          page,
          'Signature$i',
          bounds: bounds,
        );

        final PdfCertificate? certificate = _buildCertificate(request);

        if (certificate != null) {
          field.signature = PdfSignature(
            certificate: certificate,
            signedName: request.profile.name,
            reason:
                request.profile.reason.isEmpty ? null : request.profile.reason,
            contactInfo: request.profile.contact.isEmpty
                ? null
                : request.profile.contact,
            locationInfo: request.profile.location.isEmpty
                ? null
                : request.profile.location,
            digestAlgorithm: DigestAlgorithm.sha256,
            cryptographicStandard: CryptographicStandard.cms,
          );
        }

        if (request.profile.signatureBytes.isNotEmpty) {
          _drawRubricAppearance(field, request.profile, bounds);
        } else if (certificate != null) {
          _drawTextAppearance(
            field,
            request.profile,
            bounds,
          );
        }

        document.form.fields.add(field);
      }

      return Uint8List.fromList(await document.save());
    } finally {
      document.dispose();
    }
  }

  /// Tamaño de fuente preferente (pt) para la apariencia de texto.
  static const double kTextAppearanceFontSize = 8.0;

  /// Altura mínima del marco impreso (pt) para que el doble borde quepa.
  static const double kMinAppearanceHeight = 16.0;

  static const double _padX = 7.0;
  static const double _labelFraction = 0.38;
  static const double _textTopPad = 2.0;
  static const double _textBottomPad = 5.0;

  /// Filas del sello de texto (misma condición que [_drawTextAppearance]).
  static List<(String label, String value, bool isName)> textAppearanceRows(
    CertificateProfile profile,
  ) {
    return <(String, String, bool)>[
      (
        'Firmado digitalmente por',
        profile.name.isEmpty ? 'Sin nombre' : profile.name,
        true,
      ),
      // La fecha real se dibuja al firmar; para el alto basta 1 línea.
      ('Fecha', '', false),
      if (profile.reason.isNotEmpty) ('Motivo', profile.reason, false),
      if (profile.location.isNotEmpty) ('Lugar', profile.location, false),
      if (profile.contact.isNotEmpty) ('Contacto', profile.contact, false),
    ];
  }

  /// Alto necesario (pt) para la apariencia de texto a un ancho dado.
  static double contentHeightForText({
    required double width,
    required CertificateProfile profile,
  }) {
    const double fontSize = kTextAppearanceFontSize;
    const double lineHeight = fontSize * 1.9;
    final double availableW = width - _padX - 3;
    final double labelW = availableW <= 0
        ? 0
        : (availableW * _labelFraction).clamp(18.0, availableW * 0.55);
    final double valueW = availableW <= 0 ? 0 : availableW - labelW - 2;

    final PdfStandardFont titleFont = PdfStandardFont(
      PdfFontFamily.helvetica,
      fontSize + 0.5,
      style: PdfFontStyle.bold,
    );
    final PdfStandardFont valueFont =
        PdfStandardFont(PdfFontFamily.helvetica, fontSize);

    double total = _textTopPad;
    for (final (_, String value, bool isName) in textAppearanceRows(profile)) {
      // Fecha u otras filas sin valor de medida: 1 línea.
      final String sample = isName ? value : (value.isEmpty ? 'X' : value);
      final double maxW = isName ? availableW : valueW;
      final PdfFont font = isName ? titleFont : valueFont;
      final int lines = _lineCount(font, sample, maxW, lineHeight);
      total += lines * lineHeight;
    }
    return total + _textBottomPad;
  }

  /// Alto necesario (pt) para una rúbrica a un ancho dado (aspecto imagen).
  static double contentHeightForRubric({
    required double width,
    required Uint8List image,
  }) {
    const double inset = 2.0;
    final (int imgW, int imgH) = _imagePixelSize(image) ?? (1, 1);
    if (imgW <= 0 || imgH <= 0 || width <= 0) {
      return kMinAppearanceHeight;
    }
    final double aspect = imgH / imgW;
    return width * aspect + inset * 2;
  }

  /// Rect en espacio de visualización con alto = contenido, anclaje
  /// arriba-izquierda, ancho del placement y clamp a la página.
  static Rect _contentFittedDisplayRect({
    required SignaturePlacement placement,
    required CertificateProfile profile,
    required Size pageDisplaySize,
  }) {
    final Rect rect = placement.rect;
    if (rect.width <= 0 || pageDisplaySize.width <= 0) {
      return rect;
    }

    final double contentH = profile.hasRubric
        ? contentHeightForRubric(
            width: rect.width,
            image: profile.signatureBytes,
          )
        : contentHeightForText(width: rect.width, profile: profile);

    double height = contentH < kMinAppearanceHeight
        ? kMinAppearanceHeight
        : contentH;
    double top = rect.top;

    final double maxBottom = pageDisplaySize.height;
    if (top < 0) top = 0;
    if (top > maxBottom) top = maxBottom;

    if (top + height > maxBottom) {
      height = maxBottom - top;
      if (height < kMinAppearanceHeight) {
        height = kMinAppearanceHeight.clamp(0.0, maxBottom);
        top = (maxBottom - height).clamp(0.0, maxBottom);
      }
    }

    if (height <= 0) return rect;
    return Rect.fromLTWH(rect.left, top, rect.width, height);
  }

  /// Nº de líneas al medir [text] con [font] en [maxWidth] (word-wrap).
  static int _lineCount(
    PdfFont font,
    String text,
    double maxWidth,
    double lineHeight,
  ) {
    if (maxWidth <= 0 || text.isEmpty) return 1;
    final Size size = font.measureString(
      text,
      layoutArea: Size(maxWidth, 0),
    );
    final double fontH = font.height > 0 ? font.height : lineHeight;
    final int lines = (size.height / fontH).ceil();
    if (lines < 1) return 1;
    return lines > 40 ? 40 : lines;
  }

  /// Dimensiones en píxeles de un PNG (IHDR) o JPEG (SOF); null si no.
  static (int, int)? _imagePixelSize(Uint8List bytes) {
    if (bytes.length < 24) return null;
    // PNG signature
    if (bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      final int w = (bytes[16] << 24) |
          (bytes[17] << 16) |
          (bytes[18] << 8) |
          bytes[19];
      final int h = (bytes[20] << 24) |
          (bytes[21] << 16) |
          (bytes[22] << 8) |
          bytes[23];
      return (w, h);
    }
    // JPEG SOFn
    if (bytes[0] == 0xFF && bytes[1] == 0xD8) {
      int i = 2;
      while (i + 9 < bytes.length) {
        if (bytes[i] != 0xFF) {
          i++;
          continue;
        }
        final int marker = bytes[i + 1];
        // SOF0..SOF15 except DHT(C4), JPG(C8), DAC(CC)
        if (marker >= 0xC0 &&
            marker <= 0xCF &&
            marker != 0xC4 &&
            marker != 0xC8 &&
            marker != 0xCC) {
          final int h = (bytes[i + 5] << 8) | bytes[i + 6];
          final int w = (bytes[i + 7] << 8) | bytes[i + 8];
          return (w, h);
        }
        if (marker == 0xD8 || marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
          i += 2;
          continue;
        }
        final int len = (bytes[i + 2] << 8) | bytes[i + 3];
        if (len < 2) return null;
        i += 2 + len;
      }
    }
    return null;
  }

  PdfCertificate? _buildCertificate(SignRequest request) {
    final String path = request.profile.certificatePath;
    if (path.isEmpty) return null;
    final File file = File(path);
    if (!file.existsSync()) {
      throw StateError('El certificado no existe: $path');
    }
    return PdfCertificate(
      file.readAsBytesSync(),
      request.certificatePassword ?? '',
    );
  }

  /// Dibuja el sello de texto estándar cuando no hay rúbrica:
  ///
  /// ```
  /// ┃ Firmado digitalmente por: Ana
  /// ┃ Fecha: …
  /// ┃ Motivo: …
  /// ┃ Lugar: …
  /// ┃ Contacto: …
  /// └─────────────────────────────
  /// ```
  ///
  /// Incluye barra de acento izquierda, marco doble tenue y columnas
  /// fijas de etiqueta/valor.
  void _drawTextAppearance(
    PdfSignatureField field,
    CertificateProfile profile,
    Rect bounds,
  ) {
    final PdfGraphics? graphics = field.appearance.normal.graphics;
    if (graphics == null) return;

    final List<(String label, String value, bool isName)> rows =
        textAppearanceRows(profile);
    // Fecha real solo al dibujar (el alto ya asumió 1 línea).
    rows[1] = ('Fecha', _nowStamp(), false);

    final double w = bounds.width;
    final double h = bounds.height;
    const double fontSize = kTextAppearanceFontSize;
    const double lineHeight = fontSize * 1.9;

    final PdfStandardFont titleFont =
        PdfStandardFont(PdfFontFamily.helvetica, fontSize + 0.5,
            style: PdfFontStyle.bold);
    final PdfStandardFont valueFont =
        PdfStandardFont(PdfFontFamily.helvetica, fontSize);

    final PdfBrush labelBrush = PdfSolidBrush(PdfColor(0x3A, 0x3A, 0x40));
    final PdfBrush valueBrush = PdfSolidBrush(PdfColor(0x1B, 0x1B, 0x1F));
    final PdfBrush nameBrush = PdfSolidBrush(PdfColor(0x1F, 0x4E, 0x8C));
    final PdfBrush accentBrush =
        PdfSolidBrush(PdfColor(0x1F, 0x4E, 0x8C));
    final PdfBrush softBg =
        PdfSolidBrush(PdfColor(0xF7, 0xF9, 0xFC));

    // Fondo tenue + marco doble
    graphics.drawRectangle(
      brush: PdfSolidBrush(PdfColor(0xFF, 0xFF, 0xFF)),
      bounds: Rect.fromLTWH(0, 0, w, h),
    );
    graphics.drawRectangle(
      brush: softBg,
      bounds: Rect.fromLTWH(1, 1, w - 2, h - 2),
    );
    graphics.drawRectangle(
      pen: PdfPen(PdfColor(0x9A, 0xA0, 0xA6), width: 0.8),
      bounds: Rect.fromLTWH(0.5, 0.5, w - 1, h - 1),
    );
    graphics.drawRectangle(
      pen: PdfPen(PdfColor(0xC8, 0xCD, 0xD4), width: 0.4),
      bounds: Rect.fromLTWH(2.5, 2.5, w - 5, h - 5),
    );
    // Barra de acento izquierda
    graphics.drawRectangle(
      brush: accentBrush,
      bounds: Rect.fromLTWH(1, 4, 2.5, h - 8),
    );

    final PdfStringFormat format = PdfStringFormat(
      alignment: PdfTextAlignment.left,
      lineAlignment: PdfVerticalAlignment.middle,
      wordWrap: PdfWordWrapType.word,
    );

    const double padX = _padX;
    final double availableW = w - padX - 3;
    final double labelW = availableW <= 0
        ? 0
        : (availableW * _labelFraction).clamp(18.0, availableW * 0.55);
    double y = _textTopPad;

    for (final (String label, String value, bool isName) in rows) {
      final double maxW = isName ? availableW : (availableW - labelW - 2);
      final PdfFont rowFont = isName ? titleFont : valueFont;
      final String measureText =
          isName ? value : (value.isEmpty ? 'X' : value);
      final int lines =
          _lineCount(rowFont, measureText, maxW, lineHeight);
      final double rowH = lines * lineHeight;
      final Rect rowBounds = Rect.fromLTWH(padX, y, availableW, rowH);
      if (isName) {
        graphics.drawString(
          value,
          titleFont,
          brush: nameBrush,
          bounds: rowBounds,
          format: format,
        );
      } else {
        graphics.drawString(
          '$label:',
          valueFont,
          brush: labelBrush,
          bounds: Rect.fromLTWH(padX, y, labelW, rowH),
          format: format,
        );
        graphics.drawString(
          value,
          valueFont,
          brush: valueBrush,
          bounds: Rect.fromLTWH(
            padX + labelW + 2,
            y,
            availableW - labelW - 2,
            rowH,
          ),
          format: format,
        );
      }
      y += rowH;
    }
  }

  /// Apariencia con rúbrica: fondo, imagen centrada y marco fino.
  void _drawRubricAppearance(
    PdfSignatureField field,
    CertificateProfile profile,
    Rect bounds,
  ) {
    final PdfGraphics? graphics = field.appearance.normal.graphics;
    if (graphics == null) return;
    final double w = bounds.width;
    final double h = bounds.height;

    graphics.drawRectangle(
      brush: PdfSolidBrush(PdfColor(0xFF, 0xFF, 0xFF)),
      bounds: Rect.fromLTWH(0, 0, w, h),
    );

    // Pequeño margen para el marco (si hay sitio).
    final double inset = (w > 16 && h > 16) ? 2.0 : 0.0;
    final Rect imgRect = Rect.fromLTWH(
      inset,
      inset,
      w - inset * 2,
      h - inset * 2,
    );
    graphics.drawImage(
      PdfBitmap(profile.signatureBytes),
      imgRect,
    );
    graphics.drawRectangle(
      pen: PdfPen(PdfColor(0xC8, 0xCD, 0xD4), width: 0.6),
      bounds: Rect.fromLTWH(0.5, 0.5, w - 1, h - 1),
    );
    // Acento izquierdo también en rúbrica (consistencia).
    graphics.drawRectangle(
      brush: PdfSolidBrush(PdfColor(0x1F, 0x4E, 0x8C)),
      bounds: Rect.fromLTWH(1, 4, 2, (h - 8).clamp(4.0, double.infinity)),
    );
  }

  String _nowStamp() {
    final DateTime now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(now.day)}/${two(now.month)}/${now.year} '
        '${two(now.hour)}:${two(now.minute)}:${two(now.second)}';
  }

  /// Cuenta los campos de firma NO firmados (pendientes) y los firmados.
  ///
  /// Devuelve `existingSigned` con los ya firmados (para avisar al abrir y
  /// no duplicar) y `pending` con los que quedan por firmar.
  Future<PdfSignatureReport> inspectFields(
    Uint8List bytes, {
    String? openPassword,
  }) async {
    final PdfDocument document = PdfDocument(
      inputBytes: bytes,
      password: openPassword,
    );
    try {
      int signed = 0;
      int pending = 0;
      for (int i = 0; i < document.form.fields.count; i++) {
        final PdfField field = document.form.fields[i];
        if (field is PdfSignatureField) {
          if (field.signature != null) {
            signed++;
          } else {
            pending++;
          }
        }
      }
      return PdfSignatureReport(signed: signed, pending: pending);
    } finally {
      document.dispose();
    }
  }

  /// Verifica el PDF y devuelve detalle por campo de firma (nombre, página,
  /// si está firmado y fecha de firma) para el panel lateral de verificación.
  ///
  /// Equivalente estructural a [inspectFields] pero con granularidad por campo.
  /// Nota: la versión 25.1.39 no expone getter público de validez criptográfica;
  /// `hasSignature` refleja que el campo alberga una firma embebida (= integridad
  /// estructural) y `signedDate` los datos básicos legibles.
  Future<PdfSignatureDetailReport> inspectSignatureDetails(
    Uint8List bytes, {
    String? openPassword,
  }) async {
    final PdfDocument document = PdfDocument(
      inputBytes: bytes,
      password: openPassword,
    );
    try {
      final List<PdfSignatureFieldInfo> fields = <PdfSignatureFieldInfo>[];
      final PdfPageCollection pages = document.pages;
      int signed = 0;
      int pending = 0;
      for (int i = 0; i < document.form.fields.count; i++) {
        final PdfField field = document.form.fields[i];
        if (field is PdfSignatureField) {
          final PdfSignature? signature = field.signature;
          final bool hasSignature = signature != null;
          if (hasSignature) {
            signed++;
          } else {
            pending++;
          }
          int? pageIndex;
          final PdfPage? page = field.page;
          if (page != null) {
            pageIndex = pages.indexOf(page);
          }
          SignatureChainInfo? chainInfo;
          if (hasSignature) {
            chainInfo = SignatureCryptoService().analyseSignature(field, bytes);
            if (chainInfo != null && chainInfo.chainNodes.isNotEmpty) {
              try {
                final RevocationCheck rev =
                    await RevocationService().checkChain(chainInfo.chainNodes);
                chainInfo = chainInfo.withRevocation(rev);
              } catch (_) {
                // soft-fail: sin revocación no invalidamos
              }
            }
          }
          fields.add(PdfSignatureFieldInfo(
            name: field.name,
            pageIndex: pageIndex,
            hasSignature: hasSignature,
            signedDate: signature?.signedDate,
            signedName: signature?.signedName,
            reason: signature?.reason,
            locationInfo: signature?.locationInfo,
            contactInfo: signature?.contactInfo,
            certSubject: signature?.certificate?.subjectName,
            certIssuer: signature?.certificate?.issuerName,
            certValidFrom: signature?.certificate?.validFrom,
            certValidTo: signature?.certificate?.validTo,
            digestAlgorithm: signature?.digestAlgorithm.name,
            bounds: field.bounds,
            unrotatedPageSize: page?.size,
            rotationDegrees:
                page == null ? 0 : _syncfusionRotationDegrees(page.rotation),
            chainInfo: chainInfo,
          ));
        }
      }
      return PdfSignatureDetailReport(
        fields: fields,
        signed: signed,
        pending: pending,
      );
    } finally {
      document.dispose();
    }
  }

  /// Calcula la zona por defecto para firmar [bytes]: esquina **inferior
  /// derecha** de la última página, con el tamaño estándar de firma.
  ///
  /// Devuelve `null` si el documento no tiene páginas.
  Future<SignaturePlacement?> defaultPlacementForLastPage(
    Uint8List bytes, {
    required String profileId,
    String? openPassword,
  }) async {
    final PdfDocument document = PdfDocument(
      inputBytes: bytes,
      password: openPassword,
    );
    try {
      if (document.pages.count == 0) return null;

      const double stampWidth = 220;
      const double stampHeight = 96;
      const double margin = 16;

      final PdfPage last = document.pages[document.pages.count - 1];
      final Size unrotatedSize = last.size;
      final int rotationDegrees = _syncfusionRotationDegrees(last.rotation);
      final Size displaySize =
          PageCoords.displaySize(unrotatedSize, rotationDegrees);

      final Rect displayRect = Rect.fromLTWH(
        (displaySize.width - stampWidth - margin)
            .clamp(0.0, displaySize.width - stampWidth)
            .toDouble(),
        (displaySize.height - stampHeight - margin)
            .clamp(0.0, displaySize.height - stampHeight)
            .toDouble(),
        (stampWidth.clamp(0.0, displaySize.width)).toDouble(),
        (stampHeight.clamp(0.0, displaySize.height)).toDouble(),
      );

      return SignaturePlacement(
        pageIndex: document.pages.count - 1,
        rect: displayRect,
        profileId: profileId,
      );
    } finally {
      document.dispose();
    }
  }

  /// Calcula la colocación por defecto según la zona seleccionada para lote.
  Future<SignaturePlacement?> defaultPlacementForZone(
    Uint8List bytes, {
    required String profileId,
    required BatchPlacementZone zone,
    String? openPassword,
  }) async {
    final PdfDocument document = PdfDocument(
      inputBytes: bytes,
      password: openPassword,
    );
    try {
      if (document.pages.count == 0) return null;

      const double stampWidth = 220;
      const double stampHeight = 96;
      const double margin = 16;

      final bool useLastPage =
          zone == BatchPlacementZone.lastPageBottomRight ||
              zone == BatchPlacementZone.lastPageCenter;
      final int pageIndex = useLastPage ? document.pages.count - 1 : 0;
      final PdfPage page = document.pages[pageIndex];
      final Size unrotatedSize = page.size;
      final int rotationDegrees = _syncfusionRotationDegrees(page.rotation);
      final Size displaySize =
          PageCoords.displaySize(unrotatedSize, rotationDegrees);
      final double pageWidth = displaySize.width;
      final double pageHeight = displaySize.height;

      final bool center =
          zone == BatchPlacementZone.lastPageCenter ||
          zone == BatchPlacementZone.firstPageCenter;

      final double x = center
          ? ((pageWidth - stampWidth) / 2)
              .clamp(0.0, pageWidth - stampWidth)
              .toDouble()
          : (pageWidth - stampWidth - margin)
              .clamp(0.0, pageWidth - stampWidth)
              .toDouble();

      final double y = center
          ? ((pageHeight - stampHeight) / 2)
              .clamp(0.0, pageHeight - stampHeight)
              .toDouble()
          : (pageHeight - stampHeight - margin)
              .clamp(0.0, pageHeight - stampHeight)
              .toDouble();

      return SignaturePlacement(
        pageIndex: pageIndex,
        rect: Rect.fromLTWH(
          x,
          y,
          (stampWidth.clamp(0.0, pageWidth)).toDouble(),
          (stampHeight.clamp(0.0, pageHeight)).toDouble(),
        ),
        profileId: profileId,
      );
    } finally {
      document.dispose();
    }
  }

  /// Ruta donde [save] escribiría por defecto: `X_firmado.pdf` junto al original
  /// (o en [outputDirectory] si se indica).
  String intendedOutputPath(String sourcePath, {String? outputDirectory}) {
    final String directory = outputDirectory ?? p.dirname(sourcePath);
    final String base = _outputBaseName(sourcePath);
    return p.join(directory, '${base}_firmado.pdf');
  }

  /// Siguiente ruta libre si [intendedPath] ya existe:
  /// `X_firmado_2.pdf`, `X_firmado_3.pdf`, ...
  String nextAvailablePath(String intendedPath) {
    if (!File(intendedPath).existsSync()) return intendedPath;
    final String dir = p.dirname(intendedPath);
    final String filename = p.basenameWithoutExtension(intendedPath);
    final String ext = p.extension(intendedPath);
    int n = 2;
    while (true) {
      final String candidate = p.join(dir, '${filename}_$n$ext');
      if (!File(candidate).existsSync()) return candidate;
      n++;
    }
  }

  String _outputBaseName(String sourcePath) {
    final String name = sourcePath.split(RegExp(r'[\\/]')).last;
    return name.toLowerCase().endsWith('.pdf')
        ? name.replaceFirst(RegExp(r'\.pdf$', caseSensitive: false), '')
        : name;
  }

  /// Guarda el PDF firmado junto al original como `X_firmado.pdf`.
  /// Si se especifica [outputDirectory], guarda ahí en lugar del directorio original.
  /// Si se especifica [outputPath], se usa esa ruta exacta (tiene prioridad).
  Future<File> save(
    Uint8List bytes,
    String sourcePath, {
    String? outputDirectory,
    String? outputPath,
  }) async {
    final String path = outputPath ??
        intendedOutputPath(sourcePath, outputDirectory: outputDirectory);
    final File output = File(path);
    await output.writeAsBytes(bytes, flush: true);
    return output;
  }

  Future<void> open(File file) => OpenFilex.open(file.path);
}