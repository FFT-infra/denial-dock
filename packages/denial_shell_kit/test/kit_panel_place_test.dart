import 'dart:math' as math;

import 'package:denial_shell_kit/kit_panel_place.dart';

void _expect(bool ok, String what) {
  if (!ok) throw StateError(what);
}

bool _near(double? a, double b) => a != null && (a - b).abs() < 1e-9;

void main() {
  // The scene is the tablet's, the host a 33 px top bar with the bar's gaps.
  const w = 1524.0, h = 1016.0, bar = 33.0;

  // A popover centred on its item.
  var p = kitPanelPlace(
    sceneWidth: w,
    sceneHeight: h,
    edge: KitEdge.top,
    hostExtent: bar,
    gap: 8,
    width: 320,
    align: KitPanelAlign.anchorCenter,
    anchorLeft: 1100,
    anchorTop: 4,
    anchorRight: 1130,
  );
  _expect(_near(p.left, 1115 - 160), 'centred popover sits under its item');
  _expect(_near(p.top, bar + 8), 'a top host opens downwards, past the host');
  _expect(p.bottom == null && p.right == null, 'only two sides are pinned');
  _expect(_near(p.originX, 0) && p.originY == -1, 'it grows from the item');
  _expect(_near(p.maxHeight, h - 41 - 8), 'the rest of the scene is free');

  // Near the trailing side the panel stays in the scene and still grows from
  // the item, not from its own middle.
  p = kitPanelPlace(
    sceneWidth: w,
    sceneHeight: h,
    edge: KitEdge.top,
    hostExtent: bar,
    gap: 8,
    width: 320,
    align: KitPanelAlign.anchorCenter,
    anchorLeft: 1480,
    anchorTop: 4,
    anchorRight: 1510,
  );
  _expect(_near(p.left, w - 320 - 6), 'a popover is kept inside the scene');
  _expect(
    _near(p.originX, ((1495 - (w - 326)) / 320) * 2 - 1),
    'the origin follows the item',
  );

  // A menu hangs from its title's leading side, moved by the offset.
  p = kitPanelPlace(
    sceneWidth: w,
    sceneHeight: h,
    edge: KitEdge.top,
    hostExtent: bar,
    gap: 2,
    width: 240,
    align: KitPanelAlign.anchorStart,
    alignOffset: -6,
    anchorLeft: 100,
    anchorTop: 4,
    anchorRight: 160,
  );
  _expect(_near(p.left, 94) && _near(p.top, bar + 2), 'a menu under its title');

  // A sheet at the scene's trailing side ignores where its item is.
  p = kitPanelPlace(
    sceneWidth: w,
    sceneHeight: h,
    edge: KitEdge.top,
    hostExtent: bar,
    gap: 8,
    width: 360,
    align: KitPanelAlign.sceneEnd,
    alignOffset: 8,
    anchorLeft: 700,
    anchorTop: 4,
    anchorRight: 760,
  );
  _expect(_near(p.left, w - 360 - 8), 'a sheet sits at the trailing side');

  // The trailing sides meet, moved inwards by the offset.
  p = kitPanelPlace(
    sceneWidth: w,
    sceneHeight: h,
    edge: KitEdge.top,
    hostExtent: bar,
    gap: 8,
    width: 300,
    align: KitPanelAlign.anchorEnd,
    alignOffset: 4,
    anchorLeft: 900,
    anchorTop: 4,
    anchorRight: 1000,
  );
  _expect(_near(p.left, 1000 - 4 - 300), 'trailing sides meet');

  // A host on the bottom edge opens upwards from the same distance.
  p = kitPanelPlace(
    sceneWidth: w,
    sceneHeight: h,
    edge: KitEdge.bottom,
    hostExtent: 81,
    gap: 8,
    width: 320,
    align: KitPanelAlign.anchorCenter,
    anchorLeft: 900,
    anchorTop: 940,
    anchorRight: 960,
  );
  _expect(p.top == null && _near(p.bottom, 89), 'a bottom host opens upwards');
  _expect(p.originY == 1, 'and grows from its lower side');
  _expect(_near(p.maxHeight, h - 89 - 8), 'with the scene above it free');

  // Hosts on the side edges hang the panel beside the item.
  p = kitPanelPlace(
    sceneWidth: w,
    sceneHeight: h,
    edge: KitEdge.left,
    hostExtent: bar,
    gap: 8,
    width: 320,
    align: KitPanelAlign.anchorCenter,
    anchorLeft: 4,
    anchorTop: 300,
    anchorRight: 29,
  );
  _expect(_near(p.left, 41) && p.right == null, 'beside a left host');
  _expect(_near(p.top, 296), 'lifted a little above the item');
  _expect(p.originX == -1 && p.originY == -1, 'growing from the host corner');
  p = kitPanelPlace(
    sceneWidth: w,
    sceneHeight: h,
    edge: KitEdge.right,
    hostExtent: bar,
    gap: 8,
    width: 320,
    align: KitPanelAlign.anchorCenter,
    anchorLeft: 1495,
    anchorTop: 2,
    anchorRight: 1520,
  );
  _expect(p.left == null && _near(p.right, 41), 'beside a right host');
  _expect(_near(p.top, 6), 'never above the scene margin');
  _expect(p.originX == 1, 'growing from the right');

  // Without an anchor the scene stands in: the middle, or the leading side.
  p = kitPanelPlace(
    sceneWidth: w,
    sceneHeight: h,
    edge: KitEdge.top,
    hostExtent: bar,
    gap: 8,
    width: 320,
    align: KitPanelAlign.anchorCenter,
  );
  _expect(_near(p.left, w / 2 - 160) && p.originX == 0, 'no anchor: centred');

  // A panel wider than the scene keeps its leading margin.
  p = kitPanelPlace(
    sceneWidth: 300,
    sceneHeight: h,
    edge: KitEdge.top,
    hostExtent: bar,
    gap: 8,
    width: 320,
    align: KitPanelAlign.sceneEnd,
    alignOffset: 8,
  );
  _expect(_near(p.left, math.max(6, 300 - 320 - 8)), 'wider than the scene');
}
