import 'package:denial_flutter_sdk/services.dart';
import 'package:denial_flutter_sdk/state.dart';
import 'package:denial_flutter_sdk/system_services.dart'
    show AudioOutputDevice, BluetoothDeviceInfo, WifiNetwork;
import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bar_icons.dart';
import '../bar_type.dart';
import '../clipboard_history.dart';
import '../clipboard_watch.dart';
import '../l10n.dart';
import 'mac_kit.dart';

const double popoverWidth = 300;

class _Popover extends StatelessWidget {
  const _Popover({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 8, 6, 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

class _Scroll extends StatelessWidget {
  const _Scroll({required this.children, this.maxHeight = 260});

  final List<Widget> children;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: Text(
        text,
        style: BarType.menuRow.copyWith(
          color: context.shellTheme.colors.textTertiary,
        ),
      ),
    );
  }
}

/// Wi-Fi: the switch, the networks this machine knows, the rest folded behind
/// "Other Networks", and the door to settings.
class WifiPopover extends ConsumerStatefulWidget {
  const WifiPopover({
    required this.onJoin,
    required this.onSettings,
    this.onBack,
    super.key,
  });

  final ValueChanged<WifiNetwork> onJoin;
  final VoidCallback onSettings;
  final VoidCallback? onBack;

  @override
  ConsumerState<WifiPopover> createState() => _WifiPopoverState();
}

class _WifiPopoverState extends ConsumerState<WifiPopover> {
  bool _others = false;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(
      () => ref.read(networkConnectivityProvider.notifier).scan(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final state = ref.watch(networkConnectivityProvider);
    final controller = ref.read(networkConnectivityProvider.notifier);
    final on = state.snapshot.wirelessEnabled;
    final networks = state.snapshot.networks
        .where((network) => network.ssid.isNotEmpty)
        .toList();
    bool isKnown(WifiNetwork network) =>
        network.connected || (network.saved && network.available);
    final known = networks.where(isKnown).toList();
    final others = networks
        .where((network) => !isKnown(network) && network.available)
        .toList();

    Widget row(WifiNetwork network) {
      final busy = state.busyNetworks.contains(network.identity);
      return MacRow(
        leading: MacDisc(icon: BarIcons.wifi, on: network.connected),
        title: network.ssid,
        detail: busy ? context.tr('Connecting…') : null,
        trailing: network.security.requiresPassword
            ? BarGlyph(
                BarIcons.lockFill,
                size: 13,
                color: theme.colors.textSecondary,
              )
            : null,
        onTap: busy
            ? null
            : () {
                if (network.connected) {
                  controller.disconnect(network);
                } else if (network.saved ||
                    !network.security.requiresPassword) {
                  controller.connect(network);
                } else {
                  widget.onJoin(network);
                }
              },
      );
    }

    return _Popover(
      children: <Widget>[
        MacHeader(
          title: 'Wi-Fi',
          onBack: widget.onBack,
          trailing: MacSwitch(
            value: on,
            busy: state.radioChanging,
            onChanged: controller.setWirelessEnabled,
          ),
        ),
        Reveal(
          open: on,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const MacDivider(),
              if (known.isNotEmpty) ...<Widget>[
                MacSection(context.tr('Known Networks')),
                for (final network in known) row(network),
                const MacDivider(),
              ],
              MacRow(
                title: context.tr('Other Networks'),
                height: 32,
                onTap: () => setState(() => _others = !_others),
                trailing: AnimatedRotation(
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOutCubic,
                  turns: _others ? 0.25 : 0,
                  child: BarGlyph(
                    BarIcons.chevronRight,
                    size: 12,
                    color: theme.colors.textSecondary,
                  ),
                ),
              ),
              Reveal(
                open: _others,
                child: others.isEmpty
                    ? _Note(
                        context.tr(
                          state.scanning
                              ? 'Looking for networks…'
                              : 'No other networks',
                        ),
                      )
                    : _Scroll(
                        maxHeight: 228,
                        children: <Widget>[
                          for (final network in others) row(network),
                        ],
                      ),
              ),
            ],
          ),
        ),
        const MacDivider(),
        MacRow(
          title: context.tr('Wi-Fi Settings…'),
          height: 32,
          onTap: widget.onSettings,
        ),
      ],
    );
  }
}

