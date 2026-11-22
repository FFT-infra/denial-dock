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
    this.islandShowsClock = true,
    this.islandHoverPeek = true,
    this.islandNoticeSeconds = 5,
    this.activityMedia = true,
    this.activityCharging = true,
    this.activityNotifications = true,
    this.workspacePlacement = BarWorkspacePlacement.island,
    this.showSystemMenu = true,
    this.showAppMenu = true,
    this.showWindowTitle = true,
    this.showClockDate = true,
    this.showTray = true,
    this.showWifi = true,
    this.showBattery = true,
    this.showBatteryPercent = false,
    this.showNotifications = true,
    this.showControlCenter = true,
    this.showSettingsButton = true,
    this.autoHide = false,
    this.autoHideDelayMs = barAutoHideDelayDefault,
  });

  static const BarSettings defaults = BarSettings();

  final BarLayout layout;

  /// Plate opacity. NextKDE's slider spans 5%..85%; XMacTahoe's Golden Gate
  /// preset sits at 55.
  final BarGround ground;
  final double groundOpacity;
  final bool hairline;

  final bool islandEnabled;
  final bool islandShowsClock;
  final bool islandHoverPeek;

  /// How long a notice or a track change keeps the island open, in seconds.
  final int islandNoticeSeconds;

  final bool activityMedia;
  final bool activityCharging;
  final bool activityNotifications;

  final BarWorkspacePlacement workspacePlacement;

  final bool showSystemMenu;
  final bool showAppMenu;
  final bool showWindowTitle;
  final bool showClockDate;
  final bool showTray;
  final bool showWifi;
  final bool showBattery;
  final bool showBatteryPercent;
  final bool showNotifications;
  final bool showControlCenter;
  final bool showSettingsButton;

  final bool autoHide;
  final int autoHideDelayMs;

  Duration get islandNoticeHold => Duration(seconds: islandNoticeSeconds);

  BarSettings copyWith({
    BarLayout? layout,
    BarGround? ground,
    double? groundOpacity,
    bool? hairline,
    bool? islandEnabled,
    bool? islandShowsClock,
    bool? islandHoverPeek,
    int? islandNoticeSeconds,
    bool? activityMedia,
    bool? activityCharging,
    bool? activityNotifications,
    BarWorkspacePlacement? workspacePlacement,
    bool? showSystemMenu,
    bool? showAppMenu,
    bool? showWindowTitle,
    bool? showClockDate,
    bool? showTray,
    bool? showWifi,
    bool? showBattery,
    bool? showBatteryPercent,
    bool? showNotifications,
    bool? showControlCenter,
    bool? showSettingsButton,
    bool? autoHide,
    int? autoHideDelayMs,
  }) => BarSettings(
    layout: layout ?? this.layout,
    ground: ground ?? this.ground,
    groundOpacity: groundOpacity ?? this.groundOpacity,
    hairline: hairline ?? this.hairline,
    islandEnabled: islandEnabled ?? this.islandEnabled,
    islandShowsClock: islandShowsClock ?? this.islandShowsClock,
    islandHoverPeek: islandHoverPeek ?? this.islandHoverPeek,
    islandNoticeSeconds: islandNoticeSeconds ?? this.islandNoticeSeconds,
    activityMedia: activityMedia ?? this.activityMedia,
    activityCharging: activityCharging ?? this.activityCharging,
    activityNotifications: activityNotifications ?? this.activityNotifications,
    workspacePlacement: workspacePlacement ?? this.workspacePlacement,
    showSystemMenu: showSystemMenu ?? this.showSystemMenu,
    showAppMenu: showAppMenu ?? this.showAppMenu,
    showWindowTitle: showWindowTitle ?? this.showWindowTitle,
    showClockDate: showClockDate ?? this.showClockDate,
    showTray: showTray ?? this.showTray,
    showWifi: showWifi ?? this.showWifi,
    showBattery: showBattery ?? this.showBattery,
    showBatteryPercent: showBatteryPercent ?? this.showBatteryPercent,
    showNotifications: showNotifications ?? this.showNotifications,
    showControlCenter: showControlCenter ?? this.showControlCenter,
    showSettingsButton: showSettingsButton ?? this.showSettingsButton,
    autoHide: autoHide ?? this.autoHide,
    autoHideDelayMs: autoHideDelayMs ?? this.autoHideDelayMs,
  );

  factory BarSettings.fromJson(Map<String, dynamic> json) {
    bool flag(String key, bool fallback) =>
        json[key] is bool ? json[key] as bool : fallback;
    double ratio(String key, double fallback) {
      final value = json[key];
      if (value is! num) return fallback;
      return value.toDouble().clamp(0.05, 0.85);
    }

    return BarSettings(
      layout: BarLayout.parse(json['layout']),
      ground: BarGround.parse(json['ground']),
      groundOpacity: ratio('groundOpacity', 0.55),
      hairline: flag('hairline', false),
      islandEnabled: flag('islandEnabled', true),
      islandShowsClock: flag('islandShowsClock', true),
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
      showWindowTitle: flag('showWindowTitle', true),
      showClockDate: flag('showClockDate', true),
      showTray: flag('showTray', true),
      showWifi: flag('showWifi', true),
      showBattery: flag('showBattery', true),
      showBatteryPercent: flag('showBatteryPercent', false),
      showNotifications: flag('showNotifications', true),
      showControlCenter: flag('showControlCenter', true),
      showSettingsButton: flag('showSettingsButton', true),
      autoHide: flag('autoHide', false),
      autoHideDelayMs: clampAutoHideDelay(json['autoHideDelayMs']),
    );
  }

  void writeJson(Map<String, dynamic> json) {
    json['layout'] = layout.key;
    json['ground'] = ground.key;
    json['groundOpacity'] = groundOpacity;
    json['hairline'] = hairline;
    json['islandEnabled'] = islandEnabled;
    json['islandShowsClock'] = islandShowsClock;
    json['islandHoverPeek'] = islandHoverPeek;
    json['islandNoticeSeconds'] = islandNoticeSeconds;
    json['activityMedia'] = activityMedia;
    json['activityCharging'] = activityCharging;
    json['activityNotifications'] = activityNotifications;
    json['workspacePlacement'] = workspacePlacement.key;
    json['showSystemMenu'] = showSystemMenu;
    json['showAppMenu'] = showAppMenu;
    json['showWindowTitle'] = showWindowTitle;
    json['showClockDate'] = showClockDate;
    json['showTray'] = showTray;
    json['showWifi'] = showWifi;
    json['showBattery'] = showBattery;
    json['showBatteryPercent'] = showBatteryPercent;
    json['showNotifications'] = showNotifications;
    json['showControlCenter'] = showControlCenter;
    json['showSettingsButton'] = showSettingsButton;
    json['autoHide'] = autoHide;
    json['autoHideDelayMs'] = autoHideDelayMs;
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
