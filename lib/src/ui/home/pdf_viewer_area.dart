import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

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
  static const Size _kDefaultSignatureSize =
      Size(260, 120); // puntos PDF

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
    final bool signMode = ref.watch(signModeProvider);

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
                    final double scale =
                        pageSize.width / page.width;
                    return Center(
                      child: SizedBox(
                        width: pageSize.width,
                        height: pageSize.height,
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
                                    child: pageImage ?? const SizedBox.shrink(),
                                  ),
                                ),
                              ),
                              if (signMode)
                                Positioned.fill(
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTapUp: (TapUpDetails details) =>
                                        _addPlacementAt(
                                      details.localPosition,
                                      page,
                                      pageSize,
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
                ),
              ),
            );
          },
        );
      },
    );
  }

  static ui.Size _fitPageSize(ui.Size biggest, PdfPage page) {
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
    final List<Widget> widgets = <Widget>[];
    for (int i = 0; i < session.placements.length; i++) {
      final SignaturePlacement placement = session.placements[i];
      if (placement.pageIndex != pageIndex) continue;
      widgets.add(
        SignatureOverlayItem(
          key: ValueKey<int>(i),
          placement: placement,
          scale: scale,
          interactive: true,
          pageSizeInPoints: ui.Size(
            session.document.pages[pageIndex].width,
            session.document.pages[pageIndex].height,
          ),
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
    ui.Size pageSize,
  ) async {
    if (ref.read(signModeProvider) == false) {
      return;
    }

    final SignSetup? setup = await showSignSetupDialog(context);
    if (setup == null || !mounted) {
      return;
    }

    final double scale = pageSize.width / page.width;
    final double left =
        (localPosition.dx / scale - _kDefaultSignatureSize.width / 2)
            .clamp(0.0, page.width - _kDefaultSignatureSize.width);
    final double top =
        (localPosition.dy / scale - _kDefaultSignatureSize.height / 2)
            .clamp(0.0, page.height - _kDefaultSignatureSize.height);

    ref.read(pdfSessionProvider.notifier).addPlacement(
          _page,
          Rect.fromLTWH(
            left,
            top,
            _kDefaultSignatureSize.width,
            _kDefaultSignatureSize.height,
          ),
          profileId: setup.profile.id,
        );
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