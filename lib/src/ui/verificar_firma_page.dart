import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:pdfrx/pdfrx.dart';

import '../models/page_coords.dart';
import '../models/signature_chain.dart';
import '../services/pdf_signer_service.dart';
import '../services/tsa_service.dart';
import 'widgets/signature_frame.dart';
import 'widgets/tsa_status_badge.dart';

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
  TsaResult? _tsaSidecar;

  static const ui.Size _kMinViewerSize = ui.Size(320, 200);

  @override
  void initState() {
    super.initState();
    _controller = PdfViewerController();
    _loadTsaSidecar();
  }

  /// Lee el sidecar `.tsr` junto al PDF verificado (si existe).
  Future<void> _loadTsaSidecar() async {
    try {
      final String path = widget.outputPath;
      if (path.isEmpty) return;
      final File sidecar = File('$path.tsr');
      if (!await sidecar.exists()) return;
      final Uint8List bytes = await sidecar.readAsBytes();
      final TsaResult? r = TsaService.parseTimeStampResponse(bytes);
      if (r != null && mounted) {
        setState(() => _tsaSidecar = r);
      }
    } catch (_) {
      // soft-fail: sin sidecar no invalida la verificación
    }
  }

  void _selectField(int index) {
    setState(() => _selectedIndex = index);
    final PdfSignatureFieldInfo field = widget.report.fields[index];
    if (field.pageIndex != null && field.bounds != null) {
      final ui.Rect b = field.bounds!;
      final double pageHeight =
          field.unrotatedPageSize?.height ?? (b.top + b.height);
      _controller.goToRectInsidePage(
        pageNumber: field.pageIndex! + 1,
        rect: PdfRect(
          b.left,
          pageHeight - b.top,
          b.left + b.width,
          pageHeight - b.top - b.height,
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

          final ui.Size unrotatedSize =
              field.unrotatedPageSize ?? ui.Size(page.width, page.height);
          final ui.Rect displayRect = PageCoords.unrotatedToDisplay(
            rect: field.bounds!,
            unrotatedSize: unrotatedSize,
            rotationDegrees: field.rotationDegrees,
          );
          final double scaleX = pageRect.width / page.width;
          final double scaleY = pageRect.height / page.height;
          final String badge = _verifyBadge(field);
          final Color badgeColor = _verifyBadgeColor(field);
          return <Widget>[
            Positioned(
              left: displayRect.left * scaleX,
              top: displayRect.top * scaleY,
              width: displayRect.width * scaleX,
              height: displayRect.height * scaleY,
              // Key por índice → remount al cambiar de campo → pulse de entrada.
              child: TweenAnimationBuilder<double>(
                key: ValueKey<int>(_selectedIndex ?? -1),
                tween: Tween<double>(begin: 0.4, end: 1.0),
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOut,
                builder: (BuildContext context, double opacity, Widget? child) {
                  return Opacity(opacity: opacity, child: child);
                },
                child: SignatureFrame(
                  style: SignatureFrameStyle.verify,
                  badge: badge,
                  badgeColor: badgeColor,
                  child: const SizedBox.expand(),
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
          child: _selectedIndex == null
              ? (widget.report.fields.isEmpty
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
                    ))
              : _buildSelectedFieldPanel(),
        ),
      ],
    );
  }

  Widget _buildSelectedFieldPanel() {
    final PdfSignatureFieldInfo field = widget.report.fields[_selectedIndex!];
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                field.name ?? 'Firma (sin nombre)',
                style: Theme.of(context).textTheme.titleSmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              tooltip: 'Volver a la lista',
              onPressed: () => setState(() => _selectedIndex = null),
              icon: const Icon(Icons.close, size: 18),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _kv('Página', field.pageIndex == null ? '—' : '${field.pageIndex! + 1}'),
        if (field.signedDate != null)
          _kv('Fecha', _formatDateTime(field.signedDate!)),
        if (field.signedName != null && field.signedName!.isNotEmpty)
          _kv('Firmante', field.signedName!),
        if (field.reason != null && field.reason!.isNotEmpty)
          _kv('Motivo', field.reason!),
        if (field.locationInfo != null && field.locationInfo!.isNotEmpty)
          _kv('Lugar', field.locationInfo!),
        if (field.contactInfo != null && field.contactInfo!.isNotEmpty)
          _kv('Contacto', field.contactInfo!),
        if (field.certSubject != null && field.certSubject!.isNotEmpty)
          _kv('Certificado', field.certSubject!),
        if (field.certIssuer != null && field.certIssuer!.isNotEmpty)
          _kv('Emisor', field.certIssuer!),
        if (field.digestAlgorithm != null)
          _kv('Digest', field.digestAlgorithm!),
        const SizedBox(height: 12),
        if (field.chainInfo != null)
          _ChainPanel(info: field.chainInfo!)
        else if (field.hasSignature)
          Text(
            'Sin CMS extraíble para análisis de cadena.',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
          )
        else
          Text(
            'Campo pendiente de firma.',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
          ),
        if (_tsaSidecar != null) ...<Widget>[
          const SizedBox(height: 8),
          TsaStatusBadge(
            status: TsaStatus.granted,
            result: _tsaSidecar,
          ),
        ],
        const SizedBox(height: 16),
        FilledButton.tonalIcon(
          onPressed: () => setState(() => _selectedIndex = null),
          icon: const Icon(Icons.arrow_back, size: 16),
          label: const Text('Volver a la lista'),
        ),
      ],
    );
  }

  Widget _kv(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
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

String _verifyBadge(PdfSignatureFieldInfo field) {
  if (!field.hasSignature) return 'Pendiente';
  final bool? ok = field.chainInfo?.signatureValidates;
  if (ok == false) return 'Inválida';
  if (ok == true) return 'Válida';
  return 'Firmada';
}

Color _verifyBadgeColor(PdfSignatureFieldInfo field) {
  if (!field.hasSignature) return Colors.orange;
  final bool? ok = field.chainInfo?.signatureValidates;
  if (ok == false) return Colors.red;
  return Colors.green;
}

String _formatDateTime(DateTime date) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(date.day)}/${two(date.month)}/${date.year} '
      '${two(date.hour)}:${two(date.minute)}';
}

