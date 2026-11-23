import 'package:denial_dock/src/dock_stack_grid.dart';

void main() {
  // Columns follow the width, capped so a wide screen does not open one
  // endless row.
  _expect(
    DockStackGrid.columnsFor(400) == 4,
    '400 px fits 4 columns: ${DockStackGrid.columnsFor(400)}',
  );
  _expect(
    DockStackGrid.columnsFor(4000) == DockStackGrid.maxColumns,
    'a very wide screen caps the columns',
  );
  _expect(
    DockStackGrid.columnsFor(50) == DockStackGrid.minColumns,
    'a narrow screen keeps the minimum',
  );

  // The panel is sized to its contents: two files open a two-cell panel, not a
  // fixed sheet with empty space beside them.
  final two = DockStackGrid.layout(count: 2, width: 400, maxHeight: 800);
  _expect(two.columns == 2, 'two files fill two columns');
  _expect(two.rows == 1, 'two files need one row');
  _expect(
    two.width == 2 * DockStackGrid.cell + DockStackGrid.pad * 2,
    'the panel is two cells wide: ${two.width}',
  );
  _expect(!two.scrolls, 'a short grid does not scroll');

  // A long folder wraps into rows and scrolls instead of clipping.
  final many = DockStackGrid.layout(count: 100, width: 400, maxHeight: 400);
  _expect(many.columns == 4, 'a 400 px panel holds 4 columns');
  _expect(many.rows == 25, 'a hundred files need 25 rows');
  _expect(many.scrolls, 'a tall grid scrolls');
  _expect(
    many.height <= 400,
    'the visible height stays inside the room: ${many.height}',
  );
  _expect(
    many.contentHeight > many.height,
    'the content is taller than the viewport',
  );

  // Cells are laid out row-major and never overlap.
  for (var i = 1; i < many.cells.length; i++) {
    for (var j = 0; j < i; j++) {
      final a = many.cells[i];
      final b = many.cells[j];
      final overlaps =
          a.left < b.right &&
          a.right > b.left &&
          a.top < b.bottom &&
          a.bottom > b.top;
      _expect(!overlaps, 'cell $i does not overlap cell $j');
    }
  }

  // A hit lands on the cell under it.
  final first = many.cells.first;
  _expect(
    DockStackGrid.hitTest(many.cells, first.centerX, first.centerY) == 0,
    'the first cell is hit at its centre',
  );
  _expect(
    DockStackGrid.hitTest(many.cells, -100, -100) == null,
    'a point outside the grid hits nothing',
  );

  // Scrolling moves the content under a fixed pointer, so a point that sits in
  // the panel's padding can become the first cell.
  final gapY = DockStackGrid.pad / 2;
  _expect(
    DockStackGrid.hitTest(many.cells, first.centerX, gapY) == null,
    'the padding is not a cell',
  );
  _expect(
    DockStackGrid.hitTest(
          many.cells,
          first.centerX,
          gapY,
          scroll: DockStackGrid.pad.toDouble(),
        ) ==
        0,
    'scrolling the content down brings the first cell under that point',
  );

  // An empty folder still lays out one empty row without dividing by zero.
  final empty = DockStackGrid.layout(count: 0, width: 400, maxHeight: 800);
  _expect(empty.cells.isEmpty, 'no files means no cells');
  _expect(empty.rows == 1, 'an empty grid still has a row');
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
