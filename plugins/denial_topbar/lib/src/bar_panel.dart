import 'dart:math' as math;

import 'package:denial_flutter_sdk/effects.dart';
import 'package:denial_flutter_sdk/panels.dart';
import 'package:denial_flutter_sdk/popups.dart';
import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'bar_tokens.dart';

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
      child: builder(context, popup.close),
    ),
  );
  _openId = panelId;
  _openPopup = handle.id;
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
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(radius),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: theme.colors.shadow.withValues(alpha: 0.28),
                    blurRadius: 30,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: ShellBackdropBlur(
                borderRadius: BorderRadius.circular(radius),
                blendMode: BlendMode.srcOver,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    // A menu is the opaque material macOS draws behind a
                    // dropdown; a panel is the translucent glass card.
                    color:
                        fill ??
                        (glass
                            ? theme.panelColor(theme.colors.panelBackground)
                            : theme.colors.panelBackground),
                    borderRadius: BorderRadius.circular(radius),
                    border: Border.all(
                      color: theme.colors.hairline,
                      width: 0.8,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(radius - 1),
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
