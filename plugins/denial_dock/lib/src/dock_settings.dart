import 'dart:convert';
import 'dart:io';

import 'dock_visibility.dart';

export 'dock_visibility.dart' show DockVisibility, DockVisibilityMode;

/// Where a dock accessory group sits relative to the application row.
enum DockSide {
  left,
  right,
  hidden;

  String get key => switch (this) {
    DockSide.left => 'left',
    DockSide.right => 'right',
    DockSide.hidden => 'hidden',
  };

  static DockSide parse(Object? value, {DockSide fallback = DockSide.right}) =>
      switch (value) {
        'left' => DockSide.left,
        'right' => DockSide.right,
        'hidden' => DockSide.hidden,
        _ => fallback,
      };
}

/// What a click on an application whose window is already in front does.
enum DockClickAction {
  /// Clicking the front-most application minimizes its active window, the
  /// macOS default.
  minimize,

  /// Clicking the front-most application focuses its next window, in stable
  /// window-list order.
  cycle;

  String get key => this == DockClickAction.cycle ? 'cycle' : 'minimize';

  static DockClickAction parse(
    Object? value, {
    DockClickAction fallback = DockClickAction.minimize,
  }) => value == 'cycle' ? DockClickAction.cycle : fallback;
}

enum DockPosition {
  left,
  bottom,
  right;

  String get key => switch (this) {
    DockPosition.left => 'left',
    DockPosition.bottom => 'bottom',
    DockPosition.right => 'right',
  };

  static DockPosition parse(
    Object? value, {
    DockPosition fallback = DockPosition.bottom,
  }) => switch (value) {
    'left' => DockPosition.left,
    'right' => DockPosition.right,
    _ => fallback,
  };
}

/// How application icons are painted.
enum DockIconMode {
  color,
  grayscale,
  tinted;

  String get key => switch (this) {
    DockIconMode.color => 'color',
    DockIconMode.grayscale => 'grayscale',
    DockIconMode.tinted => 'tinted',
  };

  static DockIconMode parse(
    Object? value, {
    DockIconMode fallback = DockIconMode.color,
  }) => switch (value) {
    'grayscale' => DockIconMode.grayscale,
    'tinted' => DockIconMode.tinted,
    _ => fallback,
  };
}

/// Icons and their identity are matched without the `.desktop` suffix and case.
String normalizeAppId(String id) =>
    id.trim().toLowerCase().replaceFirst(RegExp(r'\.desktop$'), '');

class DockPin {
  const DockPin({required this.id, required this.appId, required this.name});

  /// Opaque launch identity. [appId] is only the icon identity.
  final String id;
  final String appId;
  final String name;

  Map<String, String> toJson() => {'id': id, 'appId': appId, 'name': name};
}

/// A folder shortcut pinned to the accessory end of the dock.
class DockFolder {
  const DockFolder({required this.path, required this.label});

  final String path;
  final String label;

  Map<String, String> toJson() => {'path': path, 'label': label};

  static DockFolder? fromJson(Object? value) {
    if (value is! Map) return null;
    final path = value['path'];
    if (path is! String || !path.startsWith('/')) return null;
    final label = value['label'];
    return DockFolder(
      path: normalizeFolderPath(path),
      label: label is String && label.trim().isNotEmpty
          ? label.trim()
          : folderLabel(path),
    );
  }
}

/// Shortens `/home/me/Documents` style paths the way a file manager labels a
/// shortcut: the last segment, or the home directory itself.
String folderLabel(String path, {String homeLabel = 'Home', String? home}) {
  final normalized = normalizeFolderPath(path);
  final resolvedHome = home ?? Platform.environment['HOME'];
  if (resolvedHome != null && normalized == normalizeFolderPath(resolvedHome)) {
    return homeLabel;
  }
  final segments = normalized.split('/').where((part) => part.isNotEmpty);
  return segments.isEmpty ? normalized : segments.last;
}

/// Drops duplicate separators and a trailing slash so two spellings of the
/// same directory compare equal.
String normalizeFolderPath(String path) {
  final trimmed = path.trim();
  if (trimmed.isEmpty) return trimmed;
  final collapsed = trimmed.replaceAll(RegExp('/+'), '/');
  final withoutTrailing = collapsed.length > 1 && collapsed.endsWith('/')
      ? collapsed.substring(0, collapsed.length - 1)
      : collapsed;
  return withoutTrailing;
}

class DockSettings {
  const DockSettings({
    this.pinned = defaultPins,
    this.visibility = DockVisibilityMode.smart,
    this.clickAction = DockClickAction.minimize,
    this.iconSize = defaultIconSize,
    this.magnification = true,
    this.magnificationAmount = 0.6,
    this.position = DockPosition.bottom,
    this.iconMode = DockIconMode.color,
    this.revealIndicator = true,
    this.bounceOnLaunch = true,
    this.showIndicators = true,
    this.showSuggestions = true,
    this.launcherSide = DockSide.left,
    this.extrasSide = DockSide.right,
    this.showTrash = true,
    this.folders = const [],
  });

