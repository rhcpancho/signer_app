import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../models/certificate_profile.dart';
import '../../models/signature_placement.dart';
import '../../services/signature_setup.dart';
import '../widgets/signature_overlay_item.dart';
import 'pdf_session.dart';

class PdfViewerArea extends ConsumerStatefulWidget {
  const PdfViewerArea({super.key});

  @override
  ConsumerState<PdfViewerArea> createState() => PdfViewerAreaState();
}

class PdfViewerAreaState extends ConsumerState<PdfViewerArea> {
  static const double _kMinZoom = 0.4;
  static const double _kMaxZoom = 8.0;
  static const double _kMargin = 28;
  static const double _kRubricTargetHeight = 64;
  static const double _kTextBoxHeight = 52;
  static const double _kTextBoxPaddingX = 40;
  static const double _kMinBoxWidth = 60;
  static const double _kMaxBoxWidth = 220;

  final PageController _pageController = PageController();
  final Map<int, TransformationController> _txControllers =
      <int, TransformationController>{};

  int _page = 0;
  double _zoom = 1.0;
  Size _viewport = Size.zero;

  int get currentPage => _page;

  TransformationController _txFor(int pageIndex) =>
      _txControllers.putIfAbsent(
        pageIndex,
        TransformationController.new,
      );

  void _applyCurrentZoom() {
    if (_viewport.isEmpty) return;
    _txFor(_page).value = _centerZoomMatrix(_zoom, _viewport);
  }

  static Matrix4 _centerZoomMatrix(double scale, Size view) {
    final Matrix4 matrix = Matrix4.identity();
    matrix.translate(view.width / 2, view.height / 2);
    matrix.scale(scale, scale, 1);
    matrix.translate(-view.width / 2, -view.height / 2);
    return matrix;
  }

  void zoomIn() => _setZoom(_zoom * 1.25);

  void zoomOut() => _setZoom(_zoom / 1.25);

  void resetZoom() => _setZoom(1.0);

  double get zoomFactor => _zoom;

  void _setZoom(double value) {
    if (!mounted) return;
    setState(() => _zoom = value.clamp(_kMinZoom, _kMaxZoom));
    _applyCurrentZoom();
  }

  void nextPage() {
    final PdfSession? session = ref.read(pdfSessionProvider);
    if (session == null || _page >= session.pageCount - 1) return;
    _pageController.nextPage(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
    );
  }

  void prevPage() {
    if (_page <= 0) return;
    _pageController.previousPage(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
    );
  }

