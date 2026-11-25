import 'package:denial_flutter_sdk/theme.dart';
import 'package:denial_shell_kit/kit_motion.dart';
import 'package:denial_shell_kit/kit_style.dart';
import 'package:flutter/widgets.dart';

/// The plate behind one item of the dock: under the pointer in a look that
/// lights an icon up rather than growing it, and under the application in
/// front on a dock that keeps its cell lit.
///
/// The plate reaches past the item by [main] along the row and by [cross]
/// across it, so neighbouring plates meet in the middle of the gap. A look
/// that outlines draws the hovered plate as a line in the accent.
class DockCell extends StatefulWidget {
  const DockCell({
    required this.child,
    required this.hover,
    required this.active,
    required this.outline,
    required this.main,
    required this.cross,
    required this.vertical,
    super.key,
  });

  final Widget child;

  /// Whether the pointer lights the plate up.
  final bool hover;

  /// Whether the plate stays lit, as under the application in front.
  final bool active;

  final bool outline;
  final double main;
  final double cross;

  /// Whether the dock runs down a side of the screen.
  final bool vertical;

  @override
  State<DockCell> createState() => _DockCellState();
}

class _DockCellState extends State<DockCell> {
  bool _hot = false;

  void _setHot(bool hot) {
    if (_hot == hot || !mounted) return;
    setState(() => _hot = hot);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final style = KitStyle.of(context);
    final hot = widget.hover && _hot;
    final ink = theme.colors.textPrimary;
    final accent = theme.kitAccent;
    final fill = widget.outline
        ? (widget.active
              ? accent.withValues(alpha: 0.20)
              : const Color(0x00000000))
        : ink.withValues(
            alpha: widget.active ? (hot ? 0.18 : 0.12) : (hot ? 0.10 : 0),
          );
    final line = widget.outline && hot
        ? Border.all(color: accent, width: 1)
        : null;
    final along = widget.vertical ? widget.cross : widget.main;
    final across = widget.vertical ? widget.main : widget.cross;
    return MouseRegion(
      opaque: false,
      onEnter: (_) => _setHot(true),
      onExit: (_) => _setHot(false),
      child: Stack(
        clipBehavior: Clip.none,
        fit: StackFit.passthrough,
        children: [
          Positioned(
            left: -along,
            right: -along,
            top: -across,
            bottom: -across,
            child: IgnorePointer(
              child: AnimatedContainer(
                duration: KitMotion.duration(context, KitMotion.tap),
                curve: KitMotion.out,
                decoration: BoxDecoration(
                  color: fill,
                  border: line,
                  borderRadius: BorderRadius.circular(style.corner(9)),
                ),
              ),
            ),
          ),
          widget.child,
        ],
      ),
    );
  }
}
