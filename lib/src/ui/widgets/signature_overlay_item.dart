import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../models/signature_placement.dart';
import 'signature_frame.dart';

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
    this.profileName,
    this.hasRubric = false,
    this.rubricBytes,
    this.selected = false,
  });

  final SignaturePlacement placement;
  final double scale;
  final bool interactive;
  final Size pageSizeInPoints;
  final ValueChanged<Rect> onChanged;
  final VoidCallback onRemove;
  final String? profileName;
  final bool hasRubric;
  final Uint8List? rubricBytes;

  /// Zona enfocada en la UI (anillo + handles visibles).
  final bool selected;

  @override
  State<SignatureOverlayItem> createState() => _SignatureOverlayItemState();
}

class _SignatureOverlayItemState extends State<SignatureOverlayItem> {
  static const double _kMinWidthPt = 48;
  static const double _kMinHeightPt = 16;

  Rect? _startRect;
  Offset? _startPointer;
  bool _hovered = false;

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

  /// Resize anclado a una esquina: mantiene opuesta fija.
  void _onResizeCorner(DragUpdateDetails details, _Corner corner) {
    final Rect r = widget.placement.rect;
    final Offset delta = details.delta / widget.scale;
    double left = r.left;
    double top = r.top;
    double right = r.right;
    double bottom = r.bottom;

    if (corner == _Corner.bottomRight || corner == _Corner.topRight) {
      right = (r.right + delta.dx).clamp(r.left + _kMinWidthPt, double.infinity);
    }
    if (corner == _Corner.bottomLeft || corner == _Corner.topLeft) {
      left = (r.left + delta.dx).clamp(0.0, r.right - _kMinWidthPt);
    }
    if (corner == _Corner.bottomRight || corner == _Corner.bottomLeft) {
      bottom =
          (r.bottom + delta.dy).clamp(r.top + _kMinHeightPt, double.infinity);
    }
    if (corner == _Corner.topLeft || corner == _Corner.topRight) {
      top = (r.top + delta.dy).clamp(0.0, r.bottom - _kMinHeightPt);
    }

    widget.onChanged(
      _clamp(Rect.fromLTRB(left, top, right, bottom)),
    );
  }

  SignatureFrameStyle get _style {
    if (widget.placement.signed) return SignatureFrameStyle.signed;
    if (!widget.interactive) return SignatureFrameStyle.pending;
    if (widget.selected) return SignatureFrameStyle.selected;
    if (_hovered) return SignatureFrameStyle.hover;
    return SignatureFrameStyle.pending;
  }

  @override
  Widget build(BuildContext context) {
    final Rect rect = widget.placement.rect;
    final bool signed = widget.placement.signed;
    final bool interactive = widget.interactive && !signed;
    final bool showChrome = interactive && (_hovered || widget.selected);

    final SignatureFrameStyle style = _style;
    final Color accent = style == SignatureFrameStyle.signed
        ? Colors.green
        : Theme.of(context).colorScheme.primary;

    Widget preview = _buildPreview(accent, signed);

    // Rúbrica se pinta a sangre (sin padding extra del frame) → clipContent.
    final bool rubricFullBleed =
        !signed && widget.hasRubric && widget.rubricBytes != null;

    return Positioned.fromRect(
      rect: rect * widget.scale,
      child: MouseRegion(
        onEnter: (_) => interactive
            ? setState(() => _hovered = true)
            : null,
        onExit: (_) => setState(() => _hovered = false),
        cursor:
            interactive ? SystemMouseCursors.move : MouseCursor.defer,
        child: GestureDetector(
          onPanStart: interactive ? _onMoveStart : null,
          onPanUpdate: interactive ? _onMoveUpdate : null,
          child: SignatureFrame(
            style: style,
            elevated: showChrome,
            clipContent: rubricFullBleed,
            badge: signed ? 'Firmada' : null,
            badgeColor: Colors.green,
            child: Stack(
              children: <Widget>[
                Positioned.fill(child: Center(child: preview)),
                if (showChrome) ...<Widget>[
                  // Handle esquina sup-izq
                  _resizeHandle(
                    corner: _Corner.topLeft,
                    left: -8,
                    top: -8,
                    interactive: interactive,
                  ),
                  // Handle esquina sup-der
                  _resizeHandle(
                    corner: _Corner.topRight,
                    right: -8,
                    top: -8,
                    interactive: interactive,
                  ),
                  // Handle esquina inf-izq
                  _resizeHandle(
                    corner: _Corner.bottomLeft,
                    left: -8,
                    bottom: -8,
                    interactive: interactive,
                  ),
                  // Handle esquina inf-der (principal)
                  _resizeHandle(
                    corner: _Corner.bottomRight,
                    right: -8,
                    bottom: -8,
                    interactive: interactive,
                    emphasize: true,
                  ),
                  // Cerrar
                  Positioned(
                    right: -8,
                    top: -18,
                    child: GestureDetector(
                      onTap: widget.onRemove,
                      child: const Tooltip(
                        message: 'Quitar firma',
                        child: Material(
                          type: MaterialType.circle,
                          color: Colors.redAccent,
                          elevation: 2,
                          child: Padding(
                            padding: EdgeInsets.all(3),
                            child: Icon(
                              Icons.close,
                              size: 12,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _resizeHandle({
    required _Corner corner,
    required bool interactive,
    double? left,
    double? right,
    double? top,
    double? bottom,
    bool emphasize = false,
  }) {
    final Color accent = widget.placement.signed
        ? Colors.green
        : Theme.of(context).colorScheme.primary;
    return Positioned(
      left: left,
      right: right,
      top: top,
      bottom: bottom,
      child: GestureDetector(
        onPanUpdate: interactive
            ? (DragUpdateDetails d) => _onResizeCorner(d, corner)
            : null,
        child: Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: accent,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: <BoxShadow>[
              BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 3),
            ],
          ),
          child: emphasize
              ? const Icon(Icons.open_in_full, size: 8, color: Colors.white)
              : null,
        ),
      ),
    );
  }

  Widget _buildPreview(Color borderColor, bool signed) {
    if (signed) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.verified, size: 22, color: borderColor),
          const Text(
            'Firmada',
            style: TextStyle(
              color: Colors.green,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
    }

    if (widget.hasRubric &&
        widget.rubricBytes != null &&
        widget.rubricBytes!.isNotEmpty) {
      return FittedBox(
        fit: BoxFit.contain,
        child: Image.memory(
          widget.rubricBytes!,
          fit: BoxFit.contain,
        ),
      );
    }

    final bool wide = widget.placement.rect.width >
        widget.placement.rect.height * 1.6;
    final Widget icon = Icon(Icons.draw, size: 20, color: borderColor);
    final Widget label = Flexible(
      child: Text(
        widget.profileName ?? 'Firma',
        style: TextStyle(
          color: borderColor,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
        textAlign: wide ? TextAlign.start : TextAlign.center,
        overflow: TextOverflow.ellipsis,
        maxLines: 2,
      ),
    );

    if (wide) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            icon,
            const SizedBox(width: 6),
            label,
          ],
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        icon,
        const SizedBox(height: 2),
        label,
      ],
    );
  }
}

enum _Corner { topLeft, topRight, bottomLeft, bottomRight }

extension on Rect {
  Rect operator *(double scale) =>
      Rect.fromLTWH(left * scale, top * scale, width * scale, height * scale);
}
