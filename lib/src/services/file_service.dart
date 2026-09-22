import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// Resultado de la apertura de un archivo.
class PickedFile {
  const PickedFile({required this.path, required this.bytes});

  final String path;
  final Uint8List bytes;
}

/// Servicio de acceso a archivos (abrir PDF, abrir cert, guardar salida).
class FileService {
  /// Resultado de la apertura de un archivo.
  static PickedFile _toPicked(PlatformFile file) =>
      PickedFile(path: file.path ?? file.name, bytes: file.bytes!);

  Future<PickedFile?> pickPdf() async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      withData: true,
    );

    final PlatformFile? file = result?.files.single;
    if (file == null || file.bytes == null) {
      return null;
    }
    return _toPicked(file);
  }

  /// Selecciona **varios** PDFs a la vez (firma por lote).
  ///
  /// Devuelve `null` si el usuario cancela o no elige ningÃºn PDF.
  Future<List<PickedFile>?> pickPdfs() async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      withData: true,
      allowMultiple: true,
    );

    final List<PickedFile> picked =
        <PickedFile>[
      for (final PlatformFile file in result?.files ?? <PlatformFile>[])
        if (file.bytes != null) _toPicked(file),
    ];
    if (picked.isEmpty) return null;
    return picked;
  }

  Future<PickedFile?> pickSignatureImage() async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final PlatformFile? file = result?.files.single;
    if (file == null || file.bytes == null) {
      return null;
    }
    return PickedFile(path: file.path ?? file.name, bytes: file.bytes!);
  }

  Future<PickedFile?> pickCertificate() async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pfx', 'p12'],
      withData: true,
    );
    final PlatformFile? file = result?.files.single;
    if (file == null || file.bytes == null) {
      return null;
    }
    return PickedFile(path: file.path ?? file.name, bytes: file.bytes!);
  }

  /// Selecciona un directorio del sistema.
  Future<String?> pickDirectory() async {
    return FilePicker.platform.getDirectoryPath();
  }
}
