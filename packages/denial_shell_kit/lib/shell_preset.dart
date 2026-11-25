/// A whole arrangement of the shell under one name: the look every panel
/// takes, how the top bar is laid out, how much of itself the bar draws and
/// what the dock holds at its two ends. Plain data, so a new preset is one
/// more constant here.
///
/// [bar] holds the top bar's layout settings under the keys its own
/// preferences file uses, and [dock] the dock's layout under its keys.
/// Applying a preset writes those keys and leaves every other setting alone,
/// such as which status items show or which applications are pinned.
/// Whether the dock shows is a switch of its own and no preset touches it.
class ShellPreset {
  const ShellPreset({
    required this.id,
    required this.label,
    required this.look,
    required this.bar,
    this.dock = _dock,
    this.barMode = 'shown',
  });

  final String id;
  final String label;

  /// The id of a look of the kit.
  final String look;
  final Map<String, Object?> bar;

  /// The dock's layout: what its leading and trailing ends hold, its shape
  /// and how its applications are aligned. Whether icons grow under the
  /// pointer is the look's to say, so no preset names it.
  final Map<String, Object?> dock;

  /// How much of itself the bar draws: `shown`, `islandOnly` or `hidden`.
  final String barMode;

  /// The dock as it has always been: a floating capsule with the launcher
  /// before the applications and the stacks and the trash after them.
  static const Map<String, Object?> _dock = <String, Object?>{
    'leading': <String>['dock.launcher'],
    'trailing': <String>['dock.stacks', 'dock.trash'],
    'shape': 'floating',
    'align': 'packed',
    'visibility': 'smart',
  };

  /// The bar as it has always been: a strip with no plate, the island in
  /// its centre with the workspace switcher inside.
  static const Map<String, Object?> _bar = <String, Object?>{
    'shape': 'strip',
    'cap': 'round',
    'ground': 'none',
    'groundOpacity': 0.55,
    'groundTint': 'wallpaper',
    'borderWidth': 0,
    'borderColour': 'ink',
    'textScale': 1,
    'partGap': 6,
    'edgeMargin': 6,
    'endInset': null,
    'contentPadding': 0,
    'cornerRadius': 14,
    'workspaceStyle': 'dots',
    'workspacePlacement': 'island',
    'start': <String>['system', 'app'],
    'center': <String>['island'],
    'end': <String>['status', 'clock'],
  };

  /// The usual bar with [changes] laid over it, so every preset names every
  /// key and going from one to another leaves nothing of the first behind.
  static Map<String, Object?> _barWith(Map<String, Object?> changes) =>
      Map<String, Object?>.unmodifiable(<String, Object?>{..._bar, ...changes});

  static const ShellPreset denial = ShellPreset(
    id: 'denial',
    label: 'Denial',
    look: 'denial',
    bar: _bar,
  );

  static const ShellPreset mac = ShellPreset(
    id: 'mac',
    label: 'macOS',
    look: 'mac',
    bar: _bar,
  );

  /// A solid strip from edge to edge in fixed-width type: numbered
  /// workspaces, the clock in the middle, status at the end, no island.
  static final ShellPreset omarchy = ShellPreset(
    id: 'omarchy',
    label: 'Omarchy',
    look: 'terminal',
    bar: _barWith(const <String, Object?>{
      'ground': 'plate',
      'groundOpacity': 1,
      'groundTint': 'panel',
      'endInset': 0,
      'contentPadding': 8,
      'workspaceStyle': 'numbers',
      'workspacePlacement': 'leading',
      'start': <String>['workspaces'],
      'center': <String>['clock'],
      'end': <String>['status'],
    }),
  );

  /// Three floating runs of pointed segments with the wallpaper between
  /// them.
  static final ShellPreset segments = ShellPreset(
    id: 'segments',
    label: 'Segments',
    look: 'soft',
    bar: _barWith(const <String, Object?>{
      'shape': 'islands',
      'cap': 'arrow',
      'ground': 'plate',
      'groundOpacity': 0.92,
      'groundTint': 'accent',
      'edgeMargin': 4,
      'endInset': 6,
      'contentPadding': 4,
      'workspaceStyle': 'numbers',
      'workspacePlacement': 'leading',
      'start': <String>['workspaces'],
      'center': <String>['system', 'separator', 'app', 'separator', 'clock'],
      'end': <String>['status'],
    }),
  );

  /// One solid rounded bar: launcher mark, workspaces and the application
  /// at the start, the clock in the middle, status at the end.
  static final ShellPreset compact = ShellPreset(
    id: 'compact',
    label: 'Compact',
    look: 'soft',
    bar: _barWith(const <String, Object?>{
      'shape': 'floating',
      'ground': 'plate',
      'groundOpacity': 1,
      'groundTint': 'panel',
      'endInset': 8,
      'contentPadding': 6,
      'cornerRadius': 10,
      'workspacePlacement': 'leading',
      'start': <String>['system', 'workspaces', 'app'],
      'center': <String>['clock'],
      'end': <String>['status'],
    }),
  );

  /// One bar along the bottom edge and nothing at the top: the launcher and
  /// the workspaces at its start, the applications after them, the tray, the
  /// status items and the clock at its end. It stays on screen, so windows
  /// keep clear of it.
  static const ShellPreset taskbar = ShellPreset(
    id: 'taskbar',
    label: 'Taskbar',
    look: 'soft',
    bar: _bar,
    barMode: 'hidden',
    dock: <String, Object?>{
      'leading': <String>['dock.launcher', 'workspaces'],
      'trailing': <String>['status.tray', 'status', 'clock'],
      'shape': 'bar',
      'align': 'start',
      'visibility': 'always',
    },
  );

  /// A floating dock that also carries the clock and the status items, with
  /// only the island left at the top of the screen.
  static const ShellPreset unified = ShellPreset(
    id: 'unified',
    label: 'Unified',
    look: 'mac',
    bar: _bar,
    barMode: 'islandOnly',
    dock: <String, Object?>{
      'leading': <String>['clock', 'dock.divider', 'dock.launcher'],
      'trailing': <String>[
        'dock.stacks',
        'dock.trash',
        'dock.divider',
        'status',
      ],
      'shape': 'floating',
      'align': 'packed',
      'visibility': 'smart',
    },
  );

  static final List<ShellPreset> all = <ShellPreset>[
    denial,
    mac,
    omarchy,
    segments,
    compact,
    taskbar,
    unified,
  ];

  static ShellPreset byId(String? id) =>
      all.firstWhere((preset) => preset.id == id, orElse: () => denial);

  /// Whether the shell is still as this preset set it: the same look, and
  /// every layout key of the preset unchanged in [bar]. Keys the preset does
  /// not name are the user's own and never count.
  ///
  /// [dock] and [barMode] are compared when given. A shell with no dock
  /// running has no dock layout to have changed, so it passes null.
  bool matches({
    required String look,
    required Map<String, Object?> bar,
    Map<String, Object?>? dock,
    String? barMode,
  }) =>
      look == this.look &&
      this.bar.entries.every((entry) => _same(entry.value, bar[entry.key])) &&
      (barMode == null || barMode == this.barMode) &&
      (dock == null ||
          this.dock.entries.every(
            (entry) => _same(entry.value, dock[entry.key]),
          ));

  static bool _same(Object? a, Object? b) {
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var index = 0; index < a.length; index++) {
        if (!_same(a[index], b[index])) return false;
      }
      return true;
    }
    // Numbers compare by value, so 6 in a preset is 6.0 from a slider.
    return a == b;
  }
}
