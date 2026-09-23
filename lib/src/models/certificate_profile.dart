import 'dart:convert';
import 'dart:typed_data';

/// Identidad de firma reutilizable guardada por el usuario.
///
/// `certificatePath` apunta a un PFX/P12 local (obligatorio en la interfaz);
/// su contraseña se guarda aparte en el almacenamiento seguro del sistema.
/// `signatureBytes` es opcional: una imagen PNG de la rúbrica dibujada o
/// importada; si está vacía la firma se incrusta con apariencia de texto.
class CertificateProfile {
  const CertificateProfile._({
    required this.id,
    required this.name,
    required this.reason,
    required this.location,
    required this.contact,
    required this.certificatePath,
    required this.signatureBytes,
    this.useTsa = false,
    this.tsaUrl = 'http://timestamp.digicert.com',
  });

  factory CertificateProfile({
    required String id,
    required String name,
    required String reason,
    required String certificatePath,
    String location = '',
    String contact = '',
    Uint8List? signatureBytes,
    bool useTsa = false,
    String tsaUrl = 'http://timestamp.digicert.com',
  }) {
    return CertificateProfile._(
      id: id,
      name: name,
      reason: reason,
      location: location,
      contact: contact,
      certificatePath: certificatePath,
      signatureBytes: signatureBytes ?? Uint8List(0),
      useTsa: useTsa,
      tsaUrl: tsaUrl.isEmpty ? 'http://timestamp.digicert.com' : tsaUrl,
    );
  }

  factory CertificateProfile.fromJson(Map<String, dynamic> json) {
    return CertificateProfile._(
      id: json['id'] as String,
      name: json['name'] as String,
      reason: json['reason'] as String,
      location: json['location'] as String? ?? '',
      contact: json['contact'] as String? ?? '',
      certificatePath: json['certificatePath'] as String,
      signatureBytes: (json['signature'] as String?) == null
          ? Uint8List(0)
          : Uint8List.fromList(base64Decode(json['signature'] as String)),
      useTsa: json['useTsa'] as bool? ?? false,
      tsaUrl: (json['tsaUrl'] as String?)?.isEmpty ?? true
          ? 'http://timestamp.digicert.com'
          : json['tsaUrl'] as String,
    );
  }

  final String id;
  final String name;
  final String reason;
  final String location;

  /// Contacto (email/tel) opcional → diccionario PDF `/ContactInfo`.
  final String contact;
  final String certificatePath;
  final Uint8List signatureBytes;

  /// Sello de tiempo RFC 3161 (TSA) soft-fail.
  final bool useTsa;

  /// URL del TSA (default público DigiCert).
  final String tsaUrl;

  bool get hasRubric => signatureBytes.isNotEmpty;

  CertificateProfile copyWith({
    String? name,
    String? reason,
    String? location,
    String? contact,
    String? certificatePath,
    Uint8List? signatureBytes,
    bool? useTsa,
    String? tsaUrl,
  }) {
    return CertificateProfile._(
      id: id,
      name: name ?? this.name,
      reason: reason ?? this.reason,
      location: location ?? this.location,
      contact: contact ?? this.contact,
      certificatePath: certificatePath ?? this.certificatePath,
      signatureBytes: signatureBytes ?? this.signatureBytes,
      useTsa: useTsa ?? this.useTsa,
      tsaUrl: tsaUrl ?? this.tsaUrl,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'reason': reason,
      'location': location,
      'contact': contact,
      'certificatePath': certificatePath,
      'useTsa': useTsa,
      'tsaUrl': tsaUrl,
      if (signatureBytes.isNotEmpty)
        'signature': base64Encode(signatureBytes),
    };
  }
}
