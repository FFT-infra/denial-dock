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

/// Which side of the dock icon a fan leans toward. A fan leans away from the
/// nearer screen edge so its labels stay on the screen.
enum DockFanLean { right, left }

/// The geometry of a fan, matching the macOS Stack: rows rise from the dock
/// icon in a column, drift sideways on a power curve and tilt one step per row,
/// so the icons trace an arc while the labels stay legible.
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
  /// With [widths] the fit is exact: a row turned by [tilt] lifts the far end
  /// of its label by `width x sin(angle)`, and a tall fan loses its top rows to
  /// that overhang long before it runs out of steps.
  static int fitRows({
    required double bottom,
    required double top,
    List<double> widths = const [],
    double tilt = tiltDegrees,
    double scale = 1,
  }) {
    final room = bottom - top - gap;
    if (room <= 0) return 1;
    final plain = math.max(1, (room / (rowStep * scale)).floor());
    if (widths.isEmpty || tilt <= 0) return plain;
    var fits = 0;
    for (var i = 0; i < widths.length && i < plain; i++) {
      final angle = tilt * i * math.pi / 180;
      final rise =
          rowStep * scale * (i + 1) + widths[i] * math.sin(angle) * hoverScale;
      if (rise > room) break;
      fits = i + 1;
    }
    return math.max(1, fits);
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
    DockFanLean lean = DockFanLean.right,
    double tilt = tiltDegrees,
  }) {
    final sign = lean == DockFanLean.right ? 1.0 : -1.0;
    final rows = <DockFanRow>[];
    final step = rowStep * scale;
    final height = rowHeight * scale;
    final icon = iconSize * scale;
    final pad = padX * scale;
    for (var i = 0; i < widths.length; i++) {
      final rowWidth = widths[i];
      final drift = shift * math.pow(i, shiftPower) * scale * sign;
      final centreY = bottom - step * (i + 1) + height / 2;
      // The row's edge nearest the icon column sits on the anchor plus the
      // drift, so the icon column traces the arc and the labels rag out to the
      // far side, which is the shape the reference draws.
      final edge = anchorX + drift + pad * sign;
      final leading = sign < 0;
      rows.add(
        DockFanRow(
          index: i,
          left: leading ? edge : edge - rowWidth,
          top: centreY - height / 2,
          width: rowWidth,
          height: height,
          angle: tilt * i * sign * math.pi / 180,
          iconX: leading ? edge + icon / 2 : edge - icon / 2,
          iconY: centreY,
        ),
      );
    }
    return rows;
  }

  /// A column of rows beside a side dock.
  ///
  /// A fan that grew sideways would trail every label across the dock it came
  /// from, so a side dock stacks its rows vertically and centres them on the
  /// icon, which is also what macOS does there.
  static List<DockFanRow> layoutSide({
    required List<double> widths,
    required double anchorY,
    required double edgeX,
    required bool toRight,
    double scale = 1,
  }) {
    final step = rowStep * scale;
    final height = rowHeight * scale;
    final icon = iconSize * scale;
    final pad = padX * scale;
    final total = step * widths.length;
    final first = anchorY - total / 2 + (step - height) / 2;
    final rows = <DockFanRow>[];
    for (var i = 0; i < widths.length; i++) {
      final rowWidth = widths[i];
      final top = first + step * i;
      rows.add(
        DockFanRow(
          index: i,
          left: toRight ? edgeX : edgeX - rowWidth,
          top: top,
          width: rowWidth,
          height: height,
          angle: 0,
          // The icon sits on the edge nearest the dock, so the labels always
          // read away from it.
          iconX: toRight ? edgeX + pad + icon / 2 : edgeX - pad - icon / 2,
          iconY: top + height / 2,
        ),
      );
    }
    return rows;
  }

  /// The box the settled rows occupy once turned, including the hover growth.
  static ({double left, double top, double right, double bottom}) bounds(
    List<DockFanRow> rows,
  ) {
    var left = double.infinity;
    var top = double.infinity;
    var right = double.negativeInfinity;
    var bottom = double.negativeInfinity;
    for (final row in rows) {
      final cos = math.cos(row.angle);
      final sin = math.sin(row.angle);
      // A turned label's far end swings out past the unrotated box, and a
      // hovered row grows, so the reach is measured on the grown half-size.
      final hx = row.width / 2 * hoverScale;
      final hy = row.height / 2 * hoverScale;
      for (final sx in const [-1.0, 1.0]) {
        for (final sy in const [-1.0, 1.0]) {
          final x = row.centerX + sx * hx * cos - sy * hy * sin;
          final y = row.centerY + sx * hx * sin + sy * hy * cos;
          left = math.min(left, x);
          right = math.max(right, x);
          top = math.min(top, y);
          bottom = math.max(bottom, y);
        }
      }
    }
    if (!left.isFinite) return (left: 0, top: 0, right: 0, bottom: 0);
    return (left: left, top: top, right: right, bottom: bottom);
  }

  /// The lean that keeps [reach] px of drift on the screen, preferring to lean
  /// away from the nearer edge and falling back to the other side when the
  /// outward one has no room.
  static DockFanLean leanFor({
    required double anchorX,
    required double left,
    required double right,
    required double reach,
  }) {
    final outward = anchorX > (left + right) / 2
        ? DockFanLean.right
        : DockFanLean.left;
    final room = outward == DockFanLean.right
        ? right - anchorX
        : anchorX - left;
    if (room >= reach) return outward;
    return outward == DockFanLean.right ? DockFanLean.left : DockFanLean.right;
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
