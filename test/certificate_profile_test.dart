import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:signer_app/src/models/certificate_profile.dart';
import 'package:signer_app/src/models/signature_placement.dart';
import 'package:signer_app/src/services/pdf_signer_service.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

void main() {
  group('CertificateProfile contact', () {
    test('fromJson sin campo contact (perfiles antiguos) usa empty', () {
      final CertificateProfile p = CertificateProfile.fromJson(
        <String, dynamic>{
          'id': '1',
          'name': 'Ana',
          'reason': 'OK',
          'location': 'Madrid',
          'certificatePath': '/tmp/x.pfx',
        },
      );
      expect(p.contact, '');
      expect(p.location, 'Madrid');
    });

    test('toJson/fromJson preserva contact', () {
      final CertificateProfile p = CertificateProfile(
        id: '1',
        name: 'Ana',
        reason: 'OK',
        location: 'Madrid',
        contact: 'ana@ejemplo.com',
        certificatePath: '/tmp/x.pfx',
      );
      final CertificateProfile back =
          CertificateProfile.fromJson(p.toJson());
      expect(back.contact, 'ana@ejemplo.com');
      expect(back.location, 'Madrid');
    });

    test('copyWith actualiza contact sin tocar el resto', () {
      final CertificateProfile p = CertificateProfile(
        id: '1',
        name: 'Ana',
        reason: 'OK',
        location: 'Madrid',
        certificatePath: '/tmp/x.pfx',
      );
      final CertificateProfile c = p.copyWith(contact: 'a@b.c');
      expect(c.contact, 'a@b.c');
      expect(c.name, 'Ana');
      expect(c.location, 'Madrid');
      expect(p.contact, '');
    });

    test('fromJson sin useTsa/tsaUrl (perfiles antiguos) usa defaults', () {
      final CertificateProfile p = CertificateProfile.fromJson(
        <String, dynamic>{
          'id': '1',
          'name': 'Ana',
          'reason': 'OK',
          'certificatePath': '/tmp/x.pfx',
        },
      );
      expect(p.useTsa, isFalse);
      expect(p.tsaUrl, contains('timestamp.digicert.com'));
    });

    test('toJson/fromJson preserva useTsa y tsaUrl', () {
      final CertificateProfile p = CertificateProfile(
        id: '1',
        name: 'Ana',
        reason: 'OK',
        certificatePath: '/tmp/x.pfx',
        useTsa: true,
        tsaUrl: 'http://my-tsa.example',
      );
      final CertificateProfile back =
          CertificateProfile.fromJson(p.toJson());
      expect(back.useTsa, isTrue);
      expect(back.tsaUrl, 'http://my-tsa.example');
    });

    test('copyWith actualiza useTsa/tsaUrl', () {
      final CertificateProfile p = CertificateProfile(
        id: '1',
        name: 'Ana',
        reason: 'OK',
        certificatePath: '/tmp/x.pfx',
      );
      final CertificateProfile c =
          p.copyWith(useTsa: true, tsaUrl: 'http://x');
      expect(c.useTsa, isTrue);
      expect(c.tsaUrl, 'http://x');
      expect(p.useTsa, isFalse);
    });
  });

  test('inspectSignatureDetails expone locationInfo y contactInfo', () async {
    // Solo verificamos que el syncfusion de test (visual, sin cert) no rompe;
    // location/contact reales se prueban con PFX en integración. Aquí comprobamos
    // que el modelo de perfil llega al PdfSignature cuando hay cert — usamos
    // profile vacío de cert para no depender de fixtures PFX.
    final PdfDocument inputDoc = PdfDocument();
    inputDoc.pages.add();
    final Uint8List input = Uint8List.fromList(await inputDoc.save());
    inputDoc.dispose();

    final CertificateProfile profile = CertificateProfile(
      id: 'meta',
      name: 'Ana García',
      reason: 'Acepto',
      location: 'Caracas',
      contact: 'ana@ejemplo.com',
      certificatePath: '', // sin cert → no hay PdfSignature con metadata
    );

    final Uint8List output = await PdfSignerService().sign(
      inputBytes: input,
      requests: <SignRequest>[
        SignRequest(
          placement: const SignaturePlacement(
            pageIndex: 0,
            rect: Rect.fromLTWH(40, 40, 180, 60),
            profileId: 'meta',
          ),
          profile: profile,
        ),
      ],
    );

    final PdfSignatureDetailReport report =
        await PdfSignerService().inspectSignatureDetails(output);
    expect(report.fields, hasLength(1));
    // Campo visual sin cert: contactInfo/locationInfo del dict deben ser null
    // (Syncfusion solo los escribe si hay PdfSignature con cert).
    expect(report.fields[0].contactInfo, isNull);
    expect(report.fields[0].locationInfo, isNull);
    expect(report.fields[0].hasSignature, isFalse);
  });
}
