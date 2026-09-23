import 'dart:ui' as ui show PathMetric;

import 'package:flutter/material.dart';

/// Estado visual de un recuadro de firma (visor o resaltado de verificación).
enum SignatureFrameStyle {
  /// Zona editable aún no firmada.
  pending,

  /// Ratón encima de una zona editable.
  hover,

  /// Zona enfocada/seleccionada.
  selected,

  /// Zona ya firmada.
  signed,

  /// Resaltado en la pantalla de verificación.
  verify,
}

/// Recuadro unificado de zona de firma: relleno tenue, esquinas tipo crop,
/// estados de color y opcionalmente badge/preview.
///
/// Un solo painter evita el doble borde (sólido + discontinuo) del diseño
/// anterior y mantiene el mismo lenguaje visual en visor y verificación.
class SignatureFrame extends StatelessWidget {
  const SignatureFrame({
    super.key,
    required this.style,
    required this.child,
    this.color,
    this.elevated = false,
    this.badge,
    this.badgeColor,
    this.clipContent = false,
  });

  final SignatureFrameStyle style;

  /// Color base; si es `null` se usa el del tema (primary / green / blue).
  final Color? color;

  /// Sombra y anillo exterior (hover / selected).
  final bool elevated;

  /// Etiqueta flotante en la esquina superior-izquierda (ej. «Firmada»).
  final String? badge;

  final Color? badgeColor;

  /// Si es `true`, el hijo se recorta al radio del relleno (rúbrica).
  final bool clipContent;

  final Widget child;

  Color resolvedColor(BuildContext context) {
    if (color != null) return color!;
    switch (style) {
      case SignatureFrameStyle.signed:
        return Colors.green;
      case SignatureFrameStyle.verify:
        return Colors.blue;
      case SignatureFrameStyle.pending:
      case SignatureFrameStyle.hover:
      case SignatureFrameStyle.selected:
        return Theme.of(context).colorScheme.primary;
    }
  }

  double get _fillOpacity {
    switch (style) {
      case SignatureFrameStyle.pending:
        return 0.08;
      case SignatureFrameStyle.hover:
        return 0.10;
      case SignatureFrameStyle.selected:
        return 0.12;
      case SignatureFrameStyle.signed:
        return 0.12;
      case SignatureFrameStyle.verify:
        return 0.15;
    }
  }

  bool get _showAnillo =>
      style == SignatureFrameStyle.hover ||
      style == SignatureFrameStyle.selected;

  @override
  Widget build(BuildContext context) {
    final Color base = resolvedColor(context);
    final BorderRadius radius = BorderRadius.circular(6);

    Widget content = Padding(
      padding: const EdgeInsets.all(4),
      child: child,
    );
    if (clipContent) {
      content = ClipRRect(borderRadius: radius, child: child);
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: elevated
            ? <BoxShadow>[
                BoxShadow(
                  color: base.withOpacity(0.18),
                  blurRadius: 8,
                  spreadRadius: 0,
                ),
              ]
            : null,
      ),
      child: CustomPaint(
        painter: _SignatureFramePainter(
          color: base,
          fillOpacity: _fillOpacity,
          showAnillo: _showAnillo,
          style: style,
          radius: 6,
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            content,
            if (badge != null)
              Positioned(
                left: -4,
                top: -10,
                child: _SignatureBadge(
                  label: badge!,
                  color: badgeColor ?? base,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SignatureBadge extends StatelessWidget {
  const _SignatureBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(10),
          boxShadow: <BoxShadow>[
            BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 4),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.verified, size: 11, color: Colors.white),
            const SizedBox(width: 3),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SignatureFramePainter extends CustomPainter {
  _SignatureFramePainter({
    required this.color,
    required this.fillOpacity,
    required this.showAnillo,
    required this.style,
    required this.radius,
  });

  final Color color;
  final double fillOpacity;
  final bool showAnillo;
  final SignatureFrameStyle style;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final RRect rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );

    final Paint fill = Paint()..color = color.withOpacity(fillOpacity);
    canvas.drawRRect(rrect, fill);

    if (showAnillo) {
      final Paint ring = Paint()
        ..color = color.withOpacity(0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawRRect(rrect.inflate(2), ring);
    }

    // Esquinas tipo crop (en vez de perímetro completo)
    final double len = (size.shortestSide * 0.18).clamp(8.0, 18.0);
    final Paint corner = Paint()
      ..color = color
      ..strokeWidth = style == SignatureFrameStyle.verify ? 2.0 : 1.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final double w = size.width;
    final double h = size.height;

    canvas.drawLine(Offset(0, len), const Offset(0, 0), corner);
    canvas.drawLine(const Offset(0, 0), Offset(len, 0), corner);
    canvas.drawLine(Offset(w - len, 0), Offset(w, 0), corner);
    canvas.drawLine(Offset(w, 0), Offset(w, len), corner);
    canvas.drawLine(Offset(w, h - len), Offset(w, h), corner);
    canvas.drawLine(Offset(w, h), Offset(w - len, h), corner);
    canvas.drawLine(Offset(len, h), Offset(0, h), corner);
    canvas.drawLine(Offset(0, h), Offset(0, h - len), corner);

    // Guía de contorno discontinua tenue en pending / verify
    if (style == SignatureFrameStyle.pending ||
        style == SignatureFrameStyle.verify) {
      _drawDashedRRect(canvas, rrect, color.withOpacity(0.45));
    }
  }

  static void _drawDashedRRect(Canvas canvas, RRect rrect, Color color) {
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    const double dash = 4;
    const double gap = 3;
    final Path dashed = Path()..addRRect(rrect);
    for (final ui.PathMetric metric in dashed.computeMetrics()) {
      double dist = 0;
      while (dist < metric.length) {
        final double end = (dist + dash).clamp(0, metric.length);
        dashed.addPath(metric.extractPath(dist, end), Offset.zero);
        dist += dash + gap;
      }
    }
    canvas.drawPath(dashed, paint);
  }

  @override
  bool shouldRepaint(_SignatureFramePainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.fillOpacity != fillOpacity ||
        oldDelegate.showAnillo != showAnillo ||
        oldDelegate.style != style ||
        oldDelegate.radius != radius;
  }
}
