import 'dart:async';
import 'dart:io';

import 'package:denial_flutter_sdk/models.dart';
import 'package:denial_flutter_sdk/services.dart';
import 'package:denial_flutter_sdk/settings.dart';
import 'package:denial_flutter_sdk/state.dart';
import 'package:denial_flutter_sdk/system_services.dart'
    show PowerProfile, systemActionsServiceProvider;
import 'package:denial_flutter_sdk/theme.dart';
import 'package:denial_shell_kit/kit_style.dart';
import 'package:flutter/material.dart' show Tooltip;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bar_icons.dart';
import '../bar_type.dart';
import '../l10n.dart';
import '../media_art.dart';
import '../night_light.dart';
import 'mac_kit.dart';

/// Builds a preset-authentic Control Centre / Quick Settings home layout for
/// non-macOS shell archetypes (`cutefish`, `gnome`, `windows`, `hyprpanel`,
/// `material`, `omarchy`, `cosmic`, `plasma`, `noctalia`, `caelestia`,
/// `axshell`).
///
/// Every interactive control connects to live Denial system providers and
/// drills into the shared detail pages (`wifi`, `bluetooth`, `display`,
/// `sound`) via [onOpenPage].
class ShellControlCenterView extends ConsumerStatefulWidget {
  const ShellControlCenterView({
    required this.archetype,
    required this.services,
    required this.output,
    required this.onOpenPage,
    required this.onSettings,
    required this.onConfirmPower,
    required this.onClose,
    this.tileKeys,
    super.key,
  });

  final KitShellArchetype archetype;
  final ShellServices services;
  final DisplayOutput output;
  final Map<String, GlobalKey>? tileKeys;
  final ValueChanged<String> onOpenPage;
  final VoidCallback onSettings;
  final ValueChanged<SessionPowerAction> onConfirmPower;
  final VoidCallback onClose;

  @override
  ConsumerState<ShellControlCenterView> createState() =>
      _ShellControlCenterViewState();
}

