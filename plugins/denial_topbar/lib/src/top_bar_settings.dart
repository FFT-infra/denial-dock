import 'dart:convert';
import 'dart:io';

/// How the bar sits inside the reserved strip.
enum TopBarAppearance {
  /// Edge to edge, macOS menu bar.
  attached,

  /// One inset capsule.
  floating,

  /// Separate leading, centre and trailing capsules.
  segmented;

  String get key => name;

  static TopBarAppearance parse(
    Object? value, {
    TopBarAppearance fallback = TopBarAppearance.attached,
  }) => switch (value) {
    'attached' => TopBarAppearance.attached,
    'floating' => TopBarAppearance.floating,
    'segmented' => TopBarAppearance.segmented,
    _ => fallback,
  };
}

/// Where a module is drawn, or whether it is drawn at all.
enum TopBarSlot {
  island,
  leading,
  trailing,
  hidden;

  String get key => name;

  static TopBarSlot parse(Object? value, {required TopBarSlot fallback}) =>
      switch (value) {
        'island' => TopBarSlot.island,
        'leading' => TopBarSlot.leading,
        'trailing' => TopBarSlot.trailing,
        'hidden' => TopBarSlot.hidden,
        _ => fallback,
      };
}

/// Surface of the island; black is the macOS look, theme follows the panel.
enum TopBarIslandStyle {
  black,
  theme;

  String get key => name;

  static TopBarIslandStyle parse(
    Object? value, {
    TopBarIslandStyle fallback = TopBarIslandStyle.black,
  }) => value == 'theme' ? TopBarIslandStyle.theme : fallback;
}

const double topBarMinAutoCollapse = 2;
const double topBarMaxAutoCollapse = 10;
const int topBarDefaultAutoCollapse = 4;

int clampAutoCollapse(Object? value) => value is num
    ? value.round().clamp(
        topBarMinAutoCollapse.toInt(),
        topBarMaxAutoCollapse.toInt(),
      )
    : topBarDefaultAutoCollapse;

class TopBarSettings {
  const TopBarSettings({
    this.appearance = TopBarAppearance.attached,
    this.showBackground = true,
    this.hairline = false,
    this.islandEnabled = true,
    this.islandStyle = TopBarIslandStyle.black,
    this.islandHoverPeek = true,
    this.islandAutoCollapseSeconds = topBarDefaultAutoCollapse,
    this.activityMedia = true,
    this.activityNotifications = false,
    this.activityCharging = true,
    this.activityWorkspaces = false,
    this.clockPlacement = TopBarSlot.island,
    this.clockShowsDate = false,
    this.mediaPlacement = TopBarSlot.island,
    this.notificationPlacement = TopBarSlot.trailing,
    this.notificationBadge = true,
    this.showTray = true,
    this.showBattery = true,
    this.showBatteryPercent = false,
    this.showWindowTitle = false,
    this.showSettingsButton = true,
  });

  static const TopBarSettings defaults = TopBarSettings();

  final TopBarAppearance appearance;
  final bool showBackground;
  final bool hairline;

  final bool islandEnabled;
  final TopBarIslandStyle islandStyle;
  final bool islandHoverPeek;
  final int islandAutoCollapseSeconds;
  final bool activityMedia;
  final bool activityNotifications;
  final bool activityCharging;
  final bool activityWorkspaces;

  final TopBarSlot clockPlacement;
  final bool clockShowsDate;
  final TopBarSlot mediaPlacement;
  final TopBarSlot notificationPlacement;
  final bool notificationBadge;

  final bool showTray;
  final bool showBattery;
  final bool showBatteryPercent;
  final bool showWindowTitle;
  final bool showSettingsButton;

  /// The island only exists on the top edge; every other role falls back to
  /// the trailing cluster so the module stays reachable.
  TopBarSlot resolveSlot(TopBarSlot slot, {required bool islandAvailable}) =>
      slot == TopBarSlot.island && !islandAvailable
      ? TopBarSlot.trailing
      : slot;

