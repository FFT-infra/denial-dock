import 'dart:math' as math;

class TileSize {
  const TileSize(this.w, this.h);

  final int w;
  final int h;
}

/// Places tiles on a grid, each in the first free spot in reading order.
/// Returns the column and row of every tile, and the number of rows used.
({List<({int col, int row})> cells, int rows}) packTiles(
  List<TileSize> tiles,
  int columns,
) {
  final taken = <List<bool>>[];
  final cells = <({int col, int row})>[];
  bool free(int col, int row, int w, int h) {
    for (var y = row; y < row + h; y++) {
      for (var x = col; x < col + w; x++) {
        if (y < taken.length && taken[y][x]) return false;
      }
    }
    return true;
  }

  for (final tile in tiles) {
    final w = math.min(tile.w, columns);
    var placed = false;
    for (var row = 0; !placed; row++) {
      for (var col = 0; col + w <= columns; col++) {
        if (!free(col, row, w, tile.h)) continue;
        while (taken.length < row + tile.h) {
          taken.add(List<bool>.filled(columns, false));
        }
        for (var y = row; y < row + tile.h; y++) {
          for (var x = col; x < col + w; x++) {
            taken[y][x] = true;
          }
        }
        cells.add((col: col, row: row));
        placed = true;
        break;
      }
    }
  }
  return (cells: cells, rows: taken.length);
}

/// Sizes the user chose, stored as `id:WxH`. Malformed entries are dropped.
Map<String, TileSize> parseTileSizes(List<String> entries) {
  final sizes = <String, TileSize>{};
  for (final entry in entries) {
    final match = RegExp(r'^(.+):([1-4])x([1-4])$').firstMatch(entry);
    if (match == null) continue;
    sizes[match.group(1)!] = TileSize(
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
  }
  return sizes;
}

List<String> writeTileSizes(Map<String, TileSize> sizes) => <String>[
  for (final entry in sizes.entries)
    '${entry.key}:${entry.value.w}x${entry.value.h}',
];
