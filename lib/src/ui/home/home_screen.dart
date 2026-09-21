import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../models/signature_placement.dart';
import '../../services/file_service.dart';
import '../../services/pdf_signer_service.dart';
import '../../services/signature_setup.dart';
import 'pdf_session.dart';
import 'pdf_viewer_area.dart';

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

  @override
  Widget build(BuildContext context) {
    final PdfSession? session = ref.watch(pdfSessionProvider);
    final bool signMode = ref.watch(signModeProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
      appBar: AppBar(
        title: const Text('Signer App — Firma de PDFs'),
        actions: session == null
            ? null
            : <Widget>[
                IconButton(
                  tooltip: signMode
                      ? 'Terminar de colocar firmas'
                      : 'Colocar firma',
                  onPressed: () =>
                      ref.read(signModeProvider.notifier).state = !signMode,
                  icon: Icon(
                    signMode ? Icons.draw : Icons.draw_outlined,
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (String value) {
                    switch (value) {
                      case 'batch':
                        _signBatch();
                        break;
                      case 'verify':
                        _verify();
                        break;
                    }
                  },
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
                  ],
                ),
              ],
      ),
      body: session == null ? _buildEmpty(context) : _buildViewer(),
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
            icon: const Icon(Icons.folder_open),
            label: const Text('Abrir PDF'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _batchBusy ? null : _signBatch,
            icon: const Icon(Icons.layers_outlined),
            label: const Text('Firmar por lote'),
          ),
        ],
      ),
    );
  }

  Widget _buildViewer() {
    return Column(
      children: <Widget>[
        Expanded(child: PdfViewerArea(key: _viewerKey)),
        _buildBottomBar(),
      ],
    );
  }

  Widget _buildBottomBar() {
    final PdfSession? session = ref.read(pdfSessionProvider);
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
                tooltip: 'Pagina anterior',
                onPressed: session == null
                    ? null
                    : () => _viewerKey.currentState?.prevPage(),
              ),
              IconButton(
                icon: const Icon(Icons.skip_next),
                tooltip: 'Pagina siguiente',
                onPressed: session == null
                    ? null
                    : () => _viewerKey.currentState?.nextPage(),
              ),
              Expanded(
                child: Text(
                  'Pagina ${(_viewerKey.currentState?.currentPage ?? 0) + 1}',
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
                icon: const Icon(Icons.draw),
                label: const Text('Firmar'),
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
    } catch (e) {
      if (mounted) _showSnack('No se pudo abrir el PDF: $e');
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _startSign() async {
    final PdfSession? session = ref.read(pdfSessionProvider);
    if (session == null) return;

    if (session.placements.isEmpty) {
      _showSnack('Coloca primero una firma tocando sobre el PDF.');
      ref.read(signModeProvider.notifier).state = true;
      return;
    }

    final SignSetup? setup = await showSignSetupDialog(context);
    if (setup == null || !mounted) return;

    setState(() => _signing = true);
    try {
      final List<SignRequest> requests = <SignRequest>[
        for (final SignaturePlacement placement in session.placements)
          if (!placement.signed)
            SignRequest(
              placement: placement,
              profile: setup.profile,
              certificatePassword: setup.password,
            ),
      ];
      if (requests.isEmpty) {
        _showSnack('No hay firmas pendientes por aplicar.');
        return;
      }

      final PdfSignerService service = PdfSignerService();
      final Uint8List bytes = await service.sign(
        inputBytes: session.sourceBytes,
        requests: requests,
        openPassword: session.openPassword,
      );
      final File output = await service.saveAndOpen(
        bytes,
        session.sourcePath,
      );
      final String signedPath = output.path;
      ref.read(pdfSessionProvider.notifier).markAllSigned();
      if (!mounted) return;
      _showSnack('PDF firmado y guardado en $signedPath');
    } catch (e) {
      if (mounted) _showSnack('Error al firmar: $e');
    } finally {
      if (mounted) setState(() => _signing = false);
    }
  }

  Future<void> _signBatch() async {
    if (_batchBusy) return;
    final List<PickedFile>? picked = await FileService().pickPdfs();
    if (picked == null || picked.isEmpty) return;
    if (!mounted) return;

    final SignSetup? setup = await showSignSetupDialog(context);
    if (setup == null || !mounted) return;

    setState(() => _batchBusy = true);
    final PdfSignerService service = PdfSignerService();
    int ok = 0;
    try {
      for (final PickedFile file in picked) {
        final SignaturePlacement? placement =
            await service.defaultPlacementForLastPage(
          file.bytes,
          profileId: setup.profile.id,
        );
        if (placement == null) continue;
        final Uint8List bytes = await service.sign(
          inputBytes: file.bytes,
          requests: <SignRequest>[
            SignRequest(
              placement: placement,
              profile: setup.profile,
              certificatePassword: setup.password,
            ),
          ],
        );
        await service.save(bytes, file.path);
        ok++;
      }
      if (!mounted) return;
      _showSnack('Firmados $ok de ${picked.length}');
    } catch (e) {
      if (mounted) _showSnack('Error en el lote: $e');
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
      await _showSignatureReport(report);
    } catch (e) {
      if (mounted) _showSnack('No se pudo verificar: $e');
    } finally {
      if (mounted) setState(() => _verifyBusy = false);
    }
  }

  Future<void> _showSignatureReport(PdfSignatureDetailReport report) {
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Verificacion de firmas'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SelectableText(
                'Firmadas: ${report.signed} | Pendientes: ${report.pending}',
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 4),
              if (report.fields.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text('No se encontraron campos de firma.'),
                )
              else
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: <Widget>[
                      for (final PdfSignatureFieldInfo field in report.fields)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            field.hasSignature
                                ? Icons.verified
                                : Icons.edit_outlined,
                            color: field.hasSignature
                                ? Colors.green
                                : Colors.orange,
                          ),
                          title: Text(field.name ?? 'Firma (sin nombre)'),
                          subtitle: Text(
                            field.hasSignature
                                ? (field.signedDate != null
                                    ? 'Firmada el ${field.signedDate}'
                                    : 'Firmada')
                                : 'Pendiente',
                          ),
                          trailing: Text(
                            field.pageIndex == null
                                ? '—'
                                : 'Pag. ${field.pageIndex! + 1}',
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