Color _validityColor(CertValidity v) {
  switch (v.value) {
    case true:
      return Colors.green;
    case false:
      return Colors.red;
    default:
      return Colors.orange;
  }
}

String _validityText(CertValidity v) {
  switch (v.value) {
    case true:
      return 'Vigente';
    case false:
      return 'No vigente';
    default:
      return 'Sin datos';
  }
}

class _ChainPanel extends StatelessWidget {
  const _ChainPanel({required this.info});

  final SignatureChainInfo info;

  Widget _statusChip(BuildContext context, String label, bool? ok) {
    final Color color = ok == true
        ? Colors.green
        : ok == false
            ? Colors.red
            : Colors.orange;
    final IconData icon = ok == true
        ? Icons.check_circle
        : ok == false
            ? Icons.cancel
            : Icons.help_outline;
    return _MiniChip(label: label, color: color, icon: icon);
  }

  Widget _revocationChip(BuildContext context, RevocationCheck rev) {
    final String suffix = rev.source == RevocationSource.ocsp
        ? ' (OCSP)'
        : rev.source == RevocationSource.crl
            ? ' (CRL)'
            : '';
    return _statusChip(context, 'Revocación$suffix', rev.status.value);
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    if (info.error != null && info.chainNodes.isEmpty) {
      return Card(
        margin: EdgeInsets.zero,
        color: scheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Text(
            'No se pudo analizar la cadena: ${info.error}',
            style: TextStyle(fontSize: 12, color: scheme.onErrorContainer),
          ),
        ),
      );
    }

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Cadena de certificados',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: <Widget>[
                _statusChip(context, 'Integridad', info.documentIntegrityOk),
                _statusChip(
                    context, 'Firma', info.signatureCryptographicOk),
                _statusChip(
                    context, 'Valida', info.signatureValidates),
                _statusChip(
                  context,
                  'Cadena',
                  info.chainComplete ? true : false,
                ),
                if (info.revocation != null)
                  _revocationChip(context, info.revocation!),
              ],
            ),
            if (info.revocation?.note != null) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                'Revocación: ${info.revocation!.note}',
                style: TextStyle(
                  fontSize: 11,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            if (info.signingTime != null) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                'Firmada el ${_formatDateTime(info.signingTime!)}',
                style: TextStyle(
                  fontSize: 11,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            if (info.error != null) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                info.error!,
                style: TextStyle(fontSize: 11, color: scheme.error),
              ),
            ],
            const SizedBox(height: 8),
            if (info.chainNodes.isEmpty)
              Text(
                'Sin certificados embebidos en el CMS.',
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurfaceVariant,
                ),
              )
            else
              ...List<Widget>.generate(
                info.chainNodes.length,
                (int i) => _ChainNodeTile(
                  node: info.chainNodes[i],
                  index: i,
                  isLast: i == info.chainNodes.length - 1,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ChainNodeTile extends StatelessWidget {
  const _ChainNodeTile({
    required this.node,
    required this.index,
    required this.isLast,
  });

  final CertChainNode node;
  final int index;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color vColor = _validityColor(node.validityAtSigning);
    final String role = node.isSelfSigned
        ? (node.isCa ? 'Raíz' : 'Auto-firmado')
        : (node.isCa ? 'CA intermedia' : 'Sello');
    return Padding(
      padding: const EdgeInsets.only(left: 8, top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Column(
            children: <Widget>[
              Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(
                  color: index == 0 ? scheme.primary : vColor,
                  shape: BoxShape.circle,
                ),
              ),
              if (!isLast)
                Container(width: 2, height: 36, color: scheme.outlineVariant),
            ],
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  node.subject,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600),
                ),
                Text(
                  role,
                  style: TextStyle(fontSize: 11, color: scheme.primary),
                ),
                if (node.validFrom != null && node.validTo != null)
                  Text(
                    '${_formatDateTime(node.validFrom!)} → '
                    '${_formatDateTime(node.validTo!)}',
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: _MiniChip(
                    label: _validityText(node.validityAtSigning),
                    color: vColor,
                    icon: node.validityAtSigning.value == true
                        ? Icons.event_available
                        : node.validityAtSigning.value == false
                            ? Icons.event_busy
                            : Icons.event,
                  ),
                ),
                if (node.issuer != node.subject)
                  Text(
                    'Emisor: ${node.issuer}',
                    style: TextStyle(
                      fontSize: 10,
                      color: scheme.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({
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
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
