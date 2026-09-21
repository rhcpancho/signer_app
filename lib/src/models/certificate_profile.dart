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
    required this.certificatePath,
    required this.signatureBytes,
  });

  factory CertificateProfile({
    required String id,
    required String name,
    required String reason,
    required String certificatePath,
    String location = '',
    Uint8List? signatureBytes,
  }) {
    return CertificateProfile._(
      id: id,
      name: name,
      reason: reason,
      location: location,
      certificatePath: certificatePath,
      signatureBytes: signatureBytes ?? Uint8List(0),
    );
  }

  factory CertificateProfile.fromJson(Map<String, dynamic> json) {
    return CertificateProfile._(
      id: json['id'] as String,
      name: json['name'] as String,
      reason: json['reason'] as String,
      location: json['location'] as String? ?? '',
      certificatePath: json['certificatePath'] as String,
      signatureBytes: (json['signature'] as String?) == null
          ? Uint8List(0)
          : Uint8List.fromList(base64Decode(json['signature'] as String)),
    );
  }

  final String id;
  final String name;
  final String reason;
  final String location;
  final String certificatePath;
  final Uint8List signatureBytes;

  bool get hasRubric => signatureBytes.isNotEmpty;

  CertificateProfile copyWith({
    String? name,
    String? reason,
    String? location,
    String? certificatePath,
    Uint8List? signatureBytes,
  }) {
    return CertificateProfile._(
      id: id,
      name: name ?? this.name,
      reason: reason ?? this.reason,
      location: location ?? this.location,
      certificatePath: certificatePath ?? this.certificatePath,
      signatureBytes: signatureBytes ?? this.signatureBytes,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'reason': reason,
      'location': location,
      'certificatePath': certificatePath,
      if (signatureBytes.isNotEmpty)
        'signature': base64Encode(signatureBytes),
    };
  }
}