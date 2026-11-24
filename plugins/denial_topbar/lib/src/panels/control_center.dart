import 'dart:async';

import 'package:denial_flutter_sdk/models.dart';
import 'package:denial_flutter_sdk/services.dart';
import 'package:denial_flutter_sdk/settings.dart';
import 'package:denial_flutter_sdk/state.dart';
import 'package:denial_flutter_sdk/system_services.dart'
    show PowerProfile, WifiNetwork, systemActionsServiceProvider;
import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bar_icons.dart';
import '../bar_preferences.dart';
import '../bar_settings.dart';
import '../bar_type.dart';
import '../debug_remote.dart';
import '../island/island_timer.dart';
import '../l10n.dart';
import '../media_art.dart';
import '../night_light.dart';
import 'mac_kit.dart';
import 'popovers.dart';
import 'tile_grid.dart';

const double controlCenterWidth = 320;

abstract final class _C {
  static const double inset = 14;
  static const double gap = 12;
  static const double row = 64;
}

/// Control Centre: connectivity capsules beside Now Playing, the round
/// switches, then the display and sound sliders. A capsule's disc toggles;
/// the rest of it opens the detail page in place.
class ControlCenterPanel extends ConsumerStatefulWidget {
  const ControlCenterPanel({
    required this.services,
    required this.output,
    required this.onSettings,
    required this.onJoinNetwork,
    required this.onClose,
    super.key,
  });

  final ShellServices services;
  final DisplayOutput output;
  final VoidCallback onSettings;
  final ValueChanged<WifiNetwork> onJoinNetwork;
  final VoidCallback onClose;

  @override
  ConsumerState<ControlCenterPanel> createState() => _ControlCenterPanelState();
}

class _ControlCenterPanelState extends ConsumerState<ControlCenterPanel> {
  String _page = '';
  bool _editing = false;

  ShellServices get services => widget.services;

  @override
  void initState() {
    super.initState();
    NightLight.sync();
    debugCommand.addListener(_debug);
  }

  @override
  void dispose() {
    debugCommand.removeListener(_debug);
    super.dispose();
  }

  void _debug() {
    final words = debugWords();
    if (words.length < 2 || words.first != 'ccpage') return;
    setState(() {
      _editing = words[1] == 'edit';
      _page = _editing || words[1] == 'home' ? '' : words[1];
    });
  }

  void _go(String page) => setState(() => _page = page);

