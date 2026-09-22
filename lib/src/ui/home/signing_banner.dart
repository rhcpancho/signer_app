import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'pdf_session.dart';

class SigningBanner extends ConsumerWidget {
  const SigningBanner({
    super.key,
    required this.onChangeProfile,
    required this.onSignAndSave,
    required this.onCopyToPages,
  });

  final VoidCallback onChangeProfile;
  final VoidCallback onSignAndSave;
  final VoidCallback onCopyToPages;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ActiveSignContext? ctx = ref.watch(activeSignContextProvider);
    final PdfSession? session = ref.watch(pdfSessionProvider);

    if (ctx == null) return const SizedBox.shrink();

    final int pending =
        session?.placements.where((p) => !p.signed).length ?? 0;

    return Material(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: <Widget>[
              Icon(Icons.draw, size: 18, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Firma: \u00AB${ctx.profile.name}\u00BB · '
                  '$pending zona${pending == 1 ? '' : 's'}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (pending > 0) ...<Widget>[
                TextButton.icon(
                  onPressed: onCopyToPages,
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('Copiar a otras páginas'),
                ),
                const SizedBox(width: 4),
              ],
              TextButton(
                onPressed: onChangeProfile,
                child: const Text('Cambiar'),
              ),
              const SizedBox(width: 4),
              FilledButton.tonal(
                onPressed: pending == 0 ? null : onSignAndSave,
                child: const Text('Firmar y guardar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
