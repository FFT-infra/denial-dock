import 'dart:io';

import 'package:denial_topbar/src/workspace_overview_layout.dart';

/// Checks the overview's geometry: windows inside a card, the card grid,
/// keyboard moves and the indicator's droplet.
void main() {
  const screen = OvRect(100, 50, 1920, 1080);

  // A window keeps its place and share of the screen.
  final half = mapWindowToCard(
    window: const OvRect(100 + 960, 50, 960, 1080),
    screen: screen,
    cardWidth: 192,
    cardHeight: 108,
  );
  _near(half.left, 96, 'right half starts mid-card');
  _near(half.top, 0, 'right half starts at the top');
  _near(half.width, 96, 'right half is half the card wide');
  _near(half.height, 108, 'right half is the card tall');

  // A tiny window stays visible, an off-screen one stays inside.
  final tiny = mapWindowToCard(
    window: const OvRect(100, 50, 10, 10),
    screen: screen,
    cardWidth: 192,
    cardHeight: 108,
  );
  _expect(tiny.width == 22 && tiny.height == 16, 'tiny window has a floor');
  final off = mapWindowToCard(
    window: const OvRect(3000, 2000, 800, 600),
    screen: screen,
    cardWidth: 192,
    cardHeight: 108,
  );
  _near(off.right, 192, 'off-screen window is held at the right side');
  _near(off.bottom, 108, 'off-screen window is held at the bottom');
  final huge = mapWindowToCard(
    window: const OvRect(0, 0, 9000, 9000),
    screen: screen,
    cardWidth: 192,
    cardHeight: 108,
  );
  _expect(huge.width == 192 && huge.height == 108, 'huge window fills');
  final none = mapWindowToCard(
    window: const OvRect(0, 0, 10, 10),
    screen: const OvRect(0, 0, 0, 0),
    cardWidth: 192,
    cardHeight: 108,
  );
  _expect(none.width == 22, 'an unknown screen still gives a block');

  // A card point maps back to the screen.
  final point = cardPointToScreen(
    x: 96,
    y: 54,
    screen: screen,
    cardWidth: 192,
    cardHeight: 108,
  );
  _expect(point.x == 1060 && point.y == 590, 'card centre is screen centre');
  final outside = cardPointToScreen(
    x: -20,
    y: 500,
    screen: screen,
    cardWidth: 192,
    cardHeight: 108,
  );
  _expect(outside.x == 100 && outside.y == 1130, 'points are held on screen');

  // Grid: one row when it fits, with cards no wider than the cap.
  final wide = overviewGrid(
    count: 5,
    aspect: 16 / 9,
    maxWidth: 1900,
    maxHeight: 900,
  );
  _expect(wide.columns == 5 && wide.rows == 1, 'five cards fit one row');
  _near(wide.cardWidth, 300, 'cards stop at the cap');
  _near(wide.cardHeight, 300 * 9 / 16, 'cards keep the screen ratio');
  _expect(wide.width <= 1900, 'the row fits the room');
  _near(wide.cardRect(1).left - wide.cardRect(0).right, 12, 'cards are gapped');

  // Grid: wraps when one row would make cards too small.
  final narrow = overviewGrid(
    count: 7,
    aspect: 16 / 9,
    maxWidth: 900,
    maxHeight: 2000,
  );
  _expect(narrow.columns == 4 && narrow.rows == 2, 'seven cards wrap to 4+3');
  _expect(narrow.cardWidth >= 190, 'wrapped cards keep the floor');
  _expect(narrow.width <= 900, 'wrapped grid fits');
  // The short last row is centred.
  _near(
    narrow.cardRect(4).left - narrow.pad,
    narrow.width - narrow.pad - narrow.cardRect(6).right,
    'last row is centred',
  );
  _expect(narrow.cardRect(4).top > narrow.cardRect(0).bottom, 'rows stack');

  // Grid: a low room shrinks the cards.
  final low = overviewGrid(
    count: 3,
    aspect: 16 / 9,
    maxWidth: 1900,
    maxHeight: 180,
    footer: 40,
  );
  _expect(low.height <= 180.001, 'grid fits a low room');
  _near(low.cardWidth / low.cardHeight, 16 / 9, 'shrunk cards keep ratio');

  // Grid: a tall screen on a vertical bar.
  final tall = overviewGrid(
    count: 4,
    aspect: 9 / 16,
    maxWidth: 500,
    maxHeight: 700,
  );
  _expect(tall.width <= 500 && tall.height <= 700.001, 'portrait grid fits');

  // Hit test.
  final r2 = wide.cardRect(2);
  _expect(wide.cardAt(r2.centerX, r2.centerY) == 2, 'card under a point');
  _expect(wide.cardAt(r2.left - 4, r2.centerY) == 1 ||
      wide.cardAt(r2.left - 4, r2.centerY) == 2, 'slack reaches the gap');
  _expect(wide.cardAt(-50, -50) == null, 'no card outside');

  // Keyboard.
  int move(int i, OverviewMove m) =>
      overviewMoveSelection(index: i, count: 7, columns: 4, move: m);
  _expect(move(0, OverviewMove.left) == 0, 'left stops at the first');
  _expect(move(6, OverviewMove.right) == 6, 'right stops at the last');
  _expect(move(3, OverviewMove.right) == 4, 'right runs on to the next row');
  _expect(move(1, OverviewMove.down) == 5, 'down keeps the column');
  _expect(move(3, OverviewMove.down) == 6, 'down into a short row');
  _expect(move(5, OverviewMove.down) == 5, 'down stops on the last row');
  _expect(move(5, OverviewMove.up) == 1, 'up keeps the column');
  _expect(move(2, OverviewMove.up) == 2, 'up stops on the first row');
  _expect(
    overviewMoveSelection(
          index: 9,
          count: 0,
          columns: 4,
          move: OverviewMove.right,
        ) ==
        0,
    'an empty grid selects nothing else',
  );
  _expect(overviewDigitTarget(3, 4) == 3, 'digit goes to its workspace');
  _expect(overviewDigitTarget(5, 4) == null, 'digit past the end is ignored');
  _expect(overviewDigitTarget(0, 4) == null, 'zero is ignored');

  // Live pictures are capped per card.
  _expect(!overviewLiveSlot(0, 8, 6) && !overviewLiveSlot(1, 8, 6), 'capped');
  _expect(overviewLiveSlot(2, 8, 6) && overviewLiveSlot(7, 8, 6), 'last win');
  _expect(overviewLiveSlot(0, 3, 6), 'few windows are all live');
  _expect(!overviewLiveSlot(0, 3, 0), 'a zero cap turns it off');

  // Indicator: the extents the bar already reserves.
  const dots = IndicatorMetrics.dots();
  const numbers = IndicatorMetrics.numbers();
  _near(dots.extent(4), 3 * 13 + 18 + 7, 'dots extent');
  _near(numbers.extent(4), 80, 'numbers extent');
  _expect(dots.extent(0) == 0, 'no workspaces, no strip');

  // Indicator: at rest the droplet is the active mark.
  final rest = dots.droplet(3, 3);
  _near(rest.length, 18, 'droplet rests at the long mark');
  _near(
    rest.start + rest.length / 2,
    dots.centre(3, 3, 4),
    'droplet rests on its workspace',
  );
  // Travelling, it stretches between its ends, either way round.
  final stretched = dots.droplet(3, 2.4);
  _near(stretched.length, 18 + 0.6 * 13, 'droplet stretches');
  final back = dots.droplet(2.4, 3);
  _near(back.start, stretched.start, 'stretch is symmetric');
  // Marks do not shift the strip's length while the droplet travels.
  final end1 = dots.centre(4, 1, 4);
  final endMid = dots.centre(4, 2.5, 4);
  _near(end1, endMid, 'the last mark stays put');
  _expect(dots.centre(1, 3, 4) < dots.centre(2, 3, 4), 'marks are ordered');
  // Numbers sit on an even pitch.
  _near(numbers.centre(2, 1, 4) - numbers.centre(1, 1, 4), 20, 'even pitch');
  _near(numbers.droplet(2, 2).start, 21.5, 'plate sits under its number');

  // Hit test along the strip.
  _expect(dots.workspaceAt(0, 4, 2) == 1, 'start of the strip');
  _expect(dots.workspaceAt(dots.centre(2, 2, 4), 4, 2) == 2, 'active mark');
  _expect(dots.workspaceAt(999, 4, 2) == 4, 'end of the strip');

  stdout.writeln('All workspace overview layout tests passed.');
}

void _near(double a, double b, String label) =>
    _expect((a - b).abs() < 0.001, '$label ($a vs $b)');

void _expect(bool condition, String label) {
  if (!condition) {
    stderr.writeln('FAILED: $label');
    exit(1);
  }
}
