import 'dart:async';
import 'dart:math' as math;

import 'package:denial_flutter_sdk/theme.dart';
import 'package:denial_shell_kit/kit_layer.dart' show kitPressTargets;
import 'package:denial_shell_kit/kit_motion.dart';
import 'package:flutter/material.dart';

import 'bar_ground.dart';
import 'bar_tokens.dart';
import 'bar_type.dart';

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

  static final Set<_BarButtonState> _mounted = <_BarButtonState>{};

  /// Whether a resting pointer brings up an item's name.
  static bool tips = true;

  /// The tap action of the bar item under [position], if any.
  static VoidCallback? targetAt(Offset position) {
    for (final state in _mounted) {
      final render = state.context.findRenderObject();
      if (render is! RenderBox || !render.attached || !render.hasSize) continue;
      final rect = render.localToGlobal(Offset.zero) & render.size;
      if (rect.contains(position)) {
        return state.widget.open ? null : state.widget.onTap;
      }
    }
    return null;
  }

  @override
  State<BarButton> createState() => _BarButtonState();
}

class _BarButtonState extends State<BarButton> {
  bool _hovered = false;
  bool _pressed = false;
  static const double _tipSlot = 280;

  Timer? _tipDelay;
  OverlayEntry? _tip;

  @override
  void initState() {
    super.initState();
    BarButton._mounted.add(this);
    // A press outside an open panel that lands on a bar item opens that item.
    kitPressTargets.add(BarButton.targetAt);
  }

  @override
  void dispose() {
    BarButton._mounted.remove(this);
    _hideTip();
    super.dispose();
  }

  void _armTip() {
    final label = widget.tooltip;
    _tipDelay?.cancel();
    if (label == null || label.isEmpty || !BarButton.tips || widget.open) {
      return;
    }
    _tipDelay = Timer(const Duration(milliseconds: 700), () {
      if (mounted && _hovered && !_pressed) _showTip(label);
    });
  }

  void _showTip(String label) {
    final overlay = Overlay.maybeOf(context);
    final box = context.findRenderObject();
    if (overlay == null || box is! RenderBox || !box.hasSize) return;
    final frame = box.localToGlobal(Offset.zero) & box.size;
    final screen = MediaQuery.sizeOf(context);
    // The bar's surface only has room on the side the screen is on.
    final below = frame.center.dy < screen.height / 2;
    final double left = (frame.center.dx - _tipSlot / 2).clamp(
      4.0,
      math.max(4.0, screen.width - _tipSlot - 4),
    );
    _tip?.remove();
    _tip = OverlayEntry(
      builder: (context) => Positioned(
        left: left,
        width: _tipSlot,
        top: below ? frame.bottom + 4 : null,
        bottom: below ? null : screen.height - frame.top + 4,
        child: IgnorePointer(
          child: Align(
            alignment: Alignment(
              ((frame.center.dx - left) / _tipSlot * 2 - 1).clamp(-1.0, 1.0),
              0,
            ),
            child: _Tip(label),
          ),
        ),
      ),
    );
    overlay.insert(_tip!);
  }

  void _hideTip() {
    _tipDelay?.cancel();
    _tip?.remove();
    _tip = null;
  }

  @override
  Widget build(BuildContext context) {
    final ink = widget.ink ?? context.shellTheme.colors.textPrimary;
    final darkInk = BarGroundLayer.isDark(ink);
    final active = _hovered || _pressed || widget.open;
    // shell27's plate is inset inside the 28-high box: `width - 2`,
    // `height - 6`, so the wash never touches the strip's edges.
    Widget content = SizedBox(
      width: widget.width,
      height: widget.height,
      child: Center(
        child: AnimatedContainer(
          duration: KitMotion.duration(context, Motion.pill),
          curve: KitMotion.out,
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
      onEnter: (_) {
        setState(() => _hovered = true);
        _armTip();
      },
      onExit: (_) {
        setState(() => _hovered = false);
        _hideTip();
      },
      child: content,
    );

    if (widget.onTap != null || widget.onSecondaryTap != null) {
      content = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) {
          _hideTip();
          setState(() => _pressed = true);
        },
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        onSecondaryTap: widget.onSecondaryTap,
        child: content,
      );
    }
    return content;
  }
}

class _Tip extends StatelessWidget {
  const _Tip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: KitMotion.duration(context, KitMotion.ease),
      builder: (context, shown, child) => Opacity(opacity: shown, child: child),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xf02c2c2e),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: const Color(0x29ffffff), width: 0.6),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x40000000),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Text(
          label,
          maxLines: 1,
          style: BarType.caption.copyWith(
            fontSize: 12,
            color: const Color(0xffffffff),
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }
}
