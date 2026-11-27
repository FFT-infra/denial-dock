import 'dart:convert';
import 'dart:io';

import 'bar_zones.dart';

export 'bar_zones.dart';

/// Where the workspace switcher lives.
///
/// macOS has no workspace switcher in its menu bar, so this is an addition.
/// The island is the default because it keeps the bar's three clusters intact;
/// the other placements are fallbacks for people who turn the island off.
enum BarWorkspacePlacement {
  island,
  leading,
  trailing,
  hidden;

  String get key => name;

  static BarWorkspacePlacement parse(
    Object? value, {
    BarWorkspacePlacement fallback = BarWorkspacePlacement.island,
  }) => switch (value) {
    'island' => BarWorkspacePlacement.island,
    'leading' => BarWorkspacePlacement.leading,
    'trailing' => BarWorkspacePlacement.trailing,
    'hidden' => BarWorkspacePlacement.hidden,
    _ => fallback,
  };
}

/// Ground behind the bar.
///
/// macOS ships the menu bar with no background and only offers an optional
/// wallpaper-tinted plate. `plate` reproduces that plate, `glass` uses the
/// compositor's backdrop blur, and `none` keeps the type straight on the
/// wallpaper.
enum BarGround {
  none,
  plate,
  glass;

  String get key => name;

  static BarGround parse(
    Object? value, {
    BarGround fallback = BarGround.none,
  }) => switch (value) {
    'none' => BarGround.none,
    'plate' => BarGround.plate,
    'glass' => BarGround.glass,
    _ => fallback,
  };
}

/// Whether the bar is attached to the edge or floats as a capsule.
enum BarLayout {
  attached,
  floating;

  String get key => name;

  static BarLayout parse(
    Object? value, {
    BarLayout fallback = BarLayout.attached,
  }) => switch (value) {
    'floating' => BarLayout.floating,
    _ => BarLayout.attached,
  };
}

/// The outline of the bar.
enum BarShape {
  /// Edge to edge along the screen.
  strip,

  /// One capsule, clear of the screen edge.
  floating,

  /// A plate of its own under every zone, with the wallpaper between them.
  islands;

  String get key => name;

  /// Null when [value] names no shape, so a file from before shapes falls
  /// back to its layout.
  static BarShape? parse(Object? value) => switch (value) {
    'strip' => BarShape.strip,
    'floating' => BarShape.floating,
    'islands' => BarShape.islands,
    _ => null,
  };
}

/// How a plate ends.
enum BarCap {
  round,
  square,

  /// Pointed; separators inside a zone become points too.
  arrow;

  String get key => name;

  static BarCap parse(Object? value) => switch (value) {
    'square' => BarCap.square,
    'arrow' => BarCap.arrow,
    _ => BarCap.round,
  };
}

/// Where the plate takes its colour from.
enum BarGroundTint {
  /// The neutral that matches the wallpaper's lightness.
  wallpaper,

  /// The theme's panel colour.
  panel,

  /// The wallpaper's neutral with the accent washed in.
  accent;

  String get key => name;

  static BarGroundTint parse(Object? value) => switch (value) {
    'panel' => BarGroundTint.panel,
    'accent' => BarGroundTint.accent,
    _ => BarGroundTint.wallpaper,
  };
}

enum BarBorderColour {
  /// A faint line in the bar's ink.
  ink,
  accent;

  String get key => name;

  static BarBorderColour parse(Object? value) =>
      value == 'accent' ? BarBorderColour.accent : BarBorderColour.ink;
}

/// The bar's adjustable measures: the least and most each may be, and what
/// it is until changed. Every default is what the bar measured before the
/// setting existed.
abstract final class BarMetric {
  static const int islandFadeDelayMsMin = 200;
  static const int islandFadeDelayMsMax = 2000;
  static const int islandFadeDelayMs = 600;

  static const int islandLongPressMsMin = 150;
  static const int islandLongPressMsMax = 600;
  static const int islandLongPressMs = 280;

  /// The resting island's width, as a percentage of what the look gives it.
  static const int islandWidthMin = 60;
  static const int islandWidthMax = 220;
  static const int islandWidth = 100;

  /// The sets of timers the island's home card can offer, in minutes.
  static const List<List<int>> islandTimerSets = <List<int>>[
    <int>[1, 3, 5],
    <int>[5, 15, 25],
    <int>[10, 20, 30],
    <int>[25, 50, 90],
  ];

  static const double textScaleMin = 0.8;
  static const double textScaleMax = 1.4;
  static const double textScale = 1;

  static const double partGapMin = 0;
  static const double partGapMax = 16;
  static const double partGap = 6;

  static const double edgeMarginMin = 0;
  static const double edgeMarginMax = 16;
  static const double edgeMargin = 6;

  static const double endInsetMin = 0;
  static const double endInsetMax = 48;

  static const double contentPaddingMin = 0;
  static const double contentPaddingMax = 24;
  static const double contentPadding = 0;

  static const double cornerRadiusMin = 0;
  static const double cornerRadiusMax = 20;
  static const double cornerRadius = 14;

  static const double borderWidthMin = 0;
  static const double borderWidthMax = 3;
  static const double hairline = 0.8;

  static const double opacityMin = 0.05;
  static const double opacityMax = 1;
  static const double opacity = 0.55;
}

enum BarWorkspaceStyle { dots, numbers }

/// How collected system-tray icons are presented.
enum BarTrayFold {
  /// Slides folded icons out behind a chevron button in the bar.
  inline,

  /// Reveals folded icons inline when the pointer rests over the handle.
  hover,

  /// Opens folded icons inside a compact grid popover under a tray button.
  popover,

  /// Opens folded icons in one horizontal floating capsule row (Ice-bar style).
  floatingBar,

  /// Moves folded icons out of the bar and into Control Centre.
  controlCenter;

  String get key => name;

  static BarTrayFold parse(
    Object? value, {
    BarTrayFold fallback = BarTrayFold.inline,
  }) => switch (value) {
    'hover' => BarTrayFold.hover,
    'popover' => BarTrayFold.popover,
    'floatingBar' => BarTrayFold.floatingBar,
    'controlCenter' => BarTrayFold.controlCenter,
    'inline' => BarTrayFold.inline,
    _ => fallback,
  };
}

/// Splits [trayIds] into icons that stay directly on the bar (`visible`)
/// and icons gathered into the collection target (`folded`).
({List<String> visible, List<String> folded}) partitionTrayIds(
  List<String> trayIds, {
  required BarSettings settings,
  required String Function(String id) resolveKey,
}) {
  bool listed(List<String> keys, String id) =>
      keys.contains(resolveKey(id)) || keys.contains(id);
  final tucked = <String>[
    for (final id in trayIds)
      if (listed(settings.trayHidden, id) && !listed(settings.trayNever, id)) id,
  ];
  final shown = <String>[
    for (final id in trayIds)
      if (!listed(settings.trayNever, id) && !tucked.contains(id)) id,
  ];
  if (tucked.isNotEmpty) {
    return (visible: shown, folded: tucked);
  }
  if (settings.collapseItems) {
    return (visible: const <String>[], folded: shown);
  }
  return (visible: shown, folded: const <String>[]);
}

const List<String> defaultControls = <String>[
  'wifi',
  'media',
  'bluetooth',
  'focus',
  'dark',
  'night',
  'screenshot',
  'power',
  'recording',
  'display',
  'sound',
];

const List<String> defaultWidgets = <String>['calendar', 'worldclock'];

const List<String> defaultStatusOrder = barStatusItems;

const Object _keep = Object();

const int barAutoHideDelayMin = 0;
const int barAutoHideDelayMax = 600;
const int barAutoHideDelayDefault = 120;

int clampAutoHideDelay(Object? value) => value is num
    ? value.round().clamp(barAutoHideDelayMin, barAutoHideDelayMax)
    : barAutoHideDelayDefault;

class BarSettings {
  const BarSettings({
    this.shape = BarShape.strip,
    this.cap = BarCap.round,
    this.ground = BarGround.none,
    this.groundOpacity = BarMetric.opacity,
    this.groundTint = BarGroundTint.wallpaper,
    this.borderWidth = 0,
    this.borderColour = BarBorderColour.ink,
    this.textScale = BarMetric.textScale,
    this.partGap = BarMetric.partGap,
    this.edgeMargin = BarMetric.edgeMargin,
    this.endInset,
    this.contentPadding = BarMetric.contentPadding,
    this.cornerRadius = BarMetric.cornerRadius,
    this.islandEnabled = true,
    this.islandHoverPeek = true,
    this.islandHoverFade = false,
    this.islandNoticeSeconds = 5,
    this.islandFadeDelayMs = BarMetric.islandFadeDelayMs,
    this.islandLongPressMs = BarMetric.islandLongPressMs,
    this.islandWidth = BarMetric.islandWidth,
    this.islandTimerSet = 1,
    this.activityMedia = true,
    this.activityCharging = true,
    this.activityNotifications = true,
    this.workspacePlacement = BarWorkspacePlacement.island,
    this.showSystemMenu = true,
    this.showAppMenu = true,
    this.showClockDate = true,
    this.showTray = true,
    this.showWifi = true,
    this.showVolume = true,
    this.showBattery = true,
    this.showBatteryPercent = false,
    this.showNotifications = true,
    this.showControlCenter = true,
    this.showSettingsButton = false,
    this.autoHide = false,
    this.autoHideDelayMs = barAutoHideDelayDefault,
    this.recentsClearedAt = 0,
    this.trayColour = false,
    this.mergedNotificationCenter = true,
    this.collapseItems = false,
    this.collapseAutoSeconds = 15,
    this.trayFold = BarTrayFold.inline,
    this.showBluetooth = true,
    this.showKeyboard = true,
    this.showSearch = true,
    this.showClipboard = false,
    this.activityHud = true,
    this.workspaceScroll = true,
    this.workspacePreview = true,
    this.overviewShowMinimised = true,
    this.overviewMiddleClickCloses = true,
    this.overviewLiveOtherWorkspaces = true,
    this.overviewLiveLimit = 6,
    this.clockWeekday = true,
    this.workspaceStyle = BarWorkspaceStyle.dots,
    this.activityRecording = true,
    this.activityStatus = true,
    this.activityTimer = true,
    this.activityProgress = true,
    this.islandSplit = true,
    this.islandSwipe = true,
    this.islandHome = true,
    this.showRecording = true,
    this.showMic = true,
    this.tooltips = true,
    this.recentPlaces = true,
    this.trayHidden = const <String>[],
    this.trayNever = const <String>[],
    this.tileSizes = const <String>[],
    this.controls = defaultControls,
    this.widgets = defaultWidgets,
    this.statusOrder = defaultStatusOrder,
    this.explicitZones,
  });

  static const BarSettings defaults = BarSettings();

  final BarShape shape;

  /// How a plate ends; a strip has no ends to shape.
  final BarCap cap;

  /// The setting shapes replaced, for builds that know only it.
  BarLayout get layout =>
      shape == BarShape.strip ? BarLayout.attached : BarLayout.floating;

  /// Plate opacity. XMacTahoe's Golden Gate preset sits at 55; a bar may now
  /// be fully opaque.
  final BarGround ground;
  final double groundOpacity;
  final BarGroundTint groundTint;

  /// The line around a plate, 0 for none.
  final double borderWidth;
  final BarBorderColour borderColour;
  bool get hairline => borderWidth > 0;

  /// Scales the type in the bar.
  final double textScale;

  /// Room between two parts.
  final double partGap;

  /// Room between a floating bar and the screen edge it sits on.
  final double edgeMargin;

  /// Room between the bar's two ends and the screen's sides. Null keeps the
  /// measures each shape had before this could be set.
  final double? endInset;

  /// Room between a plate's ends and its content.
  final double contentPadding;

  /// Corner radius of a floating plate with round caps.
  final double cornerRadius;

  final bool islandEnabled;
  final bool islandHoverPeek;

  /// The compact island fades away under a resting pointer, to show what
  /// it covers; a click still opens it.
  final bool islandHoverFade;

  /// How long a notice or a track change keeps the island open, in seconds.
  final int islandNoticeSeconds;

  /// How long the pointer rests on the compact island before it fades away,
  /// where fading under the pointer is on.
  final int islandFadeDelayMs;

  /// How long a press is held before it opens the island.
  final int islandLongPressMs;

  /// The resting island's width, as a percentage of the look's own.
  final int islandWidth;

  /// Which of [BarMetric.islandTimerSets] the home card offers.
  final int islandTimerSet;

  List<int> get islandTimers => BarMetric.islandTimerSets[islandTimerSet];

  final bool activityMedia;
  final bool activityCharging;
  final bool activityNotifications;

  final BarWorkspacePlacement workspacePlacement;

  final bool showSystemMenu;
  final bool showAppMenu;
  final bool showClockDate;
  final bool showTray;
  final bool showWifi;
  final bool showVolume;
  final bool showBattery;
  final bool showBatteryPercent;
  final bool showNotifications;
  final bool showControlCenter;
  final bool showSettingsButton;

  final bool autoHide;
  final int autoHideDelayMs;

  /// Recent Items older than this (ms since epoch) stay out of the menu.
  final int recentsClearedAt;

  /// Tray icons keep their own colours instead of the bar's single ink.
  final bool trayColour;

  /// The clock opens notifications and widgets as one column.
  final bool mergedNotificationCenter;

  /// Tray items fold behind a handle; 0 seconds keeps them open until the
  /// handle is pressed again.
  final bool collapseItems;
  final int collapseAutoSeconds;
  final BarTrayFold trayFold;

  /// The collection style the bar acts on. Icons sent to Control Centre need
  /// its button in the bar; without it they open in a grid of their own, so
  /// no choice of settings leaves them out of reach.
  BarTrayFold get trayFoldInForce =>
      trayFold == BarTrayFold.controlCenter && !showControlCenter
      ? BarTrayFold.popover
      : trayFold;
  final bool showBluetooth;
  final bool showKeyboard;
  final bool showSearch;

  /// Keeps the texts copied this session and shows them from a bar item.
  final bool showClipboard;
  final bool activityHud;
  final bool workspaceScroll;
  final bool workspacePreview;

  /// Overview window layout and behaviour preferences.
  final bool overviewShowMinimised;
  final bool overviewMiddleClickCloses;
  final bool overviewLiveOtherWorkspaces;
  final int overviewLiveLimit;
  final bool clockWeekday;
  final BarWorkspaceStyle workspaceStyle;

  /// Island activities beyond playback: screen recording, one-line status
  /// changes (Bluetooth, Wi-Fi, Focus), the timer, and application progress.
  final bool activityRecording;
  final bool activityStatus;
  final bool activityTimer;
  final bool activityProgress;

