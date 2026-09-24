import 'package:flutter/material.dart';

import '../../services/tsa_service.dart';

/// Estado del sello de tiempo (TSA) tras firmar.
enum TsaStatus {
  /// El perfil no pidió sello de tiempo.
  notRequested,

  /// El TSA concedió el token (sidecar `.tsr` escrito).
  granted,

  /// Se pidió pero falló (soft-fail): la firma sigue siendo válida.
  failed,
}

/// Chip que muestra el estado TSA: concedido (verde), fallido (ámbar)
/// u oculto si no se solicitó.
class TsaStatusBadge extends StatelessWidget {
  const TsaStatusBadge({
    super.key,
    required this.status,
    this.result,
    this.dense = false,
  });

  final TsaStatus status;

  /// Token parseado; solo relevante cuando [status] es [TsaStatus.granted].
  final TsaResult? result;

  /// Versión compacta para filas de lote (fuente más pequeña).
  final bool dense;

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case TsaStatus.notRequested:
        return const SizedBox.shrink();
      case TsaStatus.granted:
        final TsaResult? r = result;
        final String when =
            r?.genTime != null ? _formatDateTime(r!.genTime!) : 'ok';
        final String who = r?.tsaName != null ? ' · ${r!.tsaName}' : '';
        return _TsaChip(
          label: 'TSA $when$who',
          color: Colors.green,
          icon: Icons.schedule,
          dense: dense,
        );
      case TsaStatus.failed:
        return _TsaChip(
          label: dense
              ? 'TSA no obtenido'
              : 'Sello de tiempo no obtenido (soft-fail)',
          color: Colors.orange,
          icon: Icons.schedule,
          dense: dense,
        );
    }
  }

  static String _formatDateTime(DateTime date) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year} '
        '${two(date.hour)}:${two(date.minute)}';
  }
}

class _TsaChip extends StatelessWidget {
  const _TsaChip({
    required this.label,
    required this.color,
    required this.icon,
    required this.dense,
  });

  final String label;
  final Color color;
  final IconData icon;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final double fontSize = dense ? 10 : 12;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 6 : 8,
        vertical: dense ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: dense ? 11 : 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
