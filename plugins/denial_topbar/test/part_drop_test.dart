import 'dart:io';

import 'package:denial_topbar/src/bar_zones.dart';
import 'package:denial_topbar/src/panels/part_drop.dart';

void _expect(bool ok, String what) {
  if (!ok) throw StateError(what);
}

void main() {
  // Two lines of chips: three above, one below.
  const chips = <PartBox>[
    (left: 0, top: 0, right: 40, bottom: 26),
    (left: 46, top: 0, right: 86, bottom: 26),
    (left: 92, top: 0, right: 132, bottom: 26),
    (left: 0, top: 32, right: 40, bottom: 58),
  ];
  _expect(PartDrop.slot(chips, 5, 10) == 0, 'before the first chip');
  _expect(PartDrop.slot(chips, 30, 10) == 1, 'past the middle of the first');
  _expect(PartDrop.slot(chips, 200, 10) == 3, 'the end of the first line');
  _expect(PartDrop.slot(chips, 5, 40) == 3, 'the start of the second line');
  _expect(PartDrop.slot(chips, 200, 40) == 4, 'after the last chip');
  _expect(PartDrop.slot(chips, 5, 200) == 4, 'below every line');
  _expect(PartDrop.slot(const <PartBox>[], 5, 5) == 0, 'an empty zone');

  const rows = <(double, double)>[(0, 40), (41, 80), (81, 120)];
  _expect(PartDrop.zone(rows, -20) == 0, 'above the rows');
  _expect(PartDrop.zone(rows, 60) == 1, 'inside the middle row');
  _expect(PartDrop.zone(rows, 400) == 2, 'below the rows');

  const zones = BarZones(
    start: <String>['system', 'app'],
    center: <String>['island'],
    end: <String>['status', 'clock'],
  );
  var (next, zone, at) = PartDrop.moved(zones, 0, 0, 0, 2);
  _expect(
    next.start.join('+') == 'app+system' && zone == 0 && at == 1,
    'a part moves later inside its zone',
  );
  (next, zone, at) = PartDrop.moved(zones, 2, 1, 2, 0);
  _expect(
    next.end.join('+') == 'clock+status' && at == 0,
    'a part moves earlier inside its zone',
  );
  (next, zone, at) = PartDrop.moved(zones, 0, 1, 0, 1);
  _expect(next == zones && at == 1, 'a part let go where it was stays');
  (next, zone, at) = PartDrop.moved(zones, 0, 1, 0, 2);
  _expect(next == zones && at == 1, 'the slot after itself is its own place');
  (next, zone, at) = PartDrop.moved(zones, 0, 1, 2, 1);
  _expect(
    next.start.join('+') == 'system' &&
        next.end.join('+') == 'status+app+clock' &&
        zone == 2 &&
        at == 1,
    'a part crosses into another zone',
  );
  (next, zone, at) = PartDrop.moved(zones, 1, 0, 2, 0);
  _expect(next == zones && zone == 1, 'the island stays in the centre');
  (next, zone, at) = PartDrop.moved(zones, 0, 5, 1, 0);
  _expect(next == zones, 'a part that is not there moves nothing');
  (next, zone, at) = PartDrop.moved(zones, 0, 0, 1, 9);
  _expect(
    next.center.join('+') == 'island+system' && at == 1,
    'a slot past the end is the end',
  );
  stdout.writeln('All part drop tests passed.');
}