  TopBarSettings copyWith({
    TopBarAppearance? appearance,
    bool? showBackground,
    bool? hairline,
    bool? islandEnabled,
    TopBarIslandStyle? islandStyle,
    bool? islandHoverPeek,
    int? islandAutoCollapseSeconds,
    bool? activityMedia,
    bool? activityNotifications,
    bool? activityCharging,
    bool? activityWorkspaces,
    TopBarSlot? clockPlacement,
    bool? clockShowsDate,
    TopBarSlot? mediaPlacement,
    TopBarSlot? notificationPlacement,
    bool? notificationBadge,
    bool? showTray,
    bool? showBattery,
    bool? showBatteryPercent,
    bool? showWindowTitle,
    bool? showSettingsButton,
  }) {
    return TopBarSettings(
      appearance: appearance ?? this.appearance,
      showBackground: showBackground ?? this.showBackground,
      hairline: hairline ?? this.hairline,
      islandEnabled: islandEnabled ?? this.islandEnabled,
      islandStyle: islandStyle ?? this.islandStyle,
      islandHoverPeek: islandHoverPeek ?? this.islandHoverPeek,
      islandAutoCollapseSeconds:
          islandAutoCollapseSeconds ?? this.islandAutoCollapseSeconds,
      activityMedia: activityMedia ?? this.activityMedia,
      activityNotifications:
          activityNotifications ?? this.activityNotifications,
      activityCharging: activityCharging ?? this.activityCharging,
      activityWorkspaces: activityWorkspaces ?? this.activityWorkspaces,
      clockPlacement: clockPlacement ?? this.clockPlacement,
      clockShowsDate: clockShowsDate ?? this.clockShowsDate,
      mediaPlacement: mediaPlacement ?? this.mediaPlacement,
      notificationPlacement:
          notificationPlacement ?? this.notificationPlacement,
      notificationBadge: notificationBadge ?? this.notificationBadge,
      showTray: showTray ?? this.showTray,
      showBattery: showBattery ?? this.showBattery,
      showBatteryPercent: showBatteryPercent ?? this.showBatteryPercent,
      showWindowTitle: showWindowTitle ?? this.showWindowTitle,
      showSettingsButton: showSettingsButton ?? this.showSettingsButton,
    );
  }

  factory TopBarSettings.fromJson(Map<String, dynamic> json) {
    bool flag(String key, bool fallback) =>
        json[key] is bool ? json[key] as bool : fallback;
    return TopBarSettings(
      appearance: TopBarAppearance.parse(json['appearance']),
      showBackground: flag('showBackground', true),
      hairline: flag('hairline', false),
      islandEnabled: flag('islandEnabled', true),
      islandStyle: TopBarIslandStyle.parse(json['islandStyle']),
      islandHoverPeek: flag('islandHoverPeek', true),
      islandAutoCollapseSeconds: clampAutoCollapse(
        json['islandAutoCollapseSeconds'],
      ),
      activityMedia: flag('activityMedia', true),
      activityNotifications: flag('activityNotifications', false),
      activityCharging: flag('activityCharging', true),
      activityWorkspaces: flag('activityWorkspaces', false),
      clockPlacement: TopBarSlot.parse(
        json['clockPlacement'],
        fallback: TopBarSlot.island,
      ),
      clockShowsDate: flag('clockShowsDate', false),
      mediaPlacement: TopBarSlot.parse(
        json['mediaPlacement'],
        fallback: TopBarSlot.island,
      ),
      notificationPlacement: TopBarSlot.parse(
        json['notificationPlacement'],
        fallback: TopBarSlot.trailing,
      ),
      notificationBadge: flag('notificationBadge', true),
      showTray: flag('showTray', true),
      showBattery: flag('showBattery', true),
      showBatteryPercent: flag('showBatteryPercent', false),
      showWindowTitle: flag('showWindowTitle', false),
      showSettingsButton: flag('showSettingsButton', true),
    );
  }

  void writeJson(Map<String, dynamic> json) {
    json['appearance'] = appearance.key;
    json['showBackground'] = showBackground;
    json['hairline'] = hairline;
    json['islandEnabled'] = islandEnabled;
    json['islandStyle'] = islandStyle.key;
    json['islandHoverPeek'] = islandHoverPeek;
    json['islandAutoCollapseSeconds'] = islandAutoCollapseSeconds;
    json['activityMedia'] = activityMedia;
    json['activityNotifications'] = activityNotifications;
    json['activityCharging'] = activityCharging;
    json['activityWorkspaces'] = activityWorkspaces;
    json['clockPlacement'] = clockPlacement.key;
    json['clockShowsDate'] = clockShowsDate;
    json['mediaPlacement'] = mediaPlacement.key;
    json['notificationPlacement'] = notificationPlacement.key;
    json['notificationBadge'] = notificationBadge;
    json['showTray'] = showTray;
    json['showBattery'] = showBattery;
    json['showBatteryPercent'] = showBatteryPercent;
    json['showWindowTitle'] = showWindowTitle;
    json['showSettingsButton'] = showSettingsButton;
  }
}

/// Small JSON file beside the dock's preferences. Unknown keys survive a
/// write so a future setting is not erased by an older build.
class TopBarPreferencesStore {
  TopBarPreferencesStore(this.file);

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

  Future<TopBarSettings> read() async =>
      TopBarSettings.fromJson(await _readJson());

  Future<void> write(TopBarSettings settings) async {
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