  @override
  Widget build(BuildContext context) {
    final Widget body = switch (_page) {
      'wifi' => WifiPopover(
        onBack: () => _go(''),
        onJoin: widget.onJoinNetwork,
        onSettings: widget.onSettings,
      ),
      'bluetooth' => BluetoothPopover(
        onBack: () => _go(''),
        onSettings: widget.onSettings,
      ),
      'sound' => SoundPopover(
        services: services,
        onBack: () => _go(''),
        onSettings: widget.onSettings,
      ),
      'timer' => _TimerPage(onBack: () => _go('')),
      _ => _grid(context),
    };
    return SizedBox(
      width: controlCenterWidth,
      child: AnimatedSize(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.topCenter,
            children: <Widget>[
              for (final child in previous)
                Positioned(left: 0, right: 0, top: 0, child: child),
              ?current,
            ],
          ),
          child: KeyedSubtree(key: ValueKey<String>(_page), child: body),
        ),
      ),
    );
  }

  static const List<TileChoice> _library = <TileChoice>[
    TileChoice(id: 'wifi', icon: BarIcons.wifi, label: 'Wi-Fi'),
    TileChoice(id: 'bluetooth', icon: BarIcons.bluetooth, label: 'Bluetooth'),
    TileChoice(id: 'media', icon: BarIcons.playFill, label: 'Now Playing'),
    TileChoice(id: 'focus', icon: BarIcons.moonFill, label: 'Focus'),
    TileChoice(id: 'dark', icon: BarIcons.circleHalf, label: 'Dark Mode'),
    TileChoice(id: 'night', icon: BarIcons.sunMax, label: 'Night Light'),
    TileChoice(id: 'screenshot', icon: BarIcons.camera, label: 'Screenshot'),
    TileChoice(id: 'power', icon: BarIcons.bolt, label: 'Power Mode'),
    TileChoice(
      id: 'recording',
      icon: BarIcons.circleFill,
      label: 'Screen Recording',
    ),
    TileChoice(id: 'display', icon: BarIcons.sunMaxFill, label: 'Display'),
    TileChoice(id: 'sound', icon: BarIcons.speaker3Fill, label: 'Sound'),
    TileChoice(id: 'battery', icon: BarIcons.batteryFull, label: 'Battery'),
    TileChoice(id: 'lock', icon: BarIcons.lockFill, label: 'Lock Screen'),
    TileChoice(
      id: 'desktop',
      icon: BarIcons.desktopcomputer,
      label: 'Show Desktop',
    ),
    TileChoice(id: 'search', icon: BarIcons.search, label: 'Search'),
    TileChoice(id: 'settings', icon: BarIcons.gear, label: 'Settings'),
    TileChoice(id: 'timer', icon: BarIcons.timer, label: 'Timer'),
  ];

  void _saveControls(List<String> controls) => ref
      .read(barSettingsProvider.notifier)
      .save((s) => s.copyWith(controls: controls));

  Tile? _tile(BuildContext context, String id) {
    final sizes = parseTileSizes(
      ref.watch(
        barSettingsProvider.select(
          (state) => state.value?.tileSizes ?? const <String>[],
        ),
      ),
    );
    final key = 'cc.$id';
    // A toggle is either a capsule with its name or a bare disc; the user
    // picks, and each kind knows how to draw itself as the other.
    Tile sized(TileSize natural, Widget child) {
      final wide = (sizes[key] ?? natural).w > 1;
      return Tile(
        id: id,
        size: TileSize(wide ? 2 : 1, 1),
        child: child,
        onResize: () => ref
            .read(barSettingsProvider.notifier)
            .save(
              (s) => s.copyWith(
                tileSizes: writeTileSizes(<String, TileSize>{
                  ...parseTileSizes(s.tileSizes),
                  key: TileSize(wide ? 1 : 2, 1),
                }),
              ),
            ),
      );
    }

    final label = context.tr(
      _library.where((choice) => choice.id == id).firstOrNull?.label ?? id,
    );
    Widget fit(Widget control, TileSize natural) {
      final wide = (sizes[key] ?? natural).w > 1;
      if (control is _Capsule && !wide) {
        return _Round(
          icon: control.icon,
          on: control.on,
          colour: control.colour,
          onTap: control.onToggle,
        );
      }
      if (control is _Round && wide) {
        return _Capsule(
          icon: control.icon,
          on: control.on,
          colour: control.colour,
          title: label,
          detail: control.stateless
              ? ''
              : context.tr(control.on ? 'On' : 'Off'),
          onToggle: control.onTap,
        );
      }
      return control;
    }

    Tile capsule(Widget child) =>
        sized(const TileSize(2, 1), fit(child, const TileSize(2, 1)));
    Tile round(Widget child) =>
        sized(const TileSize(1, 1), fit(child, const TileSize(1, 1)));
    void act(VoidCallback action) {
      widget.onClose();
      action();
    }

    switch (id) {
      case 'wifi':
        final on = ref.watch(
          networkConnectivityProvider.select(
            (state) => state.snapshot.wirelessEnabled,
          ),
        );
        final wifi = ref.watch(services.connectedWifi);
        return capsule(
          _Capsule(
            icon: on ? BarIcons.wifi : BarIcons.wifiSlash,
            on: on,
            title: 'Wi-Fi',
            detail: !on
                ? context.tr('Off')
                : (wifi?.ssid ?? context.tr('Not Connected')),
            onToggle: () => ref
                .read(networkConnectivityProvider.notifier)
                .setWirelessEnabled(!on),
            onOpen: () => _go('wifi'),
          ),
        );
      case 'bluetooth':
        final bluetooth = ref.watch(bluetoothProvider);
        final on = bluetooth.available && bluetooth.powered;
        final connected = <String>[
          for (final device in bluetooth.devices)
            if (device.connected) device.name,
        ];
        return capsule(
          _Capsule(
            icon: BarIcons.bluetooth,
            on: on,
            title: context.tr('Bluetooth'),
            detail: !bluetooth.available
                ? context.tr('Unavailable')
                : !on
                ? context.tr('Off')
                : connected.isEmpty
                ? context.tr('On')
                : connected.join(', '),
            onToggle: bluetooth.available
                ? () => ref.read(bluetoothProvider.notifier).togglePower()
                : null,
            onOpen: () => _go('bluetooth'),
          ),
        );
      case 'media':
        return Tile(
          id: id,
          size: const TileSize(2, 2),
          child: _MediaTile(services: services),
        );
      case 'focus':
        final focus = ref.watch(
          desktopNotificationsProvider.select((state) => state.doNotDisturb),
        );
        return capsule(
          _Capsule(
            icon: BarIcons.moonFill,
            on: focus,
            colour: macPurple,
            title: context.tr('Focus'),
            detail: context.tr(focus ? 'On' : 'Off'),
            onToggle: () => ref
                .read(desktopNotificationsProvider.notifier)
                .toggleDoNotDisturb(),
          ),
        );
      case 'dark':
        final dark = ref.watch(
          shellSettingsProvider.select(
            (state) =>
                state.appearance.colorSchemePreference.effectiveBrightness ==
                Brightness.dark,
          ),
        );
        return round(
          _Round(
            icon: BarIcons.circleHalf,
            on: dark,
            colour: const Color(0xff636366),
            onTap: () => ref
                .read(shellSettingsProvider.notifier)
                .setColorSchemePreference(
                  dark
                      ? DesktopColorSchemePreference.preferLight
                      : DesktopColorSchemePreference.preferDark,
                ),
          ),
        );
      case 'night':
        return round(
          ValueListenableBuilder<bool>(
            valueListenable: NightLight.enabled,
            builder: (context, night, _) => fit(
              _Round(
                icon: night ? BarIcons.sunMaxFill : BarIcons.sunMax,
                on: night,
                colour: macOrange,
                onTap: NightLight.toggle,
              ),
              const TileSize(1, 1),
            ),
          ),
        );
      case 'screenshot':
        return round(
          _Round(
            icon: BarIcons.camera,
            on: false,
            stateless: true,
            onTap: () => act(
              () => ref.read(systemActionsServiceProvider).takeScreenshot(),
            ),
          ),
        );
      case 'power':
        final power = ref.watch(desktopPowerModesProvider);
        final saving = power.systemProfile == PowerProfile.powerSave;
        final fast = power.systemProfile == PowerProfile.performance;
        return round(
          _Round(
            icon: fast ? BarIcons.boltFill : BarIcons.bolt,
            on: power.systemAvailable && (saving || fast),
            colour: saving ? macYellow : macBlue,
            onTap: power.systemAvailable
                ? () => ref
                      .read(desktopPowerModesProvider.notifier)
                      .selectSystemProfile(
                        PowerProfile.next(power.systemProfile),
                      )
                : null,
          ),
        );
      case 'recording':
        final recording = ref.watch(screenRecordingProvider);
        return capsule(
          _Capsule(
            icon: BarIcons.circleFill,
            on: recording.recording,
            colour: macRed,
            title: context.tr('Screen Recording'),
            detail: context.tr(recording.recording ? 'On' : 'Off'),
            onToggle: recording.available
                ? () => act(
                    () => ref.read(screenRecordingProvider.notifier).toggle(),
                  )
                : null,
          ),
        );
      case 'display':
        final level = ref.watch(
          displayBrightnessProvider.select(
            (state) => state.levels[widget.output.monitorId] ?? 1.0,
          ),
        );
        final brightness = ref.read(displayBrightnessProvider.notifier);
        return Tile(
          id: id,
          size: const TileSize(4, 1),
          child: _SliderTile(
            label: context.tr('Display'),
            value: level,
            leading: BarIcons.sunMax,
            trailing: BarIcons.sunMaxFill,
            onChanged: (value) => brightness.setLevel(widget.output, value),
            onChangeEnd: (value) =>
                brightness.commitLevel(widget.output, value),
          ),
        );
      case 'sound':
        final volume = ref.watch(services.volume);
        return Tile(
          id: id,
          size: const TileSize(4, 1),
          child: _SliderTile(
            label: context.tr('Sound'),
            value: volume,
            leading: volume <= 0.001
                ? BarIcons.speakerSlashFill
                : BarIcons.speaker1Fill,
            trailing: BarIcons.speaker3Fill,
            onOpen: () => _go('sound'),
            onChangeStart: services.beginVolumeInteraction,
            onChanged: services.setVolume,
            onChangeEnd: services.commitVolume,
          ),
        );
      case 'battery':
        final battery = ref.watch(services.battery);
        if (battery.capacity == null) return null;
        final plugged =
            battery.charging ||
            ref.watch(
              upowerProvider.select(
                (state) => state.snapshot?.onBattery == false,
              ),
            );
        return capsule(
          _Capsule(
            icon: plugged ? BarIcons.boltFill : BarIcons.batteryFull,
            on: plugged,
            colour: macGreen,
            title: context.tr('Battery'),
            detail: plugged
                ? '${battery.capacity}% · ${context.tr('Charging')}'
                : '${battery.capacity}%',
            onToggle: widget.onSettings,
          ),
        );
      case 'timer':
        return capsule(
          _TimerWatch(
            builder: (context, now) => fit(
              _Capsule(
                icon: BarIcons.timer,
                on: islandTimer.active,
                colour: macOrange,
                title: context.tr('Timer'),
                detail: islandTimer.active
                    ? clockSpan(islandTimer.remaining(now))
                    : context.tr('Off'),
                onToggle: () => islandTimer.active
                    ? islandTimer.cancel()
                    : islandTimer.start(const Duration(minutes: 5), now),
                onOpen: () => _go('timer'),
              ),
              const TileSize(2, 1),
            ),
          ),
        );
      case 'lock':
        return round(
          _Round(
            icon: BarIcons.lockFill,
            on: false,
            stateless: true,
            onTap: () => act(
              () => ref
                  .read(sessionPowerProvider.notifier)
                  .request(SessionPowerAction.lock),
            ),
          ),
        );
      case 'desktop':
        return round(
          _Round(
            icon: BarIcons.desktopcomputer,
            on: ref.watch(services.desktopVisible),
            onTap: () => act(services.toggleDesktop),
          ),
        );
      case 'search':
        return round(
          _Round(
            icon: BarIcons.search,
            on: false,
            stateless: true,
            onTap: () => act(services.toggleLauncher),
          ),
        );
      case 'settings':
        return round(
          _Round(
            icon: BarIcons.gear,
            on: false,
            stateless: true,
            onTap: widget.onSettings,
          ),
        );
    }
    return null;
  }

  Widget _grid(BuildContext context) {
    final theme = context.shellTheme;
    final order = ref.watch(
      barSettingsProvider.select(
        (state) => state.value?.controls ?? defaultControls,
      ),
    );
    final tiles = <Tile>[for (final id in order) ?_tile(context, id)];
    final spare = <TileChoice>[
      for (final choice in _library)
        if (!order.contains(choice.id))
          TileChoice(
            id: choice.id,
            icon: choice.icon,
            label: context.tr(choice.label),
          ),
    ];
    return Padding(
      padding: const EdgeInsets.all(_C.inset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TileGrid(
            tiles: tiles,
            columns: 4,
            cell: const Size.square(_C.row),
            gap: _C.gap,
            editing: _editing,
            onReorder: _saveControls,
            onRemove: (id) => _saveControls(<String>[
              for (final other in order)
                if (other != id) other,
            ]),
          ),
          Reveal(
            open: _editing,
            child: Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(2, 0, 0, 8),
                    child: Text(
                      context.tr('Add Controls'),
                      style: BarType.section.copyWith(
                        color: theme.colors.textSecondary,
                      ),
                    ),
                  ),
                  TileLibrary(
                    choices: spare,
                    empty: context.tr('Everything is already here.'),
                    onAdd: (id) => _saveControls(<String>[...order, id]),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              if (_editing) ...<Widget>[
                TileEditButton(
                  label: context.tr('Reset'),
                  onTap: () => _saveControls(defaultControls),
                ),
                const SizedBox(width: 8),
              ],
              TileEditButton(
                label: context.tr(_editing ? 'Done' : 'Edit Controls'),
                strong: _editing,
                onTap: () => setState(() => _editing = !_editing),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.radius, required this.child});

  final double radius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    return Container(
      decoration: BoxDecoration(
        color: theme.colors.textPrimary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: theme.colors.textPrimary.withValues(alpha: 0.08),
        ),
      ),
      child: child,
    );
  }
}

class _Capsule extends StatelessWidget {
  const _Capsule({
    required this.icon,
    required this.on,
    required this.title,
    required this.detail,
    required this.onToggle,
    this.onOpen,
    this.colour = macBlue,
  });

  final IconData icon;
  final bool on;
  final String title;
  final String detail;
  final VoidCallback? onToggle;
  final VoidCallback? onOpen;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    return _Tile(
      radius: _C.row / 2,
      child: Row(
        children: <Widget>[
          const SizedBox(width: 11),
          Opacity(
            opacity: onToggle == null ? 0.45 : 1,
            child: Pressable(
              onTap: onToggle,
              scale: 0.88,
              child: MacDisc(icon: icon, on: on, size: 42, colour: colour),
            ),
          ),
          Expanded(
            child: Pressable(
              onTap: onOpen ?? onToggle,
              scale: 0.97,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(9, 0, 10, 0),
                child: SizedBox(
                  height: _C.row,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: BarType.title.copyWith(
                          color: theme.colors.textPrimary,
                        ),
                      ),
                      if (detail.isNotEmpty)
                        Text(
                          detail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: BarType.caption.copyWith(
                            fontSize: 12,
                            color: theme.colors.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Round extends StatelessWidget {
  const _Round({
    required this.icon,
    required this.on,
    required this.onTap,
    this.colour = macBlue,
    this.stateless = false,
  });

  final IconData icon;
  final bool on;
  final VoidCallback? onTap;
  final Color colour;

  /// An action rather than a switch: it has no On or Off to report.
  final bool stateless;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    return Opacity(
      opacity: onTap == null ? 0.45 : 1,
      child: Pressable(
        onTap: onTap,
        scale: 0.9,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: on
                ? colour
                : theme.colors.textPrimary.withValues(alpha: 0.07),
            border: Border.all(
              color: theme.colors.textPrimary.withValues(alpha: on ? 0 : 0.08),
            ),
          ),
          child: BarGlyph(
            icon,
            size: 24,
            color: on ? const Color(0xffffffff) : theme.colors.textPrimary,
          ),
        ),
      ),
    );
  }
}

class _MediaTile extends ConsumerWidget {
  const _MediaTile({required this.services});

  final ShellServices services;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.shellTheme;
    final playback = ref.watch(services.media).value;
    final commands = ref.watch(services.mediaCommands);
    final has = playback != null && playback.title.isNotEmpty;
    final ink = theme.colors.textPrimary;

    Widget control(IconData icon, bool enabled, VoidCallback onTap, double s) =>
        Pressable(
          onTap: enabled ? onTap : null,
          scale: 0.82,
          child: SizedBox(
            width: 36,
            height: 32,
            child: BarGlyph(
              icon,
              size: s,
              color: ink.withValues(alpha: enabled ? 1 : 0.3),
            ),
          ),
        );

    return _Tile(
      radius: 26,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(13, 13, 13, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            MediaArtwork(
              url: playback?.artUrl ?? '',
              size: 42,
              radius: 10,
              fallback: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: ink.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: BarGlyph(
                  BarIcons.playFill,
                  size: 18,
                  color: theme.colors.textSecondary,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              has ? playback.title : context.tr('Not Playing'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: BarType.title.copyWith(
                color: has ? ink : theme.colors.textSecondary,
              ),
            ),
            if (has && playback.artistLabel.isNotEmpty)
              Text(
                playback.artistLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: BarType.caption.copyWith(
                  color: theme.colors.textSecondary,
                ),
              ),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                control(
                  BarIcons.backward,
                  playback?.canGoPrevious ?? false,
                  commands.previous,
                  18,
                ),
                control(
                  playback?.playing == true
                      ? BarIcons.pauseFill
                      : BarIcons.playFill,
                  playback?.available ?? false,
                  commands.playPause,
                  24,
                ),
                control(
                  BarIcons.forward,
                  playback?.canGoNext ?? false,
                  commands.next,
                  18,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SliderTile extends StatelessWidget {
  const _SliderTile({
    required this.label,
    required this.value,
    required this.leading,
    required this.trailing,
    required this.onChanged,
    required this.onChangeEnd,
    this.onChangeStart,
    this.onOpen,
  });

  final String label;
  final double value;
  final IconData leading;
  final IconData trailing;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;
  final VoidCallback? onChangeStart;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    return _Tile(
      radius: 22,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 7, 8, 1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Pressable(
              onTap: onOpen,
              scale: 0.98,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 7),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        label,
                        style: BarType.section.copyWith(
                          color: theme.colors.textPrimary,
                        ),
                      ),
                    ),
                    if (onOpen != null)
                      BarGlyph(
                        BarIcons.chevronRight,
                        size: 11,
                        color: theme.colors.textSecondary,
                      ),
                  ],
                ),
              ),
            ),
            const Spacer(),
            MacSlider(
              value: value,
              leading: leading,
              trailing: trailing,
              onChangeStart: onChangeStart,
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            ),
          ],
        ),
      ),
    );
  }
}

/// Rebuilds once a second while the timer runs, and whenever it changes.
class _TimerWatch extends StatefulWidget {
  const _TimerWatch({required this.builder});

