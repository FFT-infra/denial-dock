import 'dart:math' as math;

import 'package:denial_dock/src/dock_stack_fan.dart';

void main() {
  // Rows rise from the anchor and drift to the right on a power curve, so the
  // gap between neighbours grows with the slot.
  final rows = DockStackFan.layout(
    widths: const [200, 200, 200, 200],
    anchorX: 500,
    bottom: 1000,
  );
  _expect(rows.length == 4, 'one row per width');
  _expect(rows[0].bottom < 1000, 'the first row sits above the anchor');
  for (var i = 1; i < rows.length; i++) {
    _expect(rows[i].top < rows[i - 1].top, 'row $i rises above row ${i - 1}');
    _expect(rows[i].right > rows[i - 1].right, 'row $i drifts right');
  }
  final firstGap = rows[1].right - rows[0].right;
  final lastGap = rows[3].right - rows[2].right;
  _expect(lastGap > firstGap, 'the drift widens with the slot');

  // Every row's icon sits on the right edge, so the icon column traces the arc.
  for (final row in rows) {
    _expect(
      (row.iconX - (row.right - DockStackFan.iconSize / 2)).abs() < 0.01,
      'row ${row.index} right-aligns its icon',
    );
  }

  // A macOS stack turns its rows with the arc. A right lean lifts the end
  // nearest the previews, so the row turns counter-clockwise: the first row
  // is level and the last is furthest off it.
  _expect(rows[0].angle == 0, 'the first row does not tilt');
  _expect(
    (rows[1].angle.abs() - DockStackFan.tiltDegrees * math.pi / 180).abs() <
        1e-9,
    'the second row tilts one step',
  );
  _expect(rows[3].angle < 0, 'a right lean lifts the preview end');

  // The rows never overlap vertically, whatever the label widths.
  for (var i = 1; i < rows.length; i++) {
    _expect(
      rows[i].bottom <= rows[i - 1].top + 0.01,
      'row $i clears row ${i - 1}',
    );
  }

  // A hit inside a row counts; the space beside it does not.
  _expect(
    DockStackFan.hitTest(rows, rows[2].centerX, rows[2].centerY) == 2,
    'the centre of a row hits that row',
  );
  _expect(
    DockStackFan.hitTest(rows, -5000, -5000) == null,
    'a point away from the fan hits nothing',
  );
  _expect(
    DockStackFan.hitTest(rows, rows[3].centerX, rows[3].centerY) == 3,
    'the upper row wins an overlap',
  );

  // A plain rectangle test would be wrong both ways: the unrotated box's
  // corner is outside the turned row, and the turned row covers points the
  // unrotated box does not.
  final turned = rows[3];
  _expect(
    !DockStackFan.contains(turned, turned.left, turned.top),
    'the unrotated corner is outside the turned row',
  );
  // A point just inside the turned end is in the row; one just past it, on
  // the unrotated box, is not.
  const inset = 0.98;
  final cornerX =
      turned.centerX + turned.width / 2 * inset * math.cos(turned.angle);
  final cornerY =
      turned.centerY + turned.width / 2 * inset * math.sin(turned.angle);
  _expect(
    DockStackFan.contains(turned, cornerX, cornerY),
    'the turned corner is inside the row',
  );

  // A left lean mirrors the arc: the rows drift and tilt the other way, so a
  // fan near the right edge stays on the screen.
  final mirrored = DockStackFan.layout(
    widths: const [200, 200, 200],
    anchorX: 500,
    bottom: 1000,
    lean: DockFanLean.left,
  );
  _expect(
    mirrored[2].left < mirrored[0].left,
    'a left lean drifts the other way',
  );
  _expect(mirrored[2].angle > 0, 'a left lean tilts the other way');
  _expect(
    (mirrored[1].left - (500 - DockStackFan.shift - DockStackFan.padX)).abs() <
        0.01,
    'the left lean keeps the row edge on the anchor',
  );

  // The bounds cover the turned rows, which reach past their unrotated boxes.
  final box = DockStackFan.bounds(rows);
  _expect(box.left < rows.first.left, 'the turned labels reach further left');
  _expect(box.right >= rows.last.right, 'the bounds contain the widest row');

  // The lean follows the room: away from the nearer edge, and back when the
  // outward side has none.
  _expect(
    DockStackFan.leanFor(anchorX: 1500, left: 0, right: 1600, reach: 50) ==
        DockFanLean.right,
    'a right-of-centre anchor leans right',
  );
  _expect(
    DockStackFan.leanFor(anchorX: 1500, left: 0, right: 1600, reach: 500) ==
        DockFanLean.left,
    'no room outward leans back',
  );

  // The row count follows the screen instead of a fixed cap.
  _expect(
    DockStackFan.fitRows(bottom: 1000, top: 0) == 15,
    'a 1000 px screen fits 15 rows: ${DockStackFan.fitRows(bottom: 1000, top: 0)}',
  );
  _expect(
    DockStackFan.fitRows(bottom: 200, top: 0) == 2,
    'a short screen fits fewer',
  );
  _expect(
    DockStackFan.fitRows(bottom: 100, top: 100) == 1,
    'no room still leaves one row',
  );

  // A turned label lifts its far end, so a tall fan loses rows to the tilt
  // before it runs out of steps. This is the bug that clipped the top row.
  final wide = List<double>.filled(20, 260);
  final withTilt = DockStackFan.fitRows(bottom: 1200, top: 0, widths: wide);
  final withoutTilt = DockStackFan.fitRows(
    bottom: 1200,
    top: 0,
    widths: wide,
    tilt: 0,
  );
  _expect(
    withTilt < withoutTilt,
    'the tilt costs rows: $withTilt vs $withoutTilt',
  );
  // And the rows it keeps really do fit once turned.
  for (var i = 0; i < withTilt; i++) {
    final angle = DockStackFan.tiltDegrees * i * math.pi / 180;
    final rise =
        DockStackFan.rowStep * (i + 1) +
        260 * math.sin(angle) * DockStackFan.hoverScale;
    _expect(rise <= 1200 - DockStackFan.gap + 0.01, 'row $i fits: $rise');
  }

  // A side dock stacks its rows vertically, centred on the icon, upright.
  final side = DockStackFan.layoutSide(
    widths: const [180, 180, 180],
    anchorY: 600,
    edgeX: 40,
    toRight: true,
  );
  _expect(side.every((row) => row.angle == 0), 'side rows stay upright');
  for (var i = 1; i < side.length; i++) {
    _expect(side[i].top > side[i - 1].top, 'side rows run downward');
    _expect(side[i].left == side[0].left, 'side rows share a column');
  }
  _expect(
    ((side[0].top + side.last.bottom) / 2 - 600).abs() < 0.01,
    'the side column is centred on the icon',
  );
  _expect(
    side[0].iconX < side[0].right,
    'a right-opening side stack puts its icon on the near edge',
  );
  final mirroredSide = DockStackFan.layoutSide(
    widths: const [180],
    anchorY: 600,
    edgeX: 1000,
    toRight: false,
  );
  _expect(
    mirroredSide.single.right <= 1000 + 0.01,
    'a left-opening side stack ends on the edge',
  );
  _expect(
    mirroredSide.single.iconX > mirroredSide.single.left,
    'a left-opening side stack keeps its icon on the near edge',
  );

  // A row is a label pill plus its own preview card, the shape a macOS stack
  // draws, so the width a fan lays out has to include both.
  _expect(
    DockStackFan.rowWidth(120) ==
        DockStackFan.pillWidth(120) +
            DockStackFan.thumbGap +
            DockStackFan.thumbSize,
    'row width is the pill plus the preview card',
  );
  _expect(
    DockStackFan.pillWidth(120) == 120 + DockStackFan.padX * 2,
    'pill width is the text plus its padding',
  );
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
