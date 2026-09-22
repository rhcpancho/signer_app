import 'package:flutter/material.dart';

/// Abre el diálogo de selección de páginas.
/// Devuelve la lista de índices de página seleccionados (0-based) o null si cancela.
Future<List<int>?> showPageSelectorDialog(
  BuildContext context, {
  required int totalPages,
  required Set<int> initiallySelected,
}) {
  return showDialog<List<int>>(
    context: context,
    builder: (_) => _PageSelectorDialog(
      totalPages: totalPages,
      initiallySelected: initiallySelected,
    ),
  );
}

class _PageSelectorDialog extends StatefulWidget {
  const _PageSelectorDialog({
    required this.totalPages,
    required this.initiallySelected,
  });

  final int totalPages;
  final Set<int> initiallySelected;

  @override
  State<_PageSelectorDialog> createState() => _PageSelectorDialogState();
}

class _PageSelectorDialogState extends State<_PageSelectorDialog> {
  late final Set<int> _selected;

  @override
  void initState() {
    super.initState();
    _selected = Set<int>.from(widget.initiallySelected);
  }

  void _toggleAll() {
    setState(() {
      if (_selected.length == widget.totalPages) {
        _selected.clear();
      } else {
        _selected.addAll(List<int>.generate(widget.totalPages, (int i) => i));
      }
    });
  }

  void _togglePage(int index) {
    setState(() {
      if (_selected.contains(index)) {
        _selected.remove(index);
      } else {
        _selected.add(index);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool allSelected = _selected.length == widget.totalPages;

    return AlertDialog(
      title: const Text('Seleccionar páginas'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Text(
                  '${_selected.length} de ${widget.totalPages} seleccionadas',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const Spacer(),
                TextButton(
                  onPressed: _toggleAll,
                  child: Text(allSelected ? 'Ninguna' : 'Todas'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Flexible(
              child: GridView.builder(
                shrinkWrap: true,
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 5,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 0.7,
                ),
                itemCount: widget.totalPages,
                itemBuilder: (BuildContext context, int index) {
                  final bool selected = _selected.contains(index);
                  return GestureDetector(
                    onTap: () => _togglePage(index),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      decoration: BoxDecoration(
                        color: selected
                            ? scheme.primaryContainer
                            : scheme.surfaceVariant,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: selected
                              ? scheme.primary
                              : scheme.outline.withOpacity(0.5),
                          width: selected ? 2 : 1,
                        ),
                      ),
                      child: Stack(
                        children: <Widget>[
                          Center(
                            child: Text(
                              '${index + 1}',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: selected
                                    ? scheme.onPrimaryContainer
                                    : scheme.onSurface,
                              ),
                            ),
                          ),
                          if (selected)
                            Positioned(
                              top: 4,
                              right: 4,
                              child: Icon(
                                Icons.check_circle,
                                size: 16,
                                color: scheme.primary,
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _selected.isEmpty
              ? null
              : () => Navigator.of(context).pop(_selected.toList()),
          child: Text('Seleccionar (${_selected.length})'),
        ),
      ],
    );
  }
}
