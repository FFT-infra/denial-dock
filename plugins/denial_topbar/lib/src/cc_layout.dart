/// The Control Centre grid.
///
/// Transcribes shell27 `MacBar.qml`'s `ccLayout`: a four-column first-fit
/// packer. Every control declares a size in grid cells, and the enabled ones
/// are packed in list order, so reordering the list is what moves a tile.
/// Pixel spacing is independent per axis — `ccGap` between columns,
/// `ccRowGap` between rows — and a row next to a slider keeps `ccSliderGap`.
library;

/// One control's footprint, in grid cells.
class CcControl {
  const CcControl({required this.id, this.columns = 1, this.rows = 1});

  final String id;
  final int columns;
  final int rows;
}

/// Where a control landed, in pixels relative to the grid's top-left corner.
class CcSlot {
  const CcSlot({
    required this.id,
    required this.column,
    required this.row,
    required this.columns,
    required this.rows,
    required this.y,
    required this.height,
  });

  final String id;
  final int column;
  final int row;
  final int columns;
  final int rows;

  /// Top edge. Row tops are uneven because a slider row takes more space.
  final double y;
  final double height;

  double x(double cellWidth, double gap) =>
      column * (cellWidth + gap);

  double width(double cellWidth, double gap) =>
      columns * cellWidth + (columns - 1) * gap;
}

class CcPlan {
  const CcPlan({required this.items, required this.rows, required this.total});

  final List<CcSlot> items;
  final int rows;

  /// Total pixel height of the grid, or 0 when nothing is enabled.
  final double total;
}

/// Packs [controls] into [columns] columns.
///
/// [sliderIds] marks the full-width slider tiles: shell27 gives a row an extra
/// [sliderGap] whenever it or the row above holds one, which is what separates
/// Display and Sound from the tiles above them.
CcPlan ccLayout(
  List<CcControl> controls, {
  int columns = 4,
  double cellHeight = 66,
  double gap = 6,
  double rowGap = 12,
  double sliderGap = 16,
  Set<String> sliderIds = const <String>{},
}) {
  final occupied = <List<bool>>[];
  final placed = <({String id, int column, int row, int columns, int rows})>[];
  final seen = <String>{};

  bool free(int row, int column, int width, int height) {
    for (var y = row; y < row + height; y++) {
      final line = y < occupied.length ? occupied[y] : null;
      if (line == null) continue;
      for (var x = column; x < column + width; x++) {
        if (x < line.length && line[x]) return false;
      }
    }
    return true;
  }

  void mark(int row, int column, int width, int height) {
    for (var y = row; y < row + height; y++) {
      while (occupied.length <= y) {
        occupied.add(<bool>[]);
      }
      for (var x = column; x < column + width; x++) {
        while (occupied[y].length <= x) {
          occupied[y].add(false);
        }
        occupied[y][x] = true;
      }
    }
  }

  var rows = 0;
  for (final control in controls) {
    if (!seen.add(control.id)) continue;
    var done = false;
    for (var row = 0; !done; row++) {
      for (var column = 0; column + control.columns <= columns; column++) {
        if (!free(row, column, control.columns, control.rows)) continue;
        mark(row, column, control.columns, control.rows);
        placed.add((
          id: control.id,
          column: column,
          row: row,
          columns: control.columns,
          rows: control.rows,
        ));
        final bottom = row + control.rows;
        if (bottom > rows) rows = bottom;
        done = true;
        break;
      }
    }
  }

  final sliderRow = <bool>[];
  for (final item in placed) {
    if (!sliderIds.contains(item.id)) continue;
    for (var r = item.row; r < item.row + item.rows; r++) {
      while (sliderRow.length <= r) {
        sliderRow.add(false);
      }
      sliderRow[r] = true;
    }
  }

  final tops = <double>[];
  for (var r = 0; r < rows; r++) {
    if (r == 0) {
      tops.add(0);
      continue;
    }
    final extra =
        (sliderRow.length > r && sliderRow[r]) ||
            (sliderRow.length > r - 1 && sliderRow[r - 1])
        ? sliderGap
        : rowGap;
    tops.add(tops[r - 1] + cellHeight + extra);
  }

  final items = <CcSlot>[
    for (final item in placed)
      CcSlot(
        id: item.id,
        column: item.column,
        row: item.row,
        columns: item.columns,
        rows: item.rows,
        y: tops[item.row],
        height: tops[item.row + item.rows - 1] + cellHeight - tops[item.row],
      ),
  ];

  return CcPlan(
    items: items,
    rows: rows,
    total: rows > 0 ? tops[rows - 1] + cellHeight : 0,
  );
}
