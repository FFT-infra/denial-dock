import 'dart:math' as math;

import 'package:denial_flutter_sdk/effects.dart';
import 'package:denial_flutter_sdk/panels.dart';
import 'package:denial_flutter_sdk/popups.dart';
import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'bar_tokens.dart';
import 'continuous_corners.dart';

const String barPanelKey = 'denial_topbar.panel';

String? _openId;
int? _openPopup;

/// How a panel is hung under its bar item.
///
/// shell27 positions each popover differently and the difference is visible:
/// a dropdown is **left-aligned** to its title (`x: menuDropX - 4`) and sits
/// at `barH + 3`; every other popover is **centred** on its icon and sits at
/// `barH + 6`; Control Centre is pinned to the right edge.
enum BarPanelAnchor {
  /// Left edge at the item's left edge − 4. Used by the Apple menu, the app
  /// menu and every title dropdown.
  dropdown,

  /// Centred on the item. Used by Wi-Fi, Bluetooth, volume, keyboard.
  centred,

  /// Right-aligned to `screen - width - 8`. Used by the clock's calendar,
  /// which shell27 pins to the right edge because the clock is always the
  /// rightmost item.
  clock,

  /// Right-aligned to `screen - width - 10`. Used by Control Centre.
  trailing,

  /// Centred on the island, at the island's own 32 pt radius and its 8 pt
  /// gap, so the card reads as the pill growing rather than a popover [S27].
  island,
}

/// Scene rectangle of a bar item, used to hang a panel under its edge.
Rect? barSceneRect(GlobalKey key) {
  final render = key.currentContext?.findRenderObject();
  if (render is! RenderBox || !render.hasSize) return null;
  return render.localToGlobal(Offset.zero) & render.size;
}

/// Opens one bar panel at a time.
///
/// Ports NextKDE `BarStatusArea.qml`'s single-open rule: opening a second
/// module closes the first, and clicking the open module's own button closes
/// it again.
void showBarPanel({
  required WidgetRef ref,
  required String panelId,
  required GlobalKey anchor,
  required Widget Function(BuildContext context, VoidCallback close) builder,
  PanelEdge side = PanelEdge.top,
  double width = BarTokens.panelMaxWidth,
  String keyName = barPanelKey,
  bool glass = true,
  BarPanelAnchor placement = BarPanelAnchor.dropdown,
  Color? fill,
  double barHeight = BarTokens.height,
  double? height,
}) {
  final controller = ref.read(shellPopupControllerProvider.notifier);
  final previous = _openPopup;
  final previousOpen =
      previous != null &&
      ref
          .read(shellPopupControllerProvider)
          .any((popup) => popup.id == previous && !popup.closing);
  if (_openId == panelId && previousOpen) {
    controller.close(previous);
    _openId = null;
    _openPopup = null;
    return;
  }
  for (final popup in ref.read(shellPopupControllerProvider)) {
    if (popup.keyName == keyName) controller.close(popup.id);
  }
  final rect = barSceneRect(anchor);
  final handle = controller.show(
    keyName: keyName,
    debugLabel: 'Top bar $panelId',
    dismissPolicy: ShellDismissPolicy.outsideTapAndEscape,
    // The surface's own fade and close both ride this duration; the island's
    // shape grows on its own longer spring inside the frame.
    transitionDuration: Motion.cardSettle,
    barrierColor: Colors.transparent,
    builder: (context, popup) => BarPanelFrame(
      anchor: rect,
      side: side,
      width: width,
      glass: glass,
      placement: placement,
      fill: fill,
      barHeight: barHeight,
      height: height,
      child: builder(context, popup.close),
    ),
  );
  _openId = panelId;
  _openPopup = handle.id;
}

const String barDialogKey = 'denial_topbar.dialog';

/// Opens a centred dialog over the desktop, outside the bar's popover chain.
///
/// NextKDE `NetworkPanel.qml` makes the join dialog a system modal rather than
/// a row inside the Wi-Fi list: it closes the list first, then shows the card
/// on its own so the card, not the scrolling list, owns the keyboard. The same
/// rule applies here — a dialog is not anchored to a bar item and is not part
/// of the single-open popover group, so it can outlive the panel that opened it.
void showBarDialog({
  required WidgetRef ref,
  required Widget Function(BuildContext context, VoidCallback close) builder,
  double width = 420,
  String keyName = barDialogKey,
}) {
  final controller = ref.read(shellPopupControllerProvider.notifier);
  for (final popup in ref.read(shellPopupControllerProvider)) {
    if (popup.keyName == keyName) controller.close(popup.id);
  }
  controller.show(
    keyName: keyName,
    debugLabel: 'Top bar dialog',
    dismissPolicy: ShellDismissPolicy.outsideTapAndEscape,
    transitionDuration: Motion.cardSettle,
    barrierColor: Colors.transparent,
    builder: (context, popup) => _CentredDialog(
      width: width,
      child: builder(context, popup.close),
    ),
  );
}