  /// Base icon edge before magnification.
  static const double defaultIconSize = 48.0;
  static const double minIconSize = 32.0;
  static const double maxIconSize = 72.0;
  static const double iconSizeStep = 4.0;
  static const double gap = 8.0;

  /// Cross-axis inset between the capsule edge and the icons. macOS keeps this
  /// small: the capsule is only a few pixels taller than the icon.
  static const double padding = 5.0;

  /// Inset at the two ends of the row, which is looser than the cross-axis
  /// padding in every reference dock.
  static const double edgePadding = 10.0;
  static const double minMagnificationAmount = 0.0;
  static const double maxMagnificationAmount = 1.0;
  static const double magnificationAmountStep = 0.1;
  static const double maxScale = 1.6;
  static const double magnificationRadius = 140.0;
  static const double liftRatio = 0.25;

  /// Release glide for a dragged icon; same 180ms ease as the reference dock's
  /// neighbour reorder.
  static const double dragSettleSeconds = 0.18;

  /// A fresh install starts with an empty dock; pin applications from their
  /// context menu. Shipping one machine's app set would render placeholders
  /// on every other machine.
  static const List<DockPin> defaultPins = [];

  static const DockSettings defaults = DockSettings();

  final List<DockPin> pinned;
  final DockVisibilityMode visibility;
  final DockClickAction clickAction;

  /// Base icon edge before magnification, clamped to the supported range.
  final double iconSize;

  final bool magnification;

  /// Extra scale at the pointer, as a fraction of [maxScale]'s headroom:
  /// 0 keeps icons at their base size, 1 is the full 1.6x peak.
  final double magnificationAmount;

  final DockPosition position;
  final DockIconMode iconMode;

  /// Draws a short bar on the dock's edge while it is retracted, so the hidden
  /// strip is still discoverable.
  final bool revealIndicator;

  final bool bounceOnLaunch;
  final bool showIndicators;
  final bool showSuggestions;

  final DockSide launcherSide;
  final DockSide extrasSide;
  final bool showTrash;
  final List<DockFolder> folders;

  /// Capsule height with no magnification.
  double get capsuleHeight => iconSize + padding * 2;

  bool get hasExtras => showTrash || folders.isNotEmpty;

  DockSettings copyWith({
    List<DockPin>? pinned,
    DockVisibilityMode? visibility,
    DockClickAction? clickAction,
    double? iconSize,
    bool? magnification,
    double? magnificationAmount,
    DockPosition? position,
    DockIconMode? iconMode,
    bool? revealIndicator,
    bool? bounceOnLaunch,
    bool? showIndicators,
    bool? showSuggestions,
    DockSide? launcherSide,
    DockSide? extrasSide,
    bool? showTrash,
    List<DockFolder>? folders,
  }) => DockSettings(
    pinned: pinned ?? this.pinned,
    visibility: visibility ?? this.visibility,
    clickAction: clickAction ?? this.clickAction,
    iconSize: clampIconSize(iconSize ?? this.iconSize),
    magnification: magnification ?? this.magnification,
    magnificationAmount: clampMagnification(
      magnificationAmount ?? this.magnificationAmount,
    ),
    position: position ?? this.position,
    iconMode: iconMode ?? this.iconMode,
    revealIndicator: revealIndicator ?? this.revealIndicator,
    bounceOnLaunch: bounceOnLaunch ?? this.bounceOnLaunch,
    showIndicators: showIndicators ?? this.showIndicators,
    showSuggestions: showSuggestions ?? this.showSuggestions,
    launcherSide: launcherSide ?? this.launcherSide,
    extrasSide: extrasSide ?? this.extrasSide,
    showTrash: showTrash ?? this.showTrash,
    folders: folders ?? this.folders,
  );

  static double clampIconSize(double value) {
    if (!value.isFinite) return defaultIconSize;
    return value.clamp(minIconSize, maxIconSize).toDouble();
  }

  static double clampMagnification(double value) {
    if (!value.isFinite) return 0.6;
    return value
        .clamp(minMagnificationAmount, maxMagnificationAmount)
        .toDouble();
  }

  double get effectiveMaxScale =>
      magnification ? 1.0 + (maxScale - 1.0) * magnificationAmount : 1.0;

  DockSettings withFolder(DockFolder folder) {
    final path = normalizeFolderPath(folder.path);
    if (path.isEmpty) return this;
    final without = folders
        .where((existing) => normalizeFolderPath(existing.path) != path)
        .toList();
    final label = folder.label.trim();
    return copyWith(
      folders: List.unmodifiable([
        ...without,
        DockFolder(
          path: path,
          label: label.isEmpty ? folderLabel(path) : label,
        ),
      ]),
    );
  }

  DockSettings withoutFolder(String path) {
    final key = normalizeFolderPath(path);
    return copyWith(
      folders: List.unmodifiable(
        folders.where((folder) => normalizeFolderPath(folder.path) != key),
      ),
    );
  }

