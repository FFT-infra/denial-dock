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
///
/// A preset the user made is the same data, kept in the kit's store and
/// written out as one JSON file to pass around; see [ShellPresetFile].
library;

import 'dart:convert';

/// Which shelf a preset stands on in the settings.
enum ShellPresetGroup {
  /// The shell's own arrangements.
  builtin,

  /// Made after another desktop shell.
  reference,

  /// Saved by the user.
  user,
}

class ShellPreset {
  const ShellPreset({
    required this.id,
    required this.label,
    required this.look,
    required this.bar,
    this.dock = _dock,
    this.barMode = 'shown',
    this.dockVisible,
    this.group = ShellPresetGroup.builtin,
  });

  final String id;
  final String label;
  final ShellPresetGroup group;

  /// The id of a look of the kit.
  final String look;
  final Map<String, Object?> bar;

  /// The dock's layout: what its leading and trailing ends hold, its shape
  /// and how its applications are aligned. Whether icons grow under the
  /// pointer is the look's to say, so no preset names it.
  final Map<String, Object?> dock;

  /// How much of itself the bar draws: `shown`, `islandOnly` or `hidden`.
  final String barMode;

  /// Whether applying this preset enables (`true`) or hides (`false`) the
  /// dock, or leaves the user's dock switch untouched (`null`).
  final bool? dockVisible;

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
    dockVisible: true,
  );

  /// A solid strip from edge to edge in fixed-width type: numbered
  /// workspaces, the clock in the middle, status at the end, no island.
  static final ShellPreset omarchy = ShellPreset(
    id: 'omarchy',
    label: 'Omarchy',
    look: 'omarchy',
    dockVisible: true,
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
    dockVisible: true,
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
    dockVisible: true,
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

  static ShellPreset _reference(
    String id,
    String label, {
    Map<String, Object?> bar = const <String, Object?>{},
    Map<String, Object?> dock = _dock,
    String barMode = 'shown',
    bool? dockVisible = true,
  }) => ShellPreset(
    id: id,
    label: label,
    look: id,
    bar: _barWith(bar),
    dock: dock,
    barMode: barMode,
    dockVisible: dockVisible,
    group: ShellPresetGroup.reference,
  );

  /// One solid plate from edge to edge with every part of the bar on it:
  /// what GNOME, COSMIC, Noctalia and HyprPanel all start from.
  static const Map<String, Object?> _solidStrip = <String, Object?>{
    'ground': 'plate',
    'groundOpacity': 1,
    'groundTint': 'panel',
    'endInset': 0,
    'contentPadding': 8,
    'workspacePlacement': 'leading',
  };

  /// After Noctalia's default bar: launcher mark and workspaces at the
  /// start, the clock in the middle, status at the end, on a solid bar.
  /// Its bar hangs its panels from itself; ours open as popovers.
  static final ShellPreset noctalia = _reference(
    'noctalia',
    'Noctalia style',
    bar: const <String, Object?>{
      ..._solidStrip,
      'cornerRadius': 12,
      'start': <String>['system', 'workspaces'],
      'center': <String>['clock'],
      'end': <String>['status'],
    },
  );

  /// After DankMaterialShell's default bar: one floating rounded bar with
  /// the launcher, the workspaces and the application at its start, the
  /// clock in the middle and status at its end. Its weather, media and
  /// system-monitor widgets have no part here.
  static final ShellPreset material = _reference(
    'material',
    'Material style',
    bar: const <String, Object?>{
      'shape': 'floating',
      'ground': 'plate',
      'groundOpacity': 1,
      'groundTint': 'panel',
      'edgeMargin': 4,
      'endInset': 6,
      'contentPadding': 6,
      'cornerRadius': 16,
      'workspacePlacement': 'leading',
      'start': <String>['system', 'workspaces', 'app'],
      'center': <String>['clock'],
      'end': <String>['status'],
    },
  );

  /// After HyprPanel's default bar: a flat solid strip with numbered
  /// workspaces and the window title at the start and everything else at
  /// the end. Its modules are pills each in a colour of its own; ours
  /// share one ink.
  static final ShellPreset hyprpanel = _reference(
    'hyprpanel',
    'HyprPanel style',
    bar: const <String, Object?>{
      ..._solidStrip,
      'workspaceStyle': 'numbers',
      'start': <String>['system', 'workspaces', 'app'],
      'center': <String>['island'],
      'end': <String>['status', 'clock'],
    },
  );

  /// After Ax-Shell's default bar: floating pills at the two ends and the
  /// notch between them, which is this shell's island. Its vertical bar is
  /// not something this bar does.
  static final ShellPreset axShell = _reference(
    'axshell',
    'Ax-Shell style',
    bar: const <String, Object?>{
      'shape': 'islands',
      'ground': 'plate',
      'groundOpacity': 1,
      'groundTint': 'panel',
      'edgeMargin': 8,
      'endInset': 8,
      'contentPadding': 6,
      'cornerRadius': 16,
      'workspacePlacement': 'leading',
      'start': <String>['system', 'workspaces'],
      'center': <String>['island'],
      'end': <String>['status', 'clock'],
    },
  );

  /// After KDE Plasma's default panel: one bar along the bottom with the
  /// launcher first, the applications after it, and the tray, status and
  /// clock at the end. Plasma 6 floats that panel off the edge until a
  /// window touches it; this one sits on the edge.
  static final ShellPreset plasma = _reference(
    'plasma',
    'Plasma style',
    barMode: 'hidden',
    dock: const <String, Object?>{
      'leading': <String>['dock.launcher', 'workspaces'],
      'trailing': <String>['status.tray', 'status', 'clock'],
      'shape': 'bar',
      'align': 'start',
      'visibility': 'always',
    },
  );

  /// After GNOME Shell: a solid top bar with the workspace dots at the
  /// start, the clock in the middle and status at the end, and a rounded
  /// dash with the application grid at its far end. GNOME shows the dash
  /// in the overview only; here it is the dock.
  static final ShellPreset gnome = _reference(
    'gnome',
    'GNOME style',
    bar: const <String, Object?>{
      ..._solidStrip,
      'start': <String>['workspaces'],
      'center': <String>['clock'],
      'end': <String>['status'],
    },
    dock: const <String, Object?>{
      'leading': <String>[],
      'trailing': <String>['dock.divider', 'dock.launcher'],
      'shape': 'floating',
      'align': 'packed',
      'visibility': 'smart',
    },
  );

  /// After the Windows 11 taskbar: one bar along the bottom with the
  /// launcher and the applications in its centre and the tray, status and
  /// clock at the end.
  static final ShellPreset windows = _reference(
    'windows',
    'Windows 11 style',
    barMode: 'hidden',
    dock: const <String, Object?>{
      'leading': <String>['dock.launcher'],
      'trailing': <String>['status.tray', 'status', 'clock'],
      'shape': 'bar',
      'align': 'center',
      'visibility': 'always',
    },
  );

  /// After COSMIC's default: a solid panel along the top with workspaces
  /// and the application at the start, the clock in the middle and status
  /// at the end, over a floating dock.
  static final ShellPreset cosmic = _reference(
    'cosmic',
    'COSMIC style',
    bar: const <String, Object?>{
      ..._solidStrip,
      'start': <String>['workspaces', 'app'],
      'center': <String>['clock'],
      'end': <String>['status'],
    },
    dock: const <String, Object?>{
      'leading': <String>['dock.launcher'],
      'trailing': <String>['dock.trash'],
      'shape': 'floating',
      'align': 'packed',
      'visibility': 'always',
    },
  );

  /// After Cutefish OS: a translucent top bar with launcher mark, workspaces
  /// and focused app at the start, clock centred and status at the end, over a
  /// floating rounded dock.
  static final ShellPreset cutefish = _reference(
    'cutefish',
    'Cutefish style',
    bar: const <String, Object?>{
      'shape': 'strip',
      'ground': 'glass',
      'groundOpacity': 0.72,
      'groundTint': 'panel',
      'endInset': 4,
      'contentPadding': 6,
      'cornerRadius': 14,
      'workspacePlacement': 'leading',
      'start': <String>['system', 'workspaces', 'app'],
      'center': <String>['clock'],
      'end': <String>['status'],
    },
    dock: const <String, Object?>{
      'leading': <String>['dock.launcher'],
      'trailing': <String>['dock.trash'],
      'shape': 'floating',
      'align': 'packed',
      'visibility': 'always',
    },
  );

  /// The presets made after other desktop shells; see `kit_look_refs.dart`
  /// for the look each one takes.
  static final List<ShellPreset> references = <ShellPreset>[
    noctalia,
    material,
    hyprpanel,
    axShell,
    plasma,
    gnome,
    windows,
    cosmic,
    cutefish,
  ];

  static final List<ShellPreset> all = <ShellPreset>[
    denial,
    mac,
    omarchy,
    segments,
    compact,
    taskbar,
    unified,
    ...references,
  ];

  /// The presets the user saved, as the kit's store holds them. The kit
  /// sets this when it reads the store and whenever one is saved or dropped.
  static List<ShellPreset> user = const <ShellPreset>[];

  /// Every preset there is to choose from.
  static List<ShellPreset> get everything => <ShellPreset>[...all, ...user];

  static Iterable<ShellPreset> inGroup(ShellPresetGroup group) =>
      everything.where((preset) => preset.group == group);

  static ShellPreset byId(String? id) =>
      everything.firstWhere((preset) => preset.id == id, orElse: () => denial);

  static const List<String> barModes = <String>[
    'shown',
    'islandOnly',
    'hidden',
  ];

  /// The values the dock's named layout keys take.
  static const Map<String, List<String>> _dockNames = <String, List<String>>{
    'shape': <String>['floating', 'bar'],
    'align': <String>['packed', 'center', 'start'],
    'visibility': <String>['always', 'smart', 'persistent'],
  };

  /// The widest range each of the bar's measures may take from a file. The
  /// bar's own settings clamp them further; this only keeps nonsense out.
  static const Map<String, (double, double)> _barRanges =
      <String, (double, double)>{
        'groundOpacity': (0, 1),
        'borderWidth': (0, 8),
        'textScale': (0.5, 2),
        'partGap': (0, 40),
        'edgeMargin': (0, 60),
        'endInset': (0, 400),
        'contentPadding': (0, 40),
        'cornerRadius': (0, 60),
      };

  static const int _longestList = 40;
  static const int _longestName = 60;

  /// [saved] laid over [base] as a file may give it: only the keys of
  /// [base], each of the kind it ships as, numbers inside [ranges], names
  /// among [names], and lists of short strings.
  static Map<String, Object?> _sound(
    Map<String, Object?> base,
    Object? saved, {
    Map<String, (double, double)> ranges = const <String, (double, double)>{},
    Map<String, List<String>> names = const <String, List<String>>{},
  }) => <String, Object?>{
    for (final entry in base.entries)
      entry.key: () {
        if (saved is! Map || !saved.containsKey(entry.key)) return entry.value;
        final value = saved[entry.key];
        if (!_kin(entry.value, value)) return entry.value;
        if (value is num) {
          if (!value.isFinite) return entry.value;
          final range = ranges[entry.key];
          return range == null ? value : value.clamp(range.$1, range.$2);
        }
        if (value is String) {
          final allowed = names[entry.key];
          if (value.length > _longestName) return entry.value;
          return allowed == null || allowed.contains(value)
              ? value
              : entry.value;
        }
        if (value is List) {
          return <String>[
            for (final item in value.take(_longestList))
              if (item is String && item.isNotEmpty && item.length <= 40) item,
          ];
        }
        return value;
      }(),
  };

  /// This preset as JSON: the form the store and a preset file hold.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'label': label,
    'look': look,
    'barMode': barMode,
    'dockVisible': ?dockVisible,
    'bar': bar,
    'dock': dock,
  };

  /// A preset of the user's from [json], which may come from anywhere:
  /// every key the bar and the dock lay out is present afterwards, of the
  /// right kind and inside its range, and nothing here throws. Null when
  /// [json] is no map at all.
  static ShellPreset? fromJson(Object? json, {String? id}) {
    if (json is! Map) return null;
    final ownId = json['id'];
    final label = json['label'];
    final look = json['look'];
    final mode = json['barMode'];
    final dockShown = json['dockVisible'];
    final name = label is String ? label.trim() : '';
    return ShellPreset(
      id: id ?? (ownId is String && ownId.isNotEmpty ? ownId : 'preset'),
      label: name.isEmpty
          ? 'Preset'
          : name.length > _longestName
          ? name.substring(0, _longestName)
          : name,
      look: look is String && look.isNotEmpty ? look : 'denial',
      barMode: barModes.contains(mode) ? mode as String : 'shown',
      dockVisible: dockShown is bool ? dockShown : null,
      bar: Map<String, Object?>.unmodifiable(
        _sound(_bar, json['bar'], ranges: _barRanges),
      ),
      dock: Map<String, Object?>.unmodifiable(
        _sound(_dock, json['dock'], names: _dockNames),
      ),
      group: ShellPresetGroup.user,
    );
  }

  /// The user's presets as the store holds them, a list of [toJson] maps.
  /// One that shares an id with a preset that ships, or with one before it,
  /// is left out.
  static List<ShellPreset> stored(Object? list) {
    final taken = <String>{for (final preset in all) preset.id};
    return List<ShellPreset>.unmodifiable(<ShellPreset>[
      if (list is List)
        for (final entry in list)
          if (fromJson(entry) case final preset?)
            if (taken.add(preset.id)) preset,
    ]);
  }

  /// This preset with another id, name, or look.
  ShellPreset renamed({String? id, String? label, String? look}) =>
      ShellPreset(
        id: id ?? this.id,
        label: label ?? this.label,
        look: look ?? this.look,
        bar: bar,
        dock: dock,
        barMode: barMode,
        dockVisible: dockVisible,
        group: group,
      );

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
    bool? dockVisible,
  }) =>
      look == this.look &&
      this.bar.entries.every((entry) => _same(entry.value, bar[entry.key])) &&
      (barMode == null || barMode == this.barMode) &&
      (dockVisible == null ||
          this.dockVisible == null ||
          dockVisible == this.dockVisible) &&
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

  /// The shell as it stands, in the shape [recall] reads: what to keep for
  /// this preset when the user goes to another. Only the keys the preset
  /// decides are kept; [dock] is null while no dock runs, and then the
  /// dock's part of an earlier memory in [before] stays.
  Map<String, Object?> remember({
    required String look,
    required String barMode,
    required Map<String, Object?> bar,
    Map<String, Object?>? dock,
    bool? dockVisible,
    Object? before,
  }) => <String, Object?>{
    'look': look,
    'barMode': barMode,
    'dockVisible': ?dockVisible,
    'bar': <String, Object?>{
      for (final key in this.bar.keys) key: bar[key],
    },
    if (dock != null)
      'dock': <String, Object?>{
        for (final key in this.dock.keys)
          if (dock.containsKey(key)) key: dock[key],
      }
    else if (before is Map && before['dock'] is Map)
      'dock': before['dock'],
  };

  /// This preset as the user left it: [memory] laid over what the preset
  /// ships with, key by key, so a memory written by an older build that
  /// lacks a key, or holds one of the wrong kind, still gives a whole
  /// preset. Null or anything that is no map gives the preset as shipped.
  ({
    String look,
    String barMode,
    bool? dockVisible,
    Map<String, Object?> bar,
    Map<String, Object?> dock,
  })
  recall(Object? memory) {
    Map<String, Object?> over(Map<String, Object?> base, Object? saved) =>
        <String, Object?>{
          for (final entry in base.entries)
            entry.key:
                saved is Map &&
                    saved.containsKey(entry.key) &&
                    _kin(entry.value, saved[entry.key])
                ? saved[entry.key]
                : entry.value,
        };
    final map = memory is Map ? memory : const <Object?, Object?>{};
    final look = map['look'];
    final mode = map['barMode'];
    final dockShown = map['dockVisible'];
    return (
      look: look is String ? look : this.look,
      barMode: mode is String ? mode : barMode,
      dockVisible: dockShown is bool ? dockShown : dockVisible,
      bar: over(bar, map['bar']),
      dock: over(dock, map['dock']),
    );
  }

  /// Whether [saved] may stand in for [shipped]: the same kind of value.
  /// A key that ships as null (no value set) takes a number or null.
  static bool _kin(Object? shipped, Object? saved) => switch (shipped) {
    null => saved == null || saved is num,
    num() => saved is num,
    String() => saved is String,
    bool() => saved is bool,
    List() => saved is List && saved.every((item) => item is String),
    _ => false,
  };
}

