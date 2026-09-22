import 'dart:io';
import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../models/batch_job.dart';
import '../../models/signature_placement.dart';
import '../../services/file_service.dart';
import '../../services/pdf_signer_service.dart';
import '../../services/signature_setup.dart';
import '../../core/theme_provider.dart';
import '../verificar_firma_page.dart';
import '../widgets/drop_zone_overlay.dart';
import 'batch_progress_page.dart';
import 'batch_setup_dialog.dart';
import 'page_selector_dialog.dart';
import 'pdf_session.dart';
import 'pdf_viewer_area.dart';
import 'signing_banner.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final GlobalKey<PdfViewerAreaState> _viewerKey =
      GlobalKey<PdfViewerAreaState>();
  bool _signing = false;
  bool _opening = false;
  bool _batchBusy = false;
  bool _verifyBusy = false;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final PdfSession? session = ref.watch(pdfSessionProvider);
    final ThemeMode currentTheme = ref.watch(themeModeProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
      appBar: AppBar(
        title: const Text('Signer App — Firma de PDFs'),
        actions: session == null
            ? <Widget>[
                PopupMenuButton<String>(
                  onSelected: (String value) => _onMenuSelected(value),
                  itemBuilder: (BuildContext context) =>
                      <PopupMenuEntry<String>>[
                    ..._buildThemeItems(context, currentTheme),
                  ],
                ),
              ]
            : <Widget>[
                IconButton(
                  tooltip: 'Abrir otro PDF',
                  onPressed: _opening ? null : _openPdf,
                  icon: const Icon(Icons.note_add_outlined),
                ),
                IconButton(
                  tooltip: 'Cerrar documento',
                  onPressed: _closePdf,
                  icon: const Icon(Icons.close),
                ),
                PopupMenuButton<String>(
                  onSelected: (String value) => _onMenuSelected(value),
                  itemBuilder: (BuildContext context) =>
                      <PopupMenuEntry<String>>[
                    const PopupMenuItem<String>(
                      value: 'batch',
                      child: Text('Firmar por lote'),
                    ),
                    const PopupMenuItem<String>(
                      value: 'verify',
                      child: Text('Verificar firma'),
                    ),
                    const PopupMenuItem<String>(
                      value: 'verifyCurrent',
                      child: Text('Verificar documento abierto'),
                    ),
                    const PopupMenuDivider(),
                    ..._buildThemeItems(context, currentTheme),
                  ],
                ),
              ],
      ),
      body: DropTarget(
        onDragEntered: (_) {
          if (!_dragging && mounted) setState(() => _dragging = true);
        },
        onDragExited: (_) {
          if (_dragging && mounted) setState(() => _dragging = false);
        },
        onDragDone: (details) => _handleDrop(details),
        child: Stack(
          children: <Widget>[
            session == null ? _buildEmpty(context) : _buildViewer(),
            DropZoneOverlay(show: _dragging),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.picture_as_pdf_outlined, size: 72),
          const SizedBox(height: 16),
          const Text('No hay un PDF abierto'),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _opening ? null : _openPdf,
            icon: _opening
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.folder_open),
            label: Text(_opening ? 'Abriendo...' : 'Abrir PDF'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _batchBusy ? null : _signBatch,
            icon: _batchBusy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.layers_outlined),
            label: Text(_batchBusy ? 'Procesando...' : 'Firmar por lote'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _verifyBusy ? null : _verify,
            icon: _verifyBusy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_circle_outline),
            label: Text(_verifyBusy ? 'Verificando...' : 'Verificar firma'),
          ),
        ],
      ),
    );
  }

  Widget _buildViewer() {
    return Column(
      children: <Widget>[
        SigningBanner(
          onChangeProfile: _changeProfile,
          onSignAndSave: _confirmSign,
          onCopyToPages: _copyPlacementToPages,
        ),
        Expanded(child: PdfViewerArea(key: _viewerKey)),
        _buildBottomBar(),
      ],
    );
  }

  Widget _buildBottomBar() {
    final PdfSession? session = ref.read(pdfSessionProvider);
    final ActiveSignContext? ctx = ref.read(activeSignContextProvider);
    return Material(
      color: Theme.of(context).colorScheme.surfaceVariant,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: <Widget>[
              IconButton(
                icon: const Icon(Icons.skip_previous),
                tooltip: 'Página anterior',
                onPressed: session == null
                    ? null
                    : () => _viewerKey.currentState?.prevPage(),
              ),
              IconButton(
                icon: const Icon(Icons.skip_next),
                tooltip: 'Página siguiente',
                onPressed: session == null
                    ? null
                    : () => _viewerKey.currentState?.nextPage(),
              ),
              Expanded(
                child: Text(
                  'Página ${(_viewerKey.currentState?.currentPage ?? 0) + 1} de ${session?.pageCount ?? 1}',
                  textAlign: TextAlign.center,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.zoom_in),
                tooltip: 'Acercar',
                onPressed: session == null
                    ? null
                    : () => _viewerKey.currentState?.zoomIn(),
              ),
              IconButton(
                icon: const Icon(Icons.zoom_out),
                tooltip: 'Alejar',
                onPressed: session == null
                    ? null
                    : () => _viewerKey.currentState?.zoomOut(),
              ),
              const SizedBox(width: 4),
              FilledButton.icon(
                onPressed: session == null || _signing ? null : _startSign,
                icon: _signing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(ctx != null ? Icons.check_circle_outline : Icons.draw),
                label: Text(
                  ctx != null
                      ? 'Firmar y guardar'
                      : (_signing ? 'Firmando...' : 'Firmar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openPdf() async {
    final PickedFile? picked = await FileService().pickPdf();
    if (picked == null || !mounted) return;
    setState(() => _opening = true);
    try {
      final PdfDocument document = await PdfDocument.openData(picked.bytes);
      await ref.read(pdfSessionProvider.notifier).load(
        document,
        picked.path,
        picked.bytes,
      );
      ref.read(activeSignContextProvider.notifier).state = null;
    } catch (e) {
      if (mounted) _showSnack('No se pudo abrir el PDF: $e');
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _startSign() async {
    final PdfSession? session = ref.read(pdfSessionProvider);
    if (session == null) return;

    final ActiveSignContext? ctx = ref.read(activeSignContextProvider);

    if (ctx == null) {
      final SignSetup? setup = await showSignSetupDialog(context);
      if (setup == null || !mounted) return;
      ref.read(activeSignContextProvider.notifier).state = ActiveSignContext(
        profile: setup.profile,
        password: setup.password ?? '',
      );
      _showSnack('Toca la página para colocar la firma.');
      return;
    }

    await _confirmSign();
  }

  Future<void> _changeProfile() async {
    final SignSetup? setup = await showSignSetupDialog(context);
    if (setup == null || !mounted) return;
    ref.read(activeSignContextProvider.notifier).state = ActiveSignContext(
      profile: setup.profile,
      password: setup.password ?? '',
    );
  }

  Future<void> _copyPlacementToPages() async {
    final PdfSession? session = ref.read(pdfSessionProvider);
    if (session == null) return;

    // Usar el último placement como referencia
    final SignaturePlacement? last = session.placements.isNotEmpty
        ? session.placements.last
        : null;
    if (last == null) {
      _showSnack('Coloca primero una firma para poder copiarla.');
      return;
    }

    // Páginas que ya tienen una placement (excluyendo la de referencia)
    final Set<int> existingPages = session.placements
        .where((p) => p != last)
        .map((p) => p.pageIndex)
        .toSet();

    final List<int>? selectedPages = await showPageSelectorDialog(
      context,
      totalPages: session.pageCount,
      initiallySelected: existingPages,
    );
    if (selectedPages == null || !mounted) return;

    ref.read(pdfSessionProvider.notifier).addPlacementToPages(
      selectedPages,
      last.rect,
      profileId: last.profileId,
    );

    _showSnack('Firma copiada a ${selectedPages.length} páginas.');
  }

  Future<void> _closePdf() async {
    final PdfSession? session = ref.read(pdfSessionProvider);
    if (session == null) return;

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Cerrar documento'),
        content: const Text(
          '¿Cerrar el documento actual? Se descartarán las firmas '
          'colocadas que no se hayan guardado.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    await ref.read(pdfSessionProvider.notifier).close();
    ref.read(activeSignContextProvider.notifier).state = null;
  }

  Future<void> _confirmSign() async {
    final PdfSession? session = ref.read(pdfSessionProvider);
    final ActiveSignContext? ctx = ref.read(activeSignContextProvider);
    if (session == null || ctx == null) return;

    final List<SignaturePlacement> pending =
        session.placements.where((p) => !p.signed).toList();

    if (pending.isEmpty) {
      _showSnack('Coloca primero una firma tocando sobre el PDF.');
      return;
    }

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Confirmar firma'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Vas a firmar ${pending.length} zona${pending.length == 1 ? '' : 's'} '
              'en este PDF con \u00AB${ctx.profile.name}\u00BB.',
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),
            for (final SignaturePlacement p in pending)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '\u2022 Página ${p.pageIndex + 1}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Firmar'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _signing = true);
    try {
      final List<SignRequest> requests = <SignRequest>[
        for (final SignaturePlacement p in pending)
          SignRequest(
            placement: p,
            profile: ctx.profile,
            certificatePassword: ctx.password,
          ),
      ];

      final PdfSignerService service = PdfSignerService();
      final Uint8List bytes = await service.sign(
        inputBytes: session.sourceBytes,
        requests: requests,
        openPassword: session.openPassword,
      );
      final File output = await service.save(
        bytes,
        session.sourcePath,
      );
      ref.read(pdfSessionProvider.notifier).markAllSigned();
      if (!mounted) return;
      await _showSignSummary(
        output: output,
        count: pending.length,
        profileName: ctx.profile.name,
        signedPlacements: pending,
      );
    } catch (e) {
      if (mounted) _showSnack('Error al firmar: $e');
    } finally {
      if (mounted) setState(() => _signing = false);
    }
  }

  Future<void> _showSignSummary({
    required File output,
    required int count,
    required String profileName,
    required List<SignaturePlacement> signedPlacements,
  }) {
    final Set<int> pages = signedPlacements.map((p) => p.pageIndex + 1).toSet()
      ..toList().sort();
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        icon: const Icon(Icons.verified, size: 48, color: Colors.green),
        title: const Text('Firma completada'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Se firmaron $count zona${count == 1 ? '' : 's'} en este PDF '
                'con \u00AB$profileName\u00BB.',
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 8),
              Text(
                'Páginas: ${pages.join(', ')}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Text(
                'Guardado en:',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 4),
              SelectableText(
                output.path,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                    ),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Listo'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _openPdf();
            },
            child: const Text('Abrir otro PDF'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _closePdf();
            },
            child: const Text('Cerrar documento'),
          ),
          FilledButton.icon(
            onPressed: () async {
              await PdfSignerService().open(output);
              if (context.mounted) Navigator.of(context).pop();
            },
            icon: const Icon(Icons.open_in_new),
            label: const Text('Abrir archivo'),
          ),
        ],
      ),
    );
  }

  Future<void> _signBatch() async {
    if (_batchBusy) return;
    final List<PickedFile>? picked = await FileService().pickPdfs();
    if (picked == null || picked.isEmpty) return;
    if (!mounted) return;

    final SignSetup? setup = await showSignSetupDialog(context);
    if (setup == null || !mounted) return;

    final BatchSetupResult? batchSetup = await showBatchSetupDialog(
      context,
      pickedFiles: picked,
    );
    if (batchSetup == null || !mounted) return;

    final BatchJobConfig config = BatchJobConfig(
      profile: setup.profile,
      password: setup.password,
      zone: batchSetup.zone,
      files: batchSetup.files,
      outputDirectory: batchSetup.outputDirectory,
    );

    setState(() => _batchBusy = true);
    try {
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => BatchProgressPage(config: config),
        ),
      );
    } finally {
      if (mounted) setState(() => _batchBusy = false);
    }
  }

  Future<void> _verify() async {
    if (_verifyBusy) return;
    final PickedFile? picked = await FileService().pickPdf();
    if (picked == null) return;

    setState(() => _verifyBusy = true);
    try {
      final PdfSignatureDetailReport report =
          await PdfSignerService().inspectSignatureDetails(picked.bytes);
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => VerificarFirmaPage(
            report: report,
            sourceBytes: picked.bytes,
            fileName: picked.path.split(RegExp(r'[\\/]')).last,
            outputPath: picked.path,
          ),
        ),
      );
    } catch (e) {
      if (mounted) _showSnack('No se pudo verificar: $e');
    } finally {
      if (mounted) setState(() => _verifyBusy = false);
    }
  }

  Future<void> _verifyCurrent() async {
    final PdfSession? session = ref.read(pdfSessionProvider);
    if (session == null) return;

    setState(() => _verifyBusy = true);
    try {
      final PdfSignatureDetailReport report =
          await PdfSignerService().inspectSignatureDetails(
        session.sourceBytes,
        openPassword: session.openPassword,
      );
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => VerificarFirmaPage(
            report: report,
            sourceBytes: session.sourceBytes,
            fileName: session.sourcePath.split(RegExp(r'[\\/]')).last,
            outputPath: session.sourcePath,
          ),
        ),
      );
    } catch (e) {
      if (mounted) _showSnack('No se pudo verificar: $e');
    } finally {
      if (mounted) setState(() => _verifyBusy = false);
    }
  }

  void _onMenuSelected(String value) {
    switch (value) {
      case 'batch':
        _signBatch();
        break;
      case 'verify':
        _verify();
        break;
      case 'verifyCurrent':
        _verifyCurrent();
        break;
      case 'themeLight':
        ref.read(themeModeProvider.notifier).setThemeMode(ThemeMode.light);
        break;
      case 'themeDark':
        ref.read(themeModeProvider.notifier).setThemeMode(ThemeMode.dark);
        break;
      case 'themeSystem':
        ref.read(themeModeProvider.notifier).setThemeMode(ThemeMode.system);
        break;
    }
  }

  List<PopupMenuEntry<String>> _buildThemeItems(
    BuildContext context,
    ThemeMode current,
  ) {
    return <PopupMenuEntry<String>>[
      CheckedPopupMenuItem<String>(
        value: 'themeLight',
        checked: current == ThemeMode.light,
        child: const Text('Tema claro'),
      ),
      CheckedPopupMenuItem<String>(
        value: 'themeDark',
        checked: current == ThemeMode.dark,
        child: const Text('Tema oscuro'),
      ),
      CheckedPopupMenuItem<String>(
        value: 'themeSystem',
        checked: current == ThemeMode.system,
        child: const Text('Tema del sistema'),
      ),
    ];
  }

  Future<void> _handleDrop(DropDoneDetails details) async {
    if (!mounted) return;
    setState(() => _dragging = false);

    final List<String> paths = details.files
        .map((file) => file.path)
        .toList();
    if (paths.isEmpty) return;

    final List<String> pdfs = <String>[];
    final List<String> certs = <String>[];
    for (final String p in paths) {
      final String lower = p.toLowerCase();
      if (lower.endsWith('.pdf')) {
        pdfs.add(p);
      } else if (lower.endsWith('.pfx') || lower.endsWith('.p12')) {
        certs.add(p);
      }
    }

    if (pdfs.length == 1 && certs.isEmpty) {
      await _openPdfFromPath(pdfs.first);
    } else if (pdfs.length > 1 && certs.isEmpty) {
      await _signBatchFromPaths(pdfs);
    } else if (pdfs.isEmpty && certs.length == 1) {
      await _importCertificateFromPath(certs.first);
    } else if (pdfs.isNotEmpty) {
      await _signBatchFromPaths(pdfs);
    }
  }

  Future<void> _openPdfFromPath(String path) async {
    final PickedFile? picked = await FileService.fromDroppedPath(path);
    if (picked == null || !mounted) return;
    setState(() => _opening = true);
    try {
      final PdfDocument document = await PdfDocument.openData(picked.bytes);
      await ref.read(pdfSessionProvider.notifier).load(
        document,
        picked.path,
        picked.bytes,
      );
      ref.read(activeSignContextProvider.notifier).state = null;
    } catch (e) {
      if (mounted) _showSnack('No se pudo abrir el PDF: $e');
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _signBatchFromPaths(List<String> paths) async {
    if (_batchBusy) return;
    final List<PickedFile> files = <PickedFile>[];
    for (final String p in paths) {
      final PickedFile? f = await FileService.fromDroppedPath(p);
      if (f != null) files.add(f);
    }
    if (files.isEmpty || !mounted) return;

    final SignSetup? setup = await showSignSetupDialog(context);
    if (setup == null || !mounted) return;

    final BatchSetupResult? batchSetup = await showBatchSetupDialog(
      context,
      pickedFiles: files,
    );
    if (batchSetup == null || !mounted) return;

    final BatchJobConfig config = BatchJobConfig(
      profile: setup.profile,
      password: setup.password,
      zone: batchSetup.zone,
      files: batchSetup.files,
      outputDirectory: batchSetup.outputDirectory,
    );

    setState(() => _batchBusy = true);
    try {
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => BatchProgressPage(config: config),
        ),
      );
    } finally {
      if (mounted) setState(() => _batchBusy = false);
    }
  }

  Future<void> _importCertificateFromPath(String path) async {
    final PickedFile? picked = await FileService.fromDroppedPath(path);
    if (picked == null || !mounted) return;

    final SignSetup? setup = await showSignSetupDialog(context);
    if (setup == null || !mounted) return;

    _showSnack('Certificado importado: ${setup.profile.name}');
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
