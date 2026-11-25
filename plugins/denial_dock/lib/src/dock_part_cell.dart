import 'package:denial_shell_kit/kit_part.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// One part of another plugin in the dock's row: a clock, the status items,
/// the workspace switcher.
///
/// The part is as long as it likes and never taller than the icons; the cell
/// centres it, which is all the shell a part without a form for the dock
/// needs. Its length is reported so the row can give it that much room.
class DockPartCell extends StatelessWidget {
  const DockPartCell({
    required this.id,
    required this.part,
    required this.vertical,
    required this.crossExtent,
    required this.onExtent,
    super.key,
  });

  final String id;
  final KitPartContext part;
  final bool vertical;
  final double crossExtent;
  final ValueChanged<double> onExtent;

  @override
  Widget build(BuildContext context) {
    return OverflowBox(
      minWidth: 0,
      minHeight: 0,
      maxWidth: vertical ? crossExtent : double.infinity,
      maxHeight: vertical ? double.infinity : crossExtent,
      child: _Measured(
        vertical: vertical,
        onExtent: onExtent,
        child: DefaultTextStyle.merge(
          style: TextStyle(color: part.ink),
          child: IconTheme.merge(
            data: IconThemeData(color: part.ink),
            child: KitPartView(id: id, part: part),
          ),
        ),
      ),
    );
  }
}

class _Measured extends SingleChildRenderObjectWidget {
  const _Measured({
    required this.vertical,
    required this.onExtent,
    required super.child,
  });

  final bool vertical;
  final ValueChanged<double> onExtent;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMeasured(vertical: vertical, onExtent: onExtent);

  @override
  void updateRenderObject(BuildContext context, _RenderMeasured renderObject) {
    renderObject
      ..vertical = vertical
      ..onExtent = onExtent;
  }
}

class _RenderMeasured extends RenderProxyBox {
  _RenderMeasured({required this.vertical, required this.onExtent});

  bool vertical;
  ValueChanged<double> onExtent;
  double? _reported;

  @override
  void performLayout() {
    super.performLayout();
    final extent = vertical ? size.height : size.width;
    if (_reported == extent) return;
    _reported = extent;
    // The row is laid out again with the new length, which may not start
    // from inside this layout.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (attached) onExtent(extent);
    });
  }
}
