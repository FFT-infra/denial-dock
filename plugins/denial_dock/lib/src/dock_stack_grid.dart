import 'dart:math' as math;

/// One cell of a grid stack.
class DockGridCell {
  const DockGridCell({
    required this.index,
    required this.left,
    required this.top,
    required this.size,
  });

  final int index;
  final double left;
  final double top;
  final double size;

  double get right => left + size;
  double get bottom => top + size;
  double get centerX => left + size / 2;
  double get centerY => top + size / 2;
}

/// The grid a stack opens into once its folder outgrows a fan.
///
/// Finder switches from Fan to Grid on the same rule — a fan that would run off
/// the screen becomes a grid — so the two views are one feature, not two.
abstract final class DockStackGrid {
  /// Cell edge: a 48 px icon with room to breathe.
  static const double cell = 76;

  /// Padding inside the panel.
  static const double pad = 12;

  /// Gap between the panel and the dock capsule.
  static const double gap = 10;

  /// Columns are capped so a wide screen does not open a single endless row.
  static const int maxColumns = 8;
  static const int minColumns = 2;

  /// Columns that fit in [width] at [cell] size.
  static int columnsFor(double width) {
    if (width <= 0) return minColumns;
    final fit = ((width - pad * 2) / cell).floor();
    return fit.clamp(minColumns, maxColumns);
  }

  /// The grid for [count] items in a panel [width] wide and [height] tall.
  ///
  /// The panel is sized to its contents up to the screen, then scrolls: a
  /// folder of two files opens a two-cell panel rather than a fixed sheet with
  /// empty space beside them.
  static ({
    List<DockGridCell> cells,
    int columns,
    int rows,
    double width,
    double height,
    double contentHeight,
    bool scrolls,
  })
  layout({
    required int count,
    required double width,
    required double maxHeight,
  }) {
    final columns = math.max(1, math.min(count, columnsFor(width)));
    final rows = math.max(1, (count / columns).ceil());
    final cells = <DockGridCell>[
      for (var i = 0; i < count; i++)
        DockGridCell(
          index: i,
          left: pad + (i % columns) * cell,
          top: pad + (i ~/ columns) * cell,
          size: cell,
        ),
    ];
    final contentHeight = rows * cell + pad * 2;
    final height = math.min(contentHeight, math.max(cell + pad * 2, maxHeight));
    return (
      cells: cells,
      columns: columns,
      rows: rows,
      width: columns * cell + pad * 2,
      height: height,
      contentHeight: contentHeight,
      scrolls: contentHeight > height + 0.5,
    );
  }

  /// The cell under [point], given the scroll offset applied to the content.
  static int? hitTest(
    List<DockGridCell> cells,
    double x,
    double y, {
    double scroll = 0,
  }) {
    for (final cell in cells) {
      if (x >= cell.left &&
          x <= cell.right &&
          y >= cell.top - scroll &&
          y <= cell.bottom - scroll) {
        return cell.index;
      }
    }
    return null;
  }
}
