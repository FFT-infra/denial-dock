import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/widgets.dart';

/// Width the dots occupy, so a container can size itself before layout.
double workspaceDotsWidth(
  int count, {
  double dotSize = 6,
  double spacing = 6,
}) => count <= 0 ? 0.0 : count * (dotSize + spacing);

/// Workspace switcher drawn as macOS Mission Control dots.
///
/// macOS has no workspace switcher in the menu bar, so this is an addition.
/// It ports the dot treatment from NextKDE's dock indicator: occupied
/// workspaces are filled, the active one takes the accent, empty ones stay at
/// low alpha.
class WorkspaceDots extends StatelessWidget {
  const WorkspaceDots({
    required this.count,
    required this.active,
    required this.occupied,
    required this.ink,
    required this.onSelect,
    this.dotSize = 6,
    this.spacing = 6,
    super.key,
  });

  final int count;
  final int active;
  final Set<int> occupied;
  final Color ink;
  final ValueChanged<int> onSelect;
  final double dotSize;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    if (count <= 0) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (var index = 0; index < count; index++)
          _Dot(
            size: dotSize,
            gap: spacing,
            colour: index == active
                ? theme.accent
                : occupied.contains(index)
                ? ink.withValues(alpha: 0.72)
                : ink.withValues(alpha: 0.28),
            onTap: () => onSelect(index),
          ),
      ],
    );
  }
}

class _Dot extends StatefulWidget {
  const _Dot({
    required this.size,
    required this.gap,
    required this.colour,
    required this.onTap,
  });

  final double size;
  final double gap;
  final Color colour;
  final VoidCallback onTap;

  @override
  State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: SizedBox(
          width: widget.size + widget.gap,
          height: 20,
          child: Center(
            child: AnimatedContainer(
              duration: Motion.pill,
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                color: widget.colour,
                shape: BoxShape.circle,
                border: _hovered
                    ? Border.all(color: widget.colour, width: 1)
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
