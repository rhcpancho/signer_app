import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:signer_app/src/models/certificate_profile.dart';
import 'package:signer_app/src/models/signature_placement.dart';
import 'package:signer_app/src/services/pdf_signer_service.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// PNG 1x1 transparente válido para las pruebas de apariencia.
const String _kPng1x1 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJ'
    'AAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

void main() {
  test('Firma visual genera un PDF firmado con campo de firma', () async {
    final PdfDocument inputDoc = PdfDocument();
    inputDoc.pages.add();
    final Uint8List input = Uint8List.fromList(await inputDoc.save());
    inputDoc.dispose();

    const SignaturePlacement placement = SignaturePlacement(
      pageIndex: 0,
      rect: Rect.fromLTWH(50, 50, 220, 80),
      profileId: 'test',
    );

    final CertificateProfile profile = CertificateProfile(
      id: 'test',
      name: 'Test',
      reason: 'Prueba unitaria',
      certificatePath: '',
      signatureBytes: base64Decode(_kPng1x1),
    );

    final Uint8List output = await PdfSignerService().sign(
      inputBytes: input,
      requests: <SignRequest>[
        SignRequest(placement: placement, profile: profile),
      ],
    );

    expect(output, isNotNull);
    expect(output.length, greaterThan(input.length));
    expect(String.fromCharCodes(output.sublist(0, 5)), startsWith('%PDF'));

    final PdfDocument signed = PdfDocument(inputBytes: output);
    expect(signed.form.fields.count, 1);
    expect(signed.form.fields[0], isA<PdfSignatureField>());
    signed.dispose();

    final PdfSignatureReport report =
        await PdfSignerService().inspectFields(output);
    // Sin certificado (firma visual) el campo existe pero no es digital.
    expect(report.signed + report.pending, 1);
  });

  test('inspectSignatureDetails no lanza y expone chainInfo posible', () async {
    final PdfDocument inputDoc = PdfDocument();
    inputDoc.pages.add();
    final Uint8List input = Uint8List.fromList(await inputDoc.save());
    inputDoc.dispose();

    const SignaturePlacement placement = SignaturePlacement(
      pageIndex: 0,
      rect: Rect.fromLTWH(50, 50, 220, 80),
      profileId: 'test-chain',
    );
    final CertificateProfile profile = CertificateProfile(
      id: 'test-chain',
      name: 'Test',
      reason: 'Prueba',
      certificatePath: '',
      signatureBytes: base64Decode(_kPng1x1),
    );

    final Uint8List output = await PdfSignerService().sign(
      inputBytes: input,
      requests: <SignRequest>[
        SignRequest(placement: placement, profile: profile),
      ],
    );

    final PdfSignatureDetailReport report =
        await PdfSignerService().inspectSignatureDetails(output);
    expect(report.fields, hasLength(1));
    // Firma visual sin certificado: chainInfo puede ser null o sin CMS.
    final chain = report.fields[0].chainInfo;
    if (chain != null) {
      expect(chain.chainNodes, isA<List<dynamic>>());
      expect(chain.error, anyOf(isNull, isA<String>()));
    }
  });

  test('Sin rúbrica el sello usa apariencia de texto estándar', () async {
    final PdfDocument inputDoc = PdfDocument();
    inputDoc.pages.add();
    final Uint8List input = Uint8List.fromList(await inputDoc.save());
    inputDoc.dispose();

    const SignaturePlacement placement = SignaturePlacement(
      pageIndex: 0,
      rect: Rect.fromLTWH(50, 50, 220, 80),
      profileId: 'test-text',
    );

    final CertificateProfile profile = CertificateProfile(
      id: 'test-text',
      name: 'Ana García',
      reason: 'Acepto los términos',
      certificatePath: '',
    );

    final Uint8List output = await PdfSignerService().sign(
      inputBytes: input,
      requests: <SignRequest>[
        SignRequest(placement: placement, profile: profile),
      ],
    );

    expect(String.fromCharCodes(output.sublist(0, 5)), startsWith('%PDF'));

    final PdfDocument signed = PdfDocument(inputBytes: output);
    expect(signed.form.fields.count, 1);
    signed.dispose();
  });

  group('alto por contenido', () {
    test('perfil con más filas pide más alto que perfil mínimo', () {
      const double width = 220;
      final CertificateProfile min = CertificateProfile(
        id: 'min',
        name: 'Ana',
        reason: '',
        certificatePath: '',
      );
      final CertificateProfile full = CertificateProfile(
        id: 'full',
        name: 'Ana García López',
        reason: 'Acepto los términos del contrato marco de servicios',
        location: 'Bogotá, Colombia',
        contact: 'ana.garcia@ejemplo.com',
        certificatePath: '',
      );

      final double hMin =
          PdfSignerService.contentHeightForText(width: width, profile: min);
      final double hFull =
          PdfSignerService.contentHeightForText(width: width, profile: full);

      expect(hFull, greaterThan(hMin));
      expect(hMin, greaterThanOrEqualTo(PdfSignerService.kMinAppearanceHeight));
    });

    test('rúbrica cuadrada 1×1 pide alto ≈ ancho + inset', () {
      final Uint8List png = base64Decode(_kPng1x1);
      final double h =
          PdfSignerService.contentHeightForRubric(width: 120, image: png);
      // 1×1 → aspecto 1; inset 2 arriba + 2 abajo = 124.
      expect(h, closeTo(124, 0.01));
    });

    test('sign adapta el bounds del campo al contenido (no al placement)', () async {
      final PdfDocument inputDoc = PdfDocument();
      inputDoc.pages.add();
      final Uint8List input = Uint8List.fromList(await inputDoc.save());
      inputDoc.dispose();

      // Placement "plano" de 80pt; el texto con motivo+lugar+contacto
      // debe pedir más alto que 80 (o al menos distinto del rect crudo).
      const SignaturePlacement placement = SignaturePlacement(
        pageIndex: 0,
        rect: Rect.fromLTWH(50, 50, 220, 80),
        profileId: 'adaptive',
      );
      final CertificateProfile profile = CertificateProfile(
        id: 'adaptive',
        name: 'María Fernanda Rodríguez de la Cruz',
        reason:
            'Firma el acta de recepción de bienes y servicios de la '
            'contratación pública con validez jurídica plena',
        location: 'Ciudad de México, CDMX',
        contact: 'maria.rodriguez@dependencia.gob.mx',
        certificatePath: '',
      );

      final Uint8List output = await PdfSignerService().sign(
        inputBytes: input,
        requests: <SignRequest>[
          SignRequest(placement: placement, profile: profile),
        ],
      );

      final double expected =
          PdfSignerService.contentHeightForText(width: 220, profile: profile);
      final PdfDocument signed = PdfDocument(inputBytes: output);
      expect(signed.form.fields.count, 1);
      final PdfSignatureField field =
          signed.form.fields[0] as PdfSignatureField;
      // Rotación 0: bounds = display. Alto = contenido (≥ mínimo de página).
      expect(field.bounds.width, closeTo(220, 0.5));
      expect(field.bounds.left, closeTo(50, 0.5));
      expect(field.bounds.height, closeTo(expected, 1.5));
      expect(field.bounds.height, isNot(80));
      // No se sale de la página (Syncfusion default A4/Letter).
      final PdfDocument probe = PdfDocument();
      probe.pages.add();
      final double pageH = probe.pages[0].size.height;
      probe.dispose();
      expect(field.bounds.bottom, lessThanOrEqualTo(pageH + 0.5));
      signed.dispose();
    });

    test('campo cerca del borde inferior se recorta a la página', () async {
      final PdfDocument inputDoc = PdfDocument();
      inputDoc.pages.add();
      final double pageH = inputDoc.pages[0].size.height;
      final Uint8List input = Uint8List.fromList(await inputDoc.save());
      inputDoc.dispose();

      // Coloca el rect casi en el borde inferior de la página real.
      const SignaturePlacement placement = SignaturePlacement(
        pageIndex: 0,
        rect: Rect.fromLTWH(50, 760, 220, 80),
        profileId: 'edge',
      );
      final CertificateProfile profile = CertificateProfile(
        id: 'edge',
        name: 'Pedro',
        reason: 'Acepto',
        location: 'Lima',
        contact: 'pedro@ejemplo.pe',
        certificatePath: '',
      );

      final Uint8List output = await PdfSignerService().sign(
        inputBytes: input,
        requests: <SignRequest>[
          SignRequest(placement: placement, profile: profile),
        ],
      );

      final PdfDocument signed = PdfDocument(inputBytes: output);
      final PdfSignatureField field =
          signed.form.fields[0] as PdfSignatureField;
      expect(field.bounds.bottom, lessThanOrEqualTo(pageH + 0.5));
      expect(field.bounds.top, greaterThanOrEqualTo(-0.5));
      expect(field.bounds.height, greaterThan(0));
      signed.dispose();
    });
  });
}