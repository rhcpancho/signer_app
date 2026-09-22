import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import '../../models/batch_job.dart';
import '../../models/signature_placement.dart';
import '../../services/pdf_signer_service.dart';

/// Página de progreso y resumen de un lote de firmas.
class BatchProgressPage extends StatefulWidget {
  const BatchProgressPage({super.key, required this.config});

  final BatchJobConfig config;

  @override
  State<BatchProgressPage> createState() => _BatchProgressPageState();
}

class _BatchProgressPageState extends State<BatchProgressPage> {
  final List<BatchFileResult> _results = <BatchFileResult>[];
  int _currentIndex = 0;
  bool _cancelled = false;
  bool _done = false;

  List<BatchFileItem> get _activeFiles =>
      widget.config.files.where((f) => f.selected).toList();

  @override
  void initState() {
    super.initState();
    _runBatch();
  }

  Future<void> _runBatch() async {
    final PdfSignerService service = PdfSignerService();
    final List<BatchFileItem> files = _activeFiles;

    for (int i = 0; i < files.length; i++) {
      if (_cancelled) {
        // Marcar restantes como omitidos
        for (int j = i; j < files.length; j++) {
          setState(() {
            _results.add(BatchFileResult(
              path: files[j].path,
              status: BatchFileStatus.skipped,
            ));
          });
        }
        break;
      }

      setState(() => _currentIndex = i);

      final BatchFileItem file = files[i];
      try {
        final SignaturePlacement? placement =
            await service.defaultPlacementForZone(
          file.bytes,
          profileId: widget.config.profile.id,
          zone: widget.config.zone,
        );
        if (placement == null) {
          setState(() {
            _results.add(BatchFileResult(
              path: file.path,
              status: BatchFileStatus.error,
              errorMessage: 'No se pudo calcular la ubicación de la firma.',
            ));
          });
          continue;
        }

        final Uint8List signed = await service.sign(
          inputBytes: file.bytes,
          requests: <SignRequest>[
            SignRequest(
              placement: placement,
              profile: widget.config.profile,
              certificatePassword: widget.config.password,
            ),
          ],
        );
        await service.save(signed, file.path,
            outputDirectory: widget.config.outputDirectory);

        setState(() {
          _results.add(BatchFileResult(
            path: file.path,
            status: BatchFileStatus.done,
          ));
        });
      } catch (e) {
        setState(() {
          _results.add(BatchFileResult(
            path: file.path,
            status: BatchFileStatus.error,
            errorMessage: '$e',
          ));
        });
      }

      // Yield para que el UI se actualice
      await Future<void>.delayed(Duration.zero);
    }

    if (mounted) setState(() => _done = true);
  }

  void _cancel() => setState(() => _cancelled = true);

