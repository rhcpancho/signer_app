import 'package:flutter/material.dart';

import '../../models/signature_placement.dart';

/// Rectángulo ajustable que representa la zona donde se colocará una firma.
///
/// `rect` está en puntos PDF; `scale` es la relación px/punto de la página
/// actual, así que la conversión de las deltas del puntero es directa.
class SignatureOverlayItem extends StatefulWidget {
  const SignatureOverlayItem({
    super.key,
    required this.placement,
    required this.scale,
    required this.interactive,
    required this.pageSizeInPoints,
    required this.onChanged,
    required this.onRemove,
  });

  final SignaturePlacement placement;
  final double scale;
  final bool interactive;
  final Size pageSizeInPoints;
  final ValueChanged<Rect> onChanged;
  final VoidCallback onRemove;

  @override
  State<SignatureOverlayItem> createState() => _SignatureOverlayItemState();
}

class _SignatureOverlayItemState extends State<SignatureOverlayItem> {
  static const double _kMinWidthPt = 48;
  static const double _kMinHeightPt = 16;

  Rect? _startRect;
  Offset? _startPointer;

  Rect _clamp(Rect rect) {
    final Size page = widget.pageSizeInPoints;
    final double left =
        rect.left.clamp(0.0, (page.width - rect.width).clamp(0.0, page.width));
    final double top =
        rect.top.clamp(0.0, (page.height - rect.height).clamp(0.0, page.height));
    return Rect.fromLTWH(left, top, rect.width, rect.height);
  }

  void _onMoveStart(DragStartDetails details) {
    _startRect = widget.placement.rect;
    _startPointer = details.localPosition;
  }

  void _onMoveUpdate(DragUpdateDetails details) {
    final Rect? start = _startRect;
    final Offset? pointer = _startPointer;
    if (start == null || pointer == null) return;
    final Offset delta = (details.localPosition - pointer) / widget.scale;
    widget.onChanged(_clamp(start.shift(delta)));
  }

  void _onResizeUpdate(DragUpdateDetails details) {
    final Rect start = _startRect ?? widget.placement.rect;
    final Offset delta = details.delta / widget.scale;
    final double width =
        (start.width + delta.dx).clamp(_kMinWidthPt, double.infinity);
    final double height =
        (start.height + delta.dy).clamp(_kMinHeightPt, double.infinity);
    final Rect grown =
        Rect.fromLTWH(start.left, start.top, width, height);
    widget.onChanged(
      _clamp(
        Rect.fromLTWH(grown.left, grown.top, width, height),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Rect rect = widget.placement.rect;
    final bool signed = widget.placement.signed;
    final Color borderColor = signed ? Colors.green : scheme.primary;
    final Color fillColor =
        (signed ? Colors.green : scheme.primary).withOpacity(0.08);
    final bool interactive = widget.interactive && !signed;

    return Positioned.fromRect(
      rect: rect * widget.scale,
      child: GestureDetector(
        onPanStart: interactive ? _onMoveStart : null,
        onPanUpdate: interactive ? _onMoveUpdate : null,
        child: Container(
          decoration: BoxDecoration(
            color: fillColor,
            border: Border.all(color: borderColor, width: 1.5),
            borderRadius: BorderRadius.circular(2),
          ),
          child: CustomPaint(
            painter: _DashedBorderPainter(color: borderColor),
            child: Stack(
              children: <Widget>[
                Positioned.fill(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(
                          signed ? Icons.verified : Icons.draw,
                          size: 22,
                          color: borderColor,
                        ),
                        if (!signed)
                          Text(
                            'Firma',
                            style: TextStyle(
                              color: borderColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          )
                        else
                          Text(
                            'Firmada',
                            style: TextStyle(
                              color: Colors.green.shade700,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (interactive)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: GestureDetector(
                      onTap: widget.onRemove,
                      child: const Tooltip(
                        message: 'Quitar firma',
                        child: Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(
                            Icons.close,
                            size: 16,
                            color: Colors.redAccent,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (interactive)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: GestureDetector(
                      onPanStart: (details) {
                        _startRect = widget.placement.rect;
                      },
                      onPanUpdate: _onResizeUpdate,
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: borderColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(
                          Icons.open_in_full,
                          size: 10,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    const double dashWidth = 5;
    const double dashSpace = 3;

    void drawDashedLine(Offset start, Offset end) {
      final double total = (end - start).distance;
      final Offset direction = (end - start) / total;
      double distance = 0;
      while (distance < total) {
        canvas.drawLine(
          start + direction * distance,
          start + direction * (distance + dashWidth).clamp(0, total - distance),
          paint,
        );
        distance += dashWidth + dashSpace;
      }
    }

    drawDashedLine(Offset.zero, Offset(size.width, 0));
    drawDashedLine(
        Offset(size.width, 0), Offset(size.width, size.height));
    drawDashedLine(
        Offset(size.width, size.height), Offset(0, size.height));
    drawDashedLine(Offset(0, size.height), Offset.zero);
  }

  @override
  bool shouldRepaint(_DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color;
}

extension on Rect {
  Rect operator *(double scale) =>
      Rect.fromLTWH(left * scale, top * scale, width * scale, height * scale);
}