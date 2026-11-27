import 'dart:async';

import 'package:denial_flutter_sdk/models.dart';
import 'package:denial_flutter_sdk/services.dart';
import 'package:denial_flutter_sdk/settings.dart';
import 'package:denial_flutter_sdk/state.dart';
import 'package:denial_flutter_sdk/system_services.dart'
    show PowerProfile, systemActionsServiceProvider;
import 'package:denial_flutter_sdk/theme.dart';
import 'package:denial_shell_kit/kit_style.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bar_icons.dart';
import '../bar_type.dart';
import '../l10n.dart';
import '../night_light.dart';
import 'mac_kit.dart';

/// Builds a preset-authentic Control Centre / Quick Settings home layout for
/// non-macOS shell archetypes (`gnome`, `windows`, `hyprpanel`, `material`,
/// `omarchy`, `cosmic`, `plasma`, `noctalia`, `caelestia`, `axshell`).
///
/// Every interactive control connects to live Denial system providers and
/// drills into the shared detail pages (`wifi`, `bluetooth`, `display`,
/// `sound`) via [onOpenPage].
class ShellControlCenterView extends ConsumerWidget {
  const ShellControlCenterView({
    required this.archetype,
    required this.services,
    required this.output,
    required this.onOpenPage,
    required this.onSettings,
    required this.onConfirmPower,
    required this.onClose,
    super.key,
  });

  final KitShellArchetype archetype;
  final ShellServices services;
  final DisplayOutput output;
  final ValueChanged<String> onOpenPage;
  final VoidCallback onSettings;
  final ValueChanged<SessionPowerAction> onConfirmPower;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (archetype) {
      KitShellArchetype.gnome => _buildGnome(context, ref),
      KitShellArchetype.windows => _buildWindows(context, ref),
      KitShellArchetype.hyprpanel => _buildHyprPanel(context, ref),
      KitShellArchetype.material => _buildMaterial(context, ref),
      KitShellArchetype.omarchy || KitShellArchetype.cosmic =>
        _buildFlatCompact(context, ref),
      KitShellArchetype.plasma => _buildPlasma(context, ref),
      KitShellArchetype.noctalia ||
      KitShellArchetype.caelestia ||
      KitShellArchetype.axshell => _buildAttachedDashboard(context, ref),
      _ => const SizedBox.shrink(),
    };
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

