import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:pdfrx/pdfrx.dart';

import '../services/pdf_signer_service.dart';

class VerificarFirmaPage extends StatefulWidget {
  const VerificarFirmaPage({
    super.key,
    required this.report,
    required this.sourceBytes,
    required this.fileName,
    required this.outputPath,
  });

  final PdfSignatureDetailReport report;
  final Uint8List sourceBytes;
  final String fileName;
  final String outputPath;

  @override
  State<VerificarFirmaPage> createState() => _VerificarFirmaPageState();
}

class _VerificarFirmaPageState extends State<VerificarFirmaPage> {
  int? _selectedIndex;
  late final PdfViewerController _controller;

  static const ui.Size _kMinViewerSize = ui.Size(320, 200);

  @override
  void initState() {
    super.initState();
    _controller = PdfViewerController();
  }

  void _selectField(int index) {
    setState(() => _selectedIndex = index);
    final PdfSignatureFieldInfo field = widget.report.fields[index];
    if (field.pageIndex != null && field.bounds != null) {
      final ui.Rect b = field.bounds!;
      _controller.goToRectInsidePage(
        pageNumber: field.pageIndex! + 1,
        rect: PdfRect(
          b.left,
          b.top + b.height,
          b.left + b.width,
          b.top,
        ),
      );
    } else if (field.pageIndex != null) {
      _controller.goToPage(pageNumber: field.pageIndex! + 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Verificación de firmas'),
      ),
      body: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final bool horizontal = constraints.maxWidth > 800;
          if (horizontal) {
            return _buildHorizontalSplit(constraints);
          } else {
            return _buildVerticalSplit(constraints);
          }
        },
      ),
      bottomNavigationBar: _buildBottomBar(context),
    );
  }

  Widget _buildHorizontalSplit(BoxConstraints constraints) {
    return Row(
      children: <Widget>[
        Expanded(
          child: _buildViewer(),
        ),
        const VerticalDivider(width: 1),
        SizedBox(
          width: 360,
          child: _buildDetailsPanel(),
        ),
      ],
    );
  }

  Widget _buildVerticalSplit(BoxConstraints constraints) {
    return Column(
      children: <Widget>[
        SizedBox(
          height: (constraints.maxHeight * 0.5).clamp(
            _kMinViewerSize.height,
            constraints.maxHeight - 200,
          ),
          child: _buildViewer(),
        ),
        const Divider(height: 1),
        Expanded(
          child: _buildDetailsPanel(),
        ),
      ],
    );
  }

  Widget _buildViewer() {
    return PdfViewer.data(
      widget.sourceBytes,
      sourceName: widget.fileName,
      controller: _controller,
      params: PdfViewerParams(
        pageOverlaysBuilder: (
          BuildContext context,
          ui.Rect pageRect,
          PdfPage page,
        ) {
          if (_selectedIndex == null) return <Widget>[];
          final PdfSignatureFieldInfo field =
              widget.report.fields[_selectedIndex!];
          if (field.pageIndex == null) return <Widget>[];
          if (field.pageIndex! != page.pageNumber - 1) return <Widget>[];
          if (field.bounds == null) return <Widget>[];

          final double scaleX = pageRect.width / page.width;
          final double scaleY = pageRect.height / page.height;
          final ui.Rect r = field.bounds!;
          return <Widget>[
            Positioned(
              left: r.left * scaleX,
              top: r.top * scaleY,
              width: r.width * scaleX,
              height: r.height * scaleY,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.25),
                  border: Border.all(color: Colors.blue, width: 2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ];
        },
      ),
    );
  }

  Widget _buildDetailsPanel() {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Column(
      children: <Widget>[
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          color: scheme.surfaceVariant,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                widget.fileName,
                style: Theme.of(context).textTheme.titleSmall,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Row(
                children: <Widget>[
                  _Badge(
                    label:
                        '${widget.report.signed} Firmada${widget.report.signed == 1 ? '' : 's'}',
                    color: Colors.green,
                    icon: Icons.verified,
                  ),
                  const SizedBox(width: 6),
                  if (widget.report.pending > 0)
                    _Badge(
                      label:
                          '${widget.report.pending} Pendiente${widget.report.pending == 1 ? '' : 's'}',
                      color: Colors.orange,
                      icon: Icons.edit_outlined,
                    ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: widget.report.fields.isEmpty
              ? const Center(
                  child: Text('No se encontraron campos de firma.'),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: widget.report.fields.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 2),
                  itemBuilder: (BuildContext context, int index) {
                    final PdfSignatureFieldInfo field =
                        widget.report.fields[index];
                    final bool selected = _selectedIndex == index;
                    return _FieldTile(
                      field: field,
                      selected: selected,
                      onTap: () => _selectField(index),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceVariant,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cerrar'),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: () async {
                  final File file = File(widget.outputPath);
                  if (await file.exists()) {
                    await OpenFilex.open(widget.outputPath);
                  }
                },
                icon: const Icon(Icons.open_in_new),
                label: const Text('Abrir archivo'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FieldTile extends StatelessWidget {
  const _FieldTile({
    required this.field,
    required this.selected,
    required this.onTap,
  });

  final PdfSignatureFieldInfo field;
  final bool selected;
  final VoidCallback onTap;

  static String _formatDate(DateTime date) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year} '
        '${two(date.hour)}:${two(date.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool signed = field.hasSignature;
    final bool certExpired =
        field.certValidTo != null && field.certValidTo!.isBefore(DateTime.now());
    final Color statusColor =
        signed ? (certExpired ? Colors.red : Colors.green) : Colors.orange;

    return Material(
      color: selected
          ? scheme.primaryContainer.withOpacity(0.5)
          : Colors.transparent,
      child: ListTile(
        dense: true,
        selected: selected,
        selectedTileColor: scheme.primaryContainer.withOpacity(0.3),
        leading: Icon(
          signed ? Icons.verified : Icons.edit_outlined,
          color: statusColor,
          size: 20,
        ),
        title: Text(
          field.name ?? 'Firma (sin nombre)',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              signed
                  ? (field.signedDate != null
                      ? 'Firmada el ${_formatDate(field.signedDate!)}'
                      : 'Firmada')
                  : 'Pendiente',
              style: TextStyle(color: statusColor, fontSize: 11),
            ),
            if (field.signedName != null && field.signedName!.isNotEmpty)
              Text(
                field.signedName!,
                style: TextStyle(
                    color: scheme.onSurfaceVariant, fontSize: 11),
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        trailing: Text(
          field.pageIndex == null ? '—' : 'Pág. ${field.pageIndex! + 1}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        onTap: onTap,
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.label,
    required this.color,
    required this.icon,
  });

  final String label;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
