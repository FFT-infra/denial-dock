import 'dart:io';

import 'package:denial_shell_kit/kit_reserve.dart' show KitBarMode;
import 'package:denial_topbar/src/bar_settings.dart';
import 'package:denial_topbar/src/island/island_options.dart';

/// Walks every combination of the island's switches, in every bar mode and
/// on either kind of edge, and holds each to the rules the settings page
/// and the bar both read.
void main() {
  const switches = <IslandOption>[
    IslandOption.shown,
    IslandOption.hoverPeek,
    IslandOption.hoverFade,
    IslandOption.home,
    IslandOption.split,
    IslandOption.swipe,
    IslandOption.media,
    IslandOption.notifications,
    IslandOption.charging,
    IslandOption.hud,
    IslandOption.recording,
    IslandOption.timer,
    IslandOption.progress,
    IslandOption.status,
  ];
  var walked = 0;
  for (var bits = 0; bits < 1 << switches.length; bits++) {
    bool bit(IslandOption o) => bits & (1 << switches.indexOf(o)) != 0;
    final stored = const BarSettings().copyWith(
      islandEnabled: bit(IslandOption.shown),
      islandHoverPeek: bit(IslandOption.hoverPeek),
      islandHoverFade: bit(IslandOption.hoverFade),
      islandHome: bit(IslandOption.home),
      islandSplit: bit(IslandOption.split),
      islandSwipe: bit(IslandOption.swipe),
      activityMedia: bit(IslandOption.media),
      activityNotifications: bit(IslandOption.notifications),
      activityCharging: bit(IslandOption.charging),
      activityHud: bit(IslandOption.hud),
      activityRecording: bit(IslandOption.recording),
      activityTimer: bit(IslandOption.timer),
      activityProgress: bit(IslandOption.progress),
      activityStatus: bit(IslandOption.status),
    );
    for (final mode in KitBarMode.values) {
      for (final top in <bool>[true, false]) {
        walked++;
        final at = 'bits $bits, $mode, top $top';
        final options = IslandOptions(stored, mode: mode, top: top);
        final live = <IslandOption>[
          IslandOption.media,
          IslandOption.timer,
          IslandOption.recording,
          IslandOption.progress,
        ].where(options.inForce).length;

        // Whether there is an island at all.
        final expected =
            mode != KitBarMode.hidden &&
            top &&
            (mode == KitBarMode.islandOnly || stored.showsIsland);
        _expect(options.present == expected, 'presence, $at');
        _expect(
          options.inForce(IslandOption.shown) == options.present,
          'the island is in force exactly when it is drawn, $at',
        );
        _expect(
          options.workspacesLost ==
              (stored.workspacesInIsland && !options.present),
          'a switcher with no island to ride in is reported, $at',
        );

        for (final option in IslandOption.values) {
          final state = options[option];
          _expect(
            state.enabled == (state.why == null),
            'a greyed option says why, and only a greyed one, $option, $at',
          );
          if (!options.present && option != IslandOption.shown) {
            _expect(!state.enabled, 'no island, nothing to set, $option, $at');
            _expect(!options.inForce(option), 'nor in force, $option, $at');
          }
          if (options.inForce(option)) {
            _expect(state.on, 'in force shows as on, $option, $at');
          }
          if (state.enabled) {
            _expect(
              state.on == options.inForce(option),
              'a switch that can be set shows what is in force, $option, $at',
            );
          }
        }

        // The island's own switch.
        final shown = options[IslandOption.shown];
        if (mode == KitBarMode.islandOnly && top) {
          _expect(options.present, 'island only always has one, $at');
          _expect(
            shown.on && !shown.enabled && shown.why == IslandWhy.islandOnly,
            'and its switch is locked on, $at',
          );
        }
        if (mode == KitBarMode.hidden) {
          _expect(shown.why == IslandWhy.barHidden, 'hidden bar, $at');
        } else if (!top) {
          _expect(shown.why == IslandWhy.barNotOnTop, 'side bar, $at');
        } else if (mode == KitBarMode.shown) {
          _expect(shown.enabled, 'an ordinary bar can switch it, $at');
        }

        // One answer to a resting pointer.
        _expect(
          !(options.inForce(IslandOption.hoverPeek) &&
              options.inForce(IslandOption.hoverFade)),
          'previewing and fading never both, $at',
        );

        // Dependants follow what they depend on.
        if (options.present) {
          _expect(
            options[IslandOption.fadeDelay].enabled ==
                options.inForce(IslandOption.hoverFade),
            'the fade delay follows fading, $at',
          );
          _expect(
            options[IslandOption.noticeHold].enabled ==
                options.inForce(IslandOption.notifications),
            'the notification hold follows notifications, $at',
          );
          _expect(
            options[IslandOption.split].enabled == (live >= 2),
            'a second bubble needs two live activities, $at',
          );
          _expect(
            options[IslandOption.swipe].enabled ==
                (live >= 2 ||
                    (live == 1 && options.inForce(IslandOption.home))),
            'swiping needs two pages, $at',
          );
          if (options.inForce(IslandOption.hoverPeek)) {
            _expect(
              live > 0 ||
                  options.inForce(IslandOption.notifications) ||
                  options.inForce(IslandOption.charging),
              'a preview needs a panel, $at',
            );
          }
        }

        // What the bar builds from needs no second pass.
        final effective = options.effective;
        final again = IslandOptions(effective, mode: mode, top: top);
        _expect(again.present == options.present, 'same island, $at');
        _expect(
          _json(again.effective) == _json(effective),
          'effective settings are settled, $at',
        );
        _expect(
          !(effective.islandHoverPeek && effective.islandHoverFade),
          'the island is never told to do both, $at',
        );
        if (!options.present) {
          _expect(
            !effective.activityMedia &&
                !effective.activityNotifications &&
                !effective.islandHome &&
                !effective.islandSplit &&
                !effective.islandSwipe,
            'no island, nothing asked of it, $at',
          );
        }

        // Setting a switch: a locked one stays, and no pair of answers to
        // a resting pointer is ever stored.
        for (final option in switches) {
          for (final value in <bool>[true, false]) {
            final next = options.set(option, value);
            if (!options[option].enabled) {
              _expect(
                _json(next) == _json(stored),
                'a greyed switch changes nothing, $option, $at',
              );
              continue;
            }
            if (option == IslandOption.hoverPeek ||
                option == IslandOption.hoverFade) {
              _expect(
                !(value && next.islandHoverPeek && next.islandHoverFade),
                'turning one on turns the other off, $option, $at',
              );
            }
            final after = IslandOptions(next, mode: mode, top: top);
            if (option != IslandOption.shown) {
              _expect(
                after._showsStored(option) == value,
                'the switch takes, $option, $at',
              );
            }
          }
        }
      }
    }
  }
  _expect(walked == (1 << switches.length) * 6, 'every combination walked');

  // Switching the island off greys what depends on it, with the reason.
  final off = IslandOptions(
    const BarSettings().copyWith(islandEnabled: false),
    mode: KitBarMode.shown,
    top: true,
  );
  _expect(!off.present, 'switched off');
  _expect(off[IslandOption.shown].enabled, 'and can be switched back');
  _expect(
    off[IslandOption.media].why == IslandWhy.islandOff &&
        off[IslandOption.cursorAbsorb].why == IslandWhy.islandOff &&
        off[IslandOption.swipe].why == IslandWhy.islandOff,
    'its options say the island is off',
  );
  final back = IslandOptions(
    off.set(IslandOption.shown, true),
    mode: KitBarMode.shown,
    top: true,
  );
  _expect(back.present, 'the switch brings it back');

  // Cursor absorption defaults on, is disabled when hoverFade is enabled,
  // and follows the active island state.
  _expect(
    back[IslandOption.cursorAbsorb].enabled &&
        back[IslandOption.cursorAbsorb].on &&
        back.inForce(IslandOption.cursorAbsorb) &&
        back.effective.islandCursorAbsorb,
    'cursorAbsorb is active by default when island is shown',
  );
  final fadeOn = IslandOptions(
    back.set(IslandOption.hoverFade, true),
    mode: KitBarMode.shown,
    top: true,
  );
  _expect(
    !fadeOn[IslandOption.cursorAbsorb].enabled &&
        fadeOn[IslandOption.cursorAbsorb].why == IslandWhy.fadesOnHover &&
        !fadeOn.inForce(IslandOption.cursorAbsorb) &&
        !fadeOn.effective.islandCursorAbsorb,
    'cursorAbsorb is disabled when hoverFade is enabled',
  );
  final absorbOff = IslandOptions(
    back.set(IslandOption.cursorAbsorb, false),
    mode: KitBarMode.shown,
    top: true,
  );
  _expect(
    !absorbOff.settings.islandCursorAbsorb &&
        !absorbOff.inForce(IslandOption.cursorAbsorb) &&
        !absorbOff.effective.islandCursorAbsorb,
    'cursorAbsorb toggles off cleanly',
  );
  _expect(
    !off.inForce(IslandOption.cursorAbsorb) && !off.effective.islandCursorAbsorb,
    'cursorAbsorb is off in effective settings when island is hidden',
  );

  // Exhaustive cursorAbsorb × hoverFade × shown × mode × top matrix.
  for (final shown in const <bool>[false, true]) {
    for (final fade in const <bool>[false, true]) {
      for (final absorb in const <bool>[false, true]) {
        for (final mode in KitBarMode.values) {
          for (final top in const <bool>[false, true]) {
            final s = const BarSettings().copyWith(
              islandEnabled: shown,
              islandHoverFade: fade,
              islandCursorAbsorb: absorb,
            );
            final opts = IslandOptions(s, mode: mode, top: top);
            final state = opts[IslandOption.cursorAbsorb];
            final wantInForce = opts.present && !fade && absorb;
            _expect(
              opts.inForce(IslandOption.cursorAbsorb) == wantInForce,
              'cursorAbsorb inForce (shown=$shown fade=$fade absorb=$absorb mode=$mode top=$top)',
            );
            _expect(
              opts.effective.islandCursorAbsorb == wantInForce,
              'cursorAbsorb effective mirrors inForce',
            );
            if (opts.present && fade) {
              _expect(
                !state.enabled && state.why == IslandWhy.fadesOnHover,
                'hoverFade disables cursorAbsorb with fadesOnHover reason',
              );
            }
          }
        }
      }
    }
  }

  stdout.writeln('All island option tests passed.');
}

extension on IslandOptions {
  /// What is stored for [option], read back through the settings.
  bool _showsStored(IslandOption option) => switch (option) {
    IslandOption.hoverPeek => settings.islandHoverPeek,
    IslandOption.hoverFade => settings.islandHoverFade,
    IslandOption.cursorAbsorb => settings.islandCursorAbsorb,
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
    _ => false,
  };
}

String _json(BarSettings settings) {
  final json = <String, dynamic>{};
  settings.writeJson(json);
  return json.toString();
}

void _expect(bool condition, String message) {
  if (!condition) {
    stderr.writeln('FAIL: $message');
    exit(1);
  }
}