  /// A second live activity rides beside the pill; a sideways swipe swaps
  /// them; the resting pill opens a home card.
  final bool islandSplit;
  final bool islandSwipe;
  final bool islandHome;

  final bool showRecording;

  /// A dot in the bar while an application records from the microphone.
  final bool showMic;
  final bool tooltips;
  final bool recentPlaces;

  /// Tray items kept behind the chevron, and ones never shown.
  final List<String> trayHidden;
  final List<String> trayNever;

  /// Tiles and widgets the user resized, as `id:WxH`.
  final List<String> tileSizes;

  /// Control Centre tiles, widgets and status items, each in display order.
  final List<String> controls;
  final List<String> widgets;
  final List<String> statusOrder;

  /// The zones as the user arranged them, or null while the bar still
  /// follows the older settings that placed its parts.
  final BarZones? explicitZones;

  /// What the bar draws in its start, centre and end.
  BarZones get zones =>
      explicitZones?.sanitized() ??
      BarZones.legacy(
        systemMenu: showSystemMenu,
        appMenu: showAppMenu,
        island: islandEnabled,
        workspaces: workspacePlacement.key,
      );

  /// The island needs both its switch and a place in the centre.
  bool get showsIsland =>
      islandEnabled && zones.center.contains(BarPart.island);

  /// The switcher rides inside the island unless a zone holds it.
  bool get workspacesInIsland =>
      workspacePlacement == BarWorkspacePlacement.island &&
      !zones.contains(BarPart.workspaces);

  bool hasPart(String id) =>
      id == BarPart.island ? showsIsland : zones.contains(id);

  /// Shows or hides one of the parts that has had a switch of its own since
  /// before zones: the switch is kept, and arranged zones follow it.
  BarSettings withPart(String id, bool shown) {
    final next = switch (id) {
      BarPart.system => copyWith(showSystemMenu: shown),
      BarPart.app => copyWith(showAppMenu: shown),
      BarPart.island => copyWith(islandEnabled: shown),
      _ => this,
    };
    final zones = explicitZones;
    if (zones == null) return next;
    if (!shown) {
      // The island's switch alone hides it, so it keeps its place.
      return id == BarPart.island
          ? next
          : next.copyWith(zones: zones.without(id));
    }
    if (zones.contains(id)) return next;
    return next.copyWith(
      zones: switch (id) {
        BarPart.system => zones.inserted(0, id, 0),
        BarPart.app => zones.inserted(0, id),
        BarPart.island => zones.inserted(1, id, 0),
        _ => zones.inserted(2, id),
      },
    );
  }

  /// Where the switcher shows, as the older setting names it. Null when an
  /// arranged bar holds it in the centre, which that setting cannot say.
  BarWorkspacePlacement? get workspacesShownIn {
    final zones = explicitZones;
    if (zones == null) return workspacePlacement;
    return switch (zones.sanitized().zoneOf(BarPart.workspaces)) {
      0 => BarWorkspacePlacement.leading,
      2 => BarWorkspacePlacement.trailing,
      1 => null,
      _ =>
        workspacePlacement == BarWorkspacePlacement.island
            ? BarWorkspacePlacement.island
            : BarWorkspacePlacement.hidden,
    };
  }

  BarSettings withWorkspacePlacement(BarWorkspacePlacement placement) {
    final next = copyWith(workspacePlacement: placement);
    final zones = explicitZones?.without(BarPart.workspaces);
    if (zones == null) return next;
    return next.copyWith(
      zones: switch (placement) {
        BarWorkspacePlacement.leading => zones.inserted(
          0,
          BarPart.workspaces,
          zones.start.contains(BarPart.system) ? 1 : 0,
        ),
        BarWorkspacePlacement.trailing => zones.inserted(
          2,
          BarPart.workspaces,
          0,
        ),
        _ => zones,
      },
    );
  }

  /// The settings a preset decides, under the keys they are stored by, as
  /// the bar draws them now: the zones are the ones in force whether or not
  /// they were ever arranged, and an island that is switched off is not in
  /// them.
  Map<String, Object?> layoutJson() {
    final zones = this.zones;
    return <String, Object?>{
      'shape': shape.key,
      'cap': cap.key,
      'ground': ground.key,
      'groundOpacity': groundOpacity,
      'groundTint': groundTint.key,
      'borderWidth': borderWidth,
      'borderColour': borderColour.key,
      'textScale': textScale,
      'partGap': partGap,
      'edgeMargin': edgeMargin,
      'endInset': endInset,
      'contentPadding': contentPadding,
      'cornerRadius': cornerRadius,
      'workspaceStyle': workspaceStyle.name,
      'workspacePlacement': workspacesShownIn?.key,
      'start': zones.start,
      'center': <String>[
        for (final id in zones.center)
          if (id != BarPart.island || islandEnabled) id,
      ],
      'end': zones.end,
    };
  }

