import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/material.dart';

import 'bar_ground.dart';
import 'bar_tokens.dart';

/// One clickable slot in the menu bar.
///
/// Transcribes shell27 `MacBar.qml`'s menu-title delegate: the box is 28 high,
/// the hover plate is `width - 2` × `height - 6` with radius 12, filled
/// `bpal.hover` (black 0.09 on a light bar, white 0.14 on a dark one). The
/// plate stays lit while the item's popover is open, which is how macOS shows
/// which title owns the open menu.
class BarButton extends StatefulWidget {
  const BarButton({
    required this.child,
    this.onTap,
    this.onSecondaryTap,
    this.open = false,
    this.width,
    this.height = BarTokens.itemHeight,
    this.padding = const EdgeInsets.symmetric(
      horizontal: BarTokens.itemPadding,
    ),
    this.radius = BarTokens.itemRadius,
    this.ink,
    this.tooltip,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onSecondaryTap;

  /// Keeps the plate visible while this button's popover is open.
  final bool open;

  /// Fixed box width, or null to size to the child.
  final double? width;
  final double height;
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
    // shell27's plate is inset inside the 28-high box: `width - 2`,
    // `height - 6`, so the wash never touches the strip's edges.
    Widget content = SizedBox(
      width: widget.width,
      height: widget.height,
      child: Center(
        child: AnimatedContainer(
          duration: Motion.pill,
          curve: Curves.easeOut,
          width: widget.width == null
              ? null
              : widget.width! - BarTokens.itemInsetX * 2,
          height: widget.height - BarTokens.itemInsetY * 2,
          padding: widget.width == null ? widget.padding : EdgeInsets.zero,
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
        ),
      ),
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
