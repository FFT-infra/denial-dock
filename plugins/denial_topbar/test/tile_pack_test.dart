import 'dart:io';

import 'package:denial_topbar/src/bar_settings.dart';
import 'package:denial_topbar/src/panels/tile_pack.dart';

void main() {
  const one = TileSize(1, 1);
  const wide = TileSize(2, 1);
  const tall = TileSize(2, 2);

  var packed = packTiles(const <TileSize>[], 4);
  _expect(packed.rows == 0 && packed.cells.isEmpty, 'empty grid');

  packed = packTiles(const <TileSize>[wide, tall, one, one, one], 4);
  _expect(_at(packed.cells[0], 0, 0), 'first tile at the origin');
  _expect(_at(packed.cells[1], 2, 0), 'tall tile beside it');
  _expect(_at(packed.cells[2], 0, 1), 'a small tile fills the hole below');
  _expect(_at(packed.cells[3], 1, 1), 'and the next one after it');
  _expect(_at(packed.cells[4], 0, 2), 'a full row wraps');
  _expect(packed.rows == 3, 'rows counted');

  packed = packTiles(const <TileSize>[TileSize(4, 1), one], 2);
  _expect(_at(packed.cells[0], 0, 0), 'an oversize tile is clamped');
  _expect(_at(packed.cells[1], 0, 1), 'and takes the whole row');

  packed = packTiles(const <TileSize>[one, wide, one], 2);
  _expect(_at(packed.cells[1], 0, 1), 'a wide tile skips a half row');
  _expect(_at(packed.cells[2], 1, 0), 'a later tile goes back to fill it');

  const defaults = BarSettings.defaults;
  _expect(
    defaults.statusOrder.toSet().length == defaults.statusOrder.length,
    'status order has no repeats',
  );
  final loaded = BarSettings.fromJson(<String, dynamic>{
    'controls': <dynamic>['wifi', 7, 'wifi', 'sound'],
    'widgets': 'nonsense',
    'statusOrder': <dynamic>['battery', 'wifi'],
    'workspaceStyle': 'numbers',
  });
  _expect(
    loaded.controls.join(',') == 'wifi,sound',
    'controls drop repeats and non-strings: ${loaded.controls}',
  );
  _expect(
    loaded.widgets.join(',') == defaults.widgets.join(','),
    'a malformed widget list falls back',
  );
  _expect(loaded.statusOrder.first == 'battery', 'status order read');
  _expect(
    loaded.workspaceStyle == BarWorkspaceStyle.numbers,
    'workspace style read',
  );
  final json = <String, dynamic>{};
  loaded.copyWith(widgets: const <String>['clock']).writeJson(json);
  final again = BarSettings.fromJson(json);
  _expect(again.widgets.join(',') == 'clock', 'widgets round-trip');
  _expect(again.controls.join(',') == 'wifi,sound', 'controls round-trip');
  _expect(
    again.workspaceStyle == BarWorkspaceStyle.numbers,
    'workspace style round-trip',
  );

  final sizes = parseTileSizes(<String>[
    'cc.wifi:1x1',
    'bad',
    'x:9x1',
    'a:b:2x1',
  ]);
  _expect(sizes.length == 2, 'malformed sizes are dropped');
  _expect(sizes['cc.wifi']!.w == 1 && sizes['a:b']!.w == 2, 'sizes parse');
  _expect(
    writeTileSizes(sizes).join(',') == 'cc.wifi:1x1,a:b:2x1',
    'and write back',
  );

  stdout.writeln('All tile and layout tests passed.');
}

bool _at(({int col, int row}) cell, int col, int row) =>
    cell.col == col && cell.row == row;

void _expect(bool condition, String message) {
  if (!condition) {
    stderr.writeln('FAILED: $message');
    exit(1);
  }
}
