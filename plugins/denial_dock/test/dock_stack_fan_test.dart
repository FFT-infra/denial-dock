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

  // macOS keeps every row upright: the arc is in the path the column takes,
  // not in the items, so a turned label never happens.
  for (final row in rows) {
    _expect(row.angle == 0, 'row ${row.index} stays upright');
  }

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

  // An upright row is a plain rectangle, so its own corners are inside it.
  final upright = rows[3];
  _expect(
    DockStackFan.contains(upright, upright.left, upright.top),
    'an upright row contains its own corner',
  );
  _expect(
    !DockStackFan.contains(upright, upright.left - 1, upright.centerY),
    'a point just outside the row misses it',
  );

  // A left lean mirrors the arc: the rows drift the other way, so a fan near
  // the right edge stays on the screen.
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
  _expect(
    (mirrored[1].left - (500 - DockStackFan.shift - DockStackFan.padX)).abs() <
        0.01,
    'the left lean keeps the row edge on the anchor',
  );

  // The bounds hold every row, and grow with the drift.
  final box = DockStackFan.bounds(rows);
  _expect(box.left <= rows.first.left, 'the bounds reach the leftmost row');
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
    DockStackFan.fitRows(bottom: 1000, top: 0) == 14,
    'a 1000 px screen fits 14 rows: ${DockStackFan.fitRows(bottom: 1000, top: 0)}',
  );
  _expect(
    DockStackFan.fitRows(bottom: 200, top: 0) == 2,
    'a short screen fits fewer',
  );
  _expect(
    DockStackFan.fitRows(bottom: 100, top: 100) == 1,
    'no room still leaves one row',
  );

  // The row count is the room divided by the step, whatever the labels are:
  // an upright row never reaches past its own box.
  final wide = List<double>.filled(20, 260);
  _expect(
    DockStackFan.fitRows(bottom: 1200, top: 0, widths: wide) ==
        DockStackFan.fitRows(bottom: 1200, top: 0),
    'label width no longer costs rows',
  );
  final kept = DockStackFan.fitRows(bottom: 1200, top: 0, widths: wide);
  for (var i = 0; i < kept; i++) {
    final rise = DockStackFan.rowStep * (i + 1);
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
