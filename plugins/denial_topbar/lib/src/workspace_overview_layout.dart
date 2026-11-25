/// The arithmetic behind the workspace indicator and its overview: where a
/// window lands inside a card, how the cards are laid out, how the keyboard
/// moves between them, and where the indicator's droplet sits.
///
/// No Flutter import, so it runs as an ordinary Dart test.
library;

import 'dart:math' as math;

/// A rectangle by its leading corner and size.
class OvRect {
  const OvRect(this.left, this.top, this.width, this.height);

  final double left;
  final double top;
  final double width;
  final double height;

  double get right => left + width;
  double get bottom => top + height;
  double get centerX => left + width / 2;
  double get centerY => top + height / 2;

  bool contains(double x, double y) =>
      x >= left && x < right && y >= top && y < bottom;

  @override
  String toString() => 'OvRect($left, $top, $width, $height)';
}

/// Where [window] (scene coordinates) goes inside a card of [cardWidth] by
/// [cardHeight] that stands for [screen]. The window keeps its place and
/// share of the screen; one that is too small to see keeps [minWidth] by
/// [minHeight], and one that hangs off the screen is held inside the card.
OvRect mapWindowToCard({
  required OvRect window,
  required OvRect screen,
  required double cardWidth,
  required double cardHeight,
  double minWidth = 22,
  double minHeight = 16,
}) {
  if (screen.width <= 0 || screen.height <= 0) {
    return OvRect(0, 0, math.min(minWidth, cardWidth), math.min(minHeight, cardHeight));
  }
  final sx = cardWidth / screen.width;
  final sy = cardHeight / screen.height;
  final w = (window.width * sx).clamp(math.min(minWidth, cardWidth), cardWidth);
  final h = (window.height * sy).clamp(
    math.min(minHeight, cardHeight),
    cardHeight,
  );
  final x = ((window.left - screen.left) * sx).clamp(0.0, cardWidth - w);
  final y = ((window.top - screen.top) * sy).clamp(0.0, cardHeight - h);
  return OvRect(x.toDouble(), y.toDouble(), w.toDouble(), h.toDouble());
}

/// The point of the screen under ([x], [y]) of a card, the inverse of
/// [mapWindowToCard]'s scaling, rounded to whole scene pixels.
({double x, double y}) cardPointToScreen({
  required double x,
  required double y,
  required OvRect screen,
  required double cardWidth,
  required double cardHeight,
}) {
  if (cardWidth <= 0 || cardHeight <= 0) return (x: screen.left, y: screen.top);
  final px = (x / cardWidth).clamp(0.0, 1.0) * screen.width + screen.left;
  final py = (y / cardHeight).clamp(0.0, 1.0) * screen.height + screen.top;
  return (x: px.roundToDouble(), y: py.roundToDouble());
}

/// The cards of an overview in rows, and the room the whole thing takes.
class OverviewGrid {
  const OverviewGrid({
    required this.count,
    required this.columns,
    required this.cardWidth,
    required this.cardHeight,
    required this.gap,
    required this.pad,
    required this.labelHeight,
    required this.footer,
  });

  final int count;
  final int columns;
  final double cardWidth;
  final double cardHeight;
  final double gap;
  final double pad;

  /// The caption under each card.
  final double labelHeight;

  /// Room under the last row, for the minimised windows.
  final double footer;

  int get rows => count <= 0 ? 0 : (count + columns - 1) ~/ columns;
  double get cellHeight => cardHeight + labelHeight;

  double get width => pad * 2 + columns * cardWidth + (columns - 1) * gap;
  double get height =>
      pad * 2 + rows * cellHeight + math.max(0, rows - 1) * gap + footer;

  /// The card at [index], without its caption. A short last row is centred.
  OvRect cardRect(int index) {
    final row = index ~/ columns;
    final col = index % columns;
    final inRow = row == rows - 1 ? count - row * columns : columns;
    final shift = (columns - inRow) * (cardWidth + gap) / 2;
    return OvRect(
      pad + shift + col * (cardWidth + gap),
      pad + row * (cellHeight + gap),
      cardWidth,
      cardHeight,
    );
  }

  /// The card under ([x], [y]), a little beyond its sides included, so a
  /// drop between two cards still lands.
  int? cardAt(double x, double y, {double slack = 6}) {
    for (var i = 0; i < count; i++) {
      final r = cardRect(i);
      if (x >= r.left - slack &&
          x < r.right + slack &&
          y >= r.top - slack &&
          y < r.bottom + slack) {
        return i;
      }
    }
    return null;
  }
}

