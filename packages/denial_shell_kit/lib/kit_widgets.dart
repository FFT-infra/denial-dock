/// Extensible widget catalog, sizing math, and custom widget definitions.
///
/// Inspired by macOS Notification Centre widgets and NextKDE's DeskCenter
/// registry (`DeskCenterConfigService` + `WidgetResizeHandle`): supports built-in
/// S/M/L widgets as well as user-defined custom command, shortcut, and note
/// widgets persisted as JSON.
///
/// Pure Dart (no Flutter import) so unit tests run directly under `dart`.
library;

import 'dart:math' as math;

/// Standard widget grid footprints on the 2-column Notification Centre grid.
enum KitWidgetSize {
  small(1, 1, 'Small', '1×1'),
  medium(2, 1, 'Medium', '2×1'),
  large(2, 2, 'Large', '2×2');

  const KitWidgetSize(this.w, this.h, this.label, this.gridLabel);

  final int w;
  final int h;
  final String label;
  final String gridLabel;

  String get code => '${w}x$h';

  static KitWidgetSize? fromDims(int w, int h) {
    if (w <= 1 && h <= 1) return KitWidgetSize.small;
    if (w >= 2 && h <= 1) return KitWidgetSize.medium;
    if (w >= 2 && h >= 2) return KitWidgetSize.large;
    return null;
  }

  static KitWidgetSize? tryParse(Object? value) {
    if (value is! String) return null;
    return switch (value) {
      'small' || '1x1' => KitWidgetSize.small,
      'medium' || '2x1' => KitWidgetSize.medium,
      'large' || '2x2' => KitWidgetSize.large,
      _ => null,
    };
  }
}

/// Gallery categories for organizing built-in and custom widgets.
enum KitWidgetCategory {
  essentials('Essentials'),
  system('System'),
  media('Media'),
  productivity('Productivity'),
  custom('Custom');

  const KitWidgetCategory(this.label);
  final String label;
}

/// Kind of user-created custom widget.
enum KitCustomWidgetKind {
  /// Runs a shell command periodically (or on tap) and displays its output.
  command,

  /// Launches a command or app on tap.
  shortcut,

  /// Editable sticky note card.
  note;

  static KitCustomWidgetKind parse(Object? value) => switch (value) {
    'command' => KitCustomWidgetKind.command,
    'shortcut' => KitCustomWidgetKind.shortcut,
    'note' => KitCustomWidgetKind.note,
    _ => KitCustomWidgetKind.note,
  };
}

/// A user-defined custom widget persisted in shell config JSON.
class KitCustomWidgetDef {
  const KitCustomWidgetDef({
    required this.id,
    required this.title,
    required this.kind,
    this.subtitle = '',
    this.command = '',
    this.noteText = '',
    this.refreshSeconds = 30,
    this.accentRgb,
    this.supportedSizes = const <KitWidgetSize>[
      KitWidgetSize.small,
      KitWidgetSize.medium,
      KitWidgetSize.large,
    ],
    this.defaultSize = KitWidgetSize.medium,
  });

  final String id;
  final String title;
  final KitCustomWidgetKind kind;
  final String subtitle;
  final String command;
  final String noteText;
  final int refreshSeconds;
  final int? accentRgb;
  final List<KitWidgetSize> supportedSizes;
  final KitWidgetSize defaultSize;

  KitCustomWidgetDef copyWith({
    String? title,
    KitCustomWidgetKind? kind,
    String? subtitle,
    String? command,
    String? noteText,
    int? refreshSeconds,
    int? accentRgb,
  }) => KitCustomWidgetDef(
    id: id,
    title: title ?? this.title,
    kind: kind ?? this.kind,
    subtitle: subtitle ?? this.subtitle,
    command: command ?? this.command,
    noteText: noteText ?? this.noteText,
    refreshSeconds: refreshSeconds ?? this.refreshSeconds,
    accentRgb: accentRgb ?? this.accentRgb,
    supportedSizes: supportedSizes,
    defaultSize: defaultSize,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'title': title,
    'kind': kind.name,
    if (subtitle.isNotEmpty) 'subtitle': subtitle,
    if (command.isNotEmpty) 'command': command,
    if (noteText.isNotEmpty) 'noteText': noteText,
    'refreshSeconds': refreshSeconds,
    if (accentRgb != null) 'accentRgb': accentRgb,
    'defaultSize': defaultSize.name,
  };

  static KitCustomWidgetDef? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final title = raw['title'];
    if (id is! String || id.isEmpty || title is! String || title.isEmpty) {
      return null;
    }
    final refresh = raw['refreshSeconds'];
    final rgb = raw['accentRgb'];
    return KitCustomWidgetDef(
      id: id.startsWith('custom.') ? id : 'custom.$id',
      title: title,
      kind: KitCustomWidgetKind.parse(raw['kind']),
      subtitle: raw['subtitle'] is String ? raw['subtitle'] as String : '',
      command: raw['command'] is String ? raw['command'] as String : '',
      noteText: raw['noteText'] is String ? raw['noteText'] as String : '',
      refreshSeconds: refresh is num
          ? refresh.round().clamp(0, 3600)
          : 30,
      accentRgb: rgb is int ? rgb : null,
      defaultSize:
          KitWidgetSize.tryParse(raw['defaultSize']) ?? KitWidgetSize.medium,
    );
  }
}

