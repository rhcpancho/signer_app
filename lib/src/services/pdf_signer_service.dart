import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../models/certificate_profile.dart';
import '../models/signature_placement.dart';

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

  /// Firma `inputBytes` aplicando todas las [SignRequest].
  ///
  /// Devuelve los bytes del PDF firmado. El documento original no cambia.
  /// [openPassword] permite firmar PDFs cifrados con contraseña.
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

        final PdfSignatureField field = PdfSignatureField(
          page,
          'Signature$i',
          bounds: Rect.fromLTWH(
            request.placement.rect.left,
            request.placement.rect.top,
            request.placement.rect.width,
            request.placement.rect.height,
          ),
        );

        final PdfCertificate? certificate = _buildCertificate(request);

        if (certificate != null) {
          field.signature = PdfSignature(
            certificate: certificate,
            signedName: request.profile.name,
            reason:
                request.profile.reason.isEmpty ? null : request.profile.reason,
            contactInfo: null,
            locationInfo: null,
            digestAlgorithm: DigestAlgorithm.sha256,
            cryptographicStandard: CryptographicStandard.cms,
          );
        }

        if (request.profile.signatureBytes.isNotEmpty) {
          final PdfGraphics? graphics = field.appearance.normal.graphics;
          graphics?.drawImage(
            PdfBitmap(request.profile.signatureBytes),
            Rect.fromLTWH(
              0,
              0,
              request.placement.rect.width,
              request.placement.rect.height,
            ),
          );
        } else if (certificate != null) {
          _drawTextAppearance(
            field,
            request.profile,
            request.placement.rect,
          );
        }

        document.form.fields.add(field);
      }

      return Uint8List.fromList(await document.save());
    } finally {
      document.dispose();
    }
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
  /// ┌─────────────────────────────┐
  /// │ Firmado digitalmente por:   │  ⤷ nombre en la misma línea si cabe
  /// │   Alexander Sosa            │
  /// │ Fecha: 18/09/2026           │
  /// │ Motivo: <texto>             │  (si lo hay)
  /// │ Lugar: <texto>              │  (si lo hay)
  /// └─────────────────────────────┘
  /// ```
  ///
  /// El par "Firmado digitalmente por: <nombre>" se dibuja en una sola línea
  /// siempre que quepa; si el texto completo supera el ancho, el nombre pasa a
  /// la línea siguiente.
  void _drawTextAppearance(
    PdfSignatureField field,
    CertificateProfile profile,
    Rect bounds,
  ) {
    final PdfGraphics? graphics = field.appearance.normal.graphics;
    if (graphics == null) return;

    final List<(String label, String value, bool isName)> rows =
        <(String, String, bool)>[
      ('Firmado digitalmente por',
          profile.name.isEmpty ? 'Sin nombre' : profile.name,
          true),
      ('Fecha', _nowStamp(), false),
      if (profile.reason.isNotEmpty) ('Motivo', profile.reason, false),
      if (profile.location.isNotEmpty) ('Lugar', profile.location, false),
    ];

    final double w = bounds.width;
    final double h = bounds.height;
    final double fontSize = (h / (rows.length * 1.8)).clamp(3.0, 10.0);
    final double lineHeight = fontSize * 1.9;

    final PdfStandardFont titleFont =
        PdfStandardFont(PdfFontFamily.helvetica, fontSize + 0.5,
            style: PdfFontStyle.bold);
    final PdfStandardFont valueFont =
        PdfStandardFont(PdfFontFamily.helvetica, fontSize);

    final PdfBrush labelBrush = PdfSolidBrush(PdfColor(0x3A, 0x3A, 0x40));
    final PdfBrush valueBrush = PdfSolidBrush(PdfColor(0x1B, 0x1B, 0x1F));
    final PdfBrush nameBrush = PdfSolidBrush(PdfColor(0x1F, 0x4E, 0x8C));

    graphics.drawRectangle(
      brush: PdfSolidBrush(PdfColor(0xFF, 0xFF, 0xFF)),
      bounds: Rect.fromLTWH(0, 0, w, h),
    );
    graphics.drawRectangle(
      pen: PdfPens.lightGray,
      bounds: Rect.fromLTWH(0.6, 0.6, w - 1.2, h - 1.2),
    );

    final PdfStringFormat format = PdfStringFormat(
      alignment: PdfTextAlignment.left,
      lineAlignment: PdfVerticalAlignment.middle,
      wordWrap: PdfWordWrapType.word,
    );

    const double padX = 3;
    final double availableW = w - padX * 2;
    double y = 1;

    for (final (String label, String value, bool isName) in rows) {
      final Rect rowBounds = Rect.fromLTWH(padX, y, availableW, lineHeight);
      if (label.isEmpty) {
        graphics.drawString(
          value,
          titleFont,
          brush: nameBrush,
          bounds: rowBounds,
          format: format,
        );
      } else {
        final String text = '$label:';
        graphics.drawString(
          text,
          titleFont,
          brush: labelBrush,
          bounds: rowBounds,
          format: format,
        );
        if (value.isNotEmpty) {
          final PdfFont valueFontForRow = isName ? titleFont : valueFont;
          final PdfBrush valueBrushForRow = isName ? nameBrush : valueBrush;
          final double labelW =
              titleFont.measureString(text, format: format).width;
          final double valueW =
              valueFontForRow.measureString(value, format: format).width;
          if (labelW + 2 + valueW <= availableW) {
            graphics.drawString(
              value,
              valueFontForRow,
              brush: valueBrushForRow,
              bounds:
                  Rect.fromLTWH(padX + labelW + 2, y, availableW - labelW - 2, lineHeight),
              format: format,
            );
          } else {
            y += lineHeight;
            graphics.drawString(
              value,
              valueFontForRow,
              brush: valueBrushForRow,
              bounds: Rect.fromLTWH(padX + 4, y, availableW - 4, lineHeight),
              format: format,
            );
          }
        }
      }
      y += lineHeight;
    }
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
          fields.add(PdfSignatureFieldInfo(
            name: field.name,
            pageIndex: pageIndex,
            hasSignature: hasSignature,
            signedDate: signature?.signedDate,
            signedName: signature?.signedName,
            reason: signature?.reason,
            locationInfo: signature?.locationInfo,
            certSubject: signature?.certificate?.subjectName,
            certIssuer: signature?.certificate?.issuerName,
            certValidFrom: signature?.certificate?.validFrom,
            certValidTo: signature?.certificate?.validTo,
            digestAlgorithm: signature?.digestAlgorithm.name,
          ));        }
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
      final double pageWidth = last.size.width;
      final double pageHeight = last.size.height;

      return SignaturePlacement(
        pageIndex: document.pages.count - 1,
        rect: Rect.fromLTWH(
          (pageWidth - stampWidth - margin)
              .clamp(0.0, pageWidth - stampWidth)
              .toDouble(),
          (pageHeight - stampHeight - margin)
              .clamp(0.0, pageHeight - stampHeight)
              .toDouble(),
          (stampWidth.clamp(0.0, pageWidth)).toDouble(),
          (stampHeight.clamp(0.0, pageHeight)).toDouble(),
        ),
        profileId: profileId,
      );
    } finally {
      document.dispose();
    }
  }

  /// Guarda el PDF firmado junto al original como `X_firmado.pdf`.
  /// No abre el resultado (útil para firmas por lote).
  Future<File> save(Uint8List bytes, String sourcePath) async {
    final String directory = p.dirname(sourcePath);
    final String base =
        sourcePath.split(RegExp(r'[\\/]')).last.toLowerCase().endsWith('.pdf')
            ? sourcePath.split(RegExp(r'[\\/]')).last.replaceFirst(RegExp(r'\.pdf$', caseSensitive: false), '')
            : sourcePath.split(RegExp(r'[\\/]')).last;

    final File output = File(p.join(directory, '${base}_firmado.pdf'));
    await output.writeAsBytes(bytes, flush: true);
    return output;
  }

  Future<void> open(File file) => OpenFilex.open(file.path);
}