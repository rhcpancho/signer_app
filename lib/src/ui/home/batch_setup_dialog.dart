import 'package:flutter/material.dart';

import '../../models/batch_job.dart';
import '../../services/file_service.dart';

/// Resultado del diálogo de configuración de lote.
class BatchSetupResult {
  const BatchSetupResult({
    required this.zone,
    required this.files,
    this.outputDirectory,
  });

  final BatchPlacementZone zone;
  final List<BatchFileItem> files;
  final String? outputDirectory;
}

/// Abre el diálogo de configuración de lote.
Future<BatchSetupResult?> showBatchSetupDialog(
  BuildContext context, {
  required List<PickedFile> pickedFiles,
}) {
  return showDialog<BatchSetupResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _BatchSetupDialog(pickedFiles: pickedFiles),
  );
}

class _BatchSetupDialog extends StatefulWidget {
  const _BatchSetupDialog({required this.pickedFiles});

  final List<PickedFile> pickedFiles;

  @override
  State<_BatchSetupDialog> createState() => _BatchSetupDialogState();
}

class _BatchSetupDialogState extends State<_BatchSetupDialog> {
  late final List<BatchFileItem> _files;
  BatchPlacementZone _zone = BatchPlacementZone.lastPageBottomRight;
  bool _useCustomDirectory = false;
  String? _outputDirectory;

  @override
  void initState() {
    super.initState();
    _files = <BatchFileItem>[
      for (final PickedFile f in widget.pickedFiles)
        BatchFileItem(path: f.path, bytes: f.bytes),
    ];
  }

  int get _selectedCount => _files.where((f) => f.selected).length;

  void _toggleAll(bool? value) {
    setState(() {
      for (final BatchFileItem f in _files) {
        f.selected = value ?? true;
      }
    });
  }

  Future<void> _pickDirectory() async {
    final String? dir = await FileService().pickDirectory();
    if (dir != null) {
      setState(() => _outputDirectory = dir);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool allSelected = _files.every((f) => f.selected);
    final bool noneSelected = _files.every((f) => !f.selected);

    return AlertDialog(
      title: const Text('Configurar firma por lote'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // --- Zona de colocación ---
              Text(
                'Zona de firma',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<BatchPlacementZone>(
                value: _zone,
                isExpanded: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: const <DropdownMenuItem<BatchPlacementZone>>[
                  DropdownMenuItem<BatchPlacementZone>(
                    value: BatchPlacementZone.lastPageBottomRight,
                    child: Text('Última página — esquina inferior derecha'),
                  ),
                  DropdownMenuItem<BatchPlacementZone>(
                    value: BatchPlacementZone.lastPageCenter,
                    child: Text('Última página — centro'),
                  ),
                  DropdownMenuItem<BatchPlacementZone>(
                    value: BatchPlacementZone.firstPageBottomRight,
                    child: Text('Primera página — esquina inferior derecha'),
                  ),
                  DropdownMenuItem<BatchPlacementZone>(
                    value: BatchPlacementZone.firstPageCenter,
                    child: Text('Primera página — centro'),
                  ),
                ],
                onChanged: (BatchPlacementZone? v) {
                  if (v != null) setState(() => _zone = v);
                },
              ),
              const SizedBox(height: 16),

              // --- Directorio de salida ---
              Text(
                'Guardar en',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              RadioListTile<bool>(
                value: false,
                groupValue: _useCustomDirectory,
                onChanged: (bool? v) {
                  setState(() {
                    _useCustomDirectory = v ?? false;
                    if (!_useCustomDirectory) _outputDirectory = null;
                  });
                },
                title: const Text('Junto al original', style: TextStyle(fontSize: 13)),
                subtitle: const Text(
                  'Cada PDF firmado se guarda junto a su archivo original',
                  style: TextStyle(fontSize: 11),
                ),
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
              RadioListTile<bool>(
                value: true,
                groupValue: _useCustomDirectory,
                onChanged: (bool? v) {
                  setState(() => _useCustomDirectory = v ?? false);
                },
                title: const Text('Elegir directorio', style: TextStyle(fontSize: 13)),
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
              if (_useCustomDirectory) ...<Widget>[
                Padding(
                  padding: const EdgeInsets.only(left: 48),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      OutlinedButton.icon(
                        onPressed: _pickDirectory,
                        icon: const Icon(Icons.folder_open, size: 18),
                        label: Text(
                          _outputDirectory != null
                              ? 'Cambiar carpeta'
                              : 'Seleccionar carpeta',
                        ),
                      ),
                      if (_outputDirectory != null) ...<Widget>[
                        const SizedBox(height: 4),
                        Text(
                          _outputDirectory!,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),

              // --- Lista de archivos ---
              Row(
                children: <Widget>[
                  Text(
                    'Archivos',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const Spacer(),
                  Text(
                    '$_selectedCount de ${_files.length} seleccionados',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              CheckboxListTile(
                value: allSelected
                    ? true
                    : noneSelected
                        ? false
                        : null,
                tristate: true,
                onChanged: _toggleAll,
                title: const Text('Seleccionar todo', style: TextStyle(fontSize: 13)),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
              ),
              const SizedBox(height: 4),
              Container(
                constraints: const BoxConstraints(maxHeight: 200),
                decoration: BoxDecoration(
                  border: Border.all(color: scheme.outline),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _files.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (BuildContext context, int index) {
                    final BatchFileItem file = _files[index];
                    final String name =
                        file.path.split(RegExp(r'[\\/]')).last;
                    return CheckboxListTile(
                      value: file.selected,
                      onChanged: (bool? v) {
                        setState(() => file.selected = v ?? true);
                      },
                      title: Text(
                        name,
                        style: const TextStyle(fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: noneSelected
              ? null
              : () {
                  Navigator.of(context).pop(BatchSetupResult(
                    zone: _zone,
                    files: _files,
                    outputDirectory: _useCustomDirectory ? _outputDirectory : null,
                  ));
                },
          child: Text('Iniciar lote ($_selectedCount)'),
        ),
      ],
    );
  }
}
