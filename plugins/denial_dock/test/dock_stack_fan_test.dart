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

  // Tilt is one step per row and zero on the first, so the row nearest the
  // icon stays upright.
  _expect(rows[0].angle == 0, 'the first row does not tilt');
  _expect(
    (rows[1].angle - DockStackFan.tiltDegrees * math.pi / 180).abs() < 1e-9,
    'the second row tilts one step',
  );

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
  final cornerX = turned.centerX + turned.width / 2 * math.cos(turned.angle);
  final cornerY = turned.centerY + turned.width / 2 * math.sin(turned.angle);
  _expect(
    DockStackFan.contains(turned, cornerX, cornerY),
    'the turned corner is inside the row',
  );

  // The reach covers the turned labels, so a fan can be shifted onto the
  // screen by the shortfall.
  _expect(
    DockStackFan.leftReach(rows) < rows.first.left,
    'the turned labels reach further left',
  );

  // The row count follows the screen instead of a fixed cap.
  _expect(
    DockStackFan.fitRows(bottom: 1000, top: 0) == 17,
    'a 1000 px screen fits 17 rows: ${DockStackFan.fitRows(bottom: 1000, top: 0)}',
  );
  _expect(
    DockStackFan.fitRows(bottom: 200, top: 0) == 3,
    'a short screen fits fewer',
  );
  _expect(
    DockStackFan.fitRows(bottom: 100, top: 100) == 1,
    'no room still leaves one row',
  );
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
