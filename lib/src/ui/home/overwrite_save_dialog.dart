import 'package:flutter/material.dart';

/// Acción elegida ante un archivo de salida ya existente.
enum OverwriteChoice { overwrite, rename, cancel }

/// Resultado del diálogo de sobrescritura.
class OverwriteDecision {
  const OverwriteDecision({
    required this.choice,
    this.applyToAll = false,
  });

  final OverwriteChoice choice;

  /// En lote: aplicar la misma decisión a los archivos restantes.
  final bool applyToAll;
}

/// Diálogo: el archivo de salida ya existe — Sobrescribir / Renombrar / Cancelar.
///
/// [showApplyToAll] añade un checkbox «Aplicar a todo el lote» (solo lote).
Future<OverwriteDecision?> showOverwriteSaveDialog(
  BuildContext context, {
  required String path,
  bool showApplyToAll = false,
}) {
  return showDialog<OverwriteDecision>(
    context: context,
    builder: (BuildContext context) => _OverwriteSaveDialog(
      path: path,
      showApplyToAll: showApplyToAll,
    ),
  );
}

class _OverwriteSaveDialog extends StatefulWidget {
  const _OverwriteSaveDialog({
    required this.path,
    required this.showApplyToAll,
  });

  final String path;
  final bool showApplyToAll;

  @override
  State<_OverwriteSaveDialog> createState() => _OverwriteSaveDialogState();
}

class _OverwriteSaveDialogState extends State<_OverwriteSaveDialog> {
  bool _applyToAll = false;

  void _pop(OverwriteChoice choice) {
    Navigator.of(context).pop(OverwriteDecision(
      choice: choice,
      // «Aplicar a todo» solo tiene sentido para sobrescribir/renombrar.
      applyToAll: choice != OverwriteChoice.cancel && _applyToAll,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Ya existe un archivo firmado'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'Ya existe un archivo con el nombre de salida previsto. '
              '¿Qué quieres hacer?',
            ),
            const SizedBox(height: 12),
            SelectableText(
              widget.path,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(fontFamily: 'monospace'),
            ),
            if (widget.showApplyToAll) ...<Widget>[
              const SizedBox(height: 8),
              CheckboxListTile(
                value: _applyToAll,
                onChanged: (bool? v) =>
                    setState(() => _applyToAll = v ?? false),
                title: const Text(
                  'Aplicar a todo el lote',
                  style: TextStyle(fontSize: 13),
                ),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
              ),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => _pop(OverwriteChoice.cancel),
          child: const Text('Cancelar'),
        ),
        TextButton(
          onPressed: () => _pop(OverwriteChoice.rename),
          child: const Text('Renombrar'),
        ),
        FilledButton(
          onPressed: () => _pop(OverwriteChoice.overwrite),
          child: const Text('Sobrescribir'),
        ),
      ],
    );
  }
}
