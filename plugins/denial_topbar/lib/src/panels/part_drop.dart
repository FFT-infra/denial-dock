import '../bar_zones.dart';

/// The box of one part chip, in the coordinates the pointer is given in.
typedef PartBox = ({double left, double top, double right, double bottom});

/// Where a part dragged on the layout page lands.
abstract final class PartDrop {
  /// The place among [chips], which wrap like words on a line, that a part
  /// let go at ([x], [y]) takes: the number of chips that come before it.
  static int slot(List<PartBox> chips, double x, double y) {
    var before = 0;
    for (final chip in chips) {
      final above = y >= chip.bottom;
      final sameLine = y >= chip.top && y < chip.bottom;
      if (above || (sameLine && x > (chip.left + chip.right) / 2)) before++;
    }
    return before;
  }

  /// The zone whose row is nearest to [y], given each row's top and bottom.
  static int zone(List<(double, double)> rows, double y) {
    var best = 0;
    var bestGap = double.infinity;
    for (var index = 0; index < rows.length; index++) {
      final (top, bottom) = rows[index];
      final gap = y < top ? top - y : (y > bottom ? y - bottom : 0.0);
      if (gap < bestGap) {
        bestGap = gap;
        best = index;
      }
    }
    return best;
  }

  /// Moves the part at [at] of zone [from] to [slot] of zone [to], where
  /// [slot] counts the chips before it with the part still in its old place.
  /// Returns the zones and where the part is now.
  static (List<List<String>>, int, int) movedIn(
    List<List<String>> zones,
    int from,
    int at,
    int to,
    int slot,
  ) {
    final lists = <List<String>>[
      for (final zone in zones) List<String>.of(zone),
    ];
    if (from < 0 ||
        from >= lists.length ||
        to < 0 ||
        to >= lists.length ||
        at < 0 ||
        at >= lists[from].length) {
      return (lists, from, at);
    }
    final id = lists[from].removeAt(at);
    final place = (from == to && slot > at ? slot - 1 : slot).clamp(
      0,
      lists[to].length,
    );
    lists[to].insert(place, id);
    return (lists, to, place);
  }

  /// [movedIn] for the bar's three zones, where the island stays in the
  /// centre.
  static (BarZones, int, int) moved(
    BarZones zones,
    int from,
    int at,
    int to,
    int slot,
  ) {
    final source = zones.zone(from);
    if (at < 0 || at >= source.length || to < 0 || to >= BarZones.count) {
      return (zones, from, at);
    }
    if (source[at] == BarPart.island && to != 1) return (zones, from, at);
    final (lists, zone, place) = movedIn(
      <List<String>>[zones.start, zones.center, zones.end],
      from,
      at,
      to,
      slot,
    );
    return (
      BarZones(start: lists[0], center: lists[1], end: lists[2]),
      zone,
      place,
    );
  }
}