  final Widget Function(BuildContext context, DateTime now) builder;

  @override
  State<_TimerWatch> createState() => _TimerWatchState();
}

class _TimerWatchState extends State<_TimerWatch> {
  late final Timer _tick = Timer.periodic(const Duration(seconds: 1), (_) {
    if (islandTimer.active && !islandTimer.paused) setState(() {});
  });

  void _changed() => setState(() {});

  @override
  void initState() {
    super.initState();
    _tick;
    islandTimer.addListener(_changed);
  }

  @override
  void dispose() {
    _tick.cancel();
    islandTimer.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, DateTime.now());
}

class _TimerPage extends StatelessWidget {
  const _TimerPage({required this.onBack});

  final VoidCallback onBack;

  static const List<int> _minutes = <int>[1, 3, 5, 10, 15, 20, 25, 30, 45, 60];

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final ink = theme.colors.textPrimary;
    Widget chip(String label, VoidCallback onTap, {Color? fill, Color? text}) =>
        Pressable(
          onTap: onTap,
          scale: 0.94,
          child: Container(
            width: 50,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: fill ?? ink.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(17),
            ),
            child: Text(
              label,
              style: BarType.caption.copyWith(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: text ?? ink,
              ),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.all(8),
      child: _TimerWatch(
        builder: (context, now) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            MacHeader(title: context.tr('Timer'), onBack: onBack),
            const MacDivider(),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Center(
                child: Text(
                  islandTimer.active
                      ? clockSpan(islandTimer.remaining(now))
                      : '0:00',
                  style: BarType.display.copyWith(
                    fontSize: 40,
                    color: islandTimer.active && !islandTimer.paused
                        ? macOrange
                        : theme.colors.textSecondary,
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
              ),
            ),
            if (islandTimer.active)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  children: <Widget>[
                    chip(
                      '+1',
                      () => islandTimer.add(const Duration(minutes: 1), now),
                    ),
                    chip(
                      context.tr(islandTimer.paused ? 'Resume' : 'Pause'),
                      () => islandTimer.toggle(now),
                      fill: macOrange,
                      text: const Color(0xffffffff),
                    ),
                    chip(context.tr('Cancel'), islandTimer.cancel),
                  ],
                ),
              ),
            MacSection(context.tr('Start a Timer')),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final minutes in _minutes)
                    chip(
                      context.tr('{}m', minutes),
                      () => islandTimer.start(Duration(minutes: minutes), now),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
