import 'package:flutter/material.dart';

/// Diálogo para pedir la contraseña de apertura de un PDF cifrado.
///
/// Devuelve la contraseña introducida o `null` si el usuario cancela.
Future<String?> showOpenPasswordDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (BuildContext context) => const _OpenPasswordDialog(),
  );
}

class _OpenPasswordDialog extends StatefulWidget {
  const _OpenPasswordDialog();

  @override
  State<_OpenPasswordDialog> createState() => _OpenPasswordDialogState();
}

class _OpenPasswordDialogState extends State<_OpenPasswordDialog> {
  final TextEditingController _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_controller.text.isEmpty) {
      setState(() => _error = 'Introduce la contraseña.');
      return;
    }
    Navigator.of(context).pop(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('PDF protegido'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'Este documento está cifrado. Introduce la contraseña de '
              'apertura para verlo y firmarlo.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              obscureText: true,
              autofocus: true,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: 'Contraseña',
                border: const OutlineInputBorder(),
                errorText: _error,
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
          onPressed: _submit,
          child: const Text('Abrir'),
        ),
      ],
    );
  }
}
