import 'dart:typed_data';

import '../models/certificate_profile.dart';

/// Zona de colocación de la firma en el PDF.
enum BatchPlacementZone {
  /// Esquina inferior derecha de la última página (comportamiento actual).
  lastPageBottomRight,

  /// Centrado en la última página.
  lastPageCenter,

  /// Esquina inferior derecha de la primera página.
  firstPageBottomRight,

  /// Centrado en la primera página.
  firstPageCenter,
}

/// Archivo PDF en el lote, con su estado de selección.
class BatchFileItem {
  BatchFileItem({
    required this.path,
    required this.bytes,
    this.selected = true,
  });

  final String path;
  final Uint8List bytes;
  bool selected;
}

/// Configuración completa de un lote de firmas.
class BatchJobConfig {
  const BatchJobConfig({
    required this.profile,
    required this.password,
    required this.zone,
    required this.files,
    this.outputDirectory,
  });

  final CertificateProfile profile;
  final String? password;
  final BatchPlacementZone zone;
  final List<BatchFileItem> files;

  /// Directorio de salida para los PDFs firmados.
  /// `null` = guardar junto al original.
  final String? outputDirectory;

  int get selectedCount => files.where((f) => f.selected).length;
}

/// Estado de procesamiento de un archivo individual en el lote.
enum BatchFileStatus { pending, signing, done, error, skipped }

/// Resultado del procesamiento de un archivo individual.
class BatchFileResult {
  const BatchFileResult({
    required this.path,
    required this.status,
    this.errorMessage,
  });

  final String path;
  final BatchFileStatus status;
  final String? errorMessage;

  String get fileName => path.split(RegExp(r'[\\/]')).last;
}
