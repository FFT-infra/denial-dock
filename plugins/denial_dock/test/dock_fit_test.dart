import 'package:denial_dock/src/dock_layout.dart';
import 'package:denial_dock/src/dock_metrics.dart';

/// The length of a row of [icons] icons of [size] with [fixed] beside them
/// and [scaled] spacing measured at [base].
double _row(int icons, double size, double fixed, double scaled, double base) =>
    fixed + icons * size + scaled * size / base;

void main() {
  // A row that fits keeps its size.
  _expect(
    DockLayout.fitIconSize(
          available: 1500,
          iconSize: 48,
          icons: 10,
          fixed: 92,
          floor: 20,
        ) ==
        48,
    'a row that fits is left alone',
  );
  _expect(
    DockLayout.fitIconSize(
          available: 10 * 48 + 92,
          iconSize: 48,
          icons: 10,
          fixed: 92,
          floor: 20,
        ) ==
        48,
    'an exact fit is a fit',
  );

  // Forty icons with 8 between them and 10 at each end, on a 1500 edge:
  // the largest whole size that fits.
  const fixed = 2 * 10 + 39 * 8.0;
  final shrunk = DockLayout.fitIconSize(
    available: 1500,
    iconSize: 48,
    icons: 40,
    fixed: fixed,
    floor: 20,
  );
  _expect(shrunk == 29, 'shrinks to fit ($shrunk)');
  _expect(
    _row(40, shrunk, fixed, 0, 48) <= 1500 &&
        _row(40, shrunk + 1, fixed, 0, 48) > 1500,
    'and no further than it has to',
  );
  _expect(shrunk == shrunk.roundToDouble(), 'whole pixels');

  // More icons never give a larger size.
  var last = 48.0;
  for (var icons = 1; icons <= 120; icons++) {
    final size = DockLayout.fitIconSize(
      available: 1500,
      iconSize: 48,
      icons: icons,
      fixed: 20 + (icons - 1) * 8.0,
      floor: DockMetrics.fitFloor,
    );
    _expect(size <= last, 'size never grows with the row ($icons)');
    _expect(
      size >= DockMetrics.fitFloor && size <= 48,
      'size stays in range ($icons)',
    );
    last = size;
  }
  _expect(last == DockMetrics.fitFloor, 'a hopeless row stops at the floor');

  // A look whose spacing follows its icons shrinks both: forty 36 pt icons
  // with the macOS look's spacing.
  const spacing = 2 * 14.5 + 39 * 12.5;
  final mac = DockLayout.fitIconSize(
    available: 1500,
    iconSize: 36,
    icons: 40,
    fixed: 0,
    scaled: spacing,
    floor: 20,
  );
  _expect(mac == 27, 'scaled spacing shrinks along ($mac)');
  _expect(
    _row(40, mac, 0, spacing, 36) <= 1500 &&
        _row(40, mac + 1, 0, spacing, 36) > 1500,
    'to the largest size that fits',
  );
  // Fixed spacing would have cost the icons more.
  _expect(
    DockLayout.fitIconSize(
          available: 1500,
          iconSize: 36,
          icons: 40,
          fixed: spacing,
          floor: 20,
        ) <
        mac,
    'fixed spacing leaves the icons less',
  );
  // Parts of other plugins keep their length while the rest shrinks.
  final withParts = DockLayout.fitIconSize(
    available: 1500,
    iconSize: 36,
    icons: 40,
    fixed: 300,
    scaled: spacing,
    floor: 20,
  );
  _expect(
    withParts < mac && _row(40, withParts, 300, spacing, 36) <= 1500,
    'parts take their room first',
  );

  // The floor is never above the size asked for, and odd input changes
  // nothing.
  _expect(
    DockLayout.fitIconSize(
          available: 10,
          iconSize: 16,
          icons: 40,
          fixed: 0,
          floor: 20,
        ) ==
        16,
    'the floor does not enlarge',
  );
  _expect(
    DockLayout.fitIconSize(
              available: double.infinity,
              iconSize: 48,
              icons: 400,
              fixed: 0,
              floor: 20,
            ) ==
            48 &&
        DockLayout.fitIconSize(
              available: 100,
              iconSize: 48,
              icons: 0,
              fixed: 500,
              floor: 20,
            ) ==
            48,
    'no edge, or no icons, keeps the size',
  );

  // The shrunken row really fits when it is laid out.
  final frame = DockLayout.compute(
    surfaceExtent: 1500,
    slots: [for (var i = 0; i < 40; i++) DockSlot(half: shrunk / 2)],
    padding: 10,
    gap: 8,
    pointer: 0,
    hover: 0,
    maxScale: 1,
    radius: 140,
  );
  _expect(
    frame.restExtent <= 1500 && frame.capsuleStart >= 0,
    'the laid out row is inside its edge',
  );

  // Task buttons: as long as the widest while there is room.
  _expect(
    DockLayout.taskExtent(available: 1000, tasks: 4, icon: 44, widest: 168) ==
        168,
    'room for full buttons',
  );
  // Then an equal share, never more than the room.
  final share = DockLayout.taskExtent(
    available: 1000,
    tasks: 8,
    icon: 44,
    widest: 168,
  );
  _expect(share == 125 && share * 8 <= 1000, 'an equal share ($share)');
  // Once a share leaves a title no room, the icon alone.
  _expect(
    DockLayout.taskExtent(available: 1000, tasks: 12, icon: 44, widest: 168) ==
        44,
    'too many for titles',
  );
  _expect(
    DockLayout.taskExtent(available: 1000, tasks: 11, icon: 44, widest: 168) ==
        90,
    'the last count that keeps titles',
  );
  _expect(
    DockLayout.taskExtent(available: 1000, tasks: 0, icon: 44, widest: 168) ==
            44 &&
        DockLayout.taskExtent(
              available: double.infinity,
              tasks: 3,
              icon: 44,
              widest: 168,
            ) ==
            44 &&
        DockLayout.taskExtent(
              available: -50,
              tasks: 3,
              icon: 44,
              widest: 168,
            ) ==
            44,
    'nothing to share out is the icon alone',
  );
  // The buttons together never pass the room they were given.
  for (var tasks = 1; tasks <= 40; tasks++) {
    final extent = DockLayout.taskExtent(
      available: 900,
      tasks: tasks,
      icon: 40,
      widest: 168,
    );
    _expect(
      extent == 40 || extent * tasks <= 900,
      'buttons fit their room ($tasks)',
    );
    _expect(extent >= 40 && extent <= 168, 'a button is in range ($tasks)');
  }
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
