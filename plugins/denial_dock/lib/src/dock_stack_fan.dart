import 'dart:math' as math;

/// One row of a fan: the box it occupies once settled, and its tilt.
///
/// Plain doubles rather than Flutter geometry, so the layout and the hit test
/// can be tested as an ordinary Dart program.
class DockFanRow {
  const DockFanRow({
    required this.index,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.angle,
    required this.iconX,
    required this.iconY,
  });

  final int index;
  final double left;
  final double top;
  final double width;
  final double height;

  /// Clockwise tilt in radians, one step per row.
  final double angle;

  /// Where the row's icon sits, which is the pivot the rows fan out from.
  final double iconX;
  final double iconY;

  double get right => left + width;
  double get bottom => top + height;
  double get centerX => left + width / 2;
  double get centerY => top + height / 2;
}

/// The geometry of a fan, matching the macOS Stack: rows rise from the dock
/// icon in a straight column, drift sideways on a power curve and tilt one
/// step per row, so the icons trace an arc while the labels stay legible.
abstract final class DockStackFan {
  /// Row height.
  static const double rowHeight = 52;

  /// Vertical distance between rows: the row plus a 4 px gap.
  static const double rowStep = 56;

  /// Sideways drift coefficient; `x = shift * i^power`.
  static const double shift = 2.5;

  /// The drift's exponent. Above 1, so the lower rows crowd the icon and the
  /// upper ones spread out.
  static const double shiftPower = 1.8;

  /// Tilt per row, in degrees.
  static const double tiltDegrees = 2.5;

  /// Distance between the dock capsule and the first row.
  static const double gap = 10;

  /// Horizontal padding inside a row.
  static const double padX = 10;

  /// Row corner radius.
  static const double radius = 10;

  /// Icon edge inside a row.
  static const double iconSize = 40;

  /// Label width past which the text ellipsizes.
  static const double labelMaxWidth = 260;

  /// How far a row grows under the pointer.
  static const double hoverScale = 1.06;

  /// Rows that fit on a screen this tall, between [bottom] and [top].
  ///
  /// The reference implementations cap the fan at 8 to 16 rows; deriving it
  /// from the screen keeps a short display from pushing the top row off it.
  static int fitRows({required double bottom, required double top}) {
    final room = bottom - top - gap;
    if (room <= 0) return 1;
    return math.max(1, (room / rowStep).floor());
  }

  /// The rows for a settled fan, in slot order (0 nearest the dock).
  ///
  /// [widths] is each row's width once its label is measured. [anchorX] is the
  /// dock icon's centre and [bottom] the y the first row sits above.
  static List<DockFanRow> layout({
    required List<double> widths,
    required double anchorX,
    required double bottom,
    double scale = 1,
  }) {
    final rows = <DockFanRow>[];
    final step = rowStep * scale;
    final height = rowHeight * scale;
    final icon = iconSize * scale;
    final pad = padX * scale;
    for (var i = 0; i < widths.length; i++) {
      final rowWidth = widths[i];
      final shiftX = shift * math.pow(i, shiftPower) * scale;
      final centreY = bottom - step * (i + 1) + height / 2;
      // Right-aligned on the anchor plus the drift, so the icon column traces
      // the arc and the labels rag out to the left, which is the shape the
      // reference draws.
      final right = anchorX + shiftX + pad;
      rows.add(
        DockFanRow(
          index: i,
          left: right - rowWidth,
          top: centreY - height / 2,
          width: rowWidth,
          height: height,
          angle: tiltDegrees * i * math.pi / 180,
          iconX: right - icon / 2,
          iconY: centreY,
        ),
      );
    }
    return rows;
  }

  /// The leftmost x the settled fan reaches once its labels are turned, so a
  /// fan near the screen edge can be shifted back onto it.
  static double leftReach(List<DockFanRow> rows, {double scale = 1}) {
    var left = double.infinity;
    for (final row in rows) {
      final reach = (row.width - iconSize * scale / 2) * hoverScale;
      final turned =
          row.centerX -
          reach * math.cos(row.angle) -
          row.height / 2 * math.sin(row.angle);
      left = math.min(left, turned);
    }
    return left.isFinite ? left : 0;
  }

  /// The row under [point], or null.
  ///
  /// Each row is tested by rotating the point back into the row's own frame:
  /// the rows are drawn turned, so a plain rectangle test would miss the
  /// corners and catch empty space. Later rows sit above earlier ones, so they
  /// are tested first.
  static int? hitTest(List<DockFanRow> rows, double x, double y) {
    for (var i = rows.length - 1; i >= 0; i--) {
      if (contains(rows[i], x, y)) return i;
    }
    return null;
  }

  /// Whether [x], [y] falls inside [row] once its tilt is undone.
  static bool contains(DockFanRow row, double x, double y) {
    final dx = x - row.centerX;
    final dy = y - row.centerY;
    final cos = math.cos(-row.angle);
    final sin = math.sin(-row.angle);
    final localX = dx * cos - dy * sin;
    final localY = dx * sin + dy * cos;
    return localX.abs() <= row.width / 2 && localY.abs() <= row.height / 2;
  }
}