IconData _bluetoothIcon(BluetoothDeviceInfo device) {
  final icon = device.icon;
  if (icon.contains('head') || icon.contains('audio')) {
    return BarIcons.headphones;
  }
  if (icon.contains('computer')) return BarIcons.desktopcomputer;
  return BarIcons.bluetooth;
}

class BluetoothPopover extends ConsumerWidget {
  const BluetoothPopover({required this.onSettings, this.onBack, super.key});

  final VoidCallback onSettings;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(bluetoothProvider);
    final controller = ref.read(bluetoothProvider.notifier);
    final on = state.available && state.powered;
    final devices =
        state.devices
            .where((device) => device.name.isNotEmpty && device.paired)
            .toList()
          ..sort((a, b) {
            if (a.connected != b.connected) return a.connected ? -1 : 1;
            return a.name.toLowerCase().compareTo(b.name.toLowerCase());
          });
    return _Popover(
      children: <Widget>[
        MacHeader(
          title: context.tr('Bluetooth'),
          onBack: onBack,
          trailing: MacSwitch(
            value: on,
            busy: state.powerChanging,
            onChanged: state.available ? (_) => controller.togglePower() : null,
          ),
        ),
        Reveal(
          open: on,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const MacDivider(),
              MacSection(context.tr('Devices')),
              if (devices.isEmpty)
                _Note(context.tr('No paired devices'))
              else
                _Scroll(
                  children: <Widget>[
                    for (final device in devices)
                      MacRow(
                        leading: MacDisc(
                          icon: _bluetoothIcon(device),
                          on: device.connected,
                        ),
                        title: device.name,
                        detail: state.busyDevices.contains(device.objectPath)
                            ? context.tr('Connecting…')
                            : null,
                        onTap: () => controller.toggleConnection(device),
                      ),
                  ],
                ),
            ],
          ),
        ),
        const MacDivider(),
        MacRow(
          title: context.tr('Bluetooth Settings…'),
          height: 32,
          onTap: onSettings,
        ),
      ],
    );
  }
}

final RegExp _profile = RegExp(
  r'\s+(Analog|Digital|Pro|Stereo|Mono|HDMI|DisplayPort|S/PDIF|Surround)\b.*$',
);

IconData outputDeviceIcon(AudioOutputDevice device) {
  final text = '${device.name} ${device.description}'.toLowerCase();
  if (text.contains('bluez') ||
      text.contains('head') ||
      text.contains('buds') ||
      text.contains('pods')) {
    return BarIcons.headphones;
  }
  if (text.contains('hdmi') || text.contains('displayport')) {
    return BarIcons.tv;
  }
  return BarIcons.speaker3Fill;
}

/// Sound: the output level and the list of outputs.
class SoundPopover extends ConsumerWidget {
  const SoundPopover({
    required this.services,
    required this.onSettings,
    this.onBack,
    super.key,
  });

  final ShellServices services;
  final VoidCallback onSettings;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final volume = ref.watch(services.volume);
    final devices = ref
        .watch(audioDevicesProvider)
        .devices
        .where((device) => device.available || device.active)
        .toList();
    final streams = ref.watch(appAudioProvider).streams;
    final apps = ref.read(appAudioProvider.notifier);
    return _Popover(
      children: <Widget>[
        MacHeader(title: context.tr('Sound'), onBack: onBack),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: MacSlider(
            value: volume,
            leading: BarIcons.speaker1Fill,
            trailing: BarIcons.speaker3Fill,
            onChangeStart: services.beginVolumeInteraction,
            onChanged: services.setVolume,
            onChangeEnd: services.commitVolume,
          ),
        ),
        const MacDivider(),
        MacSection(context.tr('Output')),
        if (devices.isEmpty)
          _Note(context.tr('No output devices'))
        else
          _Scroll(
            maxHeight: 200,
            children: <Widget>[
              for (final device in devices)
                MacRow(
                  leading: MacDisc(
                    icon: outputDeviceIcon(device),
                    on: device.active,
                  ),
                  title: device.description.isEmpty
                      ? device.name
                      : device.description.replaceFirst(_profile, ''),
                  onTap: device.active
                      ? null
                      : () => ref
                            .read(audioDevicesProvider.notifier)
                            .select(device.name),
                ),
            ],
          ),
        if (streams.isNotEmpty) ...<Widget>[
          const MacDivider(),
          MacSection(context.tr('Applications')),
          _Scroll(
            maxHeight: 150,
            children: <Widget>[
              for (final stream in streams)
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 2, 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        stream.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: BarType.caption.copyWith(
                          color: context.shellTheme.colors.textSecondary,
                        ),
                      ),
                      MacSlider(
                        height: 14,
                        value: stream.level,
                        onChanged: (value) => apps.setVolume(stream.id, value),
                        onChangeEnd: (value) =>
                            apps.commitVolume(stream.id, value),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
        const MacDivider(),
        MacRow(
          title: context.tr('Sound Settings…'),
          height: 32,
          onTap: onSettings,
        ),
      ],
    );
  }
}

class BatteryPopover extends ConsumerWidget {
  const BatteryPopover({
    required this.services,
    required this.onSettings,
    super.key,
  });

