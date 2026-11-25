import 'dart:async';
import 'dart:math' as math;

import 'package:denial_shell_kit/kit_motion.dart';
import 'package:denial_shell_kit/kit_springs.dart';
import 'package:denial_shell_kit/kit_style.dart';
import 'package:denial_flutter_sdk/effects.dart';
import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/material.dart';

import 'dock_settings.dart' show DockPosition;

import 'package:denial_shell_kit/glass_card.dart';

import 'dock_look_style.dart';

/// Which side of a menu panel carries the pointer tail, mirroring the dock's
/// edge. Menus open away from the screen edge, so the tail points back at it.
enum DockMenuTail { none, down, left, right }

/// A tail drawn in the panel's fill colour, so the seam between the tail and
/// the panel is invisible.
class DockTail extends StatelessWidget {
  const DockTail({
    required this.tail,
    required this.color,
    this.length = 6,
    super.key,
  });

  final DockMenuTail tail;
  final Color color;

  /// Height of a downward tail, or width of a sideways one.
  final double length;

  @override
  Widget build(BuildContext context) {
    if (tail == DockMenuTail.none) return const SizedBox.shrink();
    final depth = length * 2.1;
    return CustomPaint(
      size: tail == DockMenuTail.down
          ? Size(depth, length)
          : Size(length, depth),
      painter: _MenuTailPainter(color, tail),
    );
  }
}

/// Where a menu opens relative to its anchor icon, plus how the tail lines up.
class DockMenuAnchor {
  const DockMenuAnchor({
    required this.left,
    required this.width,
    required this.tail,
    required this.tailAlignment,
    this.panelBottomY,
    this.alignBox,
    this.alignmentY = 0,
  });

  final double left;
  final double width;
  final DockMenuTail tail;
  final double tailAlignment;

  /// Scene-space y of the panel's bottom edge, for docks on the bottom edge.
  final double? panelBottomY;

  /// Vertical band a side-dock panel is centred inside.
  final Rect? alignBox;

  final double alignmentY;
}

/// A menu opens away from the dock's edge: above a bottom dock, beside a side
/// dock, with the tail pointing back at the icon.
DockMenuAnchor? dockMenuAnchor({
  required Rect anchor,
  required Rect output,
  required double width,
  required DockPosition position,
  double gap = 10,
}) {
  if (width <= 0 || output.isEmpty) return null;
  const inset = 8.0;
  switch (position) {
    case DockPosition.bottom:
      if (anchor.top - gap - output.top < inset) return null;
      final left = (anchor.center.dx - width / 2).clamp(
        output.left + inset,
        math.max(output.left + inset, output.right - width - inset),
      );
      return DockMenuAnchor(
        left: left.toDouble(),
        width: width,
        tail: DockMenuTail.down,
        tailAlignment: ((anchor.center.dx - left) / width).clamp(0.08, 0.92),
        panelBottomY: anchor.top - gap,
      );
    case DockPosition.left:
    case DockPosition.right:
      final left = position == DockPosition.left
          ? anchor.right + gap
          : anchor.left - gap - width;
      if (left < output.left + inset || left + width > output.right - inset) {
        return null;
      }
      final box = Rect.fromLTRB(
        output.left,
        output.top + inset,
        output.right,
        output.bottom - inset,
      );
      final t = box.height <= 0
          ? 0.5
          : ((anchor.center.dy - box.top) / box.height).clamp(0.0, 1.0);
      return DockMenuAnchor(
        left: left,
        width: width,
        tail: position == DockPosition.left
            ? DockMenuTail.left
            : DockMenuTail.right,
        tailAlignment: 0.5,
        alignBox: box,
        alignmentY: t * 2 - 1,
      );
  }
}

/// Positions a menu panel for [anchor] inside the scene overlay.
class DockMenuLayer extends StatelessWidget {
  const DockMenuLayer({
    required this.anchor,
    required this.overlaySize,
    required this.child,
    super.key,
  });

  final DockMenuAnchor anchor;
  final Size overlaySize;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final bottomY = anchor.panelBottomY;
    if (bottomY != null) {
      return Positioned(
        left: anchor.left,
        bottom: overlaySize.height - bottomY,
        width: anchor.width,
        child: child,
      );
    }
    final box = anchor.alignBox ?? Offset.zero & overlaySize;
    return Positioned(
      left: anchor.left,
      top: box.top,
      height: math.max(0.0, box.height),
      width: anchor.width,
      child: Align(alignment: Alignment(0, anchor.alignmentY), child: child),
    );
  }
}

