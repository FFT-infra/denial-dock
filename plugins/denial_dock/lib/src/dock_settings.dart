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

/// What a wheel turn over the dock does, as in Dash to Dock's scroll action.
enum DockScrollAction {
  nothing,

  /// Bring the next window of the application under the pointer forward.
  cycleWindows,

  /// Move to the neighbouring workspace.
  switchWorkspace;

  String get key => switch (this) {
    DockScrollAction.nothing => 'nothing',
    DockScrollAction.cycleWindows => 'cycle-windows',
    DockScrollAction.switchWorkspace => 'switch-workspace',
  };

  static DockScrollAction parse(
    Object? value, {
    DockScrollAction fallback = DockScrollAction.nothing,
  }) => switch (value) {
    'cycle-windows' => DockScrollAction.cycleWindows,
    'switch-workspace' => DockScrollAction.switchWorkspace,
    'nothing' => DockScrollAction.nothing,
    _ => fallback,
  };
}

/// How the running marker under an icon is drawn.
enum DockIndicatorStyle {
  /// One dot per window, up to three, as macOS does.
  dot,

  /// A single bar the width of the icon.
  line,

  none;

  String get key => switch (this) {
    DockIndicatorStyle.dot => 'dot',
    DockIndicatorStyle.line => 'line',
    DockIndicatorStyle.none => 'none',
  };

  static DockIndicatorStyle parse(
    Object? value, {
    DockIndicatorStyle fallback = DockIndicatorStyle.dot,
  }) => switch (value) {
    'dot' => DockIndicatorStyle.dot,
    'line' => DockIndicatorStyle.line,
    'none' => DockIndicatorStyle.none,
    _ => fallback,
  };
}

/// How an application icon answers a launch.
enum DockLaunchFeedback {
  /// The macOS hop.
  hop,

  /// A slow opacity pulse, as Omarchy's dock does while an app starts.
  pulse,

  none;

  String get key => switch (this) {
    DockLaunchFeedback.hop => 'hop',
    DockLaunchFeedback.pulse => 'pulse',
    DockLaunchFeedback.none => 'none',
  };

  static DockLaunchFeedback parse(
    Object? value, {
    DockLaunchFeedback fallback = DockLaunchFeedback.hop,
  }) => switch (value) {
    'hop' => DockLaunchFeedback.hop,
    'pulse' => DockLaunchFeedback.pulse,
    'none' => DockLaunchFeedback.none,
    _ => fallback,
  };
}

/// Geometry of the window-preview popup. Named for the layout rather than the
/// desktop that popularised it.
enum DockPreviewStyle {
  /// A horizontal tray of cards above the dock.
  cards,

  /// A vertical stack of rows that follows the pointer along the dock.
  stack;

  String get key => this == DockPreviewStyle.stack ? 'stack' : 'cards';

  static DockPreviewStyle parse(
    Object? value, {
    DockPreviewStyle fallback = DockPreviewStyle.cards,
  }) => value == 'stack' ? DockPreviewStyle.stack : fallback;
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

/// Which icon language the dock's own items speak.
///
/// [macos] draws a stacked folder, a wire trash can and a Launchpad grid, the
/// shapes the reference screenshot shows. [denial] keeps the accent-tinted
/// rounded tile the dock shipped with, so the old look stays one setting away.
enum DockAppearance {
  macos,
  denial;

  String get key => this == DockAppearance.denial ? 'denial' : 'macos';

  static DockAppearance parse(
    Object? value, {
    DockAppearance fallback = DockAppearance.macos,
  }) => value == 'denial' ? DockAppearance.denial : fallback;
}

/// Tinted-mode colours are stored as lowercase `#rrggbb`; anything else means
/// the shell accent.
String? normalizeTintColor(Object? value) {
  if (value is! String) return null;
  final text = value.trim().toLowerCase();
  return RegExp(r'^#[0-9a-f]{6}$').hasMatch(text) ? text : null;
}

/// Icons and their identity are matched without the `.desktop` suffix and case.
String normalizeAppId(String id) =>
    id.trim().toLowerCase().replaceFirst(RegExp(r'\.desktop$'), '');

/// A launcher recent entry as `desktop:org.example.App.desktop`, and a pin's
/// launch identity the same way. Both reduce to the icon identity, which is
/// what the dock keys everything by: leaving the prefix on would make the same
/// application two slots, one for its window and one for its launch record.
String appIdentity(String id) {
  final text = id.trim();
  final colon = text.indexOf(':');
  return normalizeAppId(colon >= 0 ? text.substring(colon + 1) : text);
}

/// A stored list of app ids, normalised and de-duplicated, in stored order.
List<String> _identityList(Object? value) {
  final ids = <String>[];
  if (value is! List) return ids;
  for (final entry in value) {
    if (entry is! String || entry.trim().isEmpty) continue;
    final key = appIdentity(entry);
    if (ids.contains(key)) continue;
    ids.add(key);
  }
  return ids;
}

class DockPin {
  const DockPin({required this.id, required this.appId, required this.name});

