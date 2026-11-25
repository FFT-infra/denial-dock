/// The parts the dock draws itself. Anything else in a zone is a part
/// another plugin registered with the kit, asked for by its id.
abstract final class DockPart {
  static const String launcher = 'dock.launcher';

  /// The pinned folders and files, in the user's order.
  static const String stacks = 'dock.stacks';
  static const String trash = 'dock.trash';

  /// A hairline; it may appear any number of times.
  static const String divider = 'dock.divider';

  static const String _prefix = 'dock.';

  static const List<String> all = <String>[launcher, stacks, trash, divider];

  /// Whether [id] is in the dock's own name space.
  static bool own(String id) => id.startsWith(_prefix);

  static bool repeats(String id) => id == divider;
}

/// Where the applications sit along a dock that lies on its whole edge.
enum DockAlign {
  /// One group in the middle, the ends right beside the applications. The
  /// only arrangement a floating capsule has.
  packed,

  /// The ends at the two ends of the edge, the applications in the middle.
  center,

  /// The ends at the two ends of the edge, the applications after the
  /// leading end, as a taskbar has them.
  start;

  String get key => name;

  static DockAlign parse(Object? value) {
    for (final align in values) {
      if (align.name == value) return align;
    }
    return DockAlign.packed;
  }
}

/// What sits before and after the dock's applications, in order.
///
/// No Flutter import, so the rules run as an ordinary Dart test.
class DockZones {
  const DockZones({
    this.leading = const <String>[],
    this.trailing = const <String>[],
  });

  /// The arrangement the dock had before zones were stored, from the
  /// settings that decided it then: the launcher on one end, the folders and
  /// the trash as one group on one end, the trash last in its group.
  factory DockZones.legacy({
    required bool? launcherLeading,
    required bool? extrasLeading,
    required bool trash,
  }) {
    const extras = <String>[DockPart.stacks];
    final group = <String>[...extras, if (trash) DockPart.trash];
    return DockZones(
      leading: <String>[
        if (launcherLeading == true) DockPart.launcher,
        if (extrasLeading == true) ...group,
      ],
      trailing: <String>[
        if (extrasLeading == false) ...group,
        if (launcherLeading == false) DockPart.launcher,
      ],
    );
  }

  /// Zones as stored: [leading] and [trailing] read from JSON values, with
  /// [fallback] for a zone the file does not hold.
  factory DockZones.stored(
    Object? leading,
    Object? trailing, {
    required DockZones fallback,
  }) => DockZones(
    leading: leading is List ? _strings(leading) : fallback.leading,
    trailing: trailing is List ? _strings(trailing) : fallback.trailing,
  ).sanitized();

  static List<String> _strings(List<Object?> value) => <String>[
    for (final entry in value)
      if (entry is String && entry.trim().isNotEmpty) entry.trim(),
  ];

  final List<String> leading;
  final List<String> trailing;

  Iterable<String> get parts => <String>[...leading, ...trailing];

  bool contains(String id) => leading.contains(id) || trailing.contains(id);

  /// Whether [id] sits before the applications, after them, or nowhere.
  bool? leads(String id) => leading.contains(id)
      ? true
      : trailing.contains(id)
      ? false
      : null;

  /// Drops what the dock cannot draw: an id in its own name space that it
  /// does not know, and a second copy of a part that may appear once. An id
  /// of another plugin stays even while nothing offers it, so a part comes
  /// back when its plugin does.
  DockZones sanitized() {
    final seen = <String>{};
    List<String> clean(List<String> zone) => <String>[
      for (final id in zone)
        if ((!DockPart.own(id) || DockPart.all.contains(id)) &&
            (DockPart.repeats(id) || seen.add(id)))
          id,
    ];
    return DockZones(leading: clean(leading), trailing: clean(trailing));
  }

  DockZones without(String id) => DockZones(
    leading: <String>[...leading.where((part) => part != id)],
    trailing: <String>[...trailing.where((part) => part != id)],
  );

  /// Moves the launcher to the outer end of one side, or takes it away when
  /// [leading] is null.
  DockZones withLauncher({required bool? leading}) {
    final base = without(DockPart.launcher);
    return switch (leading) {
      null => base,
      true => DockZones(
        leading: <String>[DockPart.launcher, ...base.leading],
        trailing: base.trailing,
      ),
      false => DockZones(
        leading: base.leading,
        trailing: <String>[...base.trailing, DockPart.launcher],
      ),
    };
  }

  /// Moves the folders, and the trash with them when [trash] is set, to the
  /// inner end of one side, or takes both away when [leading] is null.
  DockZones withExtras({required bool? leading, required bool trash}) {
    final base = without(DockPart.stacks).without(DockPart.trash);
    final group = <String>[DockPart.stacks, if (trash) DockPart.trash];
    return switch (leading) {
      null => base,
      true => DockZones(
        leading: <String>[...base.leading, ...group],
        trailing: base.trailing,
      ),
      false => DockZones(
        leading: base.leading,
        trailing: <String>[...group, ...base.trailing],
      ),
    };
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
      other is DockZones &&
      _same(leading, other.leading) &&
      _same(trailing, other.trailing);

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(leading), Object.hashAll(trailing));

  @override
  String toString() => 'DockZones($leading | $trailing)';
}
