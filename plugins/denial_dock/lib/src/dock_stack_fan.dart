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

  /// Centre of the row's preview card, which is the column the rows fan out
  /// from.
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
  /// Row height: the preview card, which is what a row has to hold.
  static const double rowHeight = 56;

  /// Vertical distance between rows: the row plus a gap.
  ///
  /// Fixed, as the reference implementation keeps it. Spreading a short fan
  /// out to fill the screen was the wrong reading of the reference: macOS
  /// keeps every stack on the same pitch and lets the count decide how tall
  /// the fan is, so a folder of three items opens as a short fan rather than
  /// a sparse column.
  static const double rowStep = 68;

  /// Sideways drift coefficient; `x = shift * i^power`.
  ///
  /// The reference computes `FAN_ICON_SIZE * 0.03 * i^2` on a 56 px icon,
  /// capped at `FAN_ICON_SIZE * 4.2`; this is the same curve at our scale.
  static const double shift = 1.68;

  /// The drift's exponent. Two, so the column leaves the dock icon almost
  /// straight and bends harder with every row it climbs.
  static const double shiftPower = 2.0;

  /// Drift ceiling, matching the reference's cap on a tall fan.
  static const double shiftMax = 235;

  /// Tilt per row, in degrees.
  ///
  /// A macOS stack turns its name plates with the arc, the end nearest the
  /// preview staying put and the far end lifting. Measured on the reference's
  /// top plate: about 50 px of lift over 250 px, so roughly 11 degrees at the
  /// eighth row. The cards themselves never turn.
  static const double tiltDegrees = 1.5;

  /// Distance between the dock capsule and the first row.
  static const double gap = 10;

  /// Horizontal padding inside a row.
  static const double padX = 10;

  /// Row corner radius.
  static const double radius = 10;

  /// The preview card beside a label. A macOS stack draws it as its own
  /// rounded card, not as an icon inside the label pill.
  static const double thumbSize = 56;

  /// Height of the name pill: a capsule hugging one line of caption text, so
  /// it reads as a label beside the preview rather than a panel as tall as it.
  static const double pillHeight = 30;

  /// Gap between the label pill and the preview card.
  static const double thumbGap = 4;

  /// The round open-in-Files mark on the fan's top row, drawn where a file's
  /// preview would be.
  static const double openSize = 44;

  /// The most rows a fan draws, the open-in-Files row included. Every row
  /// turns one step further, so past this the top names lean too far to read
  /// however tall the screen is; a longer folder opens as a grid instead.
  static const int maxRows = 12;

  /// Label width past which the text ellipsizes by default.
  static const double labelMaxWidth = 260;

  /// Dynamic label ceiling based on available horizontal room beside the fan.
  /// No artificial 440 px cap: long filenames expand up to the screen's free
  /// width and only ellipsize (in the middle) when even that runs out.
  static double maxLabelFor({required double availableWidth}) =>
      math.max(160.0, availableWidth);

  /// Middle-truncates [text] so both the start and file extension stay
  /// visible when [text] exceeds [maxChars].
  static String middleEllipsize(String text, int maxChars) {
    final runes = text.runes.toList(growable: false);
    if (maxChars < 5 || runes.length <= maxChars) return text;
    final tail = math.min(12, math.max(3, (maxChars - 1) ~/ 3));
    final head = maxChars - 1 - tail;
    return '${String.fromCharCodes(runes.take(head))}…${String.fromCharCodes(runes.skip(runes.length - tail))}';
  }

  /// The pill around a label measured [textWidth] wide.
  static double pillWidth(double textWidth) => padX * 2 + textWidth;

  /// A row's full width: the label pill, the gap and the preview card.
  static double rowWidth(double textWidth) =>
      pillWidth(textWidth) + thumbGap + thumbSize;

  /// How far a row grows under the pointer.
  static const double hoverScale = 1.06;

  /// Rows that fit on a screen this tall, between [bottom] and [top].
  ///
  /// With [widths] the fit is exact: a row turns about the end nearest its
  /// preview, so its far end lifts by the full width times the sine while the
  /// box itself shortens a little by the cosine.
  static int fitRows({
    required double bottom,
    required double top,
    List<double> widths = const [],
    double tilt = tiltDegrees,
    double scale = 1,
  }) {
    final room = bottom - top - gap;
    if (room <= 0) return 1;
    final plain = math.min(
      maxRows,
      math.max(1, (room / (rowStep * scale)).floor()),
    );
    if (widths.isEmpty || tilt <= 0) return plain;
    final half = rowHeight / 2 * scale;
    var fits = 0;
    for (var i = 0; i < widths.length && i < plain; i++) {
      final angle = tilt * i * math.pi / 180;
      final lift =
          (widths[i] * math.sin(angle) + half * (math.cos(angle) - 1)) *
          hoverScale;
      if (rowStep * scale * (i + 1) + lift > room) break;
      fits = i + 1;
    }
    return math.max(1, fits);
  }

  /// Whether a folder of [files] entries opens as a fan: every file gets a row
  /// and the open-in-Files row still fits above them. When it does not, the
  /// automatic view falls back to the grid, which shows everything.
  ///
  /// [widths] are the rows' widths in slot order, the open row last; without
  /// them only the pitch is counted.
  static bool fits({
    required int files,
    required double bottom,
    required double top,
    List<double> widths = const [],
    double scale = 1,
  }) =>
      files + 1 <= maxRows &&
      fitRows(bottom: bottom, top: top, widths: widths, scale: scale) >=
          files + 1;

  /// The row a key press moves the selection to, or -1 when there is none.
  ///
  /// [current] is -1 before any key. [towardDock] is the arrow that points at
  /// the dock; slot 0 is the row nearest it. The first press lands on the row
  /// nearest the dock for the arrow pointing away, and on the far row for the
  /// arrow pointing at it, so either key starts from the end it points from.
  static int step({
    required int current,
    required int count,
    required bool towardDock,
  }) {
    if (count <= 0) return -1;
    if (current < 0 || current >= count) return towardDock ? count - 1 : 0;
    return (current + (towardDock ? -1 : 1)).clamp(0, count - 1);
  }

  /// The rows for a settled fan, in slot order (0 nearest the dock).
  ///
  /// [widths] is each row's width once its label is measured. [anchorX] is the
  /// dock icon's centre and [bottom] the y the first row sits above. The pitch
  /// is fixed, so the count decides how tall the fan opens, as on macOS.
  static List<DockFanRow> layout({
    required List<double> widths,
    required double anchorX,
    required double bottom,
    double? top,
    bool downward = false,
    double scale = 1,
    DockFanLean lean = DockFanLean.right,
    double tilt = tiltDegrees,
  }) {
    final sign = lean == DockFanLean.right ? 1.0 : -1.0;
    final rows = <DockFanRow>[];
    final step = rowStep * scale;
    final height = rowHeight * scale;
    final half = thumbSize * scale / 2;
    final originTop = top ?? bottom;
    for (var i = 0; i < widths.length; i++) {
      final rowWidth = widths[i];
      final drift =
          math.min(shiftMax, shift * math.pow(i, shiftPower)) * scale * sign;
      final centreY = downward
          ? originTop + step * i + height / 2
          : bottom - step * (i + 1) + height / 2;
      // The preview card is centred on the anchor plus the drift, so the
      // column starts straight above (or below for a top dock) the dock icon
      // and traces the arc from there, the labels ragging out to the far side.
      final column = anchorX + drift;
      final edge = column + half * sign;
      final leading = sign < 0;
      rows.add(
        DockFanRow(
          index: i,
          left: leading ? edge : edge - rowWidth,
          top: centreY - height / 2,
          width: rowWidth,
          height: height,
          // Mirror tilt sign when fanning downward from a top dock.
          angle: tilt * i * sign * (downward ? -1 : 1) * math.pi / 180,
          iconX: column,
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
    final half = thumbSize * scale / 2;
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
          // The card sits on the edge nearest the dock, so the labels always
          // read away from it.
          iconX: toRight ? edgeX + half : edgeX - half,
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