/// The card a bar dialog sits in: the same glass as a popover, a little
/// further from the bar, and centred on the screen rather than hung from a cell.
class _CentredDialog extends StatelessWidget {
  const _CentredDialog({required this.width, required this.child});

  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    const radius = 22.0;
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        Center(
          child: SizedBox(
            width: width,
            child: DecoratedBox(
              decoration: ShapeDecoration(
                shape: ContinuousCorners(radius: radius),
                shadows: <BoxShadow>[
                  BoxShadow(
                    color: theme.colors.shadow.withValues(alpha: 0.32),
                    blurRadius: 34,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
              child: ClipPath(
                clipper: ContinuousCornersClipper(radius: radius),
                child: ShellBackdropBlur(
                  child: CustomPaint(
                    painter: _ContinuousCardPainter(
                      radius: radius,
                      fill: theme.panelColor(theme.colors.panelBackground),
                      hairline: theme.colors.hairline,
                    ),
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The glass card every bar panel is drawn in.
///
/// shell27 gives a dropdown `radius 14` at `barH + 3` and a popover `radius 26`
/// at `barH + 6`; both keep a 6 pt screen margin.
class BarPanelFrame extends StatelessWidget {
  const BarPanelFrame({
    required this.anchor,
    required this.side,
    required this.width,
    required this.child,
    this.glass = true,
    this.placement = BarPanelAnchor.dropdown,
    this.fill,
    this.barHeight = BarTokens.height,
    this.height,
    super.key,
  });

  final Rect? anchor;
  final PanelEdge side;
  final double width;
  final Widget child;

  /// The strip's real height. shell27 measures `barH + 3` / `barH + 6` from
  /// the strip's own bottom edge, and Denial's `systemBarThickness` is often
  /// taller than the 28 pt reference, so this must come from the layout
  /// rather than the token or every panel tucks into the bar.
  final double barHeight;

  /// Menus are opaque cards on macOS; panels are glass. The bar's own
  /// dropdowns pass false so their plate does not shimmer over a wallpaper.
  final bool glass;
  final BarPanelAnchor placement;

  /// Overrides the card's colour. The island's expanded card is the pill
  /// itself grown, so it keeps the pill's black instead of the panel glass.
  final Color? fill;

  /// Fixed card height. The island's card is sized by its reference rather
  /// than its content so the shape has a known rect to morph to.
  final double? height;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final scene = MediaQuery.sizeOf(context);
    final rect = anchor;
    final below = side != PanelEdge.bottom;
    final gap = switch (placement) {
      BarPanelAnchor.dropdown => BarTokens.menuDropOffsetY,
      BarPanelAnchor.island => BarTokens.islandCardGap,
      _ => BarTokens.popoverGap,
    };
    final radius = switch (placement) {
      BarPanelAnchor.dropdown => BarTokens.menuRadius,
      BarPanelAnchor.island => BarTokens.islandPopupRadius,
      _ => BarTokens.popoverRadius,
    };

    // shell27 clamps every popover into `[6, screen - width - 6]`.
    const margin = 6.0;
    final double left = switch (placement) {
      BarPanelAnchor.dropdown =>
        ((rect?.left ?? 0) + BarTokens.menuDropOffsetX)
            .clamp(margin, math.max(margin, scene.width - width - margin))
            .toDouble(),
      BarPanelAnchor.centred || BarPanelAnchor.island =>
        ((rect?.center.dx ?? scene.width / 2) - width / 2)
            .clamp(margin, math.max(margin, scene.width - width - margin))
            .toDouble(),
      BarPanelAnchor.clock => math.max(margin, scene.width - width - 8),
      BarPanelAnchor.trailing => math.max(
        margin,
        scene.width - width - BarTokens.controlCenterInset,
      ),
    };

    // shell27 measures from the bar's own bottom edge (`barH + 3`), not from
    // the item's box, so the panel never shifts with a taller title.
    final top = below ? barHeight + gap : null;
    final bottom = below ? null : scene.height - (rect?.top ?? 0) + gap;
    final available = below
        ? scene.height - (top ?? 0) - 8
        : scene.height - (bottom ?? 0) - 8;

    // macOS 27 draws its cards with continuous corners, and NextKDE gives every
    // glass surface the same `cornerExponent: 3`; only the dropdown menus stay
    // a plain rounded rectangle, which is the radius their reference uses.
    final continuous = placement != BarPanelAnchor.dropdown;
    final cardColor =
        fill ??
        (glass
            ? theme.panelColor(theme.colors.panelBackground)
            : theme.colors.panelBackground);

    // The blur sits inside the superellipse clip so the frosted region follows
    // the corner rather than a bounding rectangle, and the fill paints over it
    // — the same order the rounded branch gets from `ShellBackdropBlur` outside
    // its `DecoratedBox`.
    final Widget card = continuous
        ? ClipPath(
            clipper: ContinuousCornersClipper(radius: radius),
            child: ShellBackdropBlur(
              blur: glass,
              child: CustomPaint(
                painter: _ContinuousCardPainter(
                  radius: radius,
                  fill: cardColor,
                  hairline: theme.colors.hairline,
                ),
                child: child,
              ),
            ),
          )
        : DecoratedBox(
            decoration: BoxDecoration(
              // A menu is the opaque material macOS draws behind a dropdown;
              // a panel is the translucent glass card.
              color: cardColor,
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: theme.colors.hairline, width: 0.8),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(radius - 1),
              child: child,
            ),
          );

    final shadows = <BoxShadow>[
      BoxShadow(
        color: theme.colors.shadow.withValues(alpha: 0.28),
        blurRadius: 30,
        offset: const Offset(0, 12),
      ),
    ];

    // A BoxShadow follows a BorderRadius and would paint a rectangle behind
    // the superellipse; ShapeDecoration casts the shadow along the shape.
    final shadow = continuous
        ? DecoratedBox(
            decoration: ShapeDecoration(
              shape: ContinuousCorners(radius: radius),
              shadows: shadows,
            ),
            child: card,
          )
        : DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              boxShadow: shadows,
            ),
            child: ShellBackdropBlur(
              borderRadius: BorderRadius.circular(radius),
              blendMode: BlendMode.srcOver,
              child: card,
            ),
          );

    if (placement == BarPanelAnchor.island && rect != null) {
      // darkshadow's card is the island growing: at t = 0 it sits on the
      // pill's own rect, at t = 1 it is the card, and position, size and
      // corners morph together [S36]. The popup surface is full-screen, so it
      // can start the card on the pill instead of fading in beside it.
      //
      // Only the island grows from its anchor; every other popover is sized by
      // its content, so it takes the plain positioned branch below.
      return _IslandCardMorph(
        from: rect,
        to: Rect.fromLTWH(left, top ?? 0, width, height ?? available),
        child: shadow,
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        Positioned(
          left: left,
          width: width,
          top: top,
          bottom: bottom,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: available.clamp(120.0, scene.height),
            ),
            child: shadow,
          ),
        ),
      ],
    );
  }
}

/// The island card growing out of the pill.
///
/// darkshadow animates one rectangle from the pill's rect to the card's, the
/// corners opening from half the strip height to 30 [S36]. The card is laid
/// out at its final rect and scaled from the pill's width about its top
/// centre: the pill and the card share that centre (the card is centred on the
/// island's anchor), so the shape reads as the pill itself swelling, and the
/// corners of a 32 pt superellipse scaled down to the pill's width are the
/// pill's own round ends.
class _IslandCardMorph extends StatefulWidget {
  const _IslandCardMorph({
    required this.from,
    required this.to,
    required this.child,
  });

  /// The pill's scene rect.
  final Rect from;

  /// The card's scene rect.
  final Rect to;
  final Widget child;

  @override
  State<_IslandCardMorph> createState() => _IslandCardMorphState();
}

class _IslandCardMorphState extends State<_IslandCardMorph>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: BarTokens.islandExpand,
  );
  late final Animation<double> _eased = CurvedAnimation(
    parent: _controller,
    // meniscus expands on `.spring(0.46, bounce 0.24)` [S35]; easeOutBack is
    // that settle with its light overshoot, without a spring solver.
    // meniscus expands on `.spring(0.46, bounce 0.24)` with subtle ~3-4% overshoot
    curve: const Cubic(0.18, 1.04, 0.22, 1.0),
  );

  @override
  void initState() {
    super.initState();
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final start = widget.to.width <= 0
        ? 1.0
        : (widget.from.width / widget.to.width).clamp(0.0, 1.0);
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        Positioned(
          left: widget.to.left,
          top: widget.to.top,
          width: widget.to.width,
          height: widget.to.height,
          child: AnimatedBuilder(
            animation: _eased,
            builder: (context, child) {
              // The curve overshoots on purpose; the scale keeps the bounce,
              // the opacity does not.
              final t = _eased.value;
              final rest = 1 - t;
              return Transform.translate(
                // At t = 0 the card is scaled to the pill's width and moved
                // onto the pill's own rect, so the first frame is the pill.
                offset: Offset(
                  (widget.from.center.dx - widget.to.center.dx) * rest,
                  (widget.from.top - widget.to.top) * rest,
                ),
                child: Transform.scale(
                  alignment: Alignment.topCenter,
                  scale: start + (1 - start) * t,
                  child: Opacity(
                    // The shape itself is there from the first frame; only the
                    // surface's own fade-in is honoured, over the first third.
                    opacity: (t * 3).clamp(0.0, 1.0),
                    child: child,
                  ),
                ),
              );
            },
            child: widget.child,
          ),
        ),
      ],
    );
  }
}

/// Paints the island card: the superellipse fill, then its hairline.
class _ContinuousCardPainter extends CustomPainter {
  const _ContinuousCardPainter({
    required this.radius,
    required this.fill,
    required this.hairline,
  });

  final double radius;
  final Color fill;
  final Color hairline;

  @override
  void paint(Canvas canvas, Size size) {
    final path = continuousRoundedRectPath(Offset.zero & size, radius);
    canvas.drawPath(path, Paint()..color = fill);
    canvas.drawPath(
      path,
      Paint()
        ..color = hairline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );
  }

  @override
  bool shouldRepaint(_ContinuousCardPainter oldDelegate) =>
      oldDelegate.radius != radius ||
      oldDelegate.fill != fill ||
      oldDelegate.hairline != hairline;
}