  String get _folderPath {
    if (widget.config.outputDirectory != null) {
      return widget.config.outputDirectory!;
    }
    if (_activeFiles.isEmpty) return '';
    return _activeFiles.first.path
        .split(RegExp(r'[\\/]'))
        .sublist(0, _activeFiles.first.path.split(RegExp(r'[\\/]')).length - 1)
        .join(Platform.pathSeparator);
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final int total = _activeFiles.length;
    final int done = _results
        .where((r) => r.status == BatchFileStatus.done)
        .length;
    final int errors = _results
        .where((r) => r.status == BatchFileStatus.error)
        .length;
    final int skipped = _results
        .where((r) => r.status == BatchFileStatus.skipped)
        .length;

    return Scaffold(
      appBar: AppBar(
        title: Text(_done ? 'Resumen del lote' : 'Firmando lote...'),
        leading: _done
            ? null
            : IconButton(
                tooltip: 'Cancelar',
                icon: const Icon(Icons.close),
                onPressed: _cancel,
              ),
      ),
      body: Column(
        children: <Widget>[
          // --- Barra de progreso ---
          if (!_done) ...<Widget>[
            LinearProgressIndicator(
              value: total > 0 ? _results.length / total : 0,
              minHeight: 4,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: <Widget>[
                  Text(
                    '$_currentIndex de $total archivos',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const Spacer(),
                  if (_cancelled)
                    Text(
                      'Cancelado',
                      style: TextStyle(color: scheme.error),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
          ],

          // --- Resumen cabecera (solo al terminar) ---
          if (_done) ...<Widget>[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: scheme.surfaceVariant,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: <Widget>[
                  _SummaryBadge(
                    count: done,
                    label: 'Exitosos',
                    color: Colors.green,
                    icon: Icons.check_circle,
                  ),
                  _SummaryBadge(
                    count: errors,
                    label: 'Errores',
                    color: Colors.red,
                    icon: Icons.error,
                  ),
                  _SummaryBadge(
                    count: skipped,
                    label: 'Omitidos',
                    color: Colors.orange,
                    icon: Icons.skip_next,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
          ],

          // --- Lista de archivos ---
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: _done ? _results.length : _activeFiles.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (BuildContext context, int index) {
                if (_done) {
                  return _ResultTile(result: _results[index]);
                }
                return _ProgressTile(
                  file: _activeFiles[index],
                  status: index < _results.length
                      ? _results[index].status
                      : (index == _currentIndex
                          ? BatchFileStatus.signing
                          : BatchFileStatus.pending),
                  errorMessage: index < _results.length
                      ? _results[index].errorMessage
                      : null,
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: _done
          ? Material(
              color: scheme.surfaceVariant,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: <Widget>[
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cerrar'),
                      ),
                      const Spacer(),
                      FilledButton.icon(
                        onPressed: () async {
                          if (_folderPath.isNotEmpty) {
                            await OpenFilex.open(_folderPath);
                          }
                        },
                        icon: const Icon(Icons.folder_open),
                        label: const Text('Abrir carpeta'),
                      ),
                    ],
                  ),
                ),
              ),
            )
          : null,
    );
  }
}

class _ProgressTile extends StatelessWidget {
  const _ProgressTile({
    required this.file,
    required this.status,
    this.errorMessage,
  });

  final BatchFileItem file;
  final BatchFileStatus status;
  final String? errorMessage;

  String get _fileName => file.path.split(RegExp(r'[\\/]')).last;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Widget leading;
    final Color? trailingColor;

    switch (status) {
      case BatchFileStatus.pending:
        leading = const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
        trailingColor = null;
        break;
      case BatchFileStatus.signing:
        leading = SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: scheme.primary,
          ),
        );
        trailingColor = scheme.primary;
        break;
      case BatchFileStatus.done:
        leading = const Icon(Icons.check_circle, color: Colors.green, size: 20);
        trailingColor = Colors.green;
        break;
      case BatchFileStatus.error:
        leading = const Icon(Icons.error, color: Colors.red, size: 20);
        trailingColor = Colors.red;
        break;
      case BatchFileStatus.skipped:
        leading =
            const Icon(Icons.skip_next, color: Colors.orange, size: 20);
        trailingColor = Colors.orange;
        break;
    }

    return ListTile(
      dense: true,
      leading: leading,
      title: Text(
        _fileName,
        style: const TextStyle(fontSize: 13),
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: errorMessage != null
          ? Text(
              errorMessage!,
              style: TextStyle(color: scheme.error, fontSize: 11),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            )
          : null,
      trailing: status == BatchFileStatus.signing
          ? Text(
              'Firmando...',
              style: TextStyle(color: trailingColor, fontSize: 11),
            )
          : null,
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({required this.result});

  final BatchFileResult result;

  @override
  Widget build(BuildContext context) {
    final Widget leading;
    final Color? statusColor;
    String statusText;

    switch (result.status) {
      case BatchFileStatus.done:
        leading = const Icon(Icons.check_circle, color: Colors.green, size: 20);
        statusColor = Colors.green;
        statusText = 'Firmado';
        break;
      case BatchFileStatus.error:
        leading = const Icon(Icons.error, color: Colors.red, size: 20);
        statusColor = Colors.red;
        statusText = result.errorMessage ?? 'Error';
        break;
      case BatchFileStatus.skipped:
        leading =
            const Icon(Icons.skip_next, color: Colors.orange, size: 20);
        statusColor = Colors.orange;
        statusText = 'Omitido';
        break;
      default:
        leading = const Icon(Icons.help_outline, size: 20);
        statusColor = null;
        statusText = '';
    }

    return ListTile(
      dense: true,
      leading: leading,
      title: Text(
        result.fileName,
        style: const TextStyle(fontSize: 13),
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        statusText,
        style: TextStyle(color: statusColor, fontSize: 11),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _SummaryBadge extends StatelessWidget {
  const _SummaryBadge({
    required this.count,
    required this.label,
    required this.color,
    required this.icon,
  });

  final int count;
  final String label;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 4),
        Text(
          '$count',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: color),
        ),
      ],
    );
  }
}
