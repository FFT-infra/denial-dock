import 'dart:io';

import 'package:denial_topbar/src/bar_settings.dart';

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}

bool _eq(List<String> a, List<String> b) => a.join(',') == b.join(',');

void main() {
  // A file from before zones draws exactly what it drew: the system menu and
  // the application name at the start, the island in the centre, the status
  // cluster and the clock at the end.
  const defaults = BarSettings.defaults;
  _expect(defaults.explicitZones == null, 'defaults carry no zones');
  _expect(_eq(defaults.zones.start, ['system', 'app']), 'default start');
  _expect(_eq(defaults.zones.center, ['island']), 'default centre');
  _expect(_eq(defaults.zones.end, ['status', 'clock']), 'default end');
  _expect(defaults.showsIsland, 'default island');
  _expect(defaults.workspacesInIsland, 'switcher rides in the island');

  // The older placement settings decide the zones while none are stored.
  BarZones legacy(Map<String, dynamic> json) =>
      BarSettings.fromJson(json).zones;
  _expect(
    _eq(legacy({'workspacePlacement': 'leading'}).start, [
      'system',
      'workspaces',
      'app',
    ]),
    'leading switcher sits between the menu and the name',
  );
  _expect(
    _eq(
      legacy({'workspacePlacement': 'leading', 'showSystemMenu': false}).start,
      ['gap', 'workspaces', 'app'],
    ),
    'leading switcher keeps its gap without the menu',
  );
  _expect(
    _eq(legacy({'workspacePlacement': 'trailing'}).end, [
      'workspaces',
      'status',
      'clock',
    ]),
    'trailing switcher leads the end',
  );
  _expect(
    legacy({'islandEnabled': false}).center.isEmpty,
    'no island, empty centre',
  );
  _expect(
    legacy({'showAppMenu': false, 'showSystemMenu': false}).start.isEmpty,
    'both switches off empty the start',
  );
  _expect(
    !legacy({'workspacePlacement': 'hidden'}).contains('workspaces'),
    'hidden switcher is in no zone',
  );

  // Gaps: the application name is a title with its own padding.
  _expect(!BarPart.gapBetween('system', 'app'), 'menu and name sit flush');
  _expect(BarPart.gapBetween('system', 'workspaces'), 'gap before switcher');
  _expect(!BarPart.gapBetween('workspaces', 'app'), 'no gap before the name');
  _expect(BarPart.gapBetween('status', 'clock'), 'gap before the clock');
  _expect(!BarPart.gapBetween('gap', 'workspaces'), 'a gap adds none');

  // Stored zones are cleaned on the way in.
  final stored = BarSettings.fromJson(<String, dynamic>{
    'start': ['workspaces', 'bogus', 'clock', 'island', 7],
    'center': ['clock', 'island', 'spacer', 'spacer'],
    'end': ['status.wifi', 'status', 'status.wifi', 'status.nope'],
  });
  _expect(stored.explicitZones != null, 'zones are read');
  _expect(
    _eq(stored.zones.start, ['workspaces', 'clock']),
    'unknown ids and a stray island are dropped',
  );
  _expect(
    _eq(stored.zones.center, ['island', 'spacer', 'spacer']),
    'a part appears once, a spacer may repeat',
  );
  _expect(
    _eq(stored.zones.end, ['status.wifi', 'status']),
    'a status item appears once',
  );
  _expect(
    stored.zones.loneStatusItems.single == 'wifi',
    'the cluster leaves out an item placed alone',
  );
  _expect(!stored.workspacesInIsland, 'a placed switcher leaves the island');
  _expect(BarPart.statusItemOf('status.battery') == 'battery', 'item id');
  _expect(BarPart.statusItemOf('status') == null, 'the cluster is no item');

  // One key is enough to mean the bar was arranged.
  _expect(
    BarSettings.fromJson(<String, dynamic>{
          'center': ['clock'],
        }).zones.start.isEmpty,
    'a missing zone is empty once any is stored',
  );

  // Round trip, and no keys for a bar that was never arranged.
  final json = <String, dynamic>{};
  defaults.writeJson(json);
  _expect(!json.containsKey('start'), 'unarranged bar writes no zones');
  final arranged = defaults.copyWith(
    zones: const BarZones(
      start: ['workspaces'],
      center: ['clock'],
      end: ['status'],
    ),
  );
  arranged.writeJson(json);
  final back = BarSettings.fromJson(json);
  _expect(back.zones == arranged.zones, 'zones survive a round trip');
  _expect(!back.showsIsland, 'an island outside the zones is not shown');
  arranged.copyWith(zones: null).writeJson(json);
  _expect(!json.containsKey('center'), 'clearing zones removes the keys');
  _expect(
    BarSettings.fromJson(json).zones == defaults.zones,
    'and the bar follows the older settings again',
  );

  // Editing.
  const zones = BarZones(
    start: ['system', 'app'],
    center: ['island'],
    end: ['status', 'clock'],
  );
  _expect(
    _eq(zones.inserted(0, 'clock').start, ['system', 'app', 'clock']) &&
        _eq(zones.inserted(0, 'clock').end, ['status']),
    'inserting a placed part moves it',
  );
  _expect(
    _eq(zones.inserted(2, 'spacer', 0).inserted(2, 'spacer').end, [
      'spacer',
      'status',
      'clock',
      'spacer',
    ]),
    'a spacer is added, not moved',
  );
  final (shifted, zone, at) = zones.shifted(2, 0, 1);
  _expect(
    _eq(shifted.end, ['clock', 'status']) && zone == 2 && at == 1,
    'shift inside a zone',
  );
  _expect(zones.shifted(2, 1, 1).$1 == zones, 'shift past the end is refused');
  final (carried, toZone, toAt) = zones.carried(2, 0, -1);
  _expect(
    _eq(carried.center, ['island', 'status']) && toZone == 1 && toAt == 1,
    'carry towards the start lands on the near end',
  );
  final (forward, _, forwardAt) = zones.carried(0, 1, 1);
  _expect(
    _eq(forward.center, ['app', 'island']) && forwardAt == 0,
    'carry towards the end lands on the near end',
  );
  _expect(zones.carried(1, 0, 1).$1 == zones, 'the island stays in the centre');
  _expect(zones.carried(2, 0, 1).$1 == zones, 'no zone past the end');

  // The older switches keep working on an arranged bar.
  final custom = defaults.copyWith(zones: zones);
  _expect(
    !custom.withPart('system', false).zones.contains('system') &&
        !custom.withPart('system', false).showSystemMenu,
    'hiding the menu removes it',
  );
  _expect(
    _eq(
      custom.withPart('system', false).withPart('system', true).zones.start,
      ['system', 'app'],
    ),
    'showing it puts it first',
  );
  final islandOff = custom.withPart('island', false);
  _expect(
    !islandOff.showsIsland && islandOff.zones.center.contains('island'),
    'the island switch hides it and keeps its place',
  );
  _expect(
    custom.workspacesShownIn == BarWorkspacePlacement.island,
    'placement reads the island',
  );
  final leading = custom.withWorkspacePlacement(BarWorkspacePlacement.leading);
  _expect(
    _eq(leading.zones.start, ['system', 'workspaces', 'app']) &&
        leading.workspacesShownIn == BarWorkspacePlacement.leading,
    'placement moves the switcher on an arranged bar',
  );
  _expect(
    !leading
        .withWorkspacePlacement(BarWorkspacePlacement.hidden)
        .zones
        .contains('workspaces'),
    'hidden takes it out',
  );
  _expect(
    custom
            .copyWith(zones: zones.inserted(1, 'workspaces'))
            .workspacesShownIn ==
        null,
    'a switcher in the centre has no older name',
  );

  // Segments of a zone.
  _expect(
    BarZones.segments(['a', 'separator', 'separator', 'b', 'c', 'separator'])
            .map((run) => run.join('+'))
            .join('|') ==
        'a|b+c',
    'separators cut a zone into runs',
  );
  stdout.writeln('All bar zone tests passed.');
}