/// Metadata for a registered widget (built-in or custom).
class KitWidgetSpec {
  const KitWidgetSpec({
    required this.id,
    required this.title,
    required this.category,
    required this.supportedSizes,
    required this.defaultSize,
    this.description = '',
    this.custom,
  });

  final String id;
  final String title;
  final KitWidgetCategory category;
  final List<KitWidgetSize> supportedSizes;
  final KitWidgetSize defaultSize;
  final String description;
  final KitCustomWidgetDef? custom;

  bool get isCustom => custom != null;
  bool get resizable => supportedSizes.length > 1;

  /// Resolves a stored `(w, h)` to the nearest supported size for this widget.
  KitWidgetSize clampSize(int w, int h) {
    final exact = KitWidgetSize.fromDims(w, h);
    if (exact != null && supportedSizes.contains(exact)) return exact;
    return defaultSize;
  }

  /// Next supported size in cycle order (used when clicking the resize handle).
  KitWidgetSize nextSize(KitWidgetSize current) {
    if (supportedSizes.length <= 1) return current;
    final idx = supportedSizes.indexOf(current);
    return supportedSizes[(idx + 1) % supportedSizes.length];
  }
}

/// Magnetic corner-resize snapping math (NextKDE `WidgetResizeHandle` style):
/// given the starting size, pointer drag delta `(dx, dy)`, cell side, and gap,
/// snaps cleanly to the closest supported [KitWidgetSize].
KitWidgetSize snapWidgetResize({
  required KitWidgetSize current,
  required List<KitWidgetSize> supported,
  required double dx,
  required double dy,
  required double cell,
  required double gap,
}) {
  if (supported.length <= 1) return current;
  final step = math.max(1.0, cell + gap);
  final startW = current.w * cell + (current.w - 1) * gap;
  final startH = current.h * cell + (current.h - 1) * gap;
  final targetW = startW + dx;
  final targetH = startH + dy;
  // Bias slightly past 40% of a cell stride so resizing feels crisp & magnetic.
  final wantCols = targetW >= cell + step * 0.42 ? 2 : 1;
  final wantRows = targetH >= cell + step * 0.42 ? 2 : 1;
  final desired = KitWidgetSize.fromDims(wantCols, wantRows) ?? current;
  if (supported.contains(desired)) return desired;
  // Pick closest supported size in Manhattan distance (w, h).
  var best = current;
  var bestDist = 999;
  for (final candidate in supported) {
    final dist = (candidate.w - wantCols).abs() + (candidate.h - wantRows).abs();
    if (dist < bestDist) {
      bestDist = dist;
      best = candidate;
    }
  }
  return best;
}

/// Shared widget registry supporting built-ins, plugin-registered widgets, and
/// user-created custom widgets.
class KitWidgetRegistry {
  KitWidgetRegistry() {
    for (final spec in builtins) {
      _specs[spec.id] = spec;
    }
  }