/// The blurred, hairline-bordered panel shared by the application menu and the
/// dock menu.
class DockMenuPanel extends StatelessWidget {
  const DockMenuPanel({
    required this.radius,
    required this.child,
    this.maxHeight,
    this.tail = DockMenuTail.none,
    this.tailAlignment = 0.5,
    this.origin,
    super.key,
  });

  final BorderRadius radius;
  final Widget child;
  final double? maxHeight;
  final DockMenuTail tail;

  /// Position of the tail along the panel edge, 0 = start, 1 = end.
  final double tailAlignment;

  /// The point the panel grows out of. A panel with a tail grows out of the
  /// tail's tip, so this is only for one without.
  final Alignment? origin;

  @override
  Widget build(BuildContext context) => _MenuEntrance(
    alignment:
        origin ??
        switch (tail) {
          DockMenuTail.down => Alignment(tailAlignment * 2 - 1, 1),
          DockMenuTail.left => Alignment(-1, tailAlignment * 2 - 1),
          DockMenuTail.right => Alignment(1, tailAlignment * 2 - 1),
          DockMenuTail.none => Alignment.topCenter,
        },
    child: _panel(context),
  );

  Widget _panel(BuildContext context) {
    final theme = context.shellTheme;
    // The rows arrive a moment after the plate, as the bar's menus do. Only
    // the rows fade: the plate carries a backdrop blur, which an opacity
    // layer around it would cut off from what it blurs.
    final child = TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: KitMotion.duration(context, KitMotion.tap),
      curve: KitMotion.out,
      builder: (context, shown, child) =>
          Opacity(opacity: shown, child: child),
      child: this.child,
    );
    // The outline is stroked over the panel and its tail as one shape, so the
    // hairline never crosses the tail's base the way a bottom border did.
    final outlined = tail != DockMenuTail.none;
    final fill = GlassCard.fillOf(theme);
    // A tail has to be stroked as one outline with its panel, so only a
    // tail-less panel takes the card's continuous corners and shadow.
    final panel = !outlined
        ? GlassCard(radius: radius.topLeft.x, child: child)
        : ShellBackdropBlur(
            blur: theme.effectivePanelOpacity < 1,
            separateChild: true,
            borderRadius: radius,
            child: DecoratedBox(
              decoration: BoxDecoration(color: fill, borderRadius: radius),
              child: child,
            ),
          );
    final height = maxHeight;
    final sized = height == null
        ? panel
        : ConstrainedBox(
            constraints: BoxConstraints(maxHeight: height),
            child: panel,
          );
    if (tail == DockMenuTail.none) return sized;
    final aligned = Align(
      alignment: switch (tail) {
        DockMenuTail.down => Alignment(tailAlignment * 2 - 1, 0),
        _ => Alignment(0, tailAlignment * 2 - 1),
      },
      child: DockTail(tail: tail, color: fill),
    );
    final body = switch (tail) {
      DockMenuTail.down => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          sized,
          SizedBox(height: 6, child: aligned),
        ],
      ),
      DockMenuTail.left => Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(width: 6, height: 14, child: aligned),
          Expanded(child: sized),
        ],
      ),
      DockMenuTail.right => Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: sized),
          SizedBox(width: 6, height: 14, child: aligned),
        ],
      ),
      DockMenuTail.none => sized,
    };
    if (!outlined) return body;
    return CustomPaint(
      foregroundPainter: _MenuOutlinePainter(
        color: theme.colors.hairline,
        radius: radius.topLeft.x,
        tail: tail,
        tailAlignment: tailAlignment,
      ),
      child: body,
    );
  }
}

/// A menu growing into its shape when it opens, on the spring the look gives
/// every popup: Denial's stretches out of a bead and settles, macOS's barely
/// moves. It runs once, when the panel is first shown; with reduced motion
/// the panel is simply there.
class _MenuEntrance extends StatefulWidget {
  const _MenuEntrance({required this.alignment, required this.child});

  final Alignment alignment;
  final Widget child;

  @override
  State<_MenuEntrance> createState() => _MenuEntranceState();
}

