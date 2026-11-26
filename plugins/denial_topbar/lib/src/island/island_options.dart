/// Which of the island's settings are in force, and why one is not. Every
/// dependency and exclusion between them is here and nowhere else: the
/// settings page draws from [IslandOptions], the bar builds the island from
/// [IslandOptions.effective], and a test walks every combination.
///
/// Plain Dart, so it runs as an ordinary test.
library;

import 'package:denial_shell_kit/kit_reserve.dart' show KitBarMode;

import '../bar_settings.dart';

/// One switch or value on the island's settings page.
enum IslandOption {
  /// The island itself.
  shown,
  hoverPeek,
  hoverFade,
  fadeDelay,
  longPress,
  home,
  split,
  swipe,
  media,
  notifications,
  charging,
  hud,
  recording,
  timer,
  progress,
  status,
  noticeHold,

  /// The workspace switcher riding inside the pill.
  workspaces,
}

/// Why an option cannot be changed, or does nothing, as things stand.
enum IslandWhy {
  /// The bar draws nothing at all.
  barHidden,

  /// The bar is on a side or at the bottom; the island lives at the top.
  barNotOnTop,

  /// The island is switched off, or has no place in the bar's centre.
  islandOff,

  /// The bar is reduced to its island, which is therefore always there.
  islandOnly,

  /// Only while the island fades under the pointer.
  needsFade,

  /// Only while the island shows notifications.
  needsNotifications,

  /// Only with two activities that can be live at once.
  needsTwoLive,

  /// Only with two pages to turn between: two live activities, or one and
  /// the home panel.
  needsPages,

  /// Only with an activity that has a panel to preview.
  needsPanel,
}

/// One option as the settings page draws it.
class IslandOptionState {
  const IslandOptionState({
    required this.on,
    required this.enabled,
    this.why,
  });

  /// What the switch shows: the value in force while it can be changed,
  /// and the stored one while it cannot.
  final bool on;

  /// Whether the user can change it now.
  final bool enabled;

  /// Why not, or why it is locked on.
  final IslandWhy? why;
}

class IslandOptions {
  /// [mode] is the mode the bar draws in now, and [top] whether the bar is
  /// on the top edge.
  factory IslandOptions(
    BarSettings settings, {
    required KitBarMode mode,
    required bool top,
  }) {
    final IslandWhy? absent = mode == KitBarMode.hidden
        ? IslandWhy.barHidden
        : !top
        ? IslandWhy.barNotOnTop
        : mode == KitBarMode.islandOnly || settings.showsIsland
        ? null
        : IslandWhy.islandOff;
    return IslandOptions._(settings, mode, absent);
  }

  const IslandOptions._(this.settings, this.mode, this._absent);

  final BarSettings settings;
  final KitBarMode mode;
  final IslandWhy? _absent;

  /// Whether an island is drawn. A bar reduced to its island has one
  /// whatever its switch says.
  bool get present => _absent == null;

  /// The activities that stay for as long as their source runs. Two of
  /// them can be live at once.
  int get _live => <bool>[
    settings.activityMedia,
    settings.activityTimer,
    settings.activityRecording,
    settings.activityProgress,
  ].where((on) => on).length;

  /// Whether anything the pill shows has a panel a resting pointer could
  /// preview. The home panel opens on a press only.
  bool get _previews =>
      _live > 0 ||
      settings.activityNotifications ||
      settings.activityCharging;

  IslandWhy? _whyNot(IslandOption option) {
    final absent = _absent;
    if (option == IslandOption.shown) {
      if (absent == IslandWhy.barHidden || absent == IslandWhy.barNotOnTop) {
        return absent;
      }
      return mode == KitBarMode.islandOnly ? IslandWhy.islandOnly : null;
    }
    if (absent != null) return absent;
    return switch (option) {
      IslandOption.fadeDelay =>
        settings.islandHoverFade ? null : IslandWhy.needsFade,
      IslandOption.noticeHold =>
        settings.activityNotifications ? null : IslandWhy.needsNotifications,
      IslandOption.split => _live >= 2 ? null : IslandWhy.needsTwoLive,
      IslandOption.swipe =>
        _live >= 2 || (_live == 1 && settings.islandHome)
            ? null
            : IslandWhy.needsPages,
      IslandOption.hoverPeek => _previews ? null : IslandWhy.needsPanel,
      _ => null,
    };
  }