/// Lays [count] cards of the screen's [aspect] (width over height) into at
/// most [maxWidth] by [maxHeight]. One row is preferred; more rows come only
/// when a card would fall under [minCard] wide, and a grid that is still too
/// tall shrinks its cards rather than being cut off.
OverviewGrid overviewGrid({
  required int count,
  required double aspect,
  required double maxWidth,
  required double maxHeight,
  double gap = 12,
  double pad = 14,
  double labelHeight = 24,
  double footer = 0,
  double minCard = 190,
  double maxCard = 300,
}) {
  final n = math.max(1, count);
  final ratio = aspect > 0 ? aspect : 16 / 9;
  double widthFor(int columns) =>
      (maxWidth - pad * 2 - (columns - 1) * gap) / columns;

  var columns = n;
  for (var rows = 1; rows <= n; rows++) {
    columns = (n + rows - 1) ~/ rows;
    if (widthFor(columns) >= minCard || columns == 1) break;
  }
  final rows = (n + columns - 1) ~/ columns;
  var cardWidth = widthFor(columns).clamp(40.0, maxCard).toDouble();
  final room =
      (maxHeight - pad * 2 - footer - (rows - 1) * gap) / rows - labelHeight;
  if (cardWidth / ratio > room) cardWidth = math.max(40.0, room * ratio);
  return OverviewGrid(
    count: n,
    columns: columns,
    cardWidth: cardWidth,
    cardHeight: cardWidth / ratio,
    gap: gap,
    pad: pad,
    labelHeight: labelHeight,
    footer: footer,
  );
}

enum OverviewMove { left, right, up, down }

/// The card the keyboard selection lands on from [index]. It stops at the
/// ends of a row and of the grid; moving down into a short last row lands
/// on that row's last card.
int overviewMoveSelection({
  required int index,
  required int count,
  required int columns,
  required OverviewMove move,
}) {
  if (count <= 0) return 0;
  final at = index.clamp(0, count - 1);
  final cols = math.max(1, columns);
  switch (move) {
    case OverviewMove.left:
      return math.max(0, at - 1);
    case OverviewMove.right:
      return math.min(count - 1, at + 1);
    case OverviewMove.up:
      return at - cols >= 0 ? at - cols : at;
    case OverviewMove.down:
      if (at + cols < count) return at + cols;
      // A row below exists but is shorter than this column.
      return at ~/ cols < (count - 1) ~/ cols ? count - 1 : at;
  }
}

/// The workspace a digit key asks for, or null when there is none.
int? overviewDigitTarget(int digit, int workspaces) =>
    digit >= 1 && digit <= workspaces ? digit : null;

/// How many of a card's windows get a live picture; the rest draw the plain
/// stand-in. The last windows of the list win.
bool overviewLiveSlot(int index, int total, int limit) =>
    limit > 0 && index >= total - limit;

/// The sizes of the indicator strip, along the bar.
class IndicatorMetrics {
  const IndicatorMetrics.dots()
    : dot = 6,
      active = 18,
      gap = 7,
      uniform = false;

  const IndicatorMetrics.numbers()
    : dot = 17,
      active = 17,
      gap = 3,
      uniform = true;

  /// A resting mark's length.
  final double dot;

  /// The current workspace's mark at rest.
  final double active;

  /// Between two marks.
  final double gap;

  /// Whether every mark has the same length, as numbers do.
  final bool uniform;

  double get pitch => dot + gap;

  /// The strip's whole length for [count] workspaces.
  double extent(int count) =>
      count <= 0 ? 0 : (count - 1) * pitch + active + gap;

  /// How much of the long mark workspace [index] (1-based) holds while the
  /// droplet is at [at]: 1 under it, 0 a whole step away.
  double weight(int index, double at) =>
      (1 - (index - at).abs()).clamp(0.0, 1.0).toDouble();

  /// The centre of workspace [index]'s mark while the droplet is at [at].
  /// Marks before the droplet stay put, those after it give way.
  double centre(int index, double at, int count) {
    final p = at.clamp(1.0, math.max(1, count).toDouble()).toDouble();
    var x = gap / 2;
    for (var i = 1; i < index; i++) {
      x += dot + (active - dot) * weight(i, p) + gap;
    }
    return x + (dot + (active - dot) * weight(index, p)) / 2;
  }

  /// The droplet between its two ends: [head] runs ahead, [tail] follows,
  /// both in workspace units. At rest on a workspace it is that workspace's
  /// long mark; in between it stretches by the distance between the ends.
  ({double start, double length}) droplet(double head, double tail) {
    final lo = math.min(head, tail);
    final hi = math.max(head, tail);
    return (
      start: gap / 2 + (lo - 1) * pitch,
      length: active + (hi - lo) * pitch,
    );
  }

  /// The workspace whose mark is nearest [position], with the droplet
  /// resting on [active]; 1-based.
  int workspaceAt(double position, int count, int active) {
    var best = 1;
    var distance = double.infinity;
    for (var i = 1; i <= count; i++) {
      final d = (centre(i, active.toDouble(), count) - position).abs();
      if (d < distance) {
        distance = d;
        best = i;
      }
    }
    return best;
  }
}