class _MenuEntranceState extends State<_MenuEntrance>
    with SingleTickerProviderStateMixin {
  late final KitSpring _grow = KitSpring(0, KitStyle.denial.panelGrow);
  late final KitSprings _springs = KitSprings(this, <KitSpring>[_grow]);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _grow
      ..tune(KitStyle.of(context).panelGrow)
      ..target = 1;
    _springs.kick(reduceMotion: KitMotion.reduced(context));
  }

  @override
  void dispose() {
    _springs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bead = KitStyle.of(context).panelBead;
    return AnimatedBuilder(
      animation: _springs,
      builder: (context, child) {
        final grown = _grow.value;
        return Transform.scale(
          alignment: widget.alignment,
          scaleX: bead.width + (1 - bead.width) * grown,
          scaleY: bead.height + (1 - bead.height) * grown,
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// The panel and its tail stroked as one path, so the hairline follows the
/// tail's slanted sides instead of running flat across its base.
class _MenuOutlinePainter extends CustomPainter {
  const _MenuOutlinePainter({
    required this.color,
    required this.radius,
    required this.tail,
    required this.tailAlignment,
  });

  final Color color;
  final double radius;
  final DockMenuTail tail;
  final double tailAlignment;

  static const double _length = 6;
  static const double _depth = _length * 2.1;

  @override
  void paint(Canvas canvas, Size size) {
    final Path body;
    final Path point;
    switch (tail) {
      case DockMenuTail.down:
        final rect = Rect.fromLTWH(0, 0, size.width, size.height - _length);
        final centre =
            (rect.left + radius + (rect.width - radius * 2) * tailAlignment)
                .clamp(rect.left + radius, rect.right - radius)
                .toDouble();
        body = Path()
          ..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
        point = Path()
          ..moveTo(centre - _depth / 2, rect.bottom - 1)
          ..lineTo(centre, size.height)
          ..lineTo(centre + _depth / 2, rect.bottom - 1)
          ..close();
      case DockMenuTail.left:
        final rect = Rect.fromLTWH(
          _length,
          0,
          size.width - _length,
          size.height,
        );
        body = Path()
          ..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
        point = Path()
          ..moveTo(rect.left + 1, rect.center.dy - _depth / 2)
          ..lineTo(0, rect.center.dy)
          ..lineTo(rect.left + 1, rect.center.dy + _depth / 2)
          ..close();
      case DockMenuTail.right:
        final rect = Rect.fromLTWH(0, 0, size.width - _length, size.height);
        body = Path()
          ..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
        point = Path()
          ..moveTo(rect.right - 1, rect.center.dy - _depth / 2)
          ..lineTo(size.width, rect.center.dy)
          ..lineTo(rect.right - 1, rect.center.dy + _depth / 2)
          ..close();
      case DockMenuTail.none:
        return;
    }
    final shape = Path.combine(PathOperation.union, body, point);
    canvas.drawPath(
      shape,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _MenuOutlinePainter old) =>
      old.color != color ||
      old.radius != radius ||
      old.tail != tail ||
      old.tailAlignment != tailAlignment;
}

class _MenuTailPainter extends CustomPainter {
  const _MenuTailPainter(this.fill, this.tail);

  final Color fill;
  final DockMenuTail tail;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    switch (tail) {
      case DockMenuTail.down:
        path
          ..moveTo(0, 0)
          ..lineTo(size.width / 2, size.height)
          ..lineTo(size.width, 0);
      case DockMenuTail.left:
        path
          ..moveTo(0, size.height / 2)
          ..lineTo(size.width, 0)
          ..lineTo(size.width, size.height);
      case DockMenuTail.right:
        path
          ..moveTo(size.width, size.height / 2)
          ..lineTo(0, 0)
          ..lineTo(0, size.height);
      case DockMenuTail.none:
        return;
    }
    canvas.drawPath(path..close(), Paint()..color = fill);
  }

  @override
  bool shouldRepaint(covariant _MenuTailPainter oldDelegate) =>
      oldDelegate.fill != fill || oldDelegate.tail != tail;
}

class DockMenuSeparator extends StatelessWidget {
  const DockMenuSeparator({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: SizedBox(
        height: 1,
        child: ColoredBox(color: theme.colors.hairline),
      ),
    );
  }
}

/// A menu line that opens a submenu on hover, drawn to the side of the parent
/// panel like the macOS Dock's position submenu.
class DockMenuSubmenuRow extends StatefulWidget {
  const DockMenuSubmenuRow({
    required this.icon,
    required this.label,
    required this.submenu,
    super.key,
  });

  final IconData icon;
  final String label;
  final WidgetBuilder submenu;

  @override
  State<DockMenuSubmenuRow> createState() => _DockMenuSubmenuRowState();
}

class _DockMenuSubmenuRowState extends State<DockMenuSubmenuRow> {
  final OverlayPortalController _portal = OverlayPortalController();
  Timer? _openTimer;
  Timer? _closeTimer;
  bool _open = false;

  @override
  void dispose() {
    _openTimer?.cancel();
    _closeTimer?.cancel();
    super.dispose();
  }

  void _scheduleOpen() {
    _closeTimer?.cancel();
    _closeTimer = null;
    if (_open || _openTimer != null) return;
    _openTimer = Timer(const Duration(milliseconds: 90), () {
      _openTimer = null;
      if (!mounted) return;
      setState(() => _open = true);
      _portal.show();
    });
  }

  void _scheduleClose() {
    _openTimer?.cancel();
    _openTimer = null;
    _closeTimer?.cancel();
    _closeTimer = Timer(const Duration(milliseconds: 220), () {
      _closeTimer = null;
      if (!mounted || !_open) return;
      _portal.hide();
      setState(() => _open = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final row = KitStyle.of(context).menuRow(theme, hot: _open);
    return OverlayPortal.overlayChildLayoutBuilder(
      controller: _portal,
      overlayChildBuilder: (context, layout) =>
          _open ? _buildSubmenu(context, layout) : const SizedBox.shrink(),
      child: MouseRegion(
        onEnter: (_) => _scheduleOpen(),
        onExit: (_) => _scheduleClose(),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _scheduleOpen,
          child: Container(
            height: 30,
            margin: const EdgeInsets.symmetric(horizontal: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              borderRadius: theme.borderRadius(8),
              color: row.fill,
            ),
            child: Row(
              children: [
                Icon(widget.icon, size: 17, color: row.ink),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.text.systemBarCaption.inLook.copyWith(
                      color: row.ink,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right, size: 16, color: row.dim),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSubmenu(BuildContext context, OverlayChildLayoutInfo layout) {
    final theme = context.shellTheme;
    final anchor = MatrixUtils.transformRect(
      layout.childPaintTransform,
      Offset.zero & layout.childSize,
    );
    final scene = Offset.zero & layout.overlaySize;
    final width = math.min(190.0, math.max(0.0, scene.width - 16));
    final opensRight = anchor.right + 6 + width <= scene.right - 8;
    final left = opensRight
        ? anchor.right + 6
        : math.max(scene.left + 8, anchor.left - 6 - width);
    return Positioned(
      left: left,
      top: math.min(
        math.max(scene.top + 8, anchor.top - 6),
        math.max(scene.top + 8, scene.bottom - 8 - 150),
      ),
      width: width,
      child: MouseRegion(
        onEnter: (_) {
          _closeTimer?.cancel();
          _closeTimer = null;
        },
        onExit: (_) => _scheduleClose(),
        child: DockMenuPanel(
          radius: theme.borderRadius(13),
          origin: opensRight ? Alignment.topLeft : Alignment.topRight,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [widget.submenu(context)],
            ),
          ),
        ),
      ),
    );
  }
}

/// A grey caption that groups the rows under it, the way macOS titles the
/// sections of a stack's menu.
class DockMenuSectionLabel extends StatelessWidget {
  const DockMenuSectionLabel(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 9, 16, 3),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.text.systemBarCaption.inLook.copyWith(
            color: theme.colors.textTertiary,
          ),
        ),
      ),
    );
  }
}

/// One selectable line in a dock menu. [selected] draws a trailing check, used
/// by on/off settings and the active application.
class DockMenuRow extends StatefulWidget {
  const DockMenuRow({
    required this.label,
    required this.onTap,
    this.icon,
    this.selected = false,
    super.key,
  });

  /// Drawn ahead of the label when given; the stack's own menu is plain text
  /// the way macOS draws it.
  final IconData? icon;
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
    final row = KitStyle.of(context).menuRow(theme, hot: _hovered);
    final foreground = row.ink;
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
            height: 30,
            margin: const EdgeInsets.symmetric(horizontal: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              borderRadius: theme.borderRadius(8),
              color: row.fill,
            ),
            child: Row(
              children: [
                if (widget.icon case final icon?) ...[
                  Icon(icon, size: 17, color: foreground),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.text.systemBarCaption.inLook.copyWith(
                      color: foreground,
                    ),
                  ),
                ),
                if (widget.selected)
                  Icon(
                    Icons.check,
                    size: 16,
                    color: _hovered && KitStyle.of(context).accentMenuRows
                        ? foreground
                        : theme.kitAccent,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
