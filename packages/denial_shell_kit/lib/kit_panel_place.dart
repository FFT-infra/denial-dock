import 'dart:math' as math;

/// The screen edge a bar or a dock sits on. A panel opens away from it.
enum KitEdge {
  top,
  bottom,
  left,
  right;

  bool get isHorizontal => this == top || this == bottom;
}

/// Where a panel sits along its host, for a host on the top or bottom edge.
enum KitPanelAlign {
  /// The panel's leading side at the anchor's leading side, moved by the
  /// offset: a menu under its title.
  anchorStart,

  /// Centred on the anchor: a popover under its status item.
  anchorCenter,

  /// The panel's trailing side at the anchor's trailing side, moved inwards
  /// by the offset.
  anchorEnd,

  /// At the scene's trailing side, the offset away from it, wherever the
  /// anchor is: a sheet such as the control centre.
  sceneEnd,
}

/// Where a panel goes. Each side is a distance from the same side of the
/// scene, or null when the panel is not pinned to that side. [originX] and
/// [originY] run from -1 to 1 and name the point of the panel nearest the
/// anchor, the point it grows out of.
class KitPanelPlace {
  const KitPanelPlace({
    required this.originX,
    required this.originY,
    required this.maxHeight,
    this.left,
    this.top,
    this.right,
    this.bottom,
  });

  final double? left;
  final double? top;
  final double? right;
  final double? bottom;
  final double originX;
  final double originY;

  /// The height left for the panel between its pinned side and the far side
  /// of the scene.
  final double maxHeight;
}

/// Places a panel of [width] that belongs to a host on [edge].
///
/// The host covers [hostExtent] from its edge, and the panel starts [gap]
/// beyond that, so every panel of one host lines up however tall the item
/// that opened it is. The anchor, the item's rectangle in the scene, decides
/// only where the panel sits along the host. Without an anchor the panel
/// falls back to the scene: the leading side for [KitPanelAlign.anchorStart]
/// and the middle for [KitPanelAlign.anchorCenter].
///
/// A host on the left or right edge hangs the panel beside the item, its top
/// [sideLift] above the item's top.
KitPanelPlace kitPanelPlace({
  required double sceneWidth,
  required double sceneHeight,
  required KitEdge edge,
  required double hostExtent,
  required double gap,
  required double width,
  required KitPanelAlign align,
  double alignOffset = 0,
  double margin = 6,
  double sideLift = 4,
  double? anchorLeft,
  double? anchorTop,
  double? anchorRight,
}) {
  final double? left;
  final double? top;
  double? right;
  double? bottom;
  final double originX;
  final double originY;
  if (edge.isHorizontal) {
    final maxLeft = math.max(margin, sceneWidth - width - margin);
    final hasAnchor = anchorLeft != null && anchorRight != null;
    final centre = hasAnchor ? (anchorLeft + anchorRight) / 2 : null;
    final double x = switch (align) {
      KitPanelAlign.anchorStart =>
        ((anchorLeft ?? 0) + alignOffset).clamp(margin, maxLeft).toDouble(),
      KitPanelAlign.anchorCenter =>
        ((centre ?? sceneWidth / 2) - width / 2)
            .clamp(margin, maxLeft)
            .toDouble(),
      KitPanelAlign.anchorEnd =>
        ((anchorRight ?? sceneWidth) - alignOffset - width)
            .clamp(margin, maxLeft)
            .toDouble(),
      KitPanelAlign.sceneEnd => math.max(
        margin,
        sceneWidth - width - alignOffset,
      ),
    };
    left = x;
    if (edge == KitEdge.bottom) {
      top = null;
      bottom = hostExtent + gap;
    } else {
      top = hostExtent + gap;
    }
    originX = centre == null
        ? 0
        : (((centre - x) / width) * 2 - 1).clamp(-1.0, 1.0).toDouble();
    originY = edge == KitEdge.bottom ? 1 : -1;
  } else {
    if (edge == KitEdge.left) {
      left = hostExtent + gap;
    } else {
      left = null;
      right = hostExtent + gap;
    }
    top = math.max(margin, (anchorTop ?? margin) - sideLift);
    originX = edge == KitEdge.left ? -1 : 1;
    originY = -1;
  }
  return KitPanelPlace(
    left: left,
    top: top,
    right: right,
    bottom: bottom,
    originX: originX,
    originY: originY,
    maxHeight: sceneHeight - (top ?? 0) - (bottom ?? 0) - 8,
  );
}

/// Where a menu of [width] by [height] goes for the anchor it drops from.
class KitMenuPlace {
  const KitMenuPlace(this.left, this.top);

  final double left;
  final double top;
}

/// Places a menu against its anchor: under the item for a horizontal host,
/// beside it for a vertical one, and above it when the room below has run out.
///
/// A menu hangs from the anchor itself rather than from the host's edge, so it
/// reads as belonging to the item that opened it. [fromRight] aligns the
/// menu's trailing side with the anchor's, and for a vertical host it means
/// the host sits on the right edge. The arithmetic for the along-the-host
/// axis is [kitPanelPlace]'s, so a menu and a popover of one host share it.
KitMenuPlace kitMenuPlace({
  required double sceneWidth,
  required double sceneHeight,
  required double anchorLeft,
  required double anchorTop,
  required double anchorRight,
  required double anchorBottom,
  required double width,
  required double height,
  required bool vertical,
  required bool fromRight,
  double margin = 6,
  double gap = 4,
  double sideGap = 6,
  double sideLift = 5,
}) {
  final double x;
  double y;
  if (vertical) {
    final place = kitPanelPlace(
      sceneWidth: sceneWidth,
      sceneHeight: sceneHeight,
      edge: fromRight ? KitEdge.right : KitEdge.left,
      hostExtent: fromRight ? sceneWidth - anchorLeft : anchorRight,
      gap: sideGap,
      width: width,
      align: KitPanelAlign.anchorStart,
      margin: margin,
      sideLift: sideLift,
      anchorTop: anchorTop,
    );
    // The left host pins the leading edge; the right host pins the trailing
    // one, so its leading edge is the scene minus both the margin and the
    // width.
    x = place.left ?? sceneWidth - (place.right ?? 0) - width;
    y = place.top ?? margin;
  } else {
    final place = kitPanelPlace(
      sceneWidth: sceneWidth,
      sceneHeight: sceneHeight,
      edge: KitEdge.top,
      hostExtent: anchorBottom,
      gap: gap,
      width: width,
      align: fromRight ? KitPanelAlign.anchorEnd : KitPanelAlign.anchorStart,
      alignOffset: -gap,
      margin: margin,
      anchorLeft: anchorLeft,
      anchorRight: anchorRight,
    );
    x = place.left ?? margin;
    y = anchorBottom + gap;
    if (y + height > sceneHeight - margin) y = anchorTop - gap - height;
  }
  final clampedX = x.clamp(
    margin,
    math.max(margin, sceneWidth - width - margin),
  );
  y = y.clamp(margin, math.max(margin, sceneHeight - height - margin));
  return KitMenuPlace(clampedX.toDouble(), y.toDouble());
}