  /// These settings with a preset's layout keys laid over them. Everything
  /// the preset does not name stays, and an island the preset places is
  /// switched on.
  BarSettings withLayout(Map<String, Object?> layout) {
    final json = <String, dynamic>{};
    writeJson(json);
    final next = BarSettings.fromJson(<String, dynamic>{...json, ...layout});
    return next.zones.center.contains(BarPart.island)
        ? next.copyWith(islandEnabled: true)
        : next;
  }

  Duration get islandNoticeHold => Duration(seconds: islandNoticeSeconds);

  Duration get islandFadeDwell => Duration(milliseconds: islandFadeDelayMs);

  Duration get islandLongPress => Duration(milliseconds: islandLongPressMs);

  BarSettings copyWith({
    BarShape? shape,
    BarCap? cap,
    BarGround? ground,
    double? groundOpacity,
    BarGroundTint? groundTint,
    double? borderWidth,
    BarBorderColour? borderColour,
    double? textScale,
    double? partGap,
    double? edgeMargin,
    Object? endInset = _keep,
    double? contentPadding,
    double? cornerRadius,
    bool? islandEnabled,
    bool? islandHoverPeek,
    bool? islandHoverFade,
    int? islandNoticeSeconds,
    int? islandFadeDelayMs,
    int? islandLongPressMs,
    int? islandWidth,
    int? islandTimerSet,
    bool? activityMedia,
    bool? activityCharging,
    bool? activityNotifications,
    BarWorkspacePlacement? workspacePlacement,
    bool? showSystemMenu,
    bool? showAppMenu,
    bool? showClockDate,
    bool? showTray,
    bool? showWifi,
    bool? showVolume,
    bool? showBattery,
    bool? showBatteryPercent,
    bool? showNotifications,
    bool? showControlCenter,
    bool? showSettingsButton,
    bool? autoHide,
    int? autoHideDelayMs,
    int? recentsClearedAt,
    bool? trayColour,
    bool? mergedNotificationCenter,
    bool? collapseItems,
    int? collapseAutoSeconds,
    BarTrayFold? trayFold,
    bool? showBluetooth,
    bool? showKeyboard,
    bool? showSearch,
    bool? showClipboard,
    bool? activityHud,
    bool? workspaceScroll,
    bool? workspacePreview,
    bool? overviewShowMinimised,
    bool? overviewMiddleClickCloses,
    bool? overviewLiveOtherWorkspaces,
    int? overviewLiveLimit,
    bool? clockWeekday,
    BarWorkspaceStyle? workspaceStyle,
    bool? activityRecording,
    bool? activityStatus,
    bool? activityTimer,
    bool? activityProgress,
    bool? islandSplit,
    bool? islandSwipe,
    bool? islandHome,
    bool? showRecording,
    bool? showMic,
    bool? tooltips,
    bool? recentPlaces,
    List<String>? trayHidden,
    List<String>? trayNever,
    List<String>? tileSizes,
    List<String>? controls,
    List<String>? widgets,
    List<String>? statusOrder,
    Object? zones = _keep,
  }) => BarSettings(
    shape: shape ?? this.shape,
    cap: cap ?? this.cap,
    ground: ground ?? this.ground,
    groundOpacity: groundOpacity ?? this.groundOpacity,
    groundTint: groundTint ?? this.groundTint,
    borderWidth: borderWidth ?? this.borderWidth,
    borderColour: borderColour ?? this.borderColour,
    textScale: textScale ?? this.textScale,
    partGap: partGap ?? this.partGap,
    edgeMargin: edgeMargin ?? this.edgeMargin,
    endInset: identical(endInset, _keep) ? this.endInset : endInset as double?,
    contentPadding: contentPadding ?? this.contentPadding,
    cornerRadius: cornerRadius ?? this.cornerRadius,
    islandEnabled: islandEnabled ?? this.islandEnabled,
    islandHoverPeek: islandHoverPeek ?? this.islandHoverPeek,
    islandHoverFade: islandHoverFade ?? this.islandHoverFade,
    islandNoticeSeconds: islandNoticeSeconds ?? this.islandNoticeSeconds,
    islandFadeDelayMs: islandFadeDelayMs ?? this.islandFadeDelayMs,
    islandLongPressMs: islandLongPressMs ?? this.islandLongPressMs,
    islandWidth: islandWidth ?? this.islandWidth,
    islandTimerSet: islandTimerSet ?? this.islandTimerSet,
    activityMedia: activityMedia ?? this.activityMedia,
    activityCharging: activityCharging ?? this.activityCharging,
    activityNotifications: activityNotifications ?? this.activityNotifications,
    workspacePlacement: workspacePlacement ?? this.workspacePlacement,
    showSystemMenu: showSystemMenu ?? this.showSystemMenu,
    showAppMenu: showAppMenu ?? this.showAppMenu,
    showClockDate: showClockDate ?? this.showClockDate,
    showTray: showTray ?? this.showTray,
    showWifi: showWifi ?? this.showWifi,
    showVolume: showVolume ?? this.showVolume,
    showBattery: showBattery ?? this.showBattery,
    showBatteryPercent: showBatteryPercent ?? this.showBatteryPercent,
    showNotifications: showNotifications ?? this.showNotifications,
    showControlCenter: showControlCenter ?? this.showControlCenter,
    showSettingsButton: showSettingsButton ?? this.showSettingsButton,
    autoHide: autoHide ?? this.autoHide,
    autoHideDelayMs: autoHideDelayMs ?? this.autoHideDelayMs,
    recentsClearedAt: recentsClearedAt ?? this.recentsClearedAt,
    trayColour: trayColour ?? this.trayColour,
    mergedNotificationCenter:
        mergedNotificationCenter ?? this.mergedNotificationCenter,
    collapseItems: collapseItems ?? this.collapseItems,
    collapseAutoSeconds: collapseAutoSeconds ?? this.collapseAutoSeconds,
    trayFold: trayFold ?? this.trayFold,
    showBluetooth: showBluetooth ?? this.showBluetooth,
    showKeyboard: showKeyboard ?? this.showKeyboard,
    showSearch: showSearch ?? this.showSearch,
    showClipboard: showClipboard ?? this.showClipboard,
    activityHud: activityHud ?? this.activityHud,
    workspaceScroll: workspaceScroll ?? this.workspaceScroll,
    workspacePreview: workspacePreview ?? this.workspacePreview,
    overviewShowMinimised:
        overviewShowMinimised ?? this.overviewShowMinimised,
    overviewMiddleClickCloses:
        overviewMiddleClickCloses ?? this.overviewMiddleClickCloses,
    overviewLiveOtherWorkspaces:
        overviewLiveOtherWorkspaces ?? this.overviewLiveOtherWorkspaces,
    overviewLiveLimit:
        (overviewLiveLimit ?? this.overviewLiveLimit).clamp(1, 12),
    clockWeekday: clockWeekday ?? this.clockWeekday,
    workspaceStyle: workspaceStyle ?? this.workspaceStyle,
    activityRecording: activityRecording ?? this.activityRecording,
    activityStatus: activityStatus ?? this.activityStatus,
    activityTimer: activityTimer ?? this.activityTimer,
    activityProgress: activityProgress ?? this.activityProgress,
    islandSplit: islandSplit ?? this.islandSplit,
    islandSwipe: islandSwipe ?? this.islandSwipe,
    islandHome: islandHome ?? this.islandHome,
    showRecording: showRecording ?? this.showRecording,
    showMic: showMic ?? this.showMic,
    tooltips: tooltips ?? this.tooltips,
    recentPlaces: recentPlaces ?? this.recentPlaces,
    trayHidden: trayHidden ?? this.trayHidden,
    trayNever: trayNever ?? this.trayNever,
    tileSizes: tileSizes ?? this.tileSizes,
    controls: controls ?? this.controls,
    widgets: widgets ?? this.widgets,
    statusOrder: statusOrder ?? this.statusOrder,
    explicitZones: identical(zones, _keep)
        ? explicitZones
        : zones as BarZones?,
  );

