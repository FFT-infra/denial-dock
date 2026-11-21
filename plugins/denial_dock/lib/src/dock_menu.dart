import 'package:denial_flutter_sdk/effects.dart';
import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/material.dart';

/// The blurred, hairline-bordered panel shared by the application menu and the
/// dock menu.
class DockMenuPanel extends StatelessWidget {
  const DockMenuPanel({
    required this.radius,
    required this.child,
    this.maxHeight,
    super.key,
  });

  final BorderRadius radius;
  final Widget child;
  final double? maxHeight;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final panel = ShellBackdropBlur(
      blur: theme.effectivePanelOpacity < 1,
      separateChild: true,
      borderRadius: radius,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.panelColor(theme.colors.surfaceContainer),
          borderRadius: radius,
          border: Border.all(color: theme.colors.hairline),
        ),
        child: child,
      ),
    );
    final height = maxHeight;
    if (height == null) return panel;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: height),
      child: panel,
    );
  }
}

/// One selectable line in a dock menu. [selected] draws a trailing check, used
/// by on/off settings.
class DockMenuRow extends StatefulWidget {
  const DockMenuRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;

  @override
  State<DockMenuRow> createState() => _DockMenuRowState();
}

class _DockMenuRowState extends State<DockMenuRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = theme.colors;
    final foreground = colors.textPrimary;
    return Semantics(
      button: true,
      selected: widget.selected,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Container(
            height: 34,
            margin: const EdgeInsets.symmetric(horizontal: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              borderRadius: theme.borderRadius(8),
              color: _hovered
                  ? colors.textPrimary.withValues(alpha: 0.08)
                  : null,
            ),
            child: Row(
              children: [
                Icon(widget.icon, size: 17, color: foreground),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.text.systemBarCaption.copyWith(
                      color: foreground,
                    ),
                  ),
                ),
                if (widget.selected)
                  Icon(Icons.check, size: 16, color: theme.accent),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