  factory DockSettings.fromJson(Map<String, dynamic> json) {
    final stored = json['pinnedApplications'];
    final seen = <String>{};
    final pins = <DockPin>[];
    if (stored is List) {
      for (final entry in stored) {
        if (entry is! Map) continue;
        final id = entry['id'];
        final appId = entry['appId'];
        final name = entry['name'];
        if (id is! String ||
            id.isEmpty ||
            appId is! String ||
            appId.isEmpty ||
            name is! String ||
            !seen.add(normalizeAppId(appId))) {
          continue;
        }
        pins.add(DockPin(id: id, appId: appId, name: name));
      }
    }
    final storedFolders = json['folders'];
    final folders = <DockFolder>[];
    final seenFolders = <String>{};
    if (storedFolders is List) {
      for (final entry in storedFolders) {
        final folder = DockFolder.fromJson(entry);
        if (folder == null) continue;
        if (!seenFolders.add(normalizeFolderPath(folder.path))) continue;
        folders.add(folder);
      }
    }
    final iconSize = json['iconSize'];
    return DockSettings(
      // An explicit empty list means the user removed every pin.
      pinned: stored is List ? List.unmodifiable(pins) : defaultPins,
      visibility: DockVisibilityMode.parse(json['visibility']),
      clickAction: DockClickAction.parse(json['clickAction']),
      iconSize: clampIconSize(
        iconSize is num ? iconSize.toDouble() : defaultIconSize,
      ),
      magnification: json['magnification'] is bool
          ? json['magnification'] as bool
          : true,
      magnificationAmount: clampMagnification(
        json['magnificationAmount'] is num
            ? (json['magnificationAmount'] as num).toDouble()
            : 0.6,
      ),
      position: DockPosition.parse(json['position']),
      iconMode: DockIconMode.parse(json['iconMode']),
      revealIndicator: json['revealIndicator'] is bool
          ? json['revealIndicator'] as bool
          : true,
      bounceOnLaunch: json['bounceOnLaunch'] is bool
          ? json['bounceOnLaunch'] as bool
          : true,
      showIndicators: json['showIndicators'] is bool
          ? json['showIndicators'] as bool
          : true,
      showSuggestions: json['showSuggestions'] is bool
          ? json['showSuggestions'] as bool
          : true,
      launcherSide: DockSide.parse(
        json['launcherSide'],
        fallback: DockSide.left,
      ),
      extrasSide: DockSide.parse(json['extrasSide']),
      showTrash: json['showTrash'] is bool ? json['showTrash'] as bool : true,
      folders: List.unmodifiable(folders),
    );
  }
}

/// Atomic, plugin-owned preferences. Unknown keys survive an update and a
/// malformed file is surfaced instead of being silently replaced.
class DockPreferencesStore {
  DockPreferencesStore(this.file);

  final File file;
  int _sequence = 0;

  static File defaultFile() {
    final env = Platform.environment;
    final configured = env['XDG_CONFIG_HOME'];
    final home = env['HOME'];
    final root = configured != null && configured.startsWith('/')
        ? configured
        : home != null && home.startsWith('/')
        ? '$home/.config'
        : null;
    if (root == null) {
      throw const FileSystemException('No configuration directory');
    }
    return File('$root/denial/plugins/denial_dock.json');
  }

  Future<Map<String, dynamic>> _readJson() async {
    try {
      final value = jsonDecode(await file.readAsString());
      if (value is! Map<String, dynamic>) {
        throw const FormatException('Expected a JSON object');
      }
      return value;
    } on FileSystemException catch (error) {
      if (error.osError?.errorCode == 2) return {};
      rethrow;
    }
  }

  Future<DockSettings> read() async => DockSettings.fromJson(await _readJson());

  Future<void> write(DockSettings settings) async {
    final json = await _readJson();
    json['pinnedApplications'] = settings.pinned
        .map((pin) => pin.toJson())
        .toList();
    json['visibility'] = settings.visibility.key;
    json['clickAction'] = settings.clickAction.key;
    json['iconSize'] = settings.iconSize;
    json['magnification'] = settings.magnification;
    json['magnificationAmount'] = settings.magnificationAmount;
    json['position'] = settings.position.key;
    json['iconMode'] = settings.iconMode.key;
    json['revealIndicator'] = settings.revealIndicator;
    json['bounceOnLaunch'] = settings.bounceOnLaunch;
    json['showIndicators'] = settings.showIndicators;
    json['showSuggestions'] = settings.showSuggestions;
    json['launcherSide'] = settings.launcherSide.key;
    json['extrasSide'] = settings.extrasSide.key;
    json['showTrash'] = settings.showTrash;
    json['folders'] = settings.folders
        .map((folder) => folder.toJson())
        .toList();
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.$pid.${_sequence++}.tmp');
    try {
      await temp.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(json)}\n',
        flush: true,
      );
      await temp.rename(file.path);
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  }
}
