import 'dart:convert';
import 'dart:io';

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

enum BarWorkspaceStyle { dots, numbers }

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

const List<String> defaultStatusOrder = <String>[
  'tray',
  'wifi',
  'bluetooth',
  'volume',
  'battery',
  'search',
  'clipboard',
  'notifications',
  'controlcenter',
  'settings',
];

const int barAutoHideDelayMin = 0;
const int barAutoHideDelayMax = 600;
const int barAutoHideDelayDefault = 120;

int clampAutoHideDelay(Object? value) => value is num
    ? value.round().clamp(barAutoHideDelayMin, barAutoHideDelayMax)
    : barAutoHideDelayDefault;

class BarSettings {
  const BarSettings({
    this.layout = BarLayout.attached,
    this.ground = BarGround.none,
    this.groundOpacity = 0.55,
    this.hairline = false,
    this.islandEnabled = true,
    this.islandHoverPeek = true,
    this.islandNoticeSeconds = 5,
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
    this.showBluetooth = true,
    this.showSearch = true,
    this.showClipboard = false,
    this.activityHud = true,
    this.workspaceScroll = true,
    this.workspacePreview = true,
    this.clockWeekday = true,
    this.workspaceStyle = BarWorkspaceStyle.dots,
    this.activityRecording = true,
    this.activityStatus = true,
    this.activityTimer = true,
    this.activityProgress = true,
    this.islandSplit = true,
    this.islandSwipe = true,
    this.islandHome = false,
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
  });

  static const BarSettings defaults = BarSettings();

  final BarLayout layout;

  /// Plate opacity. NextKDE's slider spans 5%..85%; XMacTahoe's Golden Gate
  /// preset sits at 55.
  final BarGround ground;
  final double groundOpacity;
  final bool hairline;

  final bool islandEnabled;
  final bool islandHoverPeek;

  /// How long a notice or a track change keeps the island open, in seconds.
  final int islandNoticeSeconds;

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

  /// Tray items fold behind a chevron; 0 seconds keeps them open until the
  /// chevron is pressed again.
  final bool collapseItems;
  final int collapseAutoSeconds;
  final bool showBluetooth;
  final bool showSearch;

  /// Keeps the texts copied this session and shows them from a bar item.
  final bool showClipboard;
  final bool activityHud;
  final bool workspaceScroll;
  final bool workspacePreview;
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

  Duration get islandNoticeHold => Duration(seconds: islandNoticeSeconds);

  BarSettings copyWith({
    BarLayout? layout,
    BarGround? ground,
    double? groundOpacity,
    bool? hairline,
    bool? islandEnabled,
    bool? islandHoverPeek,
    int? islandNoticeSeconds,
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
    bool? showBluetooth,
    bool? showSearch,
    bool? showClipboard,
    bool? activityHud,
    bool? workspaceScroll,
    bool? workspacePreview,
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
  }) => BarSettings(
    layout: layout ?? this.layout,
    ground: ground ?? this.ground,
    groundOpacity: groundOpacity ?? this.groundOpacity,
    hairline: hairline ?? this.hairline,
    islandEnabled: islandEnabled ?? this.islandEnabled,
    islandHoverPeek: islandHoverPeek ?? this.islandHoverPeek,
    islandNoticeSeconds: islandNoticeSeconds ?? this.islandNoticeSeconds,
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
    showBluetooth: showBluetooth ?? this.showBluetooth,
    showSearch: showSearch ?? this.showSearch,
    showClipboard: showClipboard ?? this.showClipboard,
    activityHud: activityHud ?? this.activityHud,
    workspaceScroll: workspaceScroll ?? this.workspaceScroll,
    workspacePreview: workspacePreview ?? this.workspacePreview,
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
  );

  factory BarSettings.fromJson(Map<String, dynamic> json) {
    bool flag(String key, bool fallback) =>
        json[key] is bool ? json[key] as bool : fallback;
    double ratio(String key, double fallback) {
      final value = json[key];
      if (value is! num) return fallback;
      return value.toDouble().clamp(0.05, 0.85);
    }

    List<String> ids(String key, List<String> fallback) {
      final value = json[key];
      if (value is! List) return fallback;
      return <String>{
        for (final id in value)
          if (id is String) id,
      }.toList();
    }

    return BarSettings(
      layout: BarLayout.parse(json['layout']),
      ground: BarGround.parse(json['ground']),
      groundOpacity: ratio('groundOpacity', 0.55),
      hairline: flag('hairline', false),
      islandEnabled: flag('islandEnabled', true),
      islandHoverPeek: flag('islandHoverPeek', true),
      islandNoticeSeconds: (json['islandNoticeSeconds'] is num)
          ? (json['islandNoticeSeconds'] as num).round().clamp(2, 12)
          : 5,
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
      showBluetooth: flag('showBluetooth', true),
      showSearch: flag('showSearch', true),
      showClipboard: flag('showClipboard', false),
      activityHud: flag('activityHud', true),
      workspaceScroll: flag('workspaceScroll', true),
      workspacePreview: flag('workspacePreview', true),
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
      islandHome: flag('islandHome', false),
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
    json['layout'] = layout.key;
    json['ground'] = ground.key;
    json['groundOpacity'] = groundOpacity;
    json['hairline'] = hairline;
    json['islandEnabled'] = islandEnabled;
    json['islandHoverPeek'] = islandHoverPeek;
    json['islandNoticeSeconds'] = islandNoticeSeconds;
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
    json['showBluetooth'] = showBluetooth;
    json['showSearch'] = showSearch;
    json['showClipboard'] = showClipboard;
    json['activityHud'] = activityHud;
    json['workspaceScroll'] = workspaceScroll;
    json['workspacePreview'] = workspacePreview;
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