/// Why a preset file could not be read.
enum ShellPresetFault {
  /// The text is not JSON.
  notJson,

  /// It is JSON, but not a preset of this shell.
  notPreset,

  /// It was written by a newer build than this one.
  newer,
}

class ShellPresetException implements Exception {
  const ShellPresetException(this.fault);

  final ShellPresetFault fault;

  @override
  String toString() => 'ShellPresetException(${fault.name})';
}

/// A preset as one JSON document, to keep as a file or pass through the
/// clipboard:
///
///     {"format": "denial-shell-preset", "version": 1,
///      "preset": {"id", "label", "look", "barMode", "bar", "dock"},
///      "look": { a whole look, when the preset's look is the user's own }}
///
/// The look is opaque here; the kit reads it with `KitLook.fromJson`.
class ShellPresetFile {
  const ShellPresetFile(this.preset, {this.look});

  static const String format = 'denial-shell-preset';
  static const int version = 1;

  /// The most text a preset is read from, so that a clipboard holding
  /// something else entirely is turned away before it is parsed.
  static const int longest = 400000;

  final ShellPreset preset;

  /// The preset's look in full, when it does not ship with the shell.
  final Map<String, Object?>? look;

  String encode() => const JsonEncoder.withIndent('  ').convert(
    <String, Object?>{
      'format': format,
      'version': version,
      'preset': preset.toJson(),
      if (look != null) 'look': look,
    },
  );