  bool _stored(IslandOption option) => switch (option) {
    IslandOption.shown => settings.showsIsland,
    IslandOption.hoverPeek => settings.islandHoverPeek,
    IslandOption.hoverFade => settings.islandHoverFade,
    IslandOption.fadeDelay => settings.islandHoverFade,
    IslandOption.longPress => true,
    IslandOption.home => settings.islandHome,
    IslandOption.split => settings.islandSplit,
    IslandOption.swipe => settings.islandSwipe,
    IslandOption.media => settings.activityMedia,
    IslandOption.notifications => settings.activityNotifications,
    IslandOption.charging => settings.activityCharging,
    IslandOption.hud => settings.activityHud,
    IslandOption.recording => settings.activityRecording,
    IslandOption.timer => settings.activityTimer,
    IslandOption.progress => settings.activityProgress,
    IslandOption.status => settings.activityStatus,
    IslandOption.noticeHold => settings.activityNotifications,
    IslandOption.workspaces => settings.workspacesInIsland,
  };

  /// Whether [option] does anything now.
  bool inForce(IslandOption option) {
    if (option == IslandOption.shown) return present;
    if (!present) return false;
    final why = _whyNot(option);
    if (why != null) return false;
    // Fading and previewing both answer a resting pointer; fading wins.
    if (option == IslandOption.hoverPeek && settings.islandHoverFade) {
      return false;
    }
    return _stored(option);
  }

  IslandOptionState operator [](IslandOption option) {
    final why = _whyNot(option);
    // Locked on rather than greyed off: the one case where the reason
    // explains a value the user cannot turn off.
    final locked = why == IslandWhy.islandOnly;
    return IslandOptionState(
      // An option that is out of reach keeps showing what is stored, which
      // is what comes back once it is in reach again.
      on: locked || (why == null ? inForce(option) : _stored(option)),
      enabled: why == null,
      why: why,
    );
  }

  /// The settings the island is built from: the stored ones with every
  /// option that is not in force turned off, so the island needs no rule
  /// of its own.
  BarSettings get effective => settings.copyWith(
    islandHoverPeek: inForce(IslandOption.hoverPeek),
    islandHoverFade: inForce(IslandOption.hoverFade),
    islandHome: inForce(IslandOption.home),
    islandSplit: inForce(IslandOption.split),
    islandSwipe: inForce(IslandOption.swipe),
    activityMedia: inForce(IslandOption.media),
    activityNotifications: inForce(IslandOption.notifications),
    activityCharging: inForce(IslandOption.charging),
    activityHud: inForce(IslandOption.hud),
    activityRecording: inForce(IslandOption.recording),
    activityTimer: inForce(IslandOption.timer),
    activityProgress: inForce(IslandOption.progress),
    activityStatus: inForce(IslandOption.status),
  );

  /// Whether the workspace switcher is asked to ride in an island that is
  /// not there, and so shows nowhere.
  bool get workspacesLost => settings.workspacesInIsland && !present;

  /// [settings] with [option] switched, and whatever excludes it switched
  /// with it. An option that cannot be changed now is left alone.
  BarSettings set(IslandOption option, bool value) {
    if (!this[option].enabled) return settings;
    return switch (option) {
      IslandOption.shown => settings.withPart(BarPart.island, value),
      // One answer to a resting pointer at a time.
      IslandOption.hoverPeek => settings.copyWith(
        islandHoverPeek: value,
        islandHoverFade: value ? false : settings.islandHoverFade,
      ),
      IslandOption.hoverFade => settings.copyWith(
        islandHoverFade: value,
        islandHoverPeek: value ? false : settings.islandHoverPeek,
      ),
      IslandOption.home => settings.copyWith(islandHome: value),
      IslandOption.split => settings.copyWith(islandSplit: value),
      IslandOption.swipe => settings.copyWith(islandSwipe: value),
      IslandOption.media => settings.copyWith(activityMedia: value),
      IslandOption.notifications => settings.copyWith(
        activityNotifications: value,
      ),
      IslandOption.charging => settings.copyWith(activityCharging: value),
      IslandOption.hud => settings.copyWith(activityHud: value),
      IslandOption.recording => settings.copyWith(activityRecording: value),
      IslandOption.timer => settings.copyWith(activityTimer: value),
      IslandOption.progress => settings.copyWith(activityProgress: value),
      IslandOption.status => settings.copyWith(activityStatus: value),
      IslandOption.fadeDelay ||
      IslandOption.longPress ||
      IslandOption.noticeHold ||
      IslandOption.workspaces => settings,
    };
  }
}