    Widget circleBtn(IconData icon, String tip, VoidCallback onTap) =>
        Pressable(
          onTap: onTap,
          shape: BorderRadius.circular(18),
          child: Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: plate,
              borderRadius: BorderRadius.circular(17),
            ),
            child: BarGlyph(icon, size: 15, color: theme.colors.textPrimary),
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
                context.tr('Shut Down'),
                () {
                  onClose();
                  onConfirmPower(SessionPowerAction.powerOff);
                },
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Sliders: Volume & Brightness
          _SliderRow(
            icon: s.volume <= 0.001 ? BarIcons.speakerSlashFill : BarIcons.speaker3Fill,
            value: s.volume,
            enabled: s.audible,
            onChanged: services.setVolume,
            onDetail: () => onOpenPage('sound'),
          ),
          const SizedBox(height: 8),
          _SliderRow(
            icon: BarIcons.sunMaxFill,
            value: s.brightness ?? 0.5,
            enabled: s.brightness != null,
            onChanged: (v) => _setBrightness(ref, v),
            onChangeEnd: (v) => _setBrightness(ref, v, commit: true),
            onDetail: () => onOpenPage('display'),
          ),
          const SizedBox(height: 14),
          // 2-column Adwaita pill toggles
          Row(
            children: <Widget>[
              Expanded(
                child: pillToggle(
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
                child: pillToggle(
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
              _SliderRow(
                icon: BarIcons.sunMaxFill,
                value: s.brightness ?? 0.5,
                enabled: s.brightness != null,
                onChanged: (v) => _setBrightness(ref, v),
                onChangeEnd: (v) => _setBrightness(ref, v, commit: true),
                onDetail: () => onOpenPage('display'),
              ),
              const SizedBox(height: 10),
              _SliderRow(
                icon: s.volume <= 0.001
                    ? BarIcons.speakerSlashFill
                    : BarIcons.speaker3Fill,
                value: s.volume,
                enabled: s.audible,
                onChanged: services.setVolume,
                onDetail: () => onOpenPage('sound'),
              ),
            ],
          ),
        ),
        // Bottom Fluent bar
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
                onTap: () => _lock(ref),
                shape: BorderRadius.circular(4),
                wash: true,
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: BarGlyph(
                    BarIcons.lockFill,
                    size: 14,
                    color: theme.colors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 4),
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

  // ── 3. HyprPanel Catppuccin Tabbed Dashboard ──────────────────────────────

  Widget _buildHyprPanel(BuildContext context, WidgetRef ref) {
    final theme = context.shellTheme;
    final s = _readState(context, ref);
    final dark = theme.brightness == Brightness.dark;
    final cardBg = theme.colors.surfaceContainerHigh;
    final border = theme.colors.hairline;

    // Catppuccin Mocha / Latte module accent hues
    final tabBlue = dark ? const Color(0xff89b4fa) : const Color(0xff1e66f5);
    final tabMauve = dark ? const Color(0xffcba6f7) : const Color(0xff8839ef);
    final tabSky = dark ? const Color(0xff89dceb) : const Color(0xff04a5e5);
    final tabPeach = dark ? const Color(0xfffab387) : const Color(0xfffe640b);

    Widget tabBtn(String label, IconData icon, Color tint, VoidCallback? onTap, {bool active = false}) {
      return Expanded(
        child: Pressable(
          onTap: onTap,
          shape: BorderRadius.circular(6),
          child: Container(
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? tint : tint.withValues(alpha: dark ? 0.18 : 0.14),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: tint.withValues(alpha: active ? 1 : 0.4),
                width: 0.8,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                BarGlyph(
                  icon,
                  size: 13,
                  color: active
                      ? (dark ? const Color(0xff1e1e2e) : const Color(0xffffffff))
                      : tint,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: BarType.caption.copyWith(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: active
                          ? (dark ? const Color(0xff1e1e2e) : const Color(0xffffffff))
                          : theme.colors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

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
                color: on
                    ? (dark ? const Color(0xff1e1e2e) : const Color(0xffffffff))
                    : theme.colors.textPrimary,
              ),
            ),
          ),
        );

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Colored quick-module tab header
          Row(
            children: <Widget>[
              tabBtn(context.tr('System'), BarIcons.gear, tabMauve, null, active: true),
              const SizedBox(width: 6),
              tabBtn('Wi-Fi', BarIcons.wifi, tabBlue, () => onOpenPage('wifi')),
              const SizedBox(width: 6),
              tabBtn('BT', BarIcons.bluetooth, tabSky, () => onOpenPage('bluetooth')),
              const SizedBox(width: 6),
              tabBtn(context.tr('Sound'), BarIcons.speaker3Fill, tabPeach, () => onOpenPage('sound')),
            ],
          ),
          const SizedBox(height: 12),
          // 5-toggle control strip
          Row(
            children: <Widget>[
              toggleChip(
                s.wifiOn ? BarIcons.wifi : BarIcons.wifiSlash,
                tabBlue,
                s.wifiOn,
                () => _toggleWifi(ref, s.wifiOn),
              ),
              const SizedBox(width: 6),
              toggleChip(
                BarIcons.bluetooth,
                tabSky,
                s.btOn,
                () => _toggleBt(ref, s.btAvailable),
              ),
              const SizedBox(width: 6),
              toggleChip(
                BarIcons.moonFill,
                tabMauve,
                s.focus,
                () => _toggleDnd(ref),
              ),
              const SizedBox(width: 6),
              ValueListenableBuilder<bool>(
                valueListenable: NightLight.enabled,
                builder: (context, night, _) => toggleChip(
                  BarIcons.sunMaxFill,
                  tabPeach,
                  night,
                  NightLight.toggle,
                ),
              ),
              const SizedBox(width: 6),
              toggleChip(
                BarIcons.circleHalf,
                tabMauve,
                s.dark,
                () => _toggleDark(ref, s.dark),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: border, width: 0.8),
            ),
            child: Column(
              children: <Widget>[
                _SliderRow(
                  icon: BarIcons.speaker3Fill,
                  value: s.volume,
                  enabled: s.audible,
                  onChanged: services.setVolume,
                  onDetail: () => onOpenPage('sound'),
                ),
                const SizedBox(height: 8),
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
            radius: 7,
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

  // ── 4. Material 3 (DMS / Dux) Control Dashboard ───────────────────────────

  Widget _buildMaterial(BuildContext context, WidgetRef ref) {
    final theme = context.shellTheme;
    final style = KitStyle.of(context);
    final s = _readState(context, ref);
    final accent = style.accent(theme);
    final onAccent = style.onAccent(theme);
    final cardBg = theme.colors.surfaceContainerHigh;

    Widget m3Card({
      required IconData icon,
      required String title,
      required String subtitle,
      required bool on,
      required VoidCallback onToggle,
      VoidCallback? onDetail,
    }) {
      final fg = on ? onAccent : theme.colors.textPrimary;
      final sub = on ? onAccent.withValues(alpha: 0.8) : theme.colors.textSecondary;
      return Container(
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
    }

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _CompactPowerFooter(
            batteryPercent: s.batteryPercent,
            charging: s.charging,
            radius: 18,
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
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: m3Card(
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
                  title: context.tr('Focus'),
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
                  on: s.powerAvailable && s.powerProfile != PowerProfile.balanced,
                  onToggle: () => _cyclePower(ref, s),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _SliderRow(
            icon: BarIcons.sunMaxFill,
            value: s.brightness ?? 0.5,
            enabled: s.brightness != null,
            height: 28,
            onChanged: (v) => _setBrightness(ref, v),
            onChangeEnd: (v) => _setBrightness(ref, v, commit: true),
            onDetail: () => onOpenPage('display'),
          ),
          const SizedBox(height: 10),
          _SliderRow(
            icon: s.volume <= 0.001
                ? BarIcons.speakerSlashFill
                : BarIcons.speaker3Fill,
            value: s.volume,
            enabled: s.audible,
            height: 28,
            onChanged: services.setVolume,
            onDetail: () => onOpenPage('sound'),
          ),
        ],
      ),
    );
  }

  // ── 5. Omarchy & COSMIC Flat Crisp Quick Panel ────────────────────────────

  Widget _buildFlatCompact(BuildContext context, WidgetRef ref) {
    final theme = context.shellTheme;
    final style = KitStyle.of(context);
    final s = _readState(context, ref);
    final r = archetype == KitShellArchetype.omarchy ? 0.0 : 6.0;
    final accent = style.accent(theme);
    final onAccent = style.onAccent(theme);
    final border = theme.colors.hairline;

    Widget rowBtn({
      required IconData icon,
      required String title,
      required String status,
      required bool on,
      required VoidCallback onToggle,
      VoidCallback? onDetail,
    }) {
      return Container(
        height: 36,
        decoration: BoxDecoration(
          color: on
              ? accent.withValues(alpha: 0.16)
              : theme.colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(r),
          border: Border.all(
            color: on ? accent : border,
            width: 1,
          ),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Pressable(
                onTap: onToggle,
                shape: BorderRadius.circular(r),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    children: <Widget>[
                      BarGlyph(
                        icon,
                        size: 14,
                        color: on ? accent : theme.colors.textSecondary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: BarType.menuRow.copyWith(
                            color: theme.colors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        status,
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
                shape: BorderRadius.circular(r),
                child: Container(
                  width: 30,
                  height: 36,
                  decoration: BoxDecoration(
                    border: Border(left: BorderSide(color: border, width: 1)),
                  ),
                  alignment: Alignment.center,
                  child: BarGlyph(
                    BarIcons.chevronRight,
                    size: 11,
                    color: theme.colors.textSecondary,
                  ),
                ),
              ),
          ],
        ),
      );
    }

    Widget actionChip(IconData icon, String label, VoidCallback onTap, {bool active = false}) =>
        Expanded(
          child: Pressable(
            onTap: onTap,
            shape: BorderRadius.circular(r),
            child: Container(
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active ? accent : theme.colors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(r),
                border: Border.all(color: active ? accent : border, width: 1),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  BarGlyph(
                    icon,
                    size: 13,
                    color: active ? onAccent : theme.colors.textPrimary,
                  ),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: BarType.caption.copyWith(
                        fontSize: 11,
                        color: active ? onAccent : theme.colors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );

    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          rowBtn(
            icon: s.wifiOn ? BarIcons.wifi : BarIcons.wifiSlash,
            title: 'Wi-Fi',
            status: s.wifiLabel,
            on: s.wifiOn,
            onToggle: () => _toggleWifi(ref, s.wifiOn),
            onDetail: () => onOpenPage('wifi'),
          ),
          const SizedBox(height: 6),
          rowBtn(
            icon: BarIcons.bluetooth,
            title: context.tr('Bluetooth'),
            status: s.btLabel,
            on: s.btOn,
            onToggle: () => _toggleBt(ref, s.btAvailable),
            onDetail: () => onOpenPage('bluetooth'),
          ),
          const SizedBox(height: 6),
          Row(
            children: <Widget>[
              actionChip(
                BarIcons.moonFill,
                context.tr('Focus'),
                () => _toggleDnd(ref),
                active: s.focus,
              ),
              const SizedBox(width: 6),
              ValueListenableBuilder<bool>(
                valueListenable: NightLight.enabled,
                builder: (context, night, _) => actionChip(
                  BarIcons.sunMaxFill,
                  context.tr('Night Light'),
                  NightLight.toggle,
                  active: night,
                ),
              ),
              const SizedBox(width: 6),
              actionChip(
                BarIcons.circleHalf,
                context.tr('Dark Mode'),
                () => _toggleDark(ref, s.dark),
                active: s.dark,
              ),
            ],
          ),
          const SizedBox(height: 10),
          _SliderRow(
            icon: BarIcons.speaker3Fill,
            value: s.volume,
            enabled: s.audible,
            onChanged: services.setVolume,
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

  // ── 6. KDE Plasma Breeze Flyout ───────────────────────────────────────────

  Widget _buildPlasma(BuildContext context, WidgetRef ref) {
    final theme = context.shellTheme;
    final style = KitStyle.of(context);
    final s = _readState(context, ref);
    final accent = style.accent(theme);
    final onAccent = style.onAccent(theme);
    final border = theme.colors.hairline;

    Widget breezeBtn({
      required IconData icon,
      required String title,
      required bool on,
      required VoidCallback onToggle,
      VoidCallback? onDetail,
    }) {
      return Container(
        height: 40,
        decoration: BoxDecoration(
          color: on
              ? accent.withValues(alpha: 0.22)
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
                        size: 15,
                        color: on ? accent : theme.colors.textPrimary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: BarType.menuRow.copyWith(
                            color: theme.colors.textPrimary,
                          ),
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
                  width: 28,
                  height: 40,
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
    }

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                context.tr('Control Centre'),
                style: BarType.title.copyWith(
                  fontSize: 13.5,
                  color: theme.colors.textPrimary,
                ),
              ),
              const Spacer(),
              Pressable(
                onTap: onSettings,
                shape: BorderRadius.circular(4),
                wash: true,
                child: Padding(
                  padding: const EdgeInsets.all(5),
                  child: BarGlyph(
                    BarIcons.gear,
                    size: 14,
                    color: theme.colors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(height: 1, color: border),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: breezeBtn(
                  icon: s.wifiOn ? BarIcons.wifi : BarIcons.wifiSlash,
                  title: 'Wi-Fi',
                  on: s.wifiOn,
                  onToggle: () => _toggleWifi(ref, s.wifiOn),
                  onDetail: () => onOpenPage('wifi'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: breezeBtn(
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
                child: ValueListenableBuilder<bool>(
                  valueListenable: NightLight.enabled,
                  builder: (context, night, _) => breezeBtn(
                    icon: BarIcons.sunMaxFill,
                    title: context.tr('Night Light'),
                    on: night,
                    onToggle: NightLight.toggle,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: breezeBtn(
                  icon: BarIcons.moonFill,
                  title: context.tr('Focus'),
                  on: s.focus,
                  onToggle: () => _toggleDnd(ref),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: breezeBtn(
                  icon: BarIcons.circleHalf,
                  title: context.tr('Dark Mode'),
                  on: s.dark,
                  onToggle: () => _toggleDark(ref, s.dark),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: breezeBtn(
                  icon: BarIcons.bolt,
                  title: _powerLabel(context, s.powerProfile),
                  on: s.powerAvailable && s.powerProfile != PowerProfile.balanced,
                  onToggle: () => _cyclePower(ref, s),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _SliderRow(
            icon: BarIcons.speaker3Fill,
            value: s.volume,
            enabled: s.audible,
            showPercent: true,
            onChanged: services.setVolume,
            onDetail: () => onOpenPage('sound'),
          ),
          const SizedBox(height: 8),
          _SliderRow(
            icon: BarIcons.sunMaxFill,
            value: s.brightness ?? 0.5,
            enabled: s.brightness != null,
            showPercent: true,
            onChanged: (v) => _setBrightness(ref, v),
            onChangeEnd: (v) => _setBrightness(ref, v, commit: true),
            onDetail: () => onOpenPage('display'),
          ),
          const SizedBox(height: 10),
          Container(height: 1, color: border),
          const SizedBox(height: 8),
          _CompactPowerFooter(
            batteryPercent: s.batteryPercent,
            charging: s.charging,
            radius: 5,
            accentBadge: onAccent,
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

  // ── 7. Noctalia / Caelestia / Ax-Shell Attached Drawer Dashboard ──────────

  Widget _buildAttachedDashboard(BuildContext context, WidgetRef ref) {
    final theme = context.shellTheme;
    final style = KitStyle.of(context);
    final s = _readState(context, ref);
    final accent = style.accent(theme);
    final onAccent = style.onAccent(theme);
    final r = style.corner(14);
    final padBg = theme.colors.surfaceContainerHigh;

    Widget pad({
      required IconData icon,
      required String title,
      required bool on,
      required VoidCallback onToggle,
      VoidCallback? onDetail,
    }) {
      final fg = on ? onAccent : theme.colors.textPrimary;
      return Container(
        height: 50,
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
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: <Widget>[
                      BarGlyph(icon, size: 16, color: fg),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: BarType.title.copyWith(
                            fontSize: 12.5,
                            color: fg,
                          ),
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
                  width: 28,
                  height: 50,
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
          const SizedBox(height: 10),
          _DrawerMediaStrip(services: services, radius: r, padBg: padBg),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: pad(
                  icon: s.wifiOn ? BarIcons.wifi : BarIcons.wifiSlash,
                  title: 'Wi-Fi',
                  on: s.wifiOn,
                  onToggle: () => _toggleWifi(ref, s.wifiOn),
                  onDetail: () => onOpenPage('wifi'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: pad(
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
                child: pad(
                  icon: BarIcons.moonFill,
                  title: context.tr('Focus'),
                  on: s.focus,
                  onToggle: () => _toggleDnd(ref),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ValueListenableBuilder<bool>(
                  valueListenable: NightLight.enabled,
                  builder: (context, night, _) => pad(
                    icon: BarIcons.sunMaxFill,
                    title: context.tr('Night Light'),
                    on: night,
                    onToggle: NightLight.toggle,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: pad(
                  icon: BarIcons.circleHalf,
                  title: context.tr('Dark Mode'),
                  on: s.dark,
                  onToggle: () => _toggleDark(ref, s.dark),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: pad(
                  icon: BarIcons.bolt,
                  title: _powerLabel(context, s.powerProfile),
                  on: s.powerAvailable && s.powerProfile != PowerProfile.balanced,
                  onToggle: () => _cyclePower(ref, s),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _SliderRow(
            icon: BarIcons.sunMaxFill,
            value: s.brightness ?? 0.5,
            enabled: s.brightness != null,
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
            onChanged: services.setVolume,
            onDetail: () => onOpenPage('sound'),
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
  });

  final ShellServices services;
  final double radius;
  final Color padBg;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.shellTheme;
    final style = KitStyle.of(context);
    final playback = ref.watch(services.media).value;
    final commands = ref.watch(services.mediaCommands);
    final hasTrack = playback != null && playback.title.trim().isNotEmpty;
    final playing = playback?.playing ?? false;
    final accent = style.accent(theme);

    Widget btn(IconData icon, VoidCallback? onTap, {bool primary = false}) =>
        Pressable(
          onTap: onTap,
          scale: Pressable.small,
          wash: !primary,
          shape: style.disc(28),
          child: Container(
            width: 28,
            height: 28,
            decoration: primary
                ? BoxDecoration(
                    color: accent,
                    borderRadius: style.disc(28),
                  )
                : null,
            child: Center(
              child: BarGlyph(
                icon,
                size: primary ? 12 : 13,
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: padBg,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(style.corner(8)),
            ),
            child: Center(
              child: BarGlyph(
                BarIcons.playFill,
                size: 15,
                color: accent,
              ),
            ),
          ),
          const SizedBox(width: 10),
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
                    fontSize: 12.5,
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
          const SizedBox(width: 6),
          btn(
            BarIcons.backward,
            playback?.canGoPrevious == true ? commands.previous : null,
          ),
          const SizedBox(width: 2),
          btn(
            playing ? BarIcons.pauseFill : BarIcons.playFill,
            playback?.available == true ? commands.playPause : null,
            primary: hasTrack,
          ),
          const SizedBox(width: 2),
          btn(
            BarIcons.forward,
            playback?.canGoNext == true ? commands.next : null,
          ),
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
    this.onChangeEnd,
    this.onDetail,
    this.height = 20,
    this.showPercent = false,
  });

  final IconData icon;
  final double value;
  final bool enabled;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;
  final VoidCallback? onDetail;
  final double height;
  final bool showPercent;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    return Row(
      children: <Widget>[
        SizedBox(
          width: 24,
          child: BarGlyph(
            icon,
            size: 15,
            color: enabled
                ? theme.colors.textPrimary
                : theme.colors.textTertiary,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: MacSlider(
            value: value,
            enabled: enabled,
            height: height,
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
                BarIcons.chevronRight,
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
    this.accentBadge,
  });

  final int? batteryPercent;
  final bool charging;
  final double radius;
  final Color? accentBadge;
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
