import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/material.dart';

import 'bar_ground.dart';
import 'bar_tokens.dart';

/// One clickable slot in the menu bar.
///
/// shell27 draws the hover plate as `height - 6` with radius 6, filled black
/// 0.09 under dark type and white 0.14 under light type; MacShell uses the
/// same radius. The plate stays lit while the item's menu is open, which is
/// how macOS shows which title owns the open menu.
class BarButton extends StatefulWidget {
  const BarButton({
    required this.child,
    this.onTap,
    this.onSecondaryTap,
    this.open = false,
    this.minWidth = 0,
    this.padding = const EdgeInsets.symmetric(
      horizontal: BarTokens.menuItemPadding,
    ),
    this.radius = BarTokens.itemRadius,
    this.ink,
    this.tooltip,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onSecondaryTap;

  /// Keeps the plate visible while this button's panel is open.
  final bool open;
  final double minWidth;
  final EdgeInsets padding;
  final double radius;

  /// The bar's ink, which decides whether the hover plate lightens or
  /// darkens. Defaults to the theme's text colour.
  final Color? ink;
  final String? tooltip;

  @override
  State<BarButton> createState() => _BarButtonState();
}

class _BarButtonState extends State<BarButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final ink = widget.ink ?? context.shellTheme.colors.textPrimary;
    final darkInk = BarGroundLayer.isDark(ink);
    final active = _hovered || widget.open;
    Widget content = AnimatedContainer(
      duration: Motion.pill,
      curve: Curves.easeOut,
      constraints: BoxConstraints(
        minWidth: widget.minWidth,
        minHeight: BarTokens.menuItemHeight,
      ),
      padding: widget.padding,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: active
            ? (darkInk ? const Color(0xffffffff) : const Color(0xff000000))
                  .withValues(
                    alpha: darkInk
                        ? BarTokens.itemHoverAlphaDark
                        : BarTokens.itemHoverAlphaLight,
                  )
            : const Color(0x00000000),
        borderRadius: BorderRadius.circular(widget.radius),
      ),
      child: widget.child,
    );

    content = MouseRegion(
      cursor: widget.onTap == null
          ? MouseCursor.defer
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: content,
    );

    if (widget.onTap != null || widget.onSecondaryTap != null) {
      content = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onSecondaryTap: widget.onSecondaryTap,
        child: content,
      );
    }
    final label = widget.tooltip;
    if (label == null) return content;
    return Tooltip(message: label, child: content);
  }
}
