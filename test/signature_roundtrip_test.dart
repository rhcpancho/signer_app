import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:signer_app/src/models/certificate_profile.dart';
import 'package:signer_app/src/models/page_coords.dart';
import 'package:signer_app/src/models/signature_placement.dart';
import 'package:signer_app/src/services/pdf_signer_service.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// PNG 1x1 transparente válido para las pruebas de apariencia.
const String _kPng1x1 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJ'
    'AAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

CertificateProfile _visualProfile(String id) => CertificateProfile(
      id: id,
      name: 'Test',
      reason: 'Prueba',
      certificatePath: '',
      signatureBytes: base64Decode(_kPng1x1),
    );

/// Crea un PDF de una página y, si se pide rotación, la persiste recargando
/// el documento (Syncfusion solo escribe `/Rotate` en páginas ya cargadas).
Future<Uint8List> _makeInputPdf({
  PdfPageRotateAngle rotation = PdfPageRotateAngle.rotateAngle0,
}) async {
  final PdfDocument doc = PdfDocument();
  doc.pages.add();
  var bytes = Uint8List.fromList(await doc.save());
  doc.dispose();

  if (rotation != PdfPageRotateAngle.rotateAngle0) {
    final PdfDocument loaded = PdfDocument(inputBytes: bytes);
    loaded.pages[0].rotation = rotation;
    bytes = Uint8List.fromList(await loaded.save());
    loaded.dispose();
  }
  return bytes;
}

Future<(Uint8List, Rect)> _signAndReadBounds({
  required Rect placementRect,
  PdfPageRotateAngle rotation = PdfPageRotateAngle.rotateAngle0,
}) async {
  final Uint8List input = await _makeInputPdf(rotation: rotation);

  final SignaturePlacement placement = SignaturePlacement(
    pageIndex: 0,
    rect: placementRect,
    profileId: 'test',
  );

  final Uint8List output = await PdfSignerService().sign(
    inputBytes: input,
    requests: <SignRequest>[
      SignRequest(placement: placement, profile: _visualProfile('test')),
    ],
  );

  final PdfDocument signed = PdfDocument(inputBytes: output);
  expect(signed.form.fields.count, 1);
  final PdfField field = signed.form.fields[0];
  expect(field, isA<PdfSignatureField>());
  final Rect bounds = (field as PdfSignatureField).bounds;
  signed.dispose();
  return (output, bounds);
}

void main() {
  group('Round-trip placement display → field.bounds sin rotación', () {
    test('rotación 0: ancho/posición del placement, alto del contenido', () async {
      const Rect rect = Rect.fromLTWH(50, 60, 220, 96);
      final (_, Rect bounds) = await _signAndReadBounds(
        placementRect: rect,
      );
      // Rúbrica 1×1: alto = ancho + inset (4), no el alto del placement.
      final double contentH = PdfSignerService.contentHeightForRubric(
        width: rect.width,
        image: base64Decode(_kPng1x1),
      );
      expect(bounds.left, closeTo(rect.left, 0.5));
      expect(bounds.top, closeTo(rect.top, 0.5));
      expect(bounds.width, closeTo(rect.width, 0.5));
      expect(bounds.height, closeTo(contentH, 0.5));
    });
  });

  group('Round-trip con páginas rotadas', () {
    for (final PdfPageRotateAngle rotation in <PdfPageRotateAngle>[
      PdfPageRotateAngle.rotateAngle90,
      PdfPageRotateAngle.rotateAngle180,
      PdfPageRotateAngle.rotateAngle270,
    ]) {
      test('$rotation: display→unrotated coincide con PageCoords', () async {
        // Placement en espacio de display para página apaisada 792×612
        // cuando la sin rotar es 612×792 (o según rotación).
        const Rect displayRect = Rect.fromLTWH(400, 300, 120, 60);
        final (_, Rect bounds) = await _signAndReadBounds(
          placementRect: displayRect,
          rotation: rotation,
        );

        final PdfDocument doc = PdfDocument(inputBytes: await _makeInputPdf(
          rotation: rotation,
        ));
        final Size unrot = doc.pages[0].size;
        final PdfPageRotateAngle actualRotation = doc.pages[0].rotation;
        doc.dispose();

        expect(actualRotation, rotation,
            reason: 'El PDF de prueba debe tener /Rotate persistido');

        // Alto adaptado al contenido (rúbrica 1×1) en espacio display.
        final double contentH = PdfSignerService.contentHeightForRubric(
          width: displayRect.width,
          image: base64Decode(_kPng1x1),
        );
        final Rect fittedDisplay = Rect.fromLTWH(
          displayRect.left,
          displayRect.top,
          displayRect.width,
          contentH,
        );
        final Rect expected = PageCoords.displayToUnrotated(
          rect: fittedDisplay,
          unrotatedSize: unrot,
          rotationDegrees: rotation.index * 90,
        );
        expect(bounds.left, closeTo(expected.left, 0.5));
        expect(bounds.top, closeTo(expected.top, 0.5));
        expect(bounds.width, closeTo(expected.width, 0.5));
        expect(bounds.height, closeTo(expected.height, 0.5));
      });
    }
  });

  test('inspectSignatureDetails expone unrotatedPageSize y rotationDegrees',
      () async {
    final Uint8List input = await _makeInputPdf(
      rotation: PdfPageRotateAngle.rotateAngle90,
    );

    final Uint8List output = await PdfSignerService().sign(
      inputBytes: input,
      requests: <SignRequest>[
        SignRequest(
          placement: const SignaturePlacement(
            pageIndex: 0,
            rect: Rect.fromLTWH(100, 50, 80, 40),
            profileId: 't',
          ),
          profile: _visualProfile('t'),
        ),
      ],
    );

    final PdfSignatureDetailReport report =
        await PdfSignerService().inspectSignatureDetails(output);
    expect(report.fields, hasLength(1));
    final PdfSignatureFieldInfo info = report.fields[0];
    expect(info.unrotatedPageSize, isNotNull);
    expect(info.rotationDegrees, 90);
    expect(info.bounds, isNotNull);
    // El tamaño sin rotar no cambia al firmar (puede ser Letter o A4).
    expect(info.unrotatedPageSize!.width, greaterThan(0));
    expect(info.unrotatedPageSize!.height, greaterThan(0));
    // Con rotación 90° el display intercambia ancho/alto respecto al sin rotar.
    expect(
      PageCoords.displaySize(info.unrotatedPageSize!, 90),
      Size(info.unrotatedPageSize!.height, info.unrotatedPageSize!.width),
    );
  });
}