  /// Opaque launch identity. [appId] is only the icon identity.
  final String id;
  final String appId;
  final String name;

  Map<String, String> toJson() => {'id': id, 'appId': appId, 'name': name};
}

/// How a folder stack opens. `auto` follows Finder: a fan while the folder fits
/// one column, a grid once it would run off the screen.
enum DockStackMode { auto, fan, grid, list }

extension DockStackModeKey on DockStackMode {
  String get key => switch (this) {
    DockStackMode.auto => 'auto',
    DockStackMode.fan => 'fan',
    DockStackMode.grid => 'grid',
    DockStackMode.list => 'list',
  };

  static DockStackMode parse(Object? value) => switch (value) {
    'fan' => DockStackMode.fan,
    'grid' => DockStackMode.grid,
    'list' => DockStackMode.list,
    _ => DockStackMode.auto,
  };
}

/// The order a folder stack lists its files in, matching Finder's Stack menu.
/// `manual` is the order the user dragged into place.
enum DockStackSortMode { added, modified, name, kind, manual }

extension DockStackSortModeKey on DockStackSortMode {
  String get key => switch (this) {
    DockStackSortMode.added => 'added',
    DockStackSortMode.modified => 'modified',
    DockStackSortMode.name => 'name',
    DockStackSortMode.kind => 'kind',
    DockStackSortMode.manual => 'manual',
  };

  static DockStackSortMode parse(Object? value) => switch (value) {
    'modified' => DockStackSortMode.modified,
    'name' => DockStackSortMode.name,
    'kind' => DockStackSortMode.kind,
    'manual' => DockStackSortMode.manual,
    _ => DockStackSortMode.added,
  };
}

/// A single file pinned to the accessory end of the dock, the way macOS lets
/// you drag one file out of a stack and keep it there.
class DockFile {
  const DockFile({required this.path, required this.label});

  final String path;
  final String label;

  Map<String, Object> toJson() => {'path': path, 'label': label};

  static DockFile? fromJson(Object? value) {
    if (value is! Map) return null;
    final path = value['path'];
    if (path is! String || !path.startsWith('/')) return null;
    final label = value['label'];
    return DockFile(
      path: path,
      label: label is String && label.trim().isNotEmpty
          ? label.trim()
          : folderLabel(path),
    );
  }
}

/// A folder shortcut pinned to the accessory end of the dock.
class DockFolder {
  const DockFolder({
    required this.path,
    required this.label,
    this.view = DockStackMode.auto,
    this.sort = DockStackSortMode.added,
    this.order = const [],
    this.stacked = true,
  });

  final String path;
  final String label;
  final DockStackMode view;
  final DockStackSortMode sort;

  /// File names in the order the user dragged them, used by [sort] `manual`.
  /// Names rather than paths so a folder that moves on disk keeps its order.
  final List<String> order;

  /// Whether the icon shows a pile of the newest files or a plain folder.
  final bool stacked;

  Map<String, Object> toJson() => {
    'path': path,
    'label': label,
    'view': view.key,
    'sort': sort.key,
    if (order.isNotEmpty) 'order': order,
    if (!stacked) 'stacked': false,
  };