  factory BarSettings.fromJson(Map<String, dynamic> json) {
    bool flag(String key, bool fallback) =>
        json[key] is bool ? json[key] as bool : fallback;
    double within(String key, double min, double max, double fallback) {
      final value = json[key];
      if (value is! num || value.isNaN) return fallback;
      return value.toDouble().clamp(min, max);
    }

    int whole(String key, int min, int max, int fallback) {
      final value = json[key];
      if (value is! num || !value.isFinite) return fallback;
      return value.round().clamp(min, max);
    }

    List<String> ids(String key, List<String> fallback) {
      final value = json[key];
      if (value is! List) return fallback;
      return <String>{
        for (final id in value)
          if (id is String) id,
      }.toList();
    }

    List<String> parts(String key) => <String>[
      if (json[key] case final List<dynamic> list)
        for (final id in list)
          if (id is String) id,
    ];

    return BarSettings(
      explicitZones:
          json['start'] is List || json['center'] is List || json['end'] is List
          ? BarZones(
              start: parts('start'),
              center: parts('center'),
              end: parts('end'),
            ).sanitized()
          : null,
      // A file from before shapes says attached or floating.
      shape:
          BarShape.parse(json['shape']) ??
          (BarLayout.parse(json['layout']) == BarLayout.floating
              ? BarShape.floating
              : BarShape.strip),
      cap: BarCap.parse(json['cap']),
      ground: BarGround.parse(json['ground']),
      groundOpacity: within(
        'groundOpacity',
        BarMetric.opacityMin,
        BarMetric.opacityMax,
        BarMetric.opacity,
      ),
      groundTint: BarGroundTint.parse(json['groundTint']),
      // A file from before widths says only whether there is a hairline.
      borderWidth: within(
        'borderWidth',
        BarMetric.borderWidthMin,
        BarMetric.borderWidthMax,
        flag('hairline', false) ? BarMetric.hairline : 0,
      ),
      borderColour: BarBorderColour.parse(json['borderColour']),
      textScale: within(
        'textScale',
        BarMetric.textScaleMin,
        BarMetric.textScaleMax,
        BarMetric.textScale,
      ),
      partGap: within(
        'partGap',
        BarMetric.partGapMin,
        BarMetric.partGapMax,
        BarMetric.partGap,
      ),
      edgeMargin: within(
        'edgeMargin',
        BarMetric.edgeMarginMin,
        BarMetric.edgeMarginMax,
        BarMetric.edgeMargin,
      ),
      endInset: json['endInset'] is num
          ? within('endInset', BarMetric.endInsetMin, BarMetric.endInsetMax, 0)
          : null,
      contentPadding: within(
        'contentPadding',
        BarMetric.contentPaddingMin,
        BarMetric.contentPaddingMax,
        BarMetric.contentPadding,
      ),
      cornerRadius: within(
        'cornerRadius',
        BarMetric.cornerRadiusMin,
        BarMetric.cornerRadiusMax,
        BarMetric.cornerRadius,
      ),
      islandEnabled: flag('islandEnabled', true),
      islandHoverPeek: flag('islandHoverPeek', true),
      islandHoverFade: flag('islandHoverFade', false),
      islandNoticeSeconds: (json['islandNoticeSeconds'] is num)
          ? (json['islandNoticeSeconds'] as num).round().clamp(2, 12)
          : 5,
      islandFadeDelayMs: whole(
        'islandFadeDelayMs',
        BarMetric.islandFadeDelayMsMin,
        BarMetric.islandFadeDelayMsMax,
        BarMetric.islandFadeDelayMs,
      ),
      islandLongPressMs: whole(
        'islandLongPressMs',
        BarMetric.islandLongPressMsMin,
        BarMetric.islandLongPressMsMax,
        BarMetric.islandLongPressMs,
      ),
      islandWidth: whole(
        'islandWidth',
        BarMetric.islandWidthMin,
        BarMetric.islandWidthMax,
        BarMetric.islandWidth,
      ),
      islandTimerSet: whole(
        'islandTimerSet',
        0,
        BarMetric.islandTimerSets.length - 1,
        1,
      ),
      activityMedia: flag('activityMedia', true),
      activityCharging: flag('activityCharging', true),
      activityNotifications: flag('activityNotifications', true),
      workspacePlacement: BarWorkspacePlacement.parse(
        json['workspacePlacement'],
      ),
      showSystemMenu: flag('showSystemMenu', true),
      showAppMenu: flag('showAppMenu', true),
      showClockDate: flag('showClockDate', true),
      showTray: flag('showTray', true),
      showWifi: flag('showWifi', true),
      showVolume: flag('showVolume', true),
      showBattery: flag('showBattery', true),
      showBatteryPercent: flag('showBatteryPercent', false),
      showNotifications: flag('showNotifications', true),
      showControlCenter: flag('showControlCenter', true),
      showSettingsButton: flag('showSettingsButton', false),
      autoHide: flag('autoHide', false),
      autoHideDelayMs: clampAutoHideDelay(json['autoHideDelayMs']),
      recentsClearedAt: json['recentsClearedAt'] is int
          ? json['recentsClearedAt'] as int
          : 0,
      trayColour: flag('trayColour', false),
      mergedNotificationCenter: flag('mergedNotificationCenter', true),
      collapseItems: flag('collapseItems', false),
      collapseAutoSeconds: json['collapseAutoSeconds'] is num
          ? (json['collapseAutoSeconds'] as num).round().clamp(0, 120)
          : 15,
      trayFold: BarTrayFold.parse(json['trayFold']),
      showBluetooth: flag('showBluetooth', true),
      showKeyboard: flag('showKeyboard', true),
      showSearch: flag('showSearch', true),
      showClipboard: flag('showClipboard', false),
      activityHud: flag('activityHud', true),
      workspaceScroll: flag('workspaceScroll', true),
      workspacePreview: flag('workspacePreview', true),
      overviewShowMinimised: flag('overviewShowMinimised', true),
      overviewMiddleClickCloses: flag('overviewMiddleClickCloses', true),
      overviewLiveOtherWorkspaces: flag('overviewLiveOtherWorkspaces', true),
      overviewLiveLimit: whole('overviewLiveLimit', 1, 12, 6),
      clockWeekday: flag('clockWeekday', true),
      workspaceStyle: json['workspaceStyle'] == 'numbers'
          ? BarWorkspaceStyle.numbers
          : BarWorkspaceStyle.dots,
      activityRecording: flag('activityRecording', true),
      activityStatus: flag('activityStatus', true),
      activityTimer: flag('activityTimer', true),
      activityProgress: flag('activityProgress', true),
      islandSplit: flag('islandSplit', true),
      islandSwipe: flag('islandSwipe', true),
      islandHome: flag('islandHome', true),
      showRecording: flag('showRecording', true),
      showMic: flag('showMic', true),
      tooltips: flag('tooltips', true),
      recentPlaces: flag('recentPlaces', true),
      trayHidden: ids('trayHidden', const <String>[]),
      trayNever: ids('trayNever', const <String>[]),
      tileSizes: ids('tileSizes', const <String>[]),
      controls: ids('controls', defaultControls),
      widgets: ids('widgets', defaultWidgets),
      statusOrder: ids('statusOrder', defaultStatusOrder),
    );
  }

