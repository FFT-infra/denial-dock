import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/material.dart';

import 'bar_tokens.dart';
import 'bar_type.dart';

/// One row of a macOS dropdown.
///
/// shell27's `PopItem` is 28 high with a 6 radius highlight and the shortcut
/// right-aligned in the dimmed colour; macOS's own menus are tighter (24),
/// which is what this uses. A checked row swaps the shortcut for a checkmark,
/// exactly as `PopItem` does.
class BarMenuRow extends StatefulWidget {
  const BarMenuRow({
    required this.label,
    this.shortcut = '',
    this.enabled = true,
    this.checked = false,
    this.destructive = false,
    this.onTap,
    super.key,
  });

  final String label;
  final String shortcut;
  final bool enabled;
  final bool checked;

  /// Draws the label in the shell's error colour, as macOS does for Shut
  /// Down and Force Quit.
  final bool destructive;
  final VoidCallback? onTap;

  @override
  State<BarMenuRow> createState() => _BarMenuRowState();
}

class _BarMenuRowState extends State<BarMenuRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final interactive = widget.enabled && widget.onTap != null;
    final accent = theme.accent;
    final active = _hovered && interactive;
    final ink = !widget.enabled
        ? theme.colors.textTertiary.withValues(alpha: 0.5)
        : active
        ? const Color(0xffffffff)
        : widget.destructive
        ? theme.colors.performanceBad
        : theme.colors.textPrimary;
    return MouseRegion(
      cursor: interactive ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: interactive ? widget.onTap : null,
        child: Container(
          height: BarTokens.menuRowHeight,
          margin: const EdgeInsets.symmetric(
            horizontal: BarTokens.menuRowInset,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 9),
          decoration: BoxDecoration(
            color: active ? accent : const Color(0x00000000),
            borderRadius: BorderRadius.circular(BarTokens.menuRowRadius),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: BarType.menuRow.copyWith(color: ink),
                ),
              ),
              if (widget.checked)
                Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Text('✓', style: BarType.menuRow.copyWith(color: ink)),
                )
              else if (widget.shortcut.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Text(
                    widget.shortcut,
                    style: BarType.shortcut.copyWith(
                      color: active
                          ? ink.withValues(alpha: 0.8)
                          : theme.colors.textTertiary,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A divider between menu groups.
///
/// shell27 `PopSep`: 1 px at white 0.12 on dark, black 0.12 on light, with
/// 4 above and below.
class BarMenuDivider extends StatelessWidget {
  const BarMenuDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final dark = theme.colors.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        height: 1,
        color: (dark ? const Color(0xffffffff) : const Color(0xff000000))
            .withValues(alpha: 0.12),
      ),
    );
  }
}

/// A small section heading inside a menu.
class BarMenuHeader extends StatelessWidget {
  const BarMenuHeader({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 4),
      child: Text(
        label,
        style: BarType.caption.copyWith(
          color: theme.colors.textTertiary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// A full-width button that fills a menu row's slot.
class BarMenuAction extends StatelessWidget {
  const BarMenuAction({
    required this.label,
    required this.onTap,
    this.primary = false,
    super.key,
  });

  final String label;
  final VoidCallback? onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final enabled = onTap != null;
    final fill = primary
        ? theme.accent.withValues(alpha: enabled ? 0.95 : 0.4)
        : theme.colors.textPrimary.withValues(alpha: 0.08);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: fill,
          borderRadius: theme.borderRadius(7),
        ),
        child: Text(
          label,
          style: BarType.menuRow.copyWith(
            color: primary ? const Color(0xffffffff) : theme.colors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
