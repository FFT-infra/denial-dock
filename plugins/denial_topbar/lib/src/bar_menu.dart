import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/material.dart';

import 'bar_icons.dart';
import 'bar_tokens.dart';
import 'bar_type.dart';

/// One row of a macOS dropdown.
///
/// Transcribes shell27 `MacBar.qml`'s `menuCol` delegate: 26 high, a 12-radius
/// highlight in the accent colour, the label at `x: 12` (`x: 28` when the menu
/// reserves a leading glyph column), the shortcut right-aligned with a 12
/// inset, and a checkmark at `x: 11` in place of the label's lead. Disabled
/// rows keep their place and drop to the dimmed ink.
class BarMenuRow extends StatefulWidget {
  const BarMenuRow({
    required this.label,
    this.shortcut = '',
    this.enabled = true,
    this.checked = false,
    this.glyph,
    this.destructive = false,
    this.leadInset = false,
    this.onTap,
    super.key,
  });

  final String label;
  final String shortcut;
  final bool enabled;
  final bool checked;

  /// Leading glyph, drawn at `x: 10` in a 15 pt box.
  final IconData? glyph;

  /// Draws the label in the system red, as macOS does for Shut Down.
  final bool destructive;

  /// Reserves the leading column, which lines every row's text up.
  final bool leadInset;
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
    final active = _hovered && interactive;
    final ink = !widget.enabled
        ? theme.colors.textTertiary
        : active
        ? const Color(0xffffffff)
        : widget.destructive
        ? theme.colors.performanceBad
        : theme.colors.textPrimary;
    final dim = theme.colors.textSecondary;
    final lead = widget.glyph != null || widget.checked || widget.leadInset;

    return MouseRegion(
      cursor: interactive ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: interactive ? widget.onTap : null,
        child: SizedBox(
          height: BarTokens.menuRowHeight,
          child: Stack(
            children: <Widget>[
              if (active)
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: theme.accent,
                      borderRadius: BorderRadius.circular(
                        BarTokens.menuRowRadius,
                      ),
                    ),
                  ),
                ),
              if (widget.glyph != null)
                Positioned(
                  left: BarTokens.menuRowGlyphInset,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: BarGlyph(
                      widget.glyph!,
                      size: BarTokens.menuRowGlyphSize,
                      color: ink,
                    ),
                  ),
                )
              else if (widget.checked)
                Positioned(
                  left: 11,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: Text(
                      '✓',
                      style: BarType.menuRow.copyWith(color: ink),
                    ),
                  ),
                ),
              Positioned(
                left: lead ? BarTokens.menuRowLeadInset : 12,
                right: BarTokens.menuRowShortcutInset,
                top: 0,
                bottom: 0,
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
                    if (widget.shortcut.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 12),
                        child: Text(
                          widget.shortcut,
                          style: BarType.shortcut.copyWith(
                            color: active
                                ? const Color(0xffffffff).withValues(alpha: 0.8)
                                : dim,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A separator: shell27's `height: 11` slot with a 1 px line inset 8 each
/// side, in `bpal.sep` (black 0.12 on a light panel, white 0.14 on a dark one).
class BarMenuDivider extends StatelessWidget {
  const BarMenuDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final dark = theme.colors.brightness == Brightness.dark;
    return SizedBox(
      height: BarTokens.menuSeparatorHeight,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: BarTokens.menuSeparatorInset,
          ),
          child: Container(
            height: 1,
            color: (dark ? const Color(0xffffffff) : const Color(0xff000000))
                .withValues(
                  alpha: dark
                      ? BarTokens.separatorDark
                      : BarTokens.separatorLight,
                ),
          ),
        ),
      ),
    );
  }
}

/// The column a dropdown's rows sit in: shell27 `menuCol` at `x: 6; y: 7`,
/// `width: parent.width - 12`.
class BarMenuColumn extends StatelessWidget {
  const BarMenuColumn({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: BarTokens.menuColumnInsetX,
        vertical: BarTokens.menuColumnInsetY,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

/// A full-width action inside a popover, at shell27's row height of 32.
class BarMenuAction extends StatefulWidget {
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
  State<BarMenuAction> createState() => _BarMenuActionState();
}

class _BarMenuActionState extends State<BarMenuAction> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final enabled = widget.onTap != null;
    final fill = widget.primary
        ? theme.accent.withValues(alpha: enabled ? (_hovered ? 1 : 0.9) : 0.4)
        : theme.colors.textPrimary.withValues(alpha: _hovered ? 0.12 : 0.07);
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: Motion.pill,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            widget.label,
            style: BarType.section.copyWith(
              color: widget.primary
                  ? const Color(0xffffffff)
                  : theme.colors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