  void writeJson(Map<String, dynamic> json) {
    json['shape'] = shape.key;
    json['layout'] = layout.key;
    json['cap'] = cap.key;
    json['ground'] = ground.key;
    json['groundOpacity'] = groundOpacity;
    json['groundTint'] = groundTint.key;
    json['borderWidth'] = borderWidth;
    json['hairline'] = hairline;
    json['borderColour'] = borderColour.key;
    json['textScale'] = textScale;
    json['partGap'] = partGap;
    json['edgeMargin'] = edgeMargin;
    if (endInset == null) {
      json.remove('endInset');
    } else {
      json['endInset'] = endInset;
    }
    json['contentPadding'] = contentPadding;
    json['cornerRadius'] = cornerRadius;
    json['islandEnabled'] = islandEnabled;
    json['islandHoverPeek'] = islandHoverPeek;
    json['islandHoverFade'] = islandHoverFade;
    json['islandNoticeSeconds'] = islandNoticeSeconds;
    json['islandFadeDelayMs'] = islandFadeDelayMs;
    json['islandLongPressMs'] = islandLongPressMs;
    json['islandWidth'] = islandWidth;
    json['islandTimerSet'] = islandTimerSet;
    json['activityMedia'] = activityMedia;
    json['activityCharging'] = activityCharging;
    json['activityNotifications'] = activityNotifications;
    json['workspacePlacement'] = workspacePlacement.key;
    json['showSystemMenu'] = showSystemMenu;
    json['showAppMenu'] = showAppMenu;
    json['showClockDate'] = showClockDate;
    json['showTray'] = showTray;
    json['showWifi'] = showWifi;
    json['showVolume'] = showVolume;
    json['showBattery'] = showBattery;
    json['showBatteryPercent'] = showBatteryPercent;
    json['showNotifications'] = showNotifications;
    json['showControlCenter'] = showControlCenter;
    json['showSettingsButton'] = showSettingsButton;
    json['autoHide'] = autoHide;
    json['autoHideDelayMs'] = autoHideDelayMs;
    json['recentsClearedAt'] = recentsClearedAt;
    json['trayColour'] = trayColour;
    json['mergedNotificationCenter'] = mergedNotificationCenter;
    json['collapseItems'] = collapseItems;
    json['collapseAutoSeconds'] = collapseAutoSeconds;
    json['trayFold'] = trayFold.key;
    json['showBluetooth'] = showBluetooth;
    json['showKeyboard'] = showKeyboard;
    json['showSearch'] = showSearch;
    json['showClipboard'] = showClipboard;
    json['activityHud'] = activityHud;
    json['workspaceScroll'] = workspaceScroll;
    json['workspacePreview'] = workspacePreview;
    json['overviewShowMinimised'] = overviewShowMinimised;
    json['overviewMiddleClickCloses'] = overviewMiddleClickCloses;
    json['overviewLiveOtherWorkspaces'] = overviewLiveOtherWorkspaces;
    json['overviewLiveLimit'] = overviewLiveLimit;
    json['clockWeekday'] = clockWeekday;
    json['activityRecording'] = activityRecording;
    json['activityStatus'] = activityStatus;
    json['activityTimer'] = activityTimer;
    json['activityProgress'] = activityProgress;
    json['islandSplit'] = islandSplit;
    json['islandSwipe'] = islandSwipe;
    json['islandHome'] = islandHome;
    json['showRecording'] = showRecording;
    json['showMic'] = showMic;
    json['tooltips'] = tooltips;
    json['recentPlaces'] = recentPlaces;
    json['trayHidden'] = trayHidden;
    json['trayNever'] = trayNever;
    json['tileSizes'] = tileSizes;
    json['controls'] = controls;
    json['widgets'] = widgets;
    json['statusOrder'] = statusOrder;
    json['workspaceStyle'] = workspaceStyle.name;
    // A bar that was never arranged keeps no zones, so it goes on following
    // the settings above.
    final zones = explicitZones;
    if (zones == null) {
      json
        ..remove('start')
        ..remove('center')
        ..remove('end');
    } else {
      json['start'] = zones.start;
      json['center'] = zones.center;
      json['end'] = zones.end;
    }
  }
}

/// JSON file beside the dock's preferences. Unknown keys survive a write so an
/// older build cannot erase a newer setting.
class BarPreferencesStore {
  BarPreferencesStore(this.file);

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
    return File('$root/denial/plugins/denial_topbar.json');
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

  Future<BarSettings> read() async => BarSettings.fromJson(await _readJson());

  Future<void> write(BarSettings settings) async {
    final json = await _readJson();
    settings.writeJson(json);
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