  /// Reads [text]. What is wrong with a preset inside a sound document is
  /// put right (see [ShellPreset.fromJson]); a document that is no preset
  /// throws a [ShellPresetException] that says why.
  static ShellPresetFile decode(String text) {
    if (text.length > longest) {
      throw const ShellPresetException(ShellPresetFault.notPreset);
    }
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException {
      throw const ShellPresetException(ShellPresetFault.notJson);
    }
    if (json is! Map || json['format'] != format) {
      throw const ShellPresetException(ShellPresetFault.notPreset);
    }
    final found = json['version'];
    if (found is! int || found < 1) {
      throw const ShellPresetException(ShellPresetFault.notPreset);
    }
    if (found > version) {
      throw const ShellPresetException(ShellPresetFault.newer);
    }
    final preset = ShellPreset.fromJson(json['preset']);
    if (preset == null) {
      throw const ShellPresetException(ShellPresetFault.notPreset);
    }
    final look = json['look'];
    return ShellPresetFile(
      preset,
      look: look is Map
          ? <String, Object?>{
              for (final entry in look.entries)
                if (entry.key is String) entry.key as String: entry.value,
            }
          : null,
    );
  }

  /// A file name for [label]: its letters and digits, lower case, with
  /// everything else a dash; `preset` when nothing is left.
  static String fileName(String label) {
    final slug = label
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\u4e00-\u9fff]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final short = slug.length > 48 ? slug.substring(0, 48) : slug;
    return '${short.isEmpty ? 'preset' : short}.json';
  }
}
