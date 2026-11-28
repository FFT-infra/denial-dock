import 'dart:ui' show lerpDouble;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'kit_control_math.dart';

/// A surface whose detail page grows out of one of its own tiles.
///
/// One [progress] drives everything, so nothing can drift apart: 0 is the
/// [home] face, 1 the [detail]. Between them a frame travels from [from], the
/// tile's rectangle in this widget, to the whole surface, its corners going
/// from [fromRadius] to [toRadius]; the home face fades early, the detail
/// fades in late inside the frame, laid out at its final size and only
/// clipped; and the surface's own height runs from one face's to the
/// other's. A progress a little outside 0..1 is allowed, so a spring may
/// overshoot.
class KitMorph extends MultiChildRenderObjectWidget {
  KitMorph({
    required this.progress,
    required this.from,
    required this.fromRadius,
    required this.toRadius,
    required this.plate,
    required this.rim,
    required Widget home,
    Widget? detail,
    this.settled,
    super.key,
  }) : super(children: <Widget>[home, ?detail]);

  final double progress;

  /// When provided, prevents an overshooting spring from flickering across
  /// `_arrived` before the animation settles.
  final bool? settled;

  /// Null grows the detail out of the whole home face: a plain cross-fade.
  final Rect? from;
  final double fromRadius;
  final double toRadius;

  /// The travelling frame's fill and edge, the tile's own, so the frame
  /// starts as the tile and dissolves into the surface.
  final Color plate;
  final Color rim;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderKitMorph(
    progress: progress,
    from: from,
    fromRadius: fromRadius,
    toRadius: toRadius,
    plate: plate,
    rim: rim,
    isSettled: settled,
  );

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderKitMorph)
      ..progress = progress
      ..from = from
      ..fromRadius = fromRadius
      ..toRadius = toRadius
      ..plate = plate
      ..rim = rim
      ..settled = settled;
  }
}

class _MorphParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderKitMorph extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _MorphParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _MorphParentData> {
  _RenderKitMorph({
    required this._progress,
    required this._from,
    required this._fromRadius,
    required this._toRadius,
    required this._plate,
    required this._rim,
    bool? isSettled,
  }) : _settled = isSettled;

  bool? _settled;
  set settled(bool? value) {
    if (value == _settled) return;
    _settled = value;
    markNeedsPaint();
  }

  double _progress;
  set progress(double value) {
    if (value == _progress) return;
    _progress = value;
    markNeedsLayout();
  }

  Rect? _from;
  set from(Rect? value) {
    if (value == _from) return;
    _from = value;
    markNeedsLayout();
  }

  double _fromRadius;
  set fromRadius(double value) {
    if (value == _fromRadius) return;
    _fromRadius = value;
    markNeedsPaint();
  }

  double _toRadius;
  set toRadius(double value) {
    if (value == _toRadius) return;
    _toRadius = value;
    markNeedsPaint();
  }

  Color _plate;
  set plate(Color value) {
    if (value == _plate) return;
    _plate = value;
    markNeedsPaint();
  }

  Color _rim;
  set rim(Color value) {
    if (value == _rim) return;
    _rim = value;
    markNeedsPaint();
  }

  RenderBox get _home => firstChild!;
  RenderBox? get _detail => childAfter(firstChild!);

  /// The travelling frame, in this box's coordinates.
  Rect _frame = Rect.zero;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _MorphParentData) {
      child.parentData = _MorphParentData();
    }
  }

  // The faces are painted through opacity and clip layers of this box's own.
  @override
  bool get alwaysNeedsCompositing => childCount > 1;

  @override
  void performLayout() {
    final width = constraints.maxWidth;
    final inner = BoxConstraints(
      minWidth: width,
      maxWidth: width,
      maxHeight: constraints.maxHeight,
    );
    final home = _home..layout(inner, parentUsesSize: true);
    final detail = _detail?..layout(inner, parentUsesSize: true);
    (home.parentData! as _MorphParentData).offset = Offset.zero;
    if (detail == null) {
      _frame = Offset.zero & home.size;
      size = constraints.constrain(home.size);
      return;
    }
    final t = _progress;
    final height = lerpDouble(home.size.height, detail.size.height, t)!;
    size = constraints.constrain(Size(width, height < 0 ? 0 : height));
    _frame = Rect.lerp(
      _from ?? Offset.zero & home.size,
      Offset.zero & detail.size,
      t,
    )!;
    (detail.parentData! as _MorphParentData).offset = _frame.topLeft;
  }

  bool get _arrived =>
      (_settled ?? true) && (_progress - 1).abs() < 0.0005;

  @override
  void paint(PaintingContext context, Offset offset) {
    final home = _home;
    final detail = _detail;
    if (detail == null) {
      context.paintChild(home, offset);
      return;
    }
    if (_arrived) {
      context.paintChild(detail, offset);
      return;
    }
    final t = _progress;
    context.pushClipRect(needsCompositing, offset, Offset.zero & size, (
      context,
      offset,
    ) {
      final leaving = 1 - kitPhase(t, 0, 0.35);
      if (leaving >= 1) {
        context.paintChild(home, offset);
      } else if (leaving > 0) {
        context.pushOpacity(
          offset,
          (leaving * 255).round(),
          (context, offset) => context.paintChild(home, offset),
        );
      }
      final frame = _frame.shift(offset);
      final radius = lerpDouble(_fromRadius, _toRadius, t.clamp(0.0, 1.0))!;
      final shape = RRect.fromRectAndRadius(frame, Radius.circular(radius));
      // The frame takes over from the tile as the tile fades, then dissolves
      // into the surface it has grown to fill.
      final body = kitPhase(t, 0, 0.3) * (1 - kitPhase(t, 0.6, 1));
      if (body > 0) {
        context.canvas
          ..drawRRect(
            shape,
            Paint()..color = _plate.withValues(alpha: _plate.a * body),
          )
          ..drawRRect(
            shape.deflate(0.5),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1
              ..color = _rim.withValues(alpha: _rim.a * body),
          );
      }
      final arriving = kitPhase(t, 0.3, 0.8);
      if (arriving <= 0) return;
      context.pushClipRRect(
        needsCompositing,
        offset,
        _frame,
        shape.shift(-offset),
        (context, offset) {
          final at = offset + _frame.topLeft;
          if (arriving >= 1) {
            context.paintChild(detail, at);
          } else {
            context.pushOpacity(
              at,
              (arriving * 255).round(),
              (context, at) => context.paintChild(detail, at),
            );
          }
        },
      );
    });
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final detail = _detail;
    // Whichever face is the more visible one takes the pointer.
    if (detail != null && _progress >= 0.5) {
      if (!_frame.contains(position)) return false;
      return result.addWithPaintOffset(
        offset: _frame.topLeft,
        position: position,
        hitTest: (result, position) =>
            detail.hitTest(result, position: position),
      );
    }
    return _home.hitTest(result, position: position);
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    final detail = _detail;
    visitor(detail != null && _progress >= 0.5 ? detail : _home);
  }
}
