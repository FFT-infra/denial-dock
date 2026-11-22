import 'dart:io';

import 'package:denial_topbar/src/cc_layout.dart';

/// Checks the grid against the values shell27 `MacBar.qml` produces for its
/// default Control Centre: four columns of 66 pt cells, 6 pt between columns,
/// 12 between rows and 16 around the two slider rows.
void main() {
  const controls = <CcControl>[
    CcControl(id: 'wifi', columns: 2),
    CcControl(id: 'nowplaying', columns: 2, rows: 2),
    CcControl(id: 'bluetooth', columns: 2),
    CcControl(id: 'focus', columns: 2),
    CcControl(id: 'darkmode'),
    CcControl(id: 'notifications'),
    CcControl(id: 'island'),
    CcControl(id: 'settings'),
    CcControl(id: 'display', columns: 4),
    CcControl(id: 'sound', columns: 4),
  ];
  const sliders = <String>{'display', 'sound'};

  final plan = ccLayout(
    controls,
    cellHeight: 66,
    gap: 6,
    rowGap: 12,
    sliderGap: 16,
    sliderIds: sliders,
  );

  CcSlot slot(String id) => plan.items.firstWhere((item) => item.id == id);

  // Wi-Fi takes the first two cells of row 0; Now Playing is 2×2 to its right.
  _expect(slot('wifi').column == 0 && slot('wifi').row == 0, 'wifi at 0,0');
  _expect(
    slot('nowplaying').column == 2 && slot('nowplaying').row == 0,
    'now playing at 2,0',
  );
  _expect(
    slot('nowplaying').height == 66 * 2 + 12,
    'a 2-row tile spans the row gap',
  );

  // Bluetooth fills row 1 under Wi-Fi; Now Playing's second row blocks the two
  // cells to its right, so row 1 is full and Focus starts row 2.
  _expect(
    slot('bluetooth').row == 1 && slot('bluetooth').column == 0,
    'bluetooth at 0,1',
  );
  _expect(slot('focus').row == 2 && slot('focus').column == 0, 'focus at 0,2');
  _expect(
    slot('darkmode').row == 2 && slot('darkmode').column == 2,
    'one-cell switches pack to the right of a 2-cell tile',
  );
  _expect(
    slot('island').row == 3 && slot('island').column == 0,
    'the next row starts once row 2 is full',
  );

  // Display and Sound are full-width rows separated from the grid by 16 pt.
  final lastTileBottom = slot('island').y + slot('island').height;
  _expect(
    slot('display').y - lastTileBottom == 16,
    'the slider row keeps ccSliderGap',
  );
  _expect(
    slot('sound').y - (slot('display').y + slot('display').height) == 16,
    'the second slider keeps ccSliderGap too',
  );
  _expect(slot('display').columns == 4, 'sliders span all four columns');
  _expect(
    plan.total == slot('sound').y + slot('sound').height,
    'total height ends at the last slider',
  );

  // Pixel geometry: four 66 pt cells with 6 pt gaps is the 300 pt panel minus
  // its 12 pt margins.
  const gridWidth = 300.0 - 12 * 2;
  const cellWidth = (gridWidth - 3 * 6) / 4;
  _expect(
    (slot('wifi').width(cellWidth, 6) - (cellWidth * 2 + 6)).abs() < 1e-9,
    'a 2-cell tile is two cells plus one gap',
  );
  _expect(
    (slot('display').width(cellWidth, 6) - gridWidth).abs() < 1e-9,
    'a 4-cell tile is the full grid width',
  );

  // Duplicates are ignored, exactly like the reference's `seen` guard.
  final duplicate = ccLayout(
    <CcControl>[
      const CcControl(id: 'wifi', columns: 2),
      const CcControl(id: 'wifi', columns: 2),
    ],
  );
  _expect(duplicate.items.length == 1, 'a repeated control is packed once');

  // An empty list is an empty grid, not a crash.
  final empty = ccLayout(const <CcControl>[]);
  _expect(empty.rows == 0 && empty.total == 0, 'no controls means no grid');

  stdout.writeln('All control centre layout tests passed.');
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