  void goToPage(int pageIndex) {
    _pageController.jumpToPage(pageIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    for (final TransformationController tx in _txControllers.values) {
      tx.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final PdfSession? session = ref.watch(pdfSessionProvider);
    final ActiveSignContext? signCtx = ref.watch(activeSignContextProvider);

    if (session == null) {
      return const _NoDocumentView();
    }

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        _viewport = constraints.biggest;
        return PageView.builder(
          controller: _pageController,
          itemCount: session.pageCount,
          onPageChanged: (int index) => setState(() => _page = index),
          itemBuilder: (BuildContext context, int index) {
            final PdfPage page = session.document.pages[index];
            return InteractiveViewer(
              transformationController: _txFor(index),
              constrained: true,
              boundaryMargin: const EdgeInsets.all(160),
              minScale: _kMinZoom,
              maxScale: _kMaxZoom,
              onInteractionEnd: (_) => _applyCurrentZoom(),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: PdfPageView(
                  document: session.document,
                  pageNumber: index + 1,
                  maximumDpi: 300,
                  pageSizeCallback: _fitPageSize,
                  decorationBuilder: (BuildContext context, ui.Size pageSize,
                      _, RawImage? pageImage) {
                    // pageSize está en píxeles físicos (×DPR); el layout y la
                    // escala de overlays/taps deben usar constraints lógicos.
                    return LayoutBuilder(
                      builder: (BuildContext context, BoxConstraints c) {
                        final double availW = c.maxWidth - _kMargin;
                        final double availH = c.maxHeight - _kMargin;
                        final double scale = (availW <= 0 || availH <= 0)
                            ? 1.0
                            : (availW / page.width < availH / page.height)
                                ? availW / page.width
                                : availH / page.height;
                        return Center(
                          child: SizedBox(
                            width: page.width * scale,
                            height: page.height * scale,
                            child: DecoratedBox(
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                boxShadow: <BoxShadow>[
                                  BoxShadow(
                                    color: Colors.black26,
                                    blurRadius: 8,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Stack(
                                children: <Widget>[
                                  Positioned.fill(
                                    child: ClipRect(
                                      child: FittedBox(
                                        fit: BoxFit.fill,
                                        child: pageImage ??
                                            const SizedBox.shrink(),
                                      ),
                                    ),
                                  ),
                                  if (signCtx != null)
                                    Positioned.fill(
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTapUp: (TapUpDetails details) =>
                                            _addPlacementAt(
                                          details.localPosition,
                                          page,
                                          scale,
                                          signCtx,
                                        ),
                                      ),
                                    ),
                                  ..._buildPageOverlays(
                                    pageIndex: index,
                                    scale: scale,
                                    session: session,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }

  static ui.Size _fitPageSize(ui.Size biggest, PdfPage page) {
    // `biggest` llega en píxeles físicos (pdfrx multiplica ×DPR); sirve solo
    // para resolver la resolución de render, no el layout lógico.
    final double availWidth = biggest.width - _kMargin;
    final double availHeight = biggest.height - _kMargin;
    if (availWidth <= 0 || availHeight <= 0) {
      return ui.Size(page.width, page.height);
    }
    final double scale =
        (availWidth / page.width < availHeight / page.height)
            ? availWidth / page.width
            : availHeight / page.height;
    return ui.Size(page.width * scale, page.height * scale);
  }

  List<Widget> _buildPageOverlays({
    required int pageIndex,
    required double scale,
    required PdfSession session,
  }) {
    final List<CertificateProfile> profiles =
        ref.read(certificateProfilesProvider).value ?? <CertificateProfile>[];
    final List<Widget> widgets = <Widget>[];
    for (int i = 0; i < session.placements.length; i++) {
      final SignaturePlacement placement = session.placements[i];
      if (placement.pageIndex != pageIndex) continue;
        final CertificateProfile? profile = profiles
            .where((p) => p.id == placement.profileId)
            .firstOrNull;
        widgets.add(
          SignatureOverlayItem(
            key: ValueKey<int>(i),
            placement: placement,
            scale: scale,
            interactive: true,
            // Hover/selected local se resuelve dentro del overlay.
            pageSizeInPoints: ui.Size(
              session.document.pages[pageIndex].width,
              session.document.pages[pageIndex].height,
            ),
            profileName: profile?.name,
            hasRubric: profile?.hasRubric ?? false,
            rubricBytes: profile?.signatureBytes,
            onChanged: (Rect rect) =>
                ref.read(pdfSessionProvider.notifier).updatePlacement(i, rect),
            onRemove: () =>
                ref.read(pdfSessionProvider.notifier).removePlacement(i),
          ),
        );
    }
    return widgets;
  }

  Future<void> _addPlacementAt(
    Offset localPosition,
    PdfPage page,
    double scale,
    ActiveSignContext signCtx,
  ) async {
    final Size boxSize = await _signatureSizeForProfile(signCtx.profile);
    final double left =
        (localPosition.dx / scale - boxSize.width / 2)
            .clamp(0.0, page.width - boxSize.width);
    final double top =
        (localPosition.dy / scale - boxSize.height / 2)
            .clamp(0.0, page.height - boxSize.height);

    ref.read(pdfSessionProvider.notifier).addPlacement(
          _page,
          Rect.fromLTWH(left, top, boxSize.width, boxSize.height),
          profileId: signCtx.profile.id,
        );
  }

  static Future<ui.Size> _signatureSizeForProfile(
    CertificateProfile profile,
  ) async {
    if (profile.hasRubric &&
        profile.signatureBytes.isNotEmpty) {
      final ui.Codec codec =
          await ui.instantiateImageCodec(profile.signatureBytes);
      final ui.FrameInfo frame = await codec.getNextFrame();
      final int imgW = frame.image.width;
      final int imgH = frame.image.height;
      frame.image.dispose();
      if (imgH > 0) {
        final double width =
            (_kRubricTargetHeight * imgW / imgH)
                .clamp(_kMinBoxWidth, _kMaxBoxWidth);
        return ui.Size(width, _kRubricTargetHeight);
      }
    }

    final String name =
        profile.name.isNotEmpty ? profile.name : 'Firma';
    final TextPainter painter = TextPainter(
      text: TextSpan(
        text: name,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    painter.layout();
    final double textWidth = painter.width;
    painter.dispose();

    final double width =
        (textWidth + _kTextBoxPaddingX)
            .clamp(_kMinBoxWidth, _kMaxBoxWidth);
    return ui.Size(width, _kTextBoxHeight);
  }
}

class _NoDocumentView extends StatelessWidget {
  const _NoDocumentView();

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.picture_as_pdf_outlined, size: 72, color: scheme.outline),
          const SizedBox(height: 16),
          Text(
            'Aún no hay ningún documento',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Pulsa «Abrir PDF» en la barra superior para empezar.',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