  static DockFolder? fromJson(Object? value) {
    if (value is! Map) return null;
    final path = value['path'];
    if (path is! String || !path.startsWith('/')) return null;
    final label = value['label'];
    final order = value['order'];
    return DockFolder(
      path: normalizeFolderPath(path),
      label: label is String && label.trim().isNotEmpty
          ? label.trim()
          : folderLabel(path),
      view: DockStackModeKey.parse(value['view']),
      sort: DockStackSortModeKey.parse(value['sort']),
      order: order is List
          ? List.unmodifiable(order.whereType<String>())
          : const [],
      stacked: value['stacked'] != false,
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
    this.appearance = DockAppearance.macos,
    this.iconOpacity = 1.0,
    this.tintColor,
    this.revealIndicator = true,
    this.launchFeedback = DockLaunchFeedback.hop,
    this.indicatorStyle = DockIndicatorStyle.dot,
    this.previewStyle = DockPreviewStyle.cards,
    this.dimInactivePinned = false,
    this.hoverFocusPreview = true,
    this.showBadges = true,
    this.showSuggestions = true,
    this.scrollAction = DockScrollAction.nothing,
    this.scrollReversed = false,
    this.scrollWraps = false,
    this.launcherSide = DockSide.left,
    this.extrasSide = DockSide.right,
    this.showTrash = true,
    this.folders = const [],
    this.files = const [],
    this.dismissedSuggestions = const [],
    this.recentCount = defaultRecentCount,
    this.recentsOrder = const [],
    this.parkedRecents = const [],
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
  static const double minIconOpacity = 0.1;
  static const double iconOpacityStep = 0.1;

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

  /// The icon language for the dock's own items (stack, trash, launcher).
  final DockAppearance appearance;

  /// Opacity of the filtered icon modes; colour icons always draw at full
  /// strength.
  final double iconOpacity;

  /// Tinted-mode colour as `#rrggbb`; null follows the shell accent.
  final String? tintColor;

  /// Draws a short bar on the dock's edge while it is retracted, so the hidden
  /// strip is still discoverable.
  final bool revealIndicator;

  final DockLaunchFeedback launchFeedback;
  final DockIndicatorStyle indicatorStyle;
  final DockPreviewStyle previewStyle;

  /// Fades a pinned application that has no window, so the running ones read
  /// first. Omarchy's dock does this; macOS and Dash to Dock do not.
  final bool dimInactivePinned;

  /// Focuses a window as the pointer reaches its preview, in either preview
  /// style. On by default, as in Omarchy's dock; turning it off keeps the
  /// pointer from moving focus while the previews are open.
  final bool hoverFocusPreview;

  /// Counts unread notifications on the application's icon.
  final bool showBadges;

  final bool showSuggestions;

  final DockScrollAction scrollAction;

  /// Inverts the wheel's direction, for a natural-scroll mouse.
  final bool scrollReversed;

  /// Steps from the last workspace round to the first and back.
  final bool scrollWraps;

  final DockSide launcherSide;
  final DockSide extrasSide;
  final bool showTrash;
  final List<DockFolder> folders;

  /// Single files pinned to the dock, in dock order. A file sits beside the
  /// folders and opens in whatever handles it.
  final List<DockFile> files;

  /// Normalized application ids the user dragged out of the suggestions. The
  /// launcher still records them as recent, so the dock filters them here
  /// rather than asking the host to forget the launch.
  final List<String> dismissedSuggestions;

  /// How many suggestions the dock shows. macOS keeps three closed apps in its
  /// recent section and exposes the number as `show-recent-count`; the range
  /// here is wider because a dock this large can hold more.
  final int recentCount;

  /// The unpinned section itself, oldest first. An id keeps its position after
  /// its app quits, which is what stops one launch from shifting every
  /// neighbour.
  final List<String> recentsOrder;

  /// Ids the section dropped, oldest first, so a smaller count or a hidden
  /// section does not throw the history away.
  final List<String> parkedRecents;

  static const int defaultRecentCount = 3;
  static const int minRecentCount = 0;
  static const int maxRecentCount = 8;

  static int clampRecentCount(int value) =>
      value.clamp(minRecentCount, maxRecentCount);

  /// Capsule height with no magnification.
  double get capsuleHeight => iconSize + padding * 2;

  bool get hasExtras => showTrash || folders.isNotEmpty || files.isNotEmpty;

  DockSettings copyWith({
    List<DockPin>? pinned,
    DockVisibilityMode? visibility,
    DockClickAction? clickAction,
    double? iconSize,
    bool? magnification,
    double? magnificationAmount,
    DockPosition? position,
    DockIconMode? iconMode,
    DockAppearance? appearance,
    double? iconOpacity,
    String? tintColor,
    bool clearTint = false,
    bool? revealIndicator,
    DockLaunchFeedback? launchFeedback,
    DockIndicatorStyle? indicatorStyle,
    DockPreviewStyle? previewStyle,
    bool? dimInactivePinned,
    bool? hoverFocusPreview,
    bool? showBadges,
    bool? showSuggestions,
    DockScrollAction? scrollAction,
    bool? scrollReversed,
    bool? scrollWraps,
    DockSide? launcherSide,
    DockSide? extrasSide,
    bool? showTrash,
    List<DockFolder>? folders,
    List<DockFile>? files,
    List<String>? dismissedSuggestions,
    int? recentCount,
    List<String>? recentsOrder,
    List<String>? parkedRecents,
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
    appearance: appearance ?? this.appearance,
    iconOpacity: clampIconOpacity(iconOpacity ?? this.iconOpacity),
    tintColor: clearTint ? null : (tintColor ?? this.tintColor),
    revealIndicator: revealIndicator ?? this.revealIndicator,
    launchFeedback: launchFeedback ?? this.launchFeedback,
    indicatorStyle: indicatorStyle ?? this.indicatorStyle,
    previewStyle: previewStyle ?? this.previewStyle,
    dimInactivePinned: dimInactivePinned ?? this.dimInactivePinned,
    hoverFocusPreview: hoverFocusPreview ?? this.hoverFocusPreview,
    showBadges: showBadges ?? this.showBadges,
    showSuggestions: showSuggestions ?? this.showSuggestions,
    scrollAction: scrollAction ?? this.scrollAction,
    scrollReversed: scrollReversed ?? this.scrollReversed,
    scrollWraps: scrollWraps ?? this.scrollWraps,
    launcherSide: launcherSide ?? this.launcherSide,
    extrasSide: extrasSide ?? this.extrasSide,
    showTrash: showTrash ?? this.showTrash,
    folders: folders ?? this.folders,
    files: files ?? this.files,
    dismissedSuggestions: dismissedSuggestions ?? this.dismissedSuggestions,
    recentCount: clampRecentCount(recentCount ?? this.recentCount),
    recentsOrder: recentsOrder ?? this.recentsOrder,
    parkedRecents: parkedRecents ?? this.parkedRecents,
  );

  static double clampIconSize(double value) {
    if (!value.isFinite) return defaultIconSize;
    return value.clamp(minIconSize, maxIconSize).toDouble();
  }

  static double clampIconOpacity(double value) {
    if (!value.isFinite) return 1.0;
    return value.clamp(minIconOpacity, 1.0).toDouble();
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
          view: folder.view,
          sort: folder.sort,
          order: folder.order,
          stacked: folder.stacked,
        ),
      ]),
    );
  }

