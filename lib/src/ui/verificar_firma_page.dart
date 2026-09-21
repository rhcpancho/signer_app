import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import '../services/pdf_signer_service.dart';

class VerificarFirmaPage extends StatelessWidget {
  const VerificarFirmaPage({
    super.key,
    required this.report,
    required this.fileName,
    required this.outputPath,
  });

  final PdfSignatureDetailReport report;
  final String fileName;
  final String outputPath;

  static String _formatDate(DateTime date) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year} '
        '${two(date.hour)}:${two(date.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Verificación de firmas'),
      ),
      body: Column(
        children: <Widget>[
          _buildHeader(context, scheme),
          const Divider(height: 1),
          Expanded(
            child: report.fields.isEmpty
                ? const Center(
                    child: Text('No se encontraron campos de firma.'),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: report.fields.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (BuildContext context, int index) =>
                        _buildFieldCard(context, scheme, report.fields[index]),
                  ),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomBar(context, scheme),
    );
  }

  Widget _buildHeader(BuildContext context, ColorScheme scheme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      color: scheme.surfaceVariant,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            fileName,
            style: Theme.of(context).textTheme.titleMedium,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              _Badge(
                label: '${report.signed} Firmada${report.signed == 1 ? '' : 's'}',
                color: Colors.green,
                icon: Icons.verified,
              ),
              const SizedBox(width: 8),
              if (report.pending > 0)
                _Badge(
                  label: '${report.pending} Pendiente${report.pending == 1 ? '' : 's'}',
                  color: Colors.orange,
                  icon: Icons.edit_outlined,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFieldCard(
    BuildContext context,
    ColorScheme scheme,
    PdfSignatureFieldInfo field,
  ) {
    final bool signed = field.hasSignature;
    final bool certExpired = field.certValidTo != null &&
        field.certValidTo!.isBefore(DateTime.now());
    final Color statusColor =
        signed ? (certExpired ? Colors.red : Colors.green) : Colors.orange;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: Icon(
          signed ? Icons.verified : Icons.edit_outlined,
          color: statusColor,
        ),
        title: Text(
          field.name ?? 'Firma (sin nombre)',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          signed
              ? (field.signedDate != null
                  ? 'Firmada el ${_formatDate(field.signedDate!)}'
                  : 'Firmada')
              : 'Pendiente',
          style: TextStyle(color: statusColor),
        ),
        trailing: Text(
          field.pageIndex == null ? '—' : 'Pág. ${field.pageIndex! + 1}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (field.signedName != null &&
                    field.signedName!.isNotEmpty)
                  _DetailRow(label: 'Firmante', value: field.signedName!),
                if (field.reason != null && field.reason!.isNotEmpty)
                  _DetailRow(label: 'Motivo', value: field.reason!),
                if (field.locationInfo != null &&
                    field.locationInfo!.isNotEmpty)
                  _DetailRow(label: 'Lugar', value: field.locationInfo!),
                if (field.digestAlgorithm != null)
                  _DetailRow(
                      label: 'Algoritmo', value: field.digestAlgorithm!),
                if (field.certSubject != null &&
                    field.certSubject!.isNotEmpty) ...<Widget>[
                  const Divider(height: 16),
                  _DetailRow(label: 'Certificado', value: field.certSubject!),
                  if (field.certIssuer != null &&
                      field.certIssuer!.isNotEmpty)
                    _DetailRow(label: 'Emisor', value: field.certIssuer!),
                  if (field.certValidFrom != null)
                    _DetailRow(
                      label: 'Válido desde',
                      value: _formatDate(field.certValidFrom!),
                    ),
                  if (field.certValidTo != null)
                    _DetailRow(
                      label: 'Válido hasta',
                      value: _formatDate(field.certValidTo!),
                    ),
                  if (certExpired)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        children: <Widget>[
                          Icon(Icons.warning_amber,
                              size: 16, color: scheme.error),
                          const SizedBox(width: 4),
                          Text(
                            'Certificado vencido',
                            style: TextStyle(
                                color: scheme.error,
                                fontWeight: FontWeight.w600,
                                fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context, ColorScheme scheme) {
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
                  final File file = File(outputPath);
                  if (await file.exists()) {
                    await OpenFilex.open(outputPath);
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 110,
            child: Text(
              '$label:',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
