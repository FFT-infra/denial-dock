/// The parts the bar can place and the three zones it places them in. Plain
/// data, so the rules here are tested without a widget.
library;

/// Status items, in the order the bar shows them by default.
const List<String> barStatusItems = <String>[
  'tray',
  'wifi',
  'bluetooth',
  'volume',
  'battery',
  'keyboard',
  'search',
  'clipboard',
  'notifications',
  'controlcenter',
  'settings',
];

abstract final class BarPart {
  static const String system = 'system';
  static const String workspaces = 'workspaces';
  static const String app = 'app';
  static const String island = 'island';
  static const String clock = 'clock';

  /// The whole status cluster, in the order the user gave its items.
  static const String status = 'status';

  /// Takes the room left over, pushing its neighbours apart.
  static const String spacer = 'spacer';

  /// A divider; between arrow segments it is where one ends.
  static const String separator = 'separator';

  /// One part gap of empty room.
  static const String gap = 'gap';

  static const String _statusPrefix = 'status.';

  /// One status item placed on its own, outside the cluster.
  static String statusItem(String item) => '$_statusPrefix$item';

  /// The status item [id] stands for, or null when it is another part.
  static String? statusItemOf(String id) {
    if (!id.startsWith(_statusPrefix)) return null;
    final item = id.substring(_statusPrefix.length);
    return barStatusItems.contains(item) ? item : null;
  }

  static final List<String> all = List<String>.unmodifiable(<String>[
    system,
    workspaces,
    app,
    island,
    clock,
    status,
    for (final item in barStatusItems) statusItem(item),
    spacer,
    separator,
    gap,
  ]);

  static bool known(String id) => all.contains(id);

  /// Whether a zone may hold it more than once.
  static bool repeats(String id) =>
      id == spacer || id == separator || id == gap;

  /// Parts that bring their own room on both sides, so the bar adds no gap
  /// next to them. The application name is a menu title with its own
  /// padding, which is why it sits flush against the system menu.
  static bool tight(String id) => id == app || repeats(id);

  /// Whether the bar puts a part gap between two neighbours.
  static bool gapBetween(String before, String after) =>
      !tight(before) && !tight(after);
}

/// What sits in the bar's start, centre and end, in order.
class BarZones {
  const BarZones({
    this.start = const <String>[],
    this.center = const <String>[],
    this.end = const <String>[],
  });

  /// The layout the bar had before zones were stored, from the settings that
  /// decided it then. [workspaces] is the old placement's key.
  factory BarZones.legacy({
    required bool systemMenu,
    required bool appMenu,
    required bool island,
    required String workspaces,
  }) => BarZones(
    start: <String>[
      if (systemMenu) BarPart.system,
      if (workspaces == 'leading') ...<String>[
        // The switcher kept its gap even with no system menu before it.
        if (!systemMenu) BarPart.gap,
        BarPart.workspaces,
      ],
      if (appMenu) BarPart.app,
    ],
    center: <String>[if (island) BarPart.island],
    end: <String>[
      if (workspaces == 'trailing') BarPart.workspaces,
      BarPart.status,
      BarPart.clock,
    ],
  );

  static const int count = 3;

  final List<String> start;
  final List<String> center;
  final List<String> end;

  List<String> zone(int index) => switch (index) {
    0 => start,
    1 => center,
    _ => end,
  };

  BarZones _with(int index, List<String> parts) => BarZones(
    start: index == 0 ? parts : start,
    center: index == 1 ? parts : center,
    end: index == 2 ? parts : end,
  );

  Iterable<String> get parts => <String>[...start, ...center, ...end];

  bool contains(String id) => zoneOf(id) != null;

  /// The zone [id] sits in, or null.
  int? zoneOf(String id) {
    for (var index = 0; index < count; index++) {
      if (zone(index).contains(id)) return index;
    }
    return null;
  }

  /// Status items placed on their own; the cluster leaves these out.
  Set<String> get loneStatusItems => <String>{
    for (final id in parts) ?BarPart.statusItemOf(id),
  };

  /// Drops what the bar cannot draw: unknown ids, a second copy of a part
  /// that may appear once, and an island outside the centre, where it has
  /// nothing to hang from.
  BarZones sanitized() {
    final seen = <String>{};
    List<String> clean(int index) => <String>[
      for (final id in zone(index))
        if (BarPart.known(id) &&
            (id != BarPart.island || index == 1) &&
            (BarPart.repeats(id) || seen.add(id)))
          id,
    ];
    return BarZones(start: clean(0), center: clean(1), end: clean(2));
  }

  BarZones without(String id) => BarZones(
    start: <String>[...start.where((part) => part != id)],
    center: <String>[...center.where((part) => part != id)],
    end: <String>[...end.where((part) => part != id)],
  );

  /// Puts [id] into zone [index] at [at] (the end when null). A part that
  /// may appear once leaves the place it had.
  BarZones inserted(int index, String id, [int? at]) {
    final base = BarPart.repeats(id) ? this : without(id);
    final parts = List<String>.of(base.zone(index));
    parts.insert((at ?? parts.length).clamp(0, parts.length), id);
    return base._with(index, parts).sanitized();
  }

  BarZones removedAt(int index, int at) {
    final parts = List<String>.of(zone(index));
    if (at < 0 || at >= parts.length) return this;
    parts.removeAt(at);
    return _with(index, parts);
  }

  /// Moves the part at [at] of zone [index] by [by] places inside its zone.
  /// Returns the zones and where the part is now.
  (BarZones, int, int) shifted(int index, int at, int by) {
    final parts = List<String>.of(zone(index));
    final to = at + by;
    if (at < 0 || at >= parts.length || to < 0 || to >= parts.length) {
      return (this, index, at);
    }
    parts.insert(to, parts.removeAt(at));
    return (_with(index, parts), index, to);
  }

  /// Moves the part at [at] of zone [index] into the zone [by] steps away:
  /// onto its near end, so the part travels the shortest way along the bar.
  (BarZones, int, int) carried(int index, int at, int by) {
    final target = index + by;
    final from = zone(index);
    if (at < 0 || at >= from.length || target < 0 || target >= count) {
      return (this, index, at);
    }
    final id = from[at];
    if (id == BarPart.island && target != 1) return (this, index, at);
    final to = by > 0 ? 0 : zone(target).length;
    final next = removedAt(index, at)._insertRaw(target, id, to);
    return (next, target, to);
  }

  BarZones _insertRaw(int index, String id, int at) {
    final parts = List<String>.of(zone(index))..insert(at, id);
    return _with(index, parts);
  }

  /// A zone cut at its separators, for a bar that draws each run as its own
  /// segment. Empty runs are dropped.
  static List<List<String>> segments(List<String> zone) {
    final runs = <List<String>>[<String>[]];
    for (final id in zone) {
      if (id == BarPart.separator) {
        runs.add(<String>[]);
      } else {
        runs.last.add(id);
      }
    }
    return <List<String>>[
      for (final run in runs)
        if (run.isNotEmpty) run,
    ];
  }

  static bool _same(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      if (a[index] != b[index]) return false;
    }
    return true;
  }

  @override
  bool operator ==(Object other) =>
      other is BarZones &&
      _same(start, other.start) &&
      _same(center, other.center) &&
      _same(end, other.end);

  @override
  int get hashCode => Object.hash(
    Object.hashAll(start),
    Object.hashAll(center),
    Object.hashAll(end),
  );

  @override
  String toString() => 'BarZones($start | $center | $end)';
}