class _ShellControlCenterViewState
    extends ConsumerState<ShellControlCenterView> {
  bool _gnomePowerOpen = false;
  int _plasmaTab = 0; // 0 Audio, 1 Networks, 2 Display, 3 Power
  double _preMuteVol = 0.5;
  double _cpuLoad = 0.0;
  double _ramLoad = 0.0;
  int _prevCpuTotal = 0;
  int _prevCpuIdle = 0;
  Timer? _statsTimer;

  KitShellArchetype get archetype => widget.archetype;
  ShellServices get services => widget.services;
  DisplayOutput get output => widget.output;
  ValueChanged<String> get onOpenPage => widget.onOpenPage;
  VoidCallback get onSettings => widget.onSettings;
  ValueChanged<SessionPowerAction> get onConfirmPower => widget.onConfirmPower;
  VoidCallback get onClose => widget.onClose;

  GlobalKey? _keyFor(String id) =>
      widget.tileKeys?.putIfAbsent(id, GlobalKey.new);

  @override
  void initState() {
    super.initState();
    if (archetype == KitShellArchetype.hyprpanel) {
      unawaited(_sampleStats());
      _statsTimer = Timer.periodic(
        const Duration(seconds: 2),
        (_) => unawaited(_sampleStats()),
      );
    }
  }

  @override
  void dispose() {
    _statsTimer?.cancel();
    super.dispose();
  }

  Future<void> _sampleStats() async {
    try {
      final stat = await File('/proc/stat').readAsString();
      final line = stat.split('\n').first.trim().split(RegExp(r'\s+'));
      if (line.length >= 5) {
        final nums = <int>[
          for (var i = 1; i < line.length; i++) int.tryParse(line[i]) ?? 0,
        ];
        final idle = (nums.length > 3 ? nums[3] : 0) +
            (nums.length > 4 ? nums[4] : 0);
        final total = nums.fold<int>(0, (a, b) => a + b);
        if (_prevCpuTotal > 0 && total > _prevCpuTotal) {
          final dt = total - _prevCpuTotal;
          final di = idle - _prevCpuIdle;
          _cpuLoad = ((dt - di) / dt).clamp(0.0, 1.0);
        }
        _prevCpuTotal = total;
        _prevCpuIdle = idle;
      }
      final mem = await File('/proc/meminfo').readAsString();
      var memTotal = 0;
      var memAvail = 0;
      for (final row in mem.split('\n')) {
        if (row.startsWith('MemTotal:')) {
          memTotal = int.tryParse(row.split(RegExp(r'\s+'))[1]) ?? 0;
        } else if (row.startsWith('MemAvailable:')) {
          memAvail = int.tryParse(row.split(RegExp(r'\s+'))[1]) ?? 0;
        }
      }
      if (memTotal > 0) {
        _ramLoad = ((memTotal - memAvail) / memTotal).clamp(0.0, 1.0);
      }
      if (mounted) setState(() {});
    } catch (_) {}
  }

  void _toggleMute(double current) {
    services.beginVolumeInteraction();
    if (current > 0.001) {
      _preMuteVol = current;
      services.setVolume(0);
      services.commitVolume(0);
    } else {
      final next = _preMuteVol > 0.05 ? _preMuteVol : 0.5;
      services.setVolume(next);
      services.commitVolume(next);
    }
  }

  static String get _userHost {
    final user = Platform.environment['USER'] ?? 'user';
    final host = Platform.localHostname;
    return host.isEmpty ? user : '$user@$host';
  }

  @override
  Widget build(BuildContext context) {
    final child = switch (archetype) {
      KitShellArchetype.cutefish => _buildCutefish(context, ref),
      KitShellArchetype.gnome => _buildGnome(context, ref),
      KitShellArchetype.windows => _buildWindows(context, ref),
      KitShellArchetype.hyprpanel => _buildHyprPanel(context, ref),
      KitShellArchetype.material => _buildMaterial(context, ref),
      KitShellArchetype.omarchy => _buildOmarchy(context, ref),
      KitShellArchetype.cosmic => _buildCosmic(context, ref),
      KitShellArchetype.plasma => _buildPlasma(context, ref),
      KitShellArchetype.noctalia => _buildNoctalia(context, ref),
      KitShellArchetype.caelestia => _buildCaelestia(context, ref),
      KitShellArchetype.axshell => _buildAxShell(context, ref),
      _ => const SizedBox.shrink(),
    };
    return SingleChildScrollView(child: child);
  }

  _ShellLiveState _readState(BuildContext context, WidgetRef ref) {
    final wifiOn = ref.watch(
      networkConnectivityProvider.select(
        (state) => state.snapshot.wirelessEnabled,
      ),
    );
    final wifi = ref.watch(services.connectedWifi);
    final bt = ref.watch(bluetoothProvider);
    final btOn = bt.available && bt.powered;
    final btConnected = <String>[
      for (final d in bt.devices)
        if (d.connected) d.name,
    ];
    final focus = ref.watch(
      desktopNotificationsProvider.select((state) => state.doNotDisturb),
    );
    final dark = ref.watch(shellSettingsProvider.select(kitSystemIsDark));
    final power = ref.watch(desktopPowerModesProvider);
    final battery = ref.watch(services.battery);
    final plugged = ref.watch(
      upowerProvider.select((state) => state.snapshot?.onBattery == false),
    );
    final volume = ref.watch(services.volume);
    final audible = ref.watch(services.volumeAvailable);
    final brightness = ref.watch(
      displayBrightnessProvider.select((s) => s.levels[output.monitorId]),
    );
    return _ShellLiveState(
      wifiOn: wifiOn,
      wifiLabel: !wifiOn
          ? context.tr('Off')
          : (wifi?.ssid ?? context.tr('Not Connected')),
      btAvailable: bt.available,
      btOn: btOn,
      btLabel: !bt.available
          ? context.tr('Unavailable')
          : !btOn
          ? context.tr('Off')
          : btConnected.isEmpty
          ? context.tr('On')
          : btConnected.first,
      focus: focus,
      dark: dark,
      powerAvailable: power.systemAvailable,
      powerProfile: power.systemProfile,
      batteryPercent: battery.capacity,
      charging: battery.charging || plugged,
      volume: volume,
      audible: audible,
      brightness: brightness,
    );
  }

  void _toggleWifi(WidgetRef ref, bool on) => ref
      .read(networkConnectivityProvider.notifier)
      .setWirelessEnabled(!on);

  void _toggleBt(WidgetRef ref, bool available) {
    if (available) ref.read(bluetoothProvider.notifier).togglePower();
  }

  void _toggleDnd(WidgetRef ref) =>
      ref.read(desktopNotificationsProvider.notifier).toggleDoNotDisturb();

  void _toggleDark(WidgetRef ref, bool dark) =>
      setKitSystemDarkMode(ref, !dark);

  void _cyclePower(WidgetRef ref, _ShellLiveState s) {
    if (!s.powerAvailable) return;
    ref
        .read(desktopPowerModesProvider.notifier)
        .selectSystemProfile(PowerProfile.next(s.powerProfile));
  }

  void _setBrightness(WidgetRef ref, double v, {bool commit = false}) {
    final ctrl = ref.read(displayBrightnessProvider.notifier);
    ctrl.setLevel(output, v);
    if (commit) ctrl.commitLevel(output, v);
  }

  void _lock(WidgetRef ref) {
    onClose();
    unawaited(
      ref.read(sessionPowerProvider.notifier).request(SessionPowerAction.lock),
    );
  }

  void _screenshot(WidgetRef ref) {
    onClose();
    ref.read(systemActionsServiceProvider).takeScreenshot();
  }

  // ── 1. GNOME Adwaita Quick Settings ───────────────────────────────────────

  Widget _buildGnome(BuildContext context, WidgetRef ref) {
    final theme = context.shellTheme;
    final style = KitStyle.of(context);
    final s = _readState(context, ref);
    final accent = style.accent(theme);
    final onAccent = style.onAccent(theme);
    final plate = theme.colors.surfaceContainerHigh;

    Widget circleBtn(
      IconData icon,
      String tip,
      VoidCallback onTap, {
      bool active = false,
    }) => Tooltip(
      message: tip,
      child: Pressable(
        onTap: onTap,
        shape: BorderRadius.circular(18),
        child: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? accent : plate,
            borderRadius: BorderRadius.circular(17),
          ),
          child: BarGlyph(
            icon,
            size: 15,
            color: active ? onAccent : theme.colors.textPrimary,
          ),
        ),
      ),
    );

    Widget pillToggle({
      required IconData icon,
      required String title,
      String? subtitle,
      required bool on,
      required VoidCallback onToggle,
      VoidCallback? onDetail,
    }) {
      final fg = on ? onAccent : theme.colors.textPrimary;
      final sub = on ? onAccent.withValues(alpha: 0.78) : theme.colors.textSecondary;
      return Container(
        height: 46,
        decoration: BoxDecoration(
          color: on ? accent : plate,
          borderRadius: BorderRadius.circular(23),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Pressable(
                onTap: onToggle,
                shape: BorderRadius.horizontal(
                  left: const Radius.circular(23),
                  right: onDetail == null ? const Radius.circular(23) : Radius.zero,
                ),
                child: Padding(
                  padding: const EdgeInsets.only(left: 12, right: 6),
                  child: Row(
                    children: <Widget>[
                      BarGlyph(icon, size: 16, color: fg),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: BarType.title.copyWith(
                                fontSize: 12.5,
                                color: fg,
                              ),
                            ),
                            if (subtitle != null && subtitle.isNotEmpty)
                              Text(
                                subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: BarType.caption.copyWith(
                                  fontSize: 10.5,
                                  color: sub,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (onDetail != null) ...<Widget>[
              Container(
                width: 1,
                height: 22,
                color: fg.withValues(alpha: 0.18),
              ),
              Pressable(
                onTap: onDetail,
                shape: const BorderRadius.horizontal(
                  right: Radius.circular(23),
                ),
                child: SizedBox(
                  width: 30,
                  height: 46,
                  child: Center(
                    child: BarGlyph(BarIcons.chevronRight, size: 11, color: fg),
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Top utility row: battery pill + circular screenshot / settings / lock / power
          Row(
            children: <Widget>[
              if (s.batteryPercent != null)
                Container(
                  height: 34,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: plate,
                    borderRadius: BorderRadius.circular(17),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      BarGlyph(
                        s.charging ? BarIcons.boltFill : BarIcons.battery75,
                        size: 14,
                        color: theme.colors.textPrimary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${s.batteryPercent}%',
                        style: BarType.title.copyWith(
                          fontSize: 12.5,
                          color: theme.colors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              const Spacer(),
              circleBtn(BarIcons.camera, context.tr('Screenshot'), () => _screenshot(ref)),
              const SizedBox(width: 8),
              circleBtn(BarIcons.gear, context.tr('Settings'), onSettings),
              const SizedBox(width: 8),
              circleBtn(BarIcons.lockFill, context.tr('Lock Screen'), () => _lock(ref)),
              const SizedBox(width: 8),
              circleBtn(
                BarIcons.power,
                context.tr('Power Off / Log Out'),
                () => setState(() => _gnomePowerOpen = !_gnomePowerOpen),
                active: _gnomePowerOpen,
              ),
            ],
          ),
          Reveal(
            open: _gnomePowerOpen,
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: plate,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    for (final item in <(IconData, String, VoidCallback)>[
                      (
                        BarIcons.moonFill,
                        context.tr('Sleep'),
                        () {
                          onClose();
                          unawaited(
                            ref
                                .read(sessionPowerProvider.notifier)
                                .request(SessionPowerAction.suspend),
                          );
                        },
                      ),
                      (
                        BarIcons.arrowClockwise,
                        context.tr('Restart'),
                        () {
                          onClose();
                          onConfirmPower(SessionPowerAction.reboot);
                        },
                      ),
                      (
                        BarIcons.power,
                        context.tr('Shut Down'),
                        () {
                          onClose();
                          onConfirmPower(SessionPowerAction.powerOff);
                        },
                      ),
                      (
                        BarIcons.lockFill,
                        context.tr('Log Out'),
                        () {
                          onClose();
                          onConfirmPower(SessionPowerAction.logout);
                        },
                      ),
                    ])
                      Pressable(
                        onTap: item.$3,
                        shape: BorderRadius.circular(10),
                        wash: true,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          child: Row(
                            children: <Widget>[
                              BarGlyph(
                                item.$1,
                                size: 14,
                                color: theme.colors.textPrimary,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  item.$2,
                                  style: BarType.menuRow.copyWith(
                                    color: theme.colors.textPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          // Sliders: Volume (tap icon to mute) & Brightness
          KeyedSubtree(
            key: _keyFor('sound'),
            child: _SliderRow(
              icon: s.volume <= 0.001
                  ? BarIcons.speakerSlashFill
                  : BarIcons.speaker3Fill,
              value: s.volume,
              enabled: s.audible,
              onIconTap: s.audible ? () => _toggleMute(s.volume) : null,
              onChangeStart: services.beginVolumeInteraction,
              onChanged: services.setVolume,
              onChangeEnd: services.commitVolume,
              onDetail: () => onOpenPage('sound'),
            ),
          ),
          const SizedBox(height: 8),
          KeyedSubtree(
            key: _keyFor('display'),
            child: _SliderRow(
              icon: BarIcons.sunMaxFill,
              value: s.brightness ?? 0.5,
              enabled: s.brightness != null,
              onChanged: (v) => _setBrightness(ref, v),
              onChangeEnd: (v) => _setBrightness(ref, v, commit: true),
              onDetail: () => onOpenPage('display'),
            ),
          ),
          const SizedBox(height: 14),
          // 2-column Adwaita pill toggles
          Row(
            children: <Widget>[
              Expanded(
                child: KeyedSubtree(
                  key: _keyFor('wifi'),
                  child: pillToggle(
                    icon: s.wifiOn ? BarIcons.wifi : BarIcons.wifiSlash,
                    title: 'Wi-Fi',
                    subtitle: s.wifiLabel,
                    on: s.wifiOn,
                    onToggle: () => _toggleWifi(ref, s.wifiOn),
                    onDetail: () => onOpenPage('wifi'),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: KeyedSubtree(
                  key: _keyFor('bluetooth'),
                  child: pillToggle(
                    icon: BarIcons.bluetooth,
                    title: context.tr('Bluetooth'),
                    subtitle: s.btLabel,
                    on: s.btOn,
                    onToggle: () => _toggleBt(ref, s.btAvailable),
                    onDetail: () => onOpenPage('bluetooth'),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: pillToggle(
                  icon: BarIcons.bolt,
                  title: context.tr('Power Mode'),
                  subtitle: _powerLabel(context, s.powerProfile),
                  on: s.powerAvailable && s.powerProfile != PowerProfile.balanced,
                  onToggle: () => _cyclePower(ref, s),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ValueListenableBuilder<bool>(
                  valueListenable: NightLight.enabled,
                  builder: (context, night, _) => pillToggle(
                    icon: night ? BarIcons.sunMaxFill : BarIcons.sunMax,
                    title: context.tr('Night Light'),
                    on: night,
                    onToggle: NightLight.toggle,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: pillToggle(
                  icon: BarIcons.circleHalf,
                  title: context.tr('Dark Mode'),
                  on: s.dark,
                  onToggle: () => _toggleDark(ref, s.dark),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: pillToggle(
                  icon: BarIcons.moonFill,
                  title: context.tr('Focus'),
                  on: s.focus,
                  onToggle: () => _toggleDnd(ref),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── 2. Windows 11 Fluent Quick Settings ───────────────────────────────────

  Widget _buildWindows(BuildContext context, WidgetRef ref) {
    final theme = context.shellTheme;
    final style = KitStyle.of(context);
    final s = _readState(context, ref);
    final accent = style.accent(theme);
    final onAccent = style.onAccent(theme);
    final tileBg = theme.colors.surfaceContainerHigh;
    final border = theme.colors.hairline;

    Widget tile({
      required IconData icon,
      required String label,
      required bool on,
      required VoidCallback onToggle,
      VoidCallback? onDetail,
    }) {
      final fg = on ? onAccent : theme.colors.textPrimary;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            height: 46,
            decoration: BoxDecoration(
              color: on ? accent : tileBg,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                color: on ? accent : border,
                width: 0.8,
              ),
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Pressable(
                    onTap: onToggle,
                    shape: BorderRadius.horizontal(
                      left: const Radius.circular(5),
                      right: onDetail == null ? const Radius.circular(5) : Radius.zero,
                    ),
                    child: Center(child: BarGlyph(icon, size: 17, color: fg)),
                  ),
                ),
                if (onDetail != null) ...<Widget>[
                  Container(width: 1, height: 24, color: fg.withValues(alpha: 0.2)),
                  Pressable(
                    onTap: onDetail,
                    shape: const BorderRadius.horizontal(
                      right: Radius.circular(5),
                    ),
                    child: SizedBox(
                      width: 28,
                      height: 46,
                      child: Center(
                        child: BarGlyph(BarIcons.chevronRight, size: 10, color: fg),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 5),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: BarType.caption.copyWith(
              fontSize: 11,
              color: theme.colors.textPrimary,
            ),
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: tile(
                      icon: s.wifiOn ? BarIcons.wifi : BarIcons.wifiSlash,
                      label: 'Wi-Fi',
                      on: s.wifiOn,
                      onToggle: () => _toggleWifi(ref, s.wifiOn),
                      onDetail: () => onOpenPage('wifi'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: tile(
                      icon: BarIcons.bluetooth,
                      label: context.tr('Bluetooth'),
                      on: s.btOn,
                      onToggle: () => _toggleBt(ref, s.btAvailable),
                      onDetail: () => onOpenPage('bluetooth'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: tile(
                      icon: BarIcons.moonFill,
                      label: context.tr('Focus'),
                      on: s.focus,
                      onToggle: () => _toggleDnd(ref),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: tile(
                      icon: BarIcons.bolt,
                      label: context.tr('Power Mode'),
                      on: s.powerAvailable && s.powerProfile != PowerProfile.balanced,
                      onToggle: () => _cyclePower(ref, s),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ValueListenableBuilder<bool>(
                      valueListenable: NightLight.enabled,
                      builder: (context, night, _) => tile(
                        icon: night ? BarIcons.sunMaxFill : BarIcons.sunMax,
                        label: context.tr('Night Light'),
                        on: night,
                        onToggle: NightLight.toggle,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: tile(
                      icon: BarIcons.circleHalf,
                      label: context.tr('Dark Mode'),
                      on: s.dark,
                      onToggle: () => _toggleDark(ref, s.dark),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              KeyedSubtree(
                key: _keyFor('display'),
                child: _SliderRow(
                  icon: BarIcons.sunMaxFill,
                  value: s.brightness ?? 0.5,
                  enabled: s.brightness != null,
                  onChanged: (v) => _setBrightness(ref, v),
                  onChangeEnd: (v) => _setBrightness(ref, v, commit: true),
                  onDetail: () => onOpenPage('display'),
                ),
              ),
              const SizedBox(height: 10),
              KeyedSubtree(
                key: _keyFor('sound'),
                child: _SliderRow(
                  icon: s.volume <= 0.001
                      ? BarIcons.speakerSlashFill
                      : BarIcons.speaker3Fill,
                  value: s.volume,
                  enabled: s.audible,
                  onIconTap: s.audible ? () => _toggleMute(s.volume) : null,
                  onChangeStart: services.beginVolumeInteraction,
                  onChanged: services.setVolume,
                  onChangeEnd: services.commitVolume,
                  detailIcon: BarIcons.headphones,
                  onDetail: () => onOpenPage('sound'),
                ),
              ),
            ],
          ),
        ),
        // Bottom Fluent bar (battery on left, Settings gear on right — real Win11 has no Lock here)
        Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: theme.colors.surfaceContainerLow.withValues(alpha: 0.65),
            border: Border(top: BorderSide(color: border, width: 0.8)),
          ),
          child: Row(
            children: <Widget>[
              if (s.batteryPercent != null) ...<Widget>[
                BarGlyph(
                  s.charging ? BarIcons.boltFill : BarIcons.battery75,
                  size: 14,
                  color: theme.colors.textPrimary,
                ),
                const SizedBox(width: 6),
                Text(
                  '${s.batteryPercent}%',
                  style: BarType.caption.copyWith(
                    fontSize: 12,
                    color: theme.colors.textPrimary,
                  ),
                ),
              ],
              const Spacer(),
              Pressable(
                onTap: onSettings,
                shape: BorderRadius.circular(4),
                wash: true,
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: BarGlyph(
                    BarIcons.gear,
                    size: 14,
                    color: theme.colors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── 3. HyprPanel Catppuccin Dashboard (`hyprpanel/src/components/menus/dashboard/`)

  Widget _buildHyprPanel(BuildContext context, WidgetRef ref) {
    final theme = context.shellTheme;
    final s = _readState(context, ref);
    final dark = theme.brightness == Brightness.dark;
    final cardBg = theme.colors.surfaceContainerHigh;
    final border = theme.colors.hairline;

    // Catppuccin Mocha / Latte module accent hues
    final cBlue = dark ? const Color(0xff89b4fa) : const Color(0xff1e66f5);
    final cMauve = dark ? const Color(0xffcba6f7) : const Color(0xff8839ef);
    final cSky = dark ? const Color(0xff89dceb) : const Color(0xff04a5e5);
    final cPeach = dark ? const Color(0xfffab387) : const Color(0xfffe640b);
    final cRed = dark ? const Color(0xfff38ba8) : const Color(0xffd20f39);
    final cGreen = dark ? const Color(0xffa6e3a1) : const Color(0xff40a02b);
    final cYellow = dark ? const Color(0xfff9e2af) : const Color(0xffdf8e1d);
    final onTint = dark ? const Color(0xff1e1e2e) : const Color(0xffffffff);

    Widget powerDot(IconData icon, Color tint, VoidCallback onTap) => Pressable(
      onTap: onTap,
      shape: BorderRadius.circular(7),
      child: Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: tint.withValues(alpha: dark ? 0.2 : 0.16),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: tint.withValues(alpha: 0.55), width: 0.8),
        ),
        child: BarGlyph(icon, size: 13, color: tint),
      ),
    );

    Widget toggleChip(IconData icon, Color tint, bool on, VoidCallback onTap) =>
        Expanded(
          child: Pressable(
            onTap: onTap,
            shape: BorderRadius.circular(7),
            child: Container(
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on ? tint : cardBg,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: on ? tint : border, width: 0.8),
              ),
              child: BarGlyph(
                icon,
                size: 16,
                color: on ? onTint : theme.colors.textPrimary,
              ),
            ),
          ),
        );

    Widget quickLink(
      String id,
      IconData icon,
      String label,
      Color tint,
      VoidCallback onTap,
    ) => Expanded(
      child: KeyedSubtree(
        key: _keyFor(id),
        child: Pressable(
          onTap: onTap,
          shape: BorderRadius.circular(6),
          child: Container(
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: dark ? 0.14 : 0.1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: tint.withValues(alpha: 0.35), width: 0.8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                BarGlyph(icon, size: 12, color: tint),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: BarType.caption.copyWith(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: theme.colors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    Widget statBar(String label, double ratio, Color tint, {String? valueText}) {
      final pct = (ratio.clamp(0.0, 1.0) * 100).round();
      return Row(
        children: <Widget>[
          SizedBox(
            width: 34,
            child: Text(
              label,
              style: BarType.caption.copyWith(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: tint,
              ),
            ),
          ),
          Expanded(
            child: Container(
              height: 8,
              decoration: BoxDecoration(
                color: theme.colors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(4),
              ),
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: ratio.clamp(0.04, 1.0),
                child: Container(
                  decoration: BoxDecoration(
                    color: tint,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 34,
            child: Text(
              valueText ?? '$pct%',
              textAlign: TextAlign.right,
              style: BarType.caption.copyWith(
                fontSize: 10.5,
                color: theme.colors.textSecondary,
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Card 1: Profile + 4-color Catppuccin PowerMenu
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: border, width: 0.8),
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: cMauve.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(17),
                    border: Border.all(color: cMauve, width: 1.2),
                  ),
                  alignment: Alignment.center,
                  child: BarGlyph(BarIcons.person, size: 16, color: cMauve),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        _userHost,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: BarType.title.copyWith(
                          fontSize: 12.5,
                          color: theme.colors.textPrimary,
                        ),
                      ),
                      Text(
                        s.batteryPercent != null
                            ? '${s.batteryPercent}% · ${_powerLabel(context, s.powerProfile)}'
                            : _powerLabel(context, s.powerProfile),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: BarType.caption.copyWith(
                          fontSize: 10.5,
                          color: theme.colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                powerDot(BarIcons.gear, cSky, onSettings),
                const SizedBox(width: 5),
                powerDot(BarIcons.lockFill, cGreen, () => _lock(ref)),
                const SizedBox(width: 5),
                powerDot(BarIcons.arrowClockwise, cYellow, () {
                  onClose();
                  onConfirmPower(SessionPowerAction.reboot);
                }),
                const SizedBox(width: 5),
                powerDot(BarIcons.power, cRed, () {
                  onClose();
                  onConfirmPower(SessionPowerAction.powerOff);
                }),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // Card 2: 5-button Controls strip (matches HyprPanel Controls.tsx)
          Row(
            children: <Widget>[
              toggleChip(
                s.wifiOn ? BarIcons.wifi : BarIcons.wifiSlash,
                cBlue,
                s.wifiOn,
                () => _toggleWifi(ref, s.wifiOn),
              ),
              const SizedBox(width: 6),
              toggleChip(
                BarIcons.bluetooth,
                cSky,
                s.btOn,
                () => _toggleBt(ref, s.btAvailable),
              ),
              const SizedBox(width: 6),
              toggleChip(
                BarIcons.moonFill,
                cMauve,
                s.focus,
                () => _toggleDnd(ref),
              ),
              const SizedBox(width: 6),
              ValueListenableBuilder<bool>(
                valueListenable: NightLight.enabled,
                builder: (context, night, _) => toggleChip(
                  BarIcons.sunMaxFill,
                  cPeach,
                  night,
                  NightLight.toggle,
                ),
              ),
              const SizedBox(width: 6),
              toggleChip(
                BarIcons.circleHalf,
                cGreen,
                s.dark,
                () => _toggleDark(ref, s.dark),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              quickLink('wifi', BarIcons.wifi, 'Wi-Fi', cBlue, () => onOpenPage('wifi')),
              const SizedBox(width: 6),
              quickLink('bluetooth', BarIcons.bluetooth, 'BT', cSky, () => onOpenPage('bluetooth')),
              const SizedBox(width: 6),
              quickLink('sound', BarIcons.speaker3Fill, context.tr('Sound'), cPeach, () => onOpenPage('sound')),
              const SizedBox(width: 6),
              quickLink('display', BarIcons.sunMaxFill, context.tr('Display'), cYellow, () => onOpenPage('display')),
            ],
          ),
          const SizedBox(height: 10),
          // Card 3: Catppuccin StatBars (CPU / RAM / Volume / Battery)
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: border, width: 0.8),
            ),
            child: Column(
              children: <Widget>[
                statBar('CPU', _cpuLoad, cRed),
                const SizedBox(height: 7),
                statBar('RAM', _ramLoad, cMauve),
                if (s.batteryPercent != null) ...<Widget>[
                  const SizedBox(height: 7),
                  statBar('BAT', s.batteryPercent! / 100.0, cGreen),
                ],
                const SizedBox(height: 10),
                _SliderRow(
                  icon: s.volume <= 0.001
                      ? BarIcons.speakerSlashFill
                      : BarIcons.speaker3Fill,
                  value: s.volume,
                  enabled: s.audible,
                  onIconTap: s.audible ? () => _toggleMute(s.volume) : null,
                  onChangeStart: services.beginVolumeInteraction,
                  onChanged: services.setVolume,
                  onChangeEnd: services.commitVolume,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 4. Material 3 (DMS / Dux) Control Dashboard ───────────────────────────

  Widget _buildMaterial(BuildContext context, WidgetRef ref) {
    final theme = context.shellTheme;
    final style = KitStyle.of(context);
    final s = _readState(context, ref);
    final accent = style.accent(theme);
    final onAccent = style.onAccent(theme);
    final cardBg = theme.colors.surfaceContainerHigh;

    Widget m3IconBtn(IconData icon, VoidCallback onTap, {bool tonal = false}) =>
        Pressable(
          onTap: onTap,
          shape: BorderRadius.circular(14),
          child: Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tonal ? accent.withValues(alpha: 0.2) : cardBg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: BarGlyph(
              icon,
              size: 15,
              color: tonal ? accent : theme.colors.textPrimary,
            ),
          ),
        );

    Widget m3Card({
      required IconData icon,
      required String title,
      required String subtitle,
      required bool on,
      required VoidCallback onToggle,
      VoidCallback? onDetail,
      String? keyId,
    }) {
      final fg = on ? onAccent : theme.colors.textPrimary;
      final sub = on
          ? onAccent.withValues(alpha: 0.8)
          : theme.colors.textSecondary;
      final card = Container(
        height: 58,
        decoration: BoxDecoration(
          color: on ? accent : cardBg,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Pressable(
                onTap: onToggle,
                shape: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: <Widget>[
                      BarGlyph(icon, size: 18, color: fg),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: BarType.title.copyWith(color: fg),
                            ),
                            Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: BarType.caption.copyWith(color: sub),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (onDetail != null)
              Pressable(
                onTap: onDetail,
                shape: const BorderRadius.horizontal(
                  right: Radius.circular(20),
                ),
                child: SizedBox(
                  width: 32,
                  height: 58,
                  child: Center(
                    child: BarGlyph(BarIcons.chevronRight, size: 12, color: fg),
                  ),
                ),
              ),
          ],
        ),
      );
      return keyId == null ? card : KeyedSubtree(key: _keyFor(keyId), child: card);
    }

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // DMS top user pill + M3 squircle action buttons
          Row(
            children: <Widget>[
              Expanded(
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    children: <Widget>[
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: accent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        alignment: Alignment.center,
                        child: BarGlyph(
                          BarIcons.person,
                          size: 12,
                          color: onAccent,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _userHost,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: BarType.caption.copyWith(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: theme.colors.textPrimary,
                          ),
                        ),
                      ),
                      if (s.batteryPercent != null)
                        Text(
                          '${s.batteryPercent}%',
                          style: BarType.caption.copyWith(
                            fontSize: 11,
                            color: theme.colors.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              m3IconBtn(BarIcons.gear, onSettings),
              const SizedBox(width: 6),
              m3IconBtn(BarIcons.lockFill, () => _lock(ref)),
              const SizedBox(width: 6),
              m3IconBtn(
                BarIcons.power,
                () {
                  onClose();
                  onConfirmPower(SessionPowerAction.powerOff);
                },
                tonal: true,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: m3Card(
                  keyId: 'wifi',
                  icon: s.wifiOn ? BarIcons.wifi : BarIcons.wifiSlash,
                  title: 'Wi-Fi',
                  subtitle: s.wifiLabel,
                  on: s.wifiOn,
                  onToggle: () => _toggleWifi(ref, s.wifiOn),
                  onDetail: () => onOpenPage('wifi'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: m3Card(
                  keyId: 'bluetooth',
                  icon: BarIcons.bluetooth,
                  title: context.tr('Bluetooth'),
                  subtitle: s.btLabel,
                  on: s.btOn,
                  onToggle: () => _toggleBt(ref, s.btAvailable),
                  onDetail: () => onOpenPage('bluetooth'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: m3Card(
                  icon: BarIcons.moonFill,
                  title: context.tr('Do Not Disturb'),
                  subtitle: context.tr(s.focus ? 'On' : 'Off'),
                  on: s.focus,
                  onToggle: () => _toggleDnd(ref),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ValueListenableBuilder<bool>(
                  valueListenable: NightLight.enabled,
                  builder: (context, night, _) => m3Card(
                    icon: BarIcons.sunMaxFill,
                    title: context.tr('Night Light'),
                    subtitle: context.tr(night ? 'On' : 'Off'),
                    on: night,
                    onToggle: NightLight.toggle,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: m3Card(
                  icon: BarIcons.circleHalf,
                  title: context.tr('Dark Mode'),
                  subtitle: context.tr(s.dark ? 'On' : 'Off'),
                  on: s.dark,
                  onToggle: () => _toggleDark(ref, s.dark),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: m3Card(
                  icon: BarIcons.bolt,
                  title: context.tr('Power Mode'),
                  subtitle: _powerLabel(context, s.powerProfile),
                  on:
                      s.powerAvailable &&
                      s.powerProfile != PowerProfile.balanced,
                  onToggle: () => _cyclePower(ref, s),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          KeyedSubtree(
            key: _keyFor('display'),
            child: _SliderRow(
              icon: BarIcons.sunMaxFill,
              value: s.brightness ?? 0.5,
              enabled: s.brightness != null,
              height: 28,
              showPercent: true,
              onChanged: (v) => _setBrightness(ref, v),
              onChangeEnd: (v) => _setBrightness(ref, v, commit: true),
              onDetail: () => onOpenPage('display'),
            ),
          ),
          const SizedBox(height: 10),
          KeyedSubtree(
            key: _keyFor('sound'),
            child: _SliderRow(
              icon: s.volume <= 0.001
                  ? BarIcons.speakerSlashFill
                  : BarIcons.speaker3Fill,
              value: s.volume,
              enabled: s.audible,
              height: 28,
              showPercent: true,
              onIconTap: s.audible ? () => _toggleMute(s.volume) : null,
              onChangeStart: services.beginVolumeInteraction,
              onChanged: services.setVolume,
              onChangeEnd: services.commitVolume,
              onDetail: () => onOpenPage('sound'),
            ),
          ),
        ],
      ),
    );
  }

  // ── 5a. Omarchy Terminal Crisp Panel (`omarchy/shell/plugins/panels/`) ────

  Widget _buildOmarchy(BuildContext context, WidgetRef ref) {
    final theme = context.shellTheme;
    final style = KitStyle.of(context);
    final s = _readState(context, ref);
    final accent = style.accent(theme);
    final onAccent = style.onAccent(theme);
    final border = theme.colors.hairline;

    Widget kvRow({
      required String tag,
      required String value,
      required bool on,
      required VoidCallback onToggle,
      VoidCallback? onDetail,
      String? keyId,
    }) {
      final row = Container(
        height: 34,
        decoration: BoxDecoration(
          color: on
              ? accent.withValues(alpha: 0.16)
              : theme.colors.surfaceContainerHigh,
          border: Border.all(color: on ? accent : border, width: 1),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Pressable(
                onTap: onToggle,
                shape: BorderRadius.zero,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    children: <Widget>[
                      Text(
                        on ? '[*]' : '[ ]',
                        style: BarType.caption.copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: on ? accent : theme.colors.textTertiary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          tag,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: BarType.menuRow.copyWith(
                            color: theme.colors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: BarType.caption.copyWith(
                          fontSize: 11,
                          color: on ? accent : theme.colors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (onDetail != null)
              Pressable(
                onTap: onDetail,
                shape: BorderRadius.zero,
                child: Container(
                  width: 30,
                  height: 34,
                  decoration: BoxDecoration(
                    border: Border(left: BorderSide(color: border, width: 1)),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '>',
                    style: BarType.caption.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: theme.colors.textSecondary,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
      return keyId == null ? row : KeyedSubtree(key: _keyFor(keyId), child: row);
    }

    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Terminal PanelHero: host + battery flow progress bar + power profile
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colors.surfaceContainerHigh,
              border: Border.all(color: border, width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Text(
                      _userHost,
                      style: BarType.caption.copyWith(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: accent,
                      ),
                    ),
                    const Spacer(),
                    Pressable(
                      onTap: () => _cyclePower(ref, s),
                      shape: BorderRadius.zero,
                      child: Text(
                        _powerLabel(context, s.powerProfile).toUpperCase(),
                        style: BarType.caption.copyWith(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: theme.colors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
                if (s.batteryPercent != null) ...<Widget>[
                  const SizedBox(height: 6),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Container(
                          height: 6,
                          color: theme.colors.surfaceContainerLow,
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: (s.batteryPercent! / 100.0).clamp(
                              0.02,
                              1.0,
                            ),
                            child: Container(color: accent),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${s.batteryPercent}%${s.charging ? '+' : ''}',
                        style: BarType.caption.copyWith(
                          fontSize: 10.5,
                          color: theme.colors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 6),
          kvRow(
            keyId: 'wifi',
            tag: 'WIFI',
            value: s.wifiLabel,
            on: s.wifiOn,
            onToggle: () => _toggleWifi(ref, s.wifiOn),
            onDetail: () => onOpenPage('wifi'),
          ),
          const SizedBox(height: 5),
          kvRow(
            keyId: 'bluetooth',
            tag: 'BT',
            value: s.btLabel,
            on: s.btOn,
            onToggle: () => _toggleBt(ref, s.btAvailable),
            onDetail: () => onOpenPage('bluetooth'),
          ),
          const SizedBox(height: 5),
          kvRow(
            tag: context.tr('Do Not Disturb'),
            value: context.tr(s.focus ? 'On' : 'Off'),
            on: s.focus,
            onToggle: () => _toggleDnd(ref),
          ),
          const SizedBox(height: 5),
          ValueListenableBuilder<bool>(
            valueListenable: NightLight.enabled,
            builder: (context, night, _) => kvRow(
              tag: context.tr('Night Light'),
              value: context.tr(night ? 'On' : 'Off'),
              on: night,
              onToggle: NightLight.toggle,
            ),
          ),
          const SizedBox(height: 5),
          kvRow(
            tag: context.tr('Dark Mode'),
            value: context.tr(s.dark ? 'On' : 'Off'),
            on: s.dark,
            onToggle: () => _toggleDark(ref, s.dark),
          ),
          const SizedBox(height: 8),
          KeyedSubtree(
            key: _keyFor('sound'),
            child: _SliderRow(
              icon: s.volume <= 0.001
                  ? BarIcons.speakerSlashFill
                  : BarIcons.speaker3Fill,
              value: s.volume,
              enabled: s.audible,
              showPercent: true,
              onIconTap: s.audible ? () => _toggleMute(s.volume) : null,
              onChangeStart: services.beginVolumeInteraction,
              onChanged: services.setVolume,
              onChangeEnd: services.commitVolume,
              onDetail: () => onOpenPage('sound'),
            ),
          ),
          const SizedBox(height: 6),
          KeyedSubtree(
            key: _keyFor('display'),
            child: _SliderRow(
              icon: BarIcons.sunMaxFill,
              value: s.brightness ?? 0.5,
              enabled: s.brightness != null,
              showPercent: true,
              onChanged: (v) => _setBrightness(ref, v),
              onChangeEnd: (v) => _setBrightness(ref, v, commit: true),
              onDetail: () => onOpenPage('display'),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              for (final item in <(String, VoidCallback, bool)>[
                (context.tr('Settings'), onSettings, false),
                (context.tr('Lock'), () => _lock(ref), false),
                (
                  context.tr('Restart'),
                  () {
                    onClose();
                    onConfirmPower(SessionPowerAction.reboot);
                  },
                  false,
                ),
                (
                  context.tr('Off'),
                  () {
                    onClose();
                    onConfirmPower(SessionPowerAction.powerOff);
                  },
                  true,
                ),
              ]) ...<Widget>[
                Expanded(
                  child: Pressable(
                    onTap: item.$2,
                    shape: BorderRadius.zero,
                    child: Container(
                      height: 30,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: item.$3
                            ? accent
                            : theme.colors.surfaceContainerHigh,
                        border: Border.all(
                          color: item.$3 ? accent : border,
                          width: 1,
                        ),
                      ),
                      child: Text(
                        item.$1,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: BarType.caption.copyWith(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: item.$3 ? onAccent : theme.colors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
                if (item.$1 != context.tr('Off')) const SizedBox(width: 5),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // ── 5b. COSMIC libcosmic Rounded Applet Menu (`cosmic-applets`) ───────────

  Widget _buildCosmic(BuildContext context, WidgetRef ref) {
    final theme = context.shellTheme;
    final style = KitStyle.of(context);
    final s = _readState(context, ref);
    final accent = style.accent(theme);
    final cardBg = theme.colors.surfaceContainerHigh;
    final border = theme.colors.hairline;

    Widget cosmicSwitchRow({
      required IconData icon,
      required String title,
      String? subtitle,
      required bool on,
      required VoidCallback onToggle,
      VoidCallback? onDetail,
      String? keyId,
    }) {
      final row = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Row(
          children: <Widget>[
            BarGlyph(
              icon,
              size: 16,
              color: on ? accent : theme.colors.textSecondary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Pressable(
                onTap: onDetail ?? onToggle,
                shape: BorderRadius.circular(6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: BarType.menuRow.copyWith(
                        color: theme.colors.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (subtitle != null && subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: BarType.caption.copyWith(
                          fontSize: 10.5,
                          color: theme.colors.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (onDetail != null) ...<Widget>[
              Pressable(
                onTap: onDetail,
                shape: BorderRadius.circular(8),
                wash: true,
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: BarGlyph(
                    BarIcons.chevronRight,
                    size: 11,
                    color: theme.colors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 4),
            ],
            MacSwitch(value: on, onChanged: (_) => onToggle()),
          ],
        ),
      );
      return keyId == null ? row : KeyedSubtree(key: _keyFor(keyId), child: row);
    }

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // libcosmic padded_control grouped switch rows
          Container(
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: border, width: 0.8),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                cosmicSwitchRow(
                  keyId: 'wifi',
                  icon: s.wifiOn ? BarIcons.wifi : BarIcons.wifiSlash,
                  title: 'Wi-Fi',
                  subtitle: s.wifiLabel,
                  on: s.wifiOn,
                  onToggle: () => _toggleWifi(ref, s.wifiOn),
                  onDetail: () => onOpenPage('wifi'),
                ),
                Container(height: 1, color: border),
                cosmicSwitchRow(
                  keyId: 'bluetooth',
                  icon: BarIcons.bluetooth,
                  title: context.tr('Bluetooth'),
                  subtitle: s.btLabel,
                  on: s.btOn,
                  onToggle: () => _toggleBt(ref, s.btAvailable),
                  onDetail: () => onOpenPage('bluetooth'),
                ),
                Container(height: 1, color: border),
                cosmicSwitchRow(
                  icon: BarIcons.moonFill,
                  title: context.tr('Do Not Disturb'),
                  on: s.focus,
                  onToggle: () => _toggleDnd(ref),
                ),
                Container(height: 1, color: border),
                ValueListenableBuilder<bool>(
                  valueListenable: NightLight.enabled,
                  builder: (context, night, _) => cosmicSwitchRow(
                    icon: BarIcons.sunMaxFill,
                    title: context.tr('Night Light'),
                    on: night,
                    onToggle: NightLight.toggle,
                  ),
                ),
                Container(height: 1, color: border),
                cosmicSwitchRow(
                  icon: BarIcons.circleHalf,
                  title: context.tr('Dark Mode'),
                  on: s.dark,
                  onToggle: () => _toggleDark(ref, s.dark),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: border, width: 0.8),
            ),
            child: Column(
              children: <Widget>[
                KeyedSubtree(
                  key: _keyFor('sound'),
                  child: _SliderRow(
                    icon: s.volume <= 0.001
                        ? BarIcons.speakerSlashFill
                        : BarIcons.speaker3Fill,
                    value: s.volume,
                    enabled: s.audible,
                    showPercent: true,
                    onIconTap: s.audible ? () => _toggleMute(s.volume) : null,
                    onChangeStart: services.beginVolumeInteraction,
                    onChanged: services.setVolume,
                    onChangeEnd: services.commitVolume,
                    onDetail: () => onOpenPage('sound'),
                  ),
                ),
                const SizedBox(height: 8),
                KeyedSubtree(
                  key: _keyFor('display'),
                  child: _SliderRow(
                    icon: BarIcons.sunMaxFill,
                    value: s.brightness ?? 0.5,
                    enabled: s.brightness != null,
                    showPercent: true,
                    onChanged: (v) => _setBrightness(ref, v),
                    onChangeEnd: (v) => _setBrightness(ref, v, commit: true),
                    onDetail: () => onOpenPage('display'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _CompactPowerFooter(
            batteryPercent: s.batteryPercent,
            charging: s.charging,
            radius: 8,
            onSettings: onSettings,
            onLock: () => _lock(ref),
            onReboot: () {
              onClose();
              onConfirmPower(SessionPowerAction.reboot);
            },
            onShutdown: () {
              onClose();
              onConfirmPower(SessionPowerAction.powerOff);
            },
          ),
        ],
      ),
    );
  }

  // ── 6. KDE Plasma 6 Breeze PlasmoidHeading Flyout ─────────────────────────

  Widget _buildPlasma(BuildContext context, WidgetRef ref) {
    final theme = context.shellTheme;
    final style = KitStyle.of(context);
    final s = _readState(context, ref);
    final accent = style.accent(theme);
    final border = theme.colors.hairline;

    final tabs = <(IconData, String)>[
      (BarIcons.speaker3Fill, context.tr('Sound')),
      (BarIcons.wifi, context.tr('Networks')),
      (BarIcons.sunMaxFill, context.tr('Display')),
      (BarIcons.boltFill, context.tr('Power')),
    ];

    Widget breezeRow({
      required IconData icon,
      required String title,
      required String detail,
      required bool on,
      required VoidCallback onToggle,
      VoidCallback? onDetail,
      String? keyId,
    }) {
      final row = Container(
        height: 44,
        decoration: BoxDecoration(
          color: on
              ? accent.withValues(alpha: 0.16)
              : theme.colors.surfaceContainerHigh.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: on ? accent : border, width: 1),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Pressable(
                onTap: onToggle,
                shape: BorderRadius.circular(5),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    children: <Widget>[
                      BarGlyph(
                        icon,
                        size: 16,
                        color: on ? accent : theme.colors.textPrimary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: BarType.menuRow.copyWith(
                                color: theme.colors.textPrimary,
                              ),
                            ),
                            Text(
                              detail,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: BarType.caption.copyWith(
                                fontSize: 10.5,
                                color: theme.colors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (onDetail != null)
              Pressable(
                onTap: onDetail,
                shape: BorderRadius.circular(5),
                child: SizedBox(
                  width: 30,
                  height: 44,
                  child: Center(
                    child: BarGlyph(
                      BarIcons.chevronRight,
                      size: 11,
                      color: theme.colors.textSecondary,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
      return keyId == null ? row : KeyedSubtree(key: _keyFor(keyId), child: row);
    }

    Widget tabBody() => switch (_plasmaTab) {
      0 => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          KeyedSubtree(
            key: _keyFor('sound'),
            child: _SliderRow(
              icon: s.volume <= 0.001
                  ? BarIcons.speakerSlashFill
                  : BarIcons.speaker3Fill,
              value: s.volume,
              enabled: s.audible,
              showPercent: true,
              onIconTap: s.audible ? () => _toggleMute(s.volume) : null,
              onChangeStart: services.beginVolumeInteraction,
              onChanged: services.setVolume,
              onChangeEnd: services.commitVolume,
              onDetail: () => onOpenPage('sound'),
            ),
          ),
          const SizedBox(height: 10),
          _DrawerMediaStrip(
            services: services,
            padBg: theme.colors.surfaceContainerHigh.withValues(alpha: 0.72),
            radius: 5,
          ),
        ],
      ),
      1 => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          breezeRow(
            keyId: 'wifi',
            icon: s.wifiOn ? BarIcons.wifi : BarIcons.wifiSlash,
            title: 'Wi-Fi',
            detail: s.wifiLabel,
            on: s.wifiOn,
            onToggle: () => _toggleWifi(ref, s.wifiOn),
            onDetail: () => onOpenPage('wifi'),
          ),
          const SizedBox(height: 8),
          breezeRow(
            keyId: 'bluetooth',
            icon: BarIcons.bluetooth,
            title: context.tr('Bluetooth'),
            detail: s.btLabel,
            on: s.btOn,
            onToggle: () => _toggleBt(ref, s.btAvailable),
            onDetail: () => onOpenPage('bluetooth'),
          ),
        ],
      ),
      2 => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          KeyedSubtree(
            key: _keyFor('display'),
            child: _SliderRow(
              icon: BarIcons.sunMaxFill,
              value: s.brightness ?? 0.5,
              enabled: s.brightness != null,
              showPercent: true,
              onChanged: (v) => _setBrightness(ref, v),
              onChangeEnd: (v) => _setBrightness(ref, v, commit: true),
              onDetail: () => onOpenPage('display'),
            ),
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder<bool>(
            valueListenable: NightLight.enabled,
            builder: (context, night, _) => breezeRow(
              icon: BarIcons.sunMaxFill,
              title: context.tr('Night Light'),
              detail: context.tr(night ? 'On' : 'Off'),
              on: night,
              onToggle: NightLight.toggle,
            ),
          ),
          const SizedBox(height: 8),
          breezeRow(
            icon: BarIcons.circleHalf,
            title: context.tr('Dark Mode'),
            detail: context.tr(s.dark ? 'On' : 'Off'),
            on: s.dark,
            onToggle: () => _toggleDark(ref, s.dark),
          ),
        ],
      ),
      _ => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          breezeRow(
            icon: BarIcons.bolt,
            title: context.tr('Power Mode'),
            detail: _powerLabel(context, s.powerProfile),
            on: s.powerAvailable && s.powerProfile != PowerProfile.balanced,
            onToggle: () => _cyclePower(ref, s),
          ),
          const SizedBox(height: 8),
          breezeRow(
            icon: BarIcons.moonFill,
            title: context.tr('Do Not Disturb'),
            detail: context.tr(s.focus ? 'On' : 'Off'),
            on: s.focus,
            onToggle: () => _toggleDnd(ref),
          ),
        ],
      ),
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // PlasmoidHeading: Breeze top tab bar + configure gear
        Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 8, 0),
          decoration: BoxDecoration(
            color: theme.colors.surfaceContainerLow.withValues(alpha: 0.72),
            border: Border(bottom: BorderSide(color: border, width: 1)),
          ),
          child: Row(
            children: <Widget>[
              for (var i = 0; i < tabs.length; i++)
                Expanded(
                  child: Pressable(
                    onTap: () => setState(() => _plasmaTab = i),
                    shape: BorderRadius.circular(4),
                    child: Container(
                      padding: const EdgeInsets.only(top: 4, bottom: 8),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: _plasmaTab == i
                                ? accent
                                : const Color(0x00000000),
                            width: 2.5,
                          ),
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          BarGlyph(
                            tabs[i].$1,
                            size: 14,
                            color: _plasmaTab == i
                                ? accent
                                : theme.colors.textSecondary,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            tabs[i].$2,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: BarType.caption.copyWith(
                              fontSize: 10.5,
                              fontWeight: _plasmaTab == i
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: _plasmaTab == i
                                  ? theme.colors.textPrimary
                                  : theme.colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              Pressable(
                onTap: onSettings,
                shape: BorderRadius.circular(4),
                wash: true,
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: BarGlyph(
                    BarIcons.gear,
                    size: 14,
                    color: theme.colors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              tabBody(),
              const SizedBox(height: 10),
              Container(height: 1, color: border),
              const SizedBox(height: 8),
              _CompactPowerFooter(
                batteryPercent: s.batteryPercent,
                charging: s.charging,
                radius: 5,
                onSettings: onSettings,
                onLock: () => _lock(ref),
                onReboot: () {
                  onClose();
                  onConfirmPower(SessionPowerAction.reboot);
                },
                onShutdown: () {
                  onClose();
                  onConfirmPower(SessionPowerAction.powerOff);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── 7. Cutefish Control Center (`cutefish-statusbar/qml/ControlCenter.qml`)

  Widget _buildCutefish(BuildContext context, WidgetRef ref) {
    final theme = context.shellTheme;
    final style = KitStyle.of(context);
    final s = _readState(context, ref);
    final accent = style.accent(theme);
    final onAccent = style.onAccent(theme);
    final cardBg = theme.colors.surfaceContainerHigh.withValues(alpha: 0.72);
    final r = style.corner(14);
    final now = DateTime.now();
    final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    Widget cardItem({
      required IconData icon,
      required String label,
      required bool on,
      required VoidCallback onTap,
      VoidCallback? onLongPress,
    }) {
      return Expanded(
        child: GestureDetector(
          onSecondaryTap: onLongPress,
          onLongPress: onLongPress,
          child: Pressable(
            onTap: onTap,
            scale: Pressable.small,
            shape: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: on
                          ? accent
                          : theme.colors.textPrimary.withValues(alpha: 0.09),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: BarGlyph(
                        icon,
                        size: 18,
                        color: on ? onAccent : theme.colors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: BarType.caption.copyWith(
                      fontSize: 11,
                      color: theme.colors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    Widget sliderCard({
      required IconData icon,
      required double value,
      required bool enabled,
      VoidCallback? onChangeStart,
      required ValueChanged<double> onChanged,
      ValueChanged<double>? onChangeEnd,
      VoidCallback? onDetail,
    }) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(r),
        ),
        child: _SliderRow(
          icon: icon,
          value: value,
          enabled: enabled,
          onChangeStart: onChangeStart,
          onChanged: onChanged,
          onChangeEnd: onChangeEnd,
          onDetail: onDetail,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                context.tr('Control Centre'),
                style: BarType.title.copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: theme.colors.textPrimary,
                ),
              ),
              const Spacer(),
              Pressable(
                onTap: onSettings,
                scale: Pressable.small,
                wash: true,
                shape: style.disc(30),
                child: SizedBox(
                  width: 30,
                  height: 30,
                  child: Center(
                    child: BarGlyph(
                      BarIcons.gear,
                      size: 15,
                      color: theme.colors.textPrimary,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 4-column Cutefish CardItem grid inside a single inner frosted plate
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(r),
            ),
            child: Column(
              children: <Widget>[
                Row(
                  children: <Widget>[
                    cardItem(
                      icon: s.wifiOn ? BarIcons.wifi : BarIcons.wifiSlash,
                      label: 'Wi-Fi',
                      on: s.wifiOn,
                      onTap: () => _toggleWifi(ref, s.wifiOn),
                      onLongPress: () => onOpenPage('wifi'),
                    ),
                    cardItem(
                      icon: BarIcons.bluetooth,
                      label: context.tr('Bluetooth'),
                      on: s.btOn,
                      onTap: () => _toggleBt(ref, s.btAvailable),
                      onLongPress: () => onOpenPage('bluetooth'),
                    ),
                    cardItem(
                      icon: BarIcons.circleHalf,
                      label: context.tr('Dark Mode'),
                      on: s.dark,
                      onTap: () => _toggleDark(ref, s.dark),
                    ),
                    cardItem(
                      icon: BarIcons.moonFill,
                      label: context.tr('Do Not Disturb'),
                      on: s.focus,
                      onTap: () => _toggleDnd(ref),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: <Widget>[
                    cardItem(
                      icon: BarIcons.camera,
                      label: context.tr('Screenshot'),
                      on: false,
                      onTap: () => _screenshot(ref),
                    ),
                    ValueListenableBuilder<bool>(
                      valueListenable: NightLight.enabled,
                      builder: (context, night, _) => cardItem(
                        icon: BarIcons.sunMaxFill,
                        label: context.tr('Night Light'),
                        on: night,
                        onTap: NightLight.toggle,
                      ),
                    ),
                    cardItem(
                      icon: BarIcons.bolt,
                      label: _powerLabel(context, s.powerProfile),
                      on: s.powerAvailable && s.powerProfile != PowerProfile.balanced,
                      onTap: () => _cyclePower(ref, s),
                    ),
                    cardItem(
                      icon: BarIcons.lockFill,
                      label: context.tr('Lock Screen'),
                      on: false,
                      onTap: () => _lock(ref),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _DrawerMediaStrip(services: services, radius: r, padBg: cardBg),
          const SizedBox(height: 10),
          sliderCard(
            icon: BarIcons.sunMaxFill,
            value: s.brightness ?? 0.5,
            enabled: s.brightness != null,
            onChanged: (v) => _setBrightness(ref, v),
            onChangeEnd: (v) => _setBrightness(ref, v, commit: true),
            onDetail: () => onOpenPage('display'),
          ),
          const SizedBox(height: 8),
          sliderCard(
            icon: s.volume <= 0.001
                ? BarIcons.speakerSlashFill
                : BarIcons.speaker3Fill,
            value: s.volume,
            enabled: s.audible,
            onChangeStart: services.beginVolumeInteraction,
            onChanged: services.setVolume,
            onChangeEnd: services.commitVolume,
            onDetail: () => onOpenPage('sound'),
          ),
          const SizedBox(height: 10),
          // Footer: Date on left, Battery percentage on right (ControlCenter.qml:431-491)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: <Widget>[
                Text(
                  dateStr,
                  style: BarType.caption.copyWith(
                    fontSize: 12,
                    color: theme.colors.textSecondary,
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
                const Spacer(),
                if (s.batteryPercent != null) ...<Widget>[
                  BarGlyph(
                    s.charging ? BarIcons.boltFill : BarIcons.battery75,
                    size: 14,
                    color: s.charging ? accent : theme.colors.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${s.batteryPercent}%',
                    style: BarType.caption.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: theme.colors.textPrimary,
                      fontFeatures: const <FontFeature>[
                        FontFeature.tabularFigures(),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 8. Noctalia Sidebar + Bento Home (`noctalia/tabs/home_tab.cpp`) ───────

  Widget _buildNoctalia(BuildContext context, WidgetRef ref) {
    final theme = context.shellTheme;
    final style = KitStyle.of(context);
    final s = _readState(context, ref);
    final accent = style.accent(theme);
    final onAccent = style.onAccent(theme);
    final r = style.corner(14);
    final cardBg = theme.colors.surfaceContainerHigh;

    Widget railBtn(IconData icon, VoidCallback? onTap, {bool active = false}) =>
        Pressable(
          onTap: onTap,
          scale: Pressable.small,
          shape: BorderRadius.circular(10),
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: active ? accent : const Color(0x00000000),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: BarGlyph(
                icon,
                size: 15,
                color: active ? onAccent : theme.colors.textSecondary,
              ),
            ),
          ),
        );

    Widget shortcutTile(IconData icon, bool on, VoidCallback onTap, {VoidCallback? onDetail}) =>
        GestureDetector(
          onSecondaryTap: onDetail,
          child: Pressable(
            onTap: onTap,
            scale: Pressable.small,
            shape: BorderRadius.circular(r),
            child: Container(
              height: 46,
              decoration: BoxDecoration(
                color: on ? accent : cardBg,
                borderRadius: BorderRadius.circular(r),
              ),
              child: Center(
                child: BarGlyph(
                  icon,
                  size: 17,
                  color: on ? onAccent : theme.colors.textPrimary,
                ),
              ),
            ),
          ),
        );

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Left vertical icon rail (Noctalia control_center_panel.cpp)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(r),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                railBtn(BarIcons.squareGrid, null, active: true),
                const SizedBox(height: 6),
                railBtn(BarIcons.wifi, () => onOpenPage('wifi')),
                const SizedBox(height: 6),
                railBtn(BarIcons.bluetooth, () => onOpenPage('bluetooth')),
                const SizedBox(height: 6),
                railBtn(BarIcons.speaker3Fill, () => onOpenPage('sound')),
                const SizedBox(height: 6),
                railBtn(BarIcons.sunMaxFill, () => onOpenPage('display')),
                const SizedBox(height: 12),
                railBtn(BarIcons.gear, onSettings),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // Right bento main pane: status banner + split (media/power | 2x3 shortcuts)
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _CompactPowerFooter(
                  batteryPercent: s.batteryPercent,
                  charging: s.charging,
                  radius: r,
                  onSettings: onSettings,
                  onLock: () => _lock(ref),
                  onReboot: () {
                    onClose();
                    onConfirmPower(SessionPowerAction.reboot);
                  },
                  onShutdown: () {
                    onClose();
                    onConfirmPower(SessionPowerAction.powerOff);
                  },
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    // Left column: Media + Power/Status card
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          _DrawerMediaStrip(
                            services: services,
                            radius: r,
                            padBg: cardBg,
                            compact: true,
                          ),
                          const SizedBox(height: 8),
                          Pressable(
                            onTap: () => _cyclePower(ref, s),
                            shape: BorderRadius.circular(r),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: cardBg,
                                borderRadius: BorderRadius.circular(r),
                              ),
                              child: Row(
                                children: <Widget>[
                                  BarGlyph(BarIcons.bolt, size: 15, color: accent),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _powerLabel(context, s.powerProfile),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: BarType.title.copyWith(
                                        fontSize: 12,
                                        color: theme.colors.textPrimary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Right column: 2×3 square Shortcuts grid
                    Expanded(
                      flex: 2,
                      child: Column(
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: shortcutTile(
                                  s.wifiOn ? BarIcons.wifi : BarIcons.wifiSlash,
                                  s.wifiOn,
                                  () => _toggleWifi(ref, s.wifiOn),
                                  onDetail: () => onOpenPage('wifi'),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: shortcutTile(
                                  BarIcons.bluetooth,
                                  s.btOn,
                                  () => _toggleBt(ref, s.btAvailable),
                                  onDetail: () => onOpenPage('bluetooth'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: shortcutTile(
                                  BarIcons.moonFill,
                                  s.focus,
                                  () => _toggleDnd(ref),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: ValueListenableBuilder<bool>(
                                  valueListenable: NightLight.enabled,
                                  builder: (context, night, _) => shortcutTile(
                                    BarIcons.sunMaxFill,
                                    night,
                                    NightLight.toggle,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: shortcutTile(
                                  BarIcons.circleHalf,
                                  s.dark,
                                  () => _toggleDark(ref, s.dark),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: shortcutTile(
                                  BarIcons.camera,
                                  false,
                                  () => _screenshot(ref),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _SliderRow(
                  icon: BarIcons.sunMaxFill,
                  value: s.brightness ?? 0.5,
                  enabled: s.brightness != null,
                  onChanged: (v) => _setBrightness(ref, v),
                  onChangeEnd: (v) => _setBrightness(ref, v, commit: true),
                  onDetail: () => onOpenPage('display'),
                ),
                const SizedBox(height: 6),
                _SliderRow(
                  icon: s.volume <= 0.001
                      ? BarIcons.speakerSlashFill
                      : BarIcons.speaker3Fill,
                  value: s.volume,
                  enabled: s.audible,
                  onChangeStart: services.beginVolumeInteraction,
                  onChanged: services.setVolume,
                  onChangeEnd: services.commitVolume,
                  onDetail: () => onOpenPage('sound'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 9. Caelestia Utilities Drawer (`caelestia/modules/utilities/Content.qml`)

  Widget _buildCaelestia(BuildContext context, WidgetRef ref) {
    final theme = context.shellTheme;
    final style = KitStyle.of(context);
    final s = _readState(context, ref);
    final accent = style.accent(theme);
    final onAccent = style.onAccent(theme);
    final r = style.corner(18);
    final padBg = theme.colors.surfaceContainerHigh;

    Widget pillToggle(
      IconData icon,
      bool on,
      VoidCallback onTap, {
      VoidCallback? onDetail,
    }) => Expanded(
      child: GestureDetector(
        onSecondaryTap: onDetail,
        child: Pressable(
          onTap: onTap,
          scale: Pressable.small,
          shape: BorderRadius.circular(20),
          child: Container(
            height: 40,
            decoration: BoxDecoration(
              color: on ? accent : padBg,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Center(
              child: BarGlyph(
                icon,
                size: 16,
                color: on ? onAccent : theme.colors.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _DrawerMediaStrip(services: services, radius: r, padBg: padBg),
          const SizedBox(height: 10),
          // Signature Caelestia M3 pill ButtonRow (cards/Toggles.qml)
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: theme.colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              children: <Widget>[
                pillToggle(
                  s.wifiOn ? BarIcons.wifi : BarIcons.wifiSlash,
                  s.wifiOn,
                  () => _toggleWifi(ref, s.wifiOn),
                  onDetail: () => onOpenPage('wifi'),
                ),
                const SizedBox(width: 6),
                pillToggle(
                  BarIcons.bluetooth,
                  s.btOn,
                  () => _toggleBt(ref, s.btAvailable),
                  onDetail: () => onOpenPage('bluetooth'),
                ),
                const SizedBox(width: 6),
                pillToggle(
                  BarIcons.moonFill,
                  s.focus,
                  () => _toggleDnd(ref),
                ),
                const SizedBox(width: 6),
                ValueListenableBuilder<bool>(
                  valueListenable: NightLight.enabled,
                  builder: (context, night, _) => pillToggle(
                    BarIcons.sunMaxFill,
                    night,
                    NightLight.toggle,
                  ),
                ),
                const SizedBox(width: 6),
                pillToggle(
                  BarIcons.circleHalf,
                  s.dark,
                  () => _toggleDark(ref, s.dark),
                ),
                const SizedBox(width: 6),
                pillToggle(
                  BarIcons.camera,
                  false,
                  () => _screenshot(ref),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // Caelestia status & power profile pill strip
          Row(
            children: <Widget>[
              Expanded(
                child: Pressable(
                  onTap: () => onOpenPage('wifi'),
                  shape: BorderRadius.circular(r),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: padBg,
                      borderRadius: BorderRadius.circular(r),
                    ),
                    child: Row(
                      children: <Widget>[
                        BarGlyph(BarIcons.wifi, size: 14, color: accent),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            s.wifiLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: BarType.caption.copyWith(
                              color: theme.colors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Pressable(
                  onTap: () => _cyclePower(ref, s),
                  shape: BorderRadius.circular(r),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: padBg,
                      borderRadius: BorderRadius.circular(r),
                    ),
                    child: Row(
                      children: <Widget>[
                        BarGlyph(BarIcons.bolt, size: 14, color: accent),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _powerLabel(context, s.powerProfile),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: BarType.caption.copyWith(
                              color: theme.colors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _SliderRow(
            icon: BarIcons.sunMaxFill,
            value: s.brightness ?? 0.5,
            enabled: s.brightness != null,
            height: 24,
            onChanged: (v) => _setBrightness(ref, v),
            onChangeEnd: (v) => _setBrightness(ref, v, commit: true),
            onDetail: () => onOpenPage('display'),
          ),
          const SizedBox(height: 8),
          _SliderRow(
            icon: s.volume <= 0.001
                ? BarIcons.speakerSlashFill
                : BarIcons.speaker3Fill,
            value: s.volume,
            enabled: s.audible,
            height: 24,
            onChangeStart: services.beginVolumeInteraction,
            onChanged: services.setVolume,
            onChangeEnd: services.commitVolume,
            onDetail: () => onOpenPage('sound'),
          ),
          const SizedBox(height: 10),
          _CompactPowerFooter(
            batteryPercent: s.batteryPercent,
            charging: s.charging,
            radius: r,
            onSettings: onSettings,
            onLock: () => _lock(ref),
            onReboot: () {
              onClose();
              onConfirmPower(SessionPowerAction.reboot);
            },
            onShutdown: () {
              onClose();
              onConfirmPower(SessionPowerAction.powerOff);
            },
          ),
        ],
      ),
    );
  }

  // ── 10. Ax-Shell Notch Dashboard (`ax-shell/modules/widgets.py`) ──────────

  Widget _buildAxShell(BuildContext context, WidgetRef ref) {
    final theme = context.shellTheme;
    final style = KitStyle.of(context);
    final s = _readState(context, ref);
    final accent = style.accent(theme);
    final onAccent = style.onAccent(theme);
    final r = style.corner(14);
    final padBg = theme.colors.surfaceContainerHigh;

    Widget splitBtn({
      required IconData icon,
      required String title,
      required bool on,
      required VoidCallback onToggle,
      VoidCallback? onDetail,
    }) {
      final fg = on ? onAccent : theme.colors.textPrimary;
      return Container(
        height: 46,
        decoration: BoxDecoration(
          color: on ? accent : padBg,
          borderRadius: BorderRadius.circular(r),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Pressable(
                onTap: onToggle,
                shape: BorderRadius.circular(r),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 11),
                  child: Row(
                    children: <Widget>[
                      BarGlyph(icon, size: 15, color: fg),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: BarType.title.copyWith(fontSize: 12, color: fg),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (onDetail != null)
              Pressable(
                onTap: onDetail,
                shape: BorderRadius.horizontal(right: Radius.circular(r)),
                child: SizedBox(
                  width: 26,
                  height: 46,
                  child: Center(
                    child: BarGlyph(BarIcons.chevronRight, size: 11, color: fg),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _DrawerMediaStrip(services: services, radius: r, padBg: padBg),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: splitBtn(
                  icon: s.wifiOn ? BarIcons.wifi : BarIcons.wifiSlash,
                  title: s.wifiLabel,
                  on: s.wifiOn,
                  onToggle: () => _toggleWifi(ref, s.wifiOn),
                  onDetail: () => onOpenPage('wifi'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: splitBtn(
                  icon: BarIcons.bluetooth,
                  title: context.tr('Bluetooth'),
                  on: s.btOn,
                  onToggle: () => _toggleBt(ref, s.btAvailable),
                  onDetail: () => onOpenPage('bluetooth'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: splitBtn(
                  icon: BarIcons.moonFill,
                  title: context.tr('Do Not Disturb'),
                  on: s.focus,
                  onToggle: () => _toggleDnd(ref),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ValueListenableBuilder<bool>(
                  valueListenable: NightLight.enabled,
                  builder: (context, night, _) => splitBtn(
                    icon: BarIcons.sunMaxFill,
                    title: context.tr('Night Light'),
                    on: night,
                    onToggle: NightLight.toggle,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: padBg,
              borderRadius: BorderRadius.circular(r),
            ),
            child: Column(
              children: <Widget>[
                _SliderRow(
                  icon: s.volume <= 0.001
                      ? BarIcons.speakerSlashFill
                      : BarIcons.speaker3Fill,
                  value: s.volume,
                  enabled: s.audible,
                  onChangeStart: services.beginVolumeInteraction,
                  onChanged: services.setVolume,
                  onChangeEnd: services.commitVolume,
                  onDetail: () => onOpenPage('sound'),
                ),
                const SizedBox(height: 6),
                _SliderRow(
                  icon: BarIcons.sunMaxFill,
                  value: s.brightness ?? 0.5,
                  enabled: s.brightness != null,
                  onChanged: (v) => _setBrightness(ref, v),
                  onChangeEnd: (v) => _setBrightness(ref, v, commit: true),
                  onDetail: () => onOpenPage('display'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _CompactPowerFooter(
            batteryPercent: s.batteryPercent,
            charging: s.charging,
            radius: r,
            onSettings: onSettings,
            onLock: () => _lock(ref),
            onReboot: () {
              onClose();
              onConfirmPower(SessionPowerAction.reboot);
            },
            onShutdown: () {
              onClose();
              onConfirmPower(SessionPowerAction.powerOff);
            },
          ),
        ],
      ),
    );
  }

  static String _powerLabel(BuildContext context, String profile) =>
      switch (profile) {
        PowerProfile.powerSave => context.tr('Low Power'),
        PowerProfile.performance => context.tr('High Power'),
        _ => context.tr('Balanced'),
      };
}

class _DrawerMediaStrip extends ConsumerWidget {
  const _DrawerMediaStrip({
    required this.services,
    required this.radius,
    required this.padBg,
    this.compact = false,
  });

  final ShellServices services;
  final double radius;
  final Color padBg;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.shellTheme;
    final style = KitStyle.of(context);
    final playback = ref.watch(services.media).value;
    final commands = ref.watch(services.mediaCommands);
    final hasTrack = playback != null && playback.title.trim().isNotEmpty;
    final playing = playback?.playing ?? false;
    final accent = style.accent(theme);
    final artSize = compact ? 32.0 : 38.0;
    final artFallback = Container(
      width: artSize,
      height: artSize,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(style.corner(8)),
      ),
      child: Center(
        child: BarGlyph(BarIcons.playFill, size: 15, color: accent),
      ),
    );

    Widget btn(IconData icon, VoidCallback? onTap, {bool primary = false}) =>
        Pressable(
          onTap: onTap,
          scale: Pressable.small,
          wash: !primary,
          shape: style.disc(26),
          child: Container(
            width: 26,
            height: 26,
            decoration: primary
                ? BoxDecoration(
                    color: accent,
                    borderRadius: style.disc(26),
                  )
                : null,
            child: Center(
              child: BarGlyph(
                icon,
                size: primary ? 11 : 12,
                color: primary
                    ? style.onAccent(theme)
                    : theme.colors.textPrimary.withValues(
                        alpha: onTap == null ? 0.35 : 0.85,
                      ),
              ),
            ),
          ),
        );

    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 9 : 12, vertical: 9),
      decoration: BoxDecoration(
        color: padBg,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Row(
        children: <Widget>[
          if (hasTrack && playback.artUrl.trim().isNotEmpty)
            MediaArtwork(
              url: playback.artUrl,
              size: artSize,
              radius: style.corner(8),
              fallback: artFallback,
            )
          else
            artFallback,
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  hasTrack ? playback.title : context.tr('Not Playing'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: BarType.title.copyWith(
                    fontSize: 12,
                    color: theme.colors.textPrimary,
                  ),
                ),
                if (hasTrack && playback.artistLabel.trim().isNotEmpty)
                  Text(
                    playback.artistLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: BarType.caption.copyWith(
                      fontSize: 10.5,
                      color: theme.colors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          if (!compact) ...<Widget>[
            btn(
              BarIcons.backward,
              playback?.canGoPrevious == true ? commands.previous : null,
            ),
            const SizedBox(width: 2),
          ],
          btn(
            playing ? BarIcons.pauseFill : BarIcons.playFill,
            playback?.available == true ? commands.playPause : null,
            primary: hasTrack,
          ),
          if (!compact) ...<Widget>[
            const SizedBox(width: 2),
            btn(
              BarIcons.forward,
              playback?.canGoNext == true ? commands.next : null,
            ),
          ],
        ],
      ),
    );
  }
}

class _ShellLiveState {
  const _ShellLiveState({
    required this.wifiOn,
    required this.wifiLabel,
    required this.btAvailable,
    required this.btOn,
    required this.btLabel,
    required this.focus,
    required this.dark,
    required this.powerAvailable,
    required this.powerProfile,
    required this.batteryPercent,
    required this.charging,
    required this.volume,
    required this.audible,
    required this.brightness,
  });

  final bool wifiOn;
  final String wifiLabel;
  final bool btAvailable;
  final bool btOn;
  final String btLabel;
  final bool focus;
  final bool dark;
  final bool powerAvailable;
  final String powerProfile;
  final int? batteryPercent;
  final bool charging;
  final double volume;
  final bool audible;
  final double? brightness;
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.icon,
    required this.value,
    required this.enabled,
    required this.onChanged,
    this.onIconTap,
    this.onChangeStart,
    this.onChangeEnd,
    this.onDetail,
    this.detailIcon = BarIcons.chevronRight,
    this.height = 20,
    this.showPercent = false,
  });

  final IconData icon;
  final double value;
  final bool enabled;
  final VoidCallback? onIconTap;
  final VoidCallback? onChangeStart;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;
  final VoidCallback? onDetail;
  final IconData detailIcon;
  final double height;
  final bool showPercent;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final iconWidget = SizedBox(
      width: 24,
      height: 24,
      child: Center(
        child: BarGlyph(
          icon,
          size: 15,
          color: enabled
              ? theme.colors.textPrimary
              : theme.colors.textTertiary,
        ),
      ),
    );
    return Row(
      children: <Widget>[
        onIconTap != null
            ? Pressable(
                onTap: onIconTap,
                shape: BorderRadius.circular(12),
                wash: true,
                child: iconWidget,
              )
            : iconWidget,
        const SizedBox(width: 6),
        Expanded(
          child: MacSlider(
            value: value,
            enabled: enabled,
            height: height,
            onChangeStart: onChangeStart,
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          ),
        ),
        if (showPercent) ...<Widget>[
          const SizedBox(width: 6),
          SizedBox(
            width: 34,
            child: Text(
              '${(value * 100).round()}%',
              textAlign: TextAlign.right,
              style: BarType.caption.copyWith(
                fontSize: 11,
                color: theme.colors.textSecondary,
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
        if (onDetail != null) ...<Widget>[
          const SizedBox(width: 4),
          Pressable(
            onTap: onDetail,
            shape: BorderRadius.circular(12),
            wash: true,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: BarGlyph(
                detailIcon,
                size: 11,
                color: theme.colors.textSecondary,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _CompactPowerFooter extends StatelessWidget {
  const _CompactPowerFooter({
    required this.batteryPercent,
    required this.charging,
    required this.radius,
    required this.onSettings,
    required this.onLock,
    required this.onReboot,
    required this.onShutdown,
  });

  final int? batteryPercent;
  final bool charging;
  final double radius;
  final VoidCallback onSettings;
  final VoidCallback onLock;
  final VoidCallback onReboot;
  final VoidCallback onShutdown;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final bg = theme.colors.surfaceContainerHigh;
    final fg = theme.colors.textPrimary;

    Widget iconBtn(IconData icon, VoidCallback onTap) => Pressable(
      onTap: onTap,
      shape: BorderRadius.circular(radius),
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(radius),
        ),
        child: BarGlyph(icon, size: 14, color: fg),
      ),
    );

    return Row(
      children: <Widget>[
        if (batteryPercent != null)
          Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(radius),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                BarGlyph(
                  charging ? BarIcons.boltFill : BarIcons.battery75,
                  size: 13,
                  color: fg,
                ),
                const SizedBox(width: 5),
                Text(
                  '$batteryPercent%',
                  style: BarType.caption.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: fg,
                  ),
                ),
              ],
            ),
          ),
        const Spacer(),
        iconBtn(BarIcons.gear, onSettings),
        const SizedBox(width: 6),
        iconBtn(BarIcons.lockFill, onLock),
        const SizedBox(width: 6),
        iconBtn(BarIcons.arrowClockwise, onReboot),
        const SizedBox(width: 6),
        iconBtn(BarIcons.power, onShutdown),
      ],
    );
  }
}