  /// Changes how one folder opens, leaving the others alone.
  DockSettings withFolderStack(
    String path, {
    DockStackMode? view,
    DockStackSortMode? sort,
    List<String>? order,
    bool? stacked,
  }) {
    final key = normalizeFolderPath(path);
    return copyWith(
      folders: List.unmodifiable([
        for (final folder in folders)
          if (normalizeFolderPath(folder.path) != key)
            folder
          else
            DockFolder(
              path: folder.path,
              label: folder.label,
              view: view ?? folder.view,
              sort: sort ?? folder.sort,
              order: order ?? folder.order,
              stacked: stacked ?? folder.stacked,
            ),
      ]),
    );
  }

  /// Adds or replaces a pinned file, keeping the others in place.
  DockSettings withFile(DockFile file) {
    final path = normalizeFolderPath(file.path);
    if (path.isEmpty) return this;
    final without = files.where((existing) => existing.path != path).toList();
    final label = file.label.trim();
    return copyWith(
      files: List.unmodifiable([
        ...without,
        DockFile(path: path, label: label.isEmpty ? folderLabel(path) : label),
      ]),
    );
  }

  DockSettings withoutFile(String path) => copyWith(
    files: List.unmodifiable(files.where((file) => file.path != path)),
  );

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
    final storedFiles = json['files'];
    final files = <DockFile>[];
    final seenFiles = <String>{};
    if (storedFiles is List) {
      for (final entry in storedFiles) {
        final file = DockFile.fromJson(entry);
        if (file == null) continue;
        if (!seenFiles.add(file.path)) continue;
        files.add(file);
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
    final storedDismissed = json['dismissedSuggestions'];
    final dismissed = <String>[];
    if (storedDismissed is List) {
      for (final entry in storedDismissed) {
        if (entry is! String || entry.trim().isEmpty) continue;
        final key = appIdentity(entry);
        if (dismissed.contains(key)) continue;
        dismissed.add(key);
      }
    }
    final order = _identityList(json['recentsOrder']);
    final parked = [
      for (final id in _identityList(json['parkedRecents']))
        if (!order.contains(id)) id,
    ];
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
      appearance: DockAppearance.parse(json['appearance']),
      iconOpacity: clampIconOpacity(
        json['iconOpacity'] is num
            ? (json['iconOpacity'] as num).toDouble()
            : 1.0,
      ),
      tintColor: normalizeTintColor(json['tintColor']),
      revealIndicator: json['revealIndicator'] is bool
          ? json['revealIndicator'] as bool
          : true,
      launchFeedback: DockLaunchFeedback.parse(
        json['launchFeedback'] ??
            (json['bounceOnLaunch'] is bool
                ? (json['bounceOnLaunch'] as bool ? 'hop' : 'none')
                : null),
      ),
      indicatorStyle: DockIndicatorStyle.parse(
        json['indicatorStyle'] ??
            (json['showIndicators'] is bool
                ? (json['showIndicators'] as bool ? 'dot' : 'none')
                : null),
      ),
      previewStyle: DockPreviewStyle.parse(json['previewStyle']),
      dimInactivePinned: json['dimInactivePinned'] is bool
          ? json['dimInactivePinned'] as bool
          : false,
      hoverFocusPreview: json['hoverFocusPreview'] is bool
          ? json['hoverFocusPreview'] as bool
          : true,
      showBadges: json['showBadges'] is bool
          ? json['showBadges'] as bool
          : true,
      showSuggestions: json['showSuggestions'] is bool
          ? json['showSuggestions'] as bool
          : true,
      scrollAction: DockScrollAction.parse(json['scrollAction']),
      scrollReversed: json['scrollReversed'] is bool
          ? json['scrollReversed'] as bool
          : false,
      scrollWraps: json['scrollWraps'] is bool
          ? json['scrollWraps'] as bool
          : false,
      launcherSide: DockSide.parse(
        json['launcherSide'],
        fallback: DockSide.left,
      ),
      extrasSide: DockSide.parse(json['extrasSide']),
      showTrash: json['showTrash'] is bool ? json['showTrash'] as bool : true,
      folders: List.unmodifiable(folders),
      files: List.unmodifiable(files),
      dismissedSuggestions: List.unmodifiable(dismissed),
      recentCount: clampRecentCount(
        json['recentCount'] is num
            ? (json['recentCount'] as num).toInt()
            : defaultRecentCount,
      ),
      recentsOrder: List.unmodifiable(order),
      parkedRecents: List.unmodifiable(parked),
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
    json['appearance'] = settings.appearance.key;
    json['iconOpacity'] = settings.iconOpacity;
    if (settings.tintColor case final tint?) {
      json['tintColor'] = tint;
    } else {
      json.remove('tintColor');
    }
    json['revealIndicator'] = settings.revealIndicator;
    json['launchFeedback'] = settings.launchFeedback.key;
    json['indicatorStyle'] = settings.indicatorStyle.key;
    json['previewStyle'] = settings.previewStyle.key;
    json['dimInactivePinned'] = settings.dimInactivePinned;
    json['hoverFocusPreview'] = settings.hoverFocusPreview;
    json.remove('bounceOnLaunch');
    json.remove('showIndicators');
    json['showBadges'] = settings.showBadges;
    json['showSuggestions'] = settings.showSuggestions;
    json['scrollAction'] = settings.scrollAction.key;
    json['scrollReversed'] = settings.scrollReversed;
    json['scrollWraps'] = settings.scrollWraps;
    json['launcherSide'] = settings.launcherSide.key;
    json['extrasSide'] = settings.extrasSide.key;
    json['showTrash'] = settings.showTrash;
    json['folders'] = settings.folders
        .map((folder) => folder.toJson())
        .toList();
    json['files'] = settings.files.map((file) => file.toJson()).toList();
    if (settings.dismissedSuggestions.isEmpty) {
      json.remove('dismissedSuggestions');
    } else {
      json['dismissedSuggestions'] = settings.dismissedSuggestions;
    }
    json['recentCount'] = settings.recentCount;
    if (settings.recentsOrder.isEmpty) {
      json.remove('recentsOrder');
    } else {
      json['recentsOrder'] = settings.recentsOrder;
    }
    if (settings.parkedRecents.isEmpty) {
      json.remove('parkedRecents');
    } else {
      json['parkedRecents'] = settings.parkedRecents;
    }
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