  static const List<KitWidgetSpec> builtins = <KitWidgetSpec>[
    KitWidgetSpec(
      id: 'calendar',
      title: 'Calendar',
      description: 'Today and monthly calendar grid',
      category: KitWidgetCategory.essentials,
      supportedSizes: <KitWidgetSize>[
        KitWidgetSize.small,
        KitWidgetSize.medium,
        KitWidgetSize.large,
      ],
      defaultSize: KitWidgetSize.medium,
    ),
    KitWidgetSpec(
      id: 'clock',
      title: 'Clock',
      description: 'Analog or digital local clock',
      category: KitWidgetCategory.essentials,
      supportedSizes: <KitWidgetSize>[
        KitWidgetSize.small,
        KitWidgetSize.medium,
        KitWidgetSize.large,
      ],
      defaultSize: KitWidgetSize.small,
    ),
    KitWidgetSpec(
      id: 'worldclock',
      title: 'World Clock',
      description: 'Multiple city dials with day/night faces',
      category: KitWidgetCategory.essentials,
      supportedSizes: <KitWidgetSize>[
        KitWidgetSize.small,
        KitWidgetSize.medium,
        KitWidgetSize.large,
      ],
      defaultSize: KitWidgetSize.medium,
    ),
    KitWidgetSpec(
      id: 'weather',
      title: 'Weather',
      description: 'Current conditions and forecast for your city',
      category: KitWidgetCategory.essentials,
      supportedSizes: <KitWidgetSize>[
        KitWidgetSize.small,
        KitWidgetSize.medium,
        KitWidgetSize.large,
      ],
      defaultSize: KitWidgetSize.medium,
    ),
    KitWidgetSpec(
      id: 'battery',
      title: 'Battery',
      description: 'Host and peripheral charge levels',
      category: KitWidgetCategory.system,
      supportedSizes: <KitWidgetSize>[
        KitWidgetSize.small,
        KitWidgetSize.medium,
        KitWidgetSize.large,
      ],
      defaultSize: KitWidgetSize.medium,
    ),
    KitWidgetSpec(
      id: 'cpu',
      title: 'System Monitor',
      description: 'CPU, memory, temperature and load',
      category: KitWidgetCategory.system,
      supportedSizes: <KitWidgetSize>[
        KitWidgetSize.small,
        KitWidgetSize.medium,
        KitWidgetSize.large,
      ],
      defaultSize: KitWidgetSize.medium,
    ),
    KitWidgetSpec(
      id: 'media',
      title: 'Now Playing',
      description: 'Playback artwork, controls and output switch',
      category: KitWidgetCategory.media,
      supportedSizes: <KitWidgetSize>[
        KitWidgetSize.medium,
        KitWidgetSize.large,
      ],
      defaultSize: KitWidgetSize.medium,
    ),
    KitWidgetSpec(
      id: 'timer',
      title: 'Timer',
      description: 'Quick countdown synced with Dynamic Island',
      category: KitWidgetCategory.productivity,
      supportedSizes: <KitWidgetSize>[
        KitWidgetSize.small,
        KitWidgetSize.medium,
      ],
      defaultSize: KitWidgetSize.medium,
    ),
    KitWidgetSpec(
      id: 'reminders',
      title: 'Reminders',
      description: 'Checkable local tasks and quick notes',
      category: KitWidgetCategory.productivity,
      supportedSizes: <KitWidgetSize>[
        KitWidgetSize.medium,
        KitWidgetSize.large,
      ],
      defaultSize: KitWidgetSize.medium,
    ),
    KitWidgetSpec(
      id: 'quickactions',
      title: 'Quick Actions',
      description: 'Fast toggles for theme, night light and capture',
      category: KitWidgetCategory.productivity,
      supportedSizes: <KitWidgetSize>[
        KitWidgetSize.small,
        KitWidgetSize.medium,
      ],
      defaultSize: KitWidgetSize.medium,
    ),
  ];

  final Map<String, KitWidgetSpec> _specs = <String, KitWidgetSpec>{};
  final List<void Function()> _listeners = <void Function()>[];

  void addListener(void Function() listener) => _listeners.add(listener);
  void removeListener(void Function() listener) => _listeners.remove(listener);

  void _notify() {
    for (final listener in List<void Function()>.of(_listeners)) {
      listener();
    }
  }

  List<KitWidgetSpec> get all => List<KitWidgetSpec>.unmodifiable(_specs.values);

  List<KitCustomWidgetDef> get customDefs => <KitCustomWidgetDef>[
    for (final spec in _specs.values)
      if (spec.custom != null) spec.custom!,
  ];

  KitWidgetSpec? byId(String id) => _specs[id];

  /// Registers a third-party/plugin widget spec.
  void register(KitWidgetSpec spec) {
    _specs[spec.id] = spec;
    _notify();
  }

  /// Registers or updates a user custom widget.
  void registerCustom(KitCustomWidgetDef def, {bool notify = true}) {
    _specs[def.id] = KitWidgetSpec(
      id: def.id,
      title: def.title,
      description: def.subtitle.isNotEmpty
          ? def.subtitle
          : switch (def.kind) {
              KitCustomWidgetKind.command => 'Command output card',
              KitCustomWidgetKind.shortcut => 'Quick launch shortcut',
              KitCustomWidgetKind.note => 'Sticky note card',
            },
      category: KitWidgetCategory.custom,
      supportedSizes: def.supportedSizes,
      defaultSize: def.defaultSize,
      custom: def,
    );
    if (notify) _notify();
  }

  void removeCustom(String id) {
    final existing = _specs[id];
    if (existing == null || !existing.isCustom) return;
    _specs.remove(id);
    _notify();
  }

  /// Loads persisted custom widget definitions from a JSON list.
  ///
  /// Pass `notify: false` during lazy startup hydration so listeners are not
  /// triggered synchronously inside a widget `build()`.
  void loadCustomJson(Object? raw, {bool notify = true}) {
    _specs.removeWhere((_, spec) => spec.isCustom);
    if (raw is List) {
      for (final item in raw) {
        final def = KitCustomWidgetDef.fromJson(item);
        if (def != null) registerCustom(def, notify: false);
      }
    }
    if (notify) _notify();
  }

  List<Map<String, Object?>> exportCustomJson() => <Map<String, Object?>>[
    for (final def in customDefs) def.toJson(),
  ];

  /// Generates a unique `custom.<slug>` id.
  String freshCustomId(String title) {
    final slug = title
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final base = slug.isEmpty ? 'widget' : slug;
    var candidate = 'custom.$base';
    var n = 2;
    while (_specs.containsKey(candidate)) {
      candidate = 'custom.${base}_$n';
      n++;
    }
    return candidate;
  }
}

/// Process-wide widget registry shared across Denial shell plugins.
final KitWidgetRegistry kitWidgetRegistry = KitWidgetRegistry();