  final ShellServices services;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.shellTheme;
    final battery = ref.watch(services.battery);
    final power = ref.watch(desktopPowerModesProvider);
    return _Popover(
      children: <Widget>[
        MacHeader(
          title: context.tr('Battery'),
          trailing: Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Text(
              battery.capacity == null ? '' : '${battery.capacity}%',
              style: BarType.title.copyWith(
                fontSize: 14,
                color: theme.colors.textSecondary,
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
          child: Text(
            context.tr(
              battery.charging
                  ? 'Power Source: Power Adapter'
                  : 'Power Source: Battery',
            ),
            style: BarType.caption.copyWith(
              fontSize: 12,
              color: theme.colors.textSecondary,
            ),
          ),
        ),
        if (power.systemAvailable) ...<Widget>[
          const MacDivider(),
          MacSection(context.tr('Energy Mode')),
          for (final (profile, label, icon)
              in const <(String, String, IconData)>[
                ('power-save', 'Low Power', BarIcons.batteryEmpty),
                ('balanced', 'Automatic', BarIcons.battery75),
                ('performance', 'High Power', BarIcons.boltFill),
              ])
            MacRow(
              leading: MacDisc(icon: icon, on: power.systemProfile == profile),
              title: context.tr(label),
              onTap: () => ref
                  .read(desktopPowerModesProvider.notifier)
                  .selectSystemProfile(profile),
            ),
        ],
        const MacDivider(),
        MacRow(
          title: context.tr('Battery Settings…'),
          height: 32,
          onTap: onSettings,
        ),
      ],
    );
  }
}

/// The texts copied this session, newest first. Choosing one copies it again.
class ClipboardPopover extends StatelessWidget {
  const ClipboardPopover({required this.onClose, super.key});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    return ValueListenableBuilder<List<String>>(
      valueListenable: clipboardWatch,
      builder: (context, items, _) => _Popover(
        children: <Widget>[
          MacHeader(
            title: context.tr('Clipboard History'),
            trailing: items.isEmpty
                ? null
                : Pressable(
                    onTap: clipboardWatch.clear,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        context.tr('Clear'),
                        style: BarType.menuRow.copyWith(
                          color: theme.colors.textSecondary,
                        ),
                      ),
                    ),
                  ),
          ),
          if (!clipboardWatch.available)
            _Note(context.tr('wl-clipboard is not installed.'))
          else if (items.isEmpty)
            _Note(context.tr('Text you copy will appear here.'))
          else
            _Scroll(
              maxHeight: 340,
              children: <Widget>[
                for (final text in items)
                  MacRow(
                    key: ValueKey<String>(text),
                    title: clipboardPreview(text),
                    detail: text.length > 120
                        ? context.tr('{} characters', text.length)
                        : null,
                    trailing: Pressable(
                      onTap: () => clipboardWatch.remove(text),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: BarGlyph(
                          BarIcons.xmark,
                          size: 10,
                          color: theme.colors.textTertiary,
                        ),
                      ),
                    ),
                    onTap: () {
                      clipboardWatch.copy(text);
                      onClose();
                    },
                  ),
              ],
            ),
          const MacDivider(),
          _Note(
            context.tr(
              'Kept in memory until the shell restarts. Passwords marked secret by a password manager are skipped.',
            ),
          ),
        ],
      ),
    );
  }
}
