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
}