import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../models/signature_placement.dart';

/// Sesión con un documento PDF abierto en el visor.
class PdfSession {
  PdfSession({
    required this.document,
    required this.sourcePath,
    required this.sourceBytes,
    this.openPassword,
  });

  final PdfDocument document;
  final String sourcePath;
  final Uint8List sourceBytes;

  /// Contraseña de apertura si el PDF está cifrado (se reutiliza al firmar).
  final String? openPassword;

  /// Firmas colocadas en el documento (0-based).
  final List<SignaturePlacement> placements = <SignaturePlacement>[];

  /// Firmas criptográficas que YA existían al abrir el documento.
  int existingSignedFields = 0;

  int get pageCount => document.pages.length;

  Future<void> dispose() async {
    await document.dispose();
  }
}

class PdfSessionNotifier extends Notifier<PdfSession?> {
  @override
  PdfSession? build() => null;

  Future<void> load(
    PdfDocument document,
    String path,
    Uint8List bytes, {
    String? openPassword,
  }) async {
    final PdfSession? old = state;
    state = null;
    await old?.dispose();

    state = PdfSession(
      document: document,
      sourcePath: path,
      sourceBytes: bytes,
      openPassword: openPassword,
    );
  }

  void setExistingSignedFields(int count) {
    final PdfSession? session = state;
    if (session == null) return;
    session.existingSignedFields = count;
    ref.notifyListeners();
  }

  void addPlacement(int pageIndex, Rect rectInPoints,
      {required String profileId}) {
    final PdfSession? session = state;
    if (session == null) return;
    session.placements.add(
      SignaturePlacement(
        pageIndex: pageIndex,
        rect: rectInPoints,
        profileId: profileId,
      ),
    );
    ref.notifyListeners();
  }

  void updatePlacement(int index, Rect rectInPoints) {
    final PdfSession? session = state;
    if (session == null) return;
    session.placements[index] =
        session.placements[index].copyWith(rect: rectInPoints);
    ref.notifyListeners();
  }

  void removePlacement(int index) {
    final PdfSession? session = state;
    if (session == null) return;
    session.placements.removeAt(index);
    ref.notifyListeners();
  }

  void markSigned(int index) {
    final PdfSession? session = state;
    if (session == null) return;
    session.placements[index] =
        session.placements[index].copyWith(signed: true);
    ref.notifyListeners();
  }

  void markAllSigned() {
    final PdfSession? session = state;
    if (session == null) return;
    for (int i = 0; i < session.placements.length; i++) {
      session.placements[i] = session.placements[i].copyWith(signed: true);
    }
    ref.notifyListeners();
  }
}

final pdfSessionProvider =
    NotifierProvider<PdfSessionNotifier, PdfSession?>(PdfSessionNotifier.new);

/// Indica si el modo "colocar firma" está activo.
final signModeProvider = StateProvider<bool>((ref) => false);