import 'dart:async';

import 'package:denial_flutter_sdk/services.dart';
import 'package:denial_flutter_sdk/state.dart';
import 'package:denial_flutter_sdk/system_services.dart'
    show
        AudioOutputDevice,
        BluetoothDeviceInfo,
        BluetoothPairingRequest,
        WifiNetwork;
import 'package:denial_flutter_sdk/theme.dart';
import 'package:denial_shell_kit/kit_motion.dart';
import 'package:denial_shell_kit/kit_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bar_icons.dart';
import '../bar_panel.dart';
import '../bar_preferences.dart';
import '../bar_settings.dart';
import '../bar_status.dart';
import '../bar_type.dart';
import '../clipboard_history.dart';
import '../clipboard_watch.dart';
import '../l10n.dart';
import '../tray_names.dart';
import 'dialogs.dart';
import 'mac_kit.dart';

const double popoverWidth = 300;

class _Popover extends StatelessWidget {
  const _Popover({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final density = KitStyle.of(context).density.clamp(0.75, 1.35);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        6 * density,
        8 * density,
        6 * density,
        6 * density,
      ),
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
      final row = MacRow(
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
      // A saved network opens the profile dialog on a hold (touch) or a
      // right-click (pointer), because that dialog is where its password can
      // be changed and where Forget lives; a plain tap still joins.
      if (!network.saved) return row;
      return GestureDetector(
        onLongPress: busy ? null : () => widget.onJoin(network),
        onSecondaryTap: busy ? null : () => widget.onJoin(network),
        child: row,
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
                  duration: KitMotion.duration(context, KitMotion.enterLarge),
                  curve: KitMotion.outCubic,
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

class BluetoothPopover extends ConsumerStatefulWidget {
  const BluetoothPopover({required this.onSettings, this.onBack, super.key});

  final VoidCallback onSettings;
  final VoidCallback? onBack;

  @override
  ConsumerState<BluetoothPopover> createState() => _BluetoothPopoverState();
}

class _BluetoothPopoverState extends ConsumerState<BluetoothPopover> {
  /// The scan runs while the popover is up and is stopped on the way out:
  /// BlueZ keeps the radio advertising for its full window otherwise, and a
  /// scan left running is how a battery dies.
  ///
  /// The controller is kept from initState because a ref may not be read
  /// while the widget is being disposed.
  late final _bluetooth = ref.read(bluetoothProvider.notifier);

  @override
  void initState() {
    super.initState();
    final controller = _bluetooth;
    Future<void>.microtask(() {
      if (!mounted) return;
      final state = ref.read(bluetoothProvider);
      if (state.available && state.powered) controller.scan();
    });
  }

  @override
  void dispose() {
    _bluetooth.stopScan();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(bluetoothProvider);
    final controller = ref.read(bluetoothProvider.notifier);
    final on = state.available && state.powered;
    final known =
        state.devices
            .where((device) => device.name.isNotEmpty && device.paired)
            .toList()
          ..sort((a, b) {
            if (a.connected != b.connected) return a.connected ? -1 : 1;
            return a.name.toLowerCase().compareTo(b.name.toLowerCase());
          });
    // What the scan turned up that is not paired yet. A blocked device stays
    // out of the list; it is one the user asked the system to ignore.
    final found =
        state.devices
            .where(
              (device) =>
                  device.name.isNotEmpty &&
                  !device.paired &&
                  !device.blocked &&
                  device.connected == false,
            )
            .toList()
          ..sort((a, b) {
            final left = a.signalStrength ?? -127;
            final right = b.signalStrength ?? -127;
            return right.compareTo(left);
          });
    Widget row(BluetoothDeviceInfo device, {required bool paired}) {
      final busy = state.busyDevices.contains(device.objectPath);
      final row = MacRow(
        leading: MacDisc(icon: _bluetoothIcon(device), on: device.connected),
        title: device.name,
        detail: busy
            ? context.tr(paired ? 'Connecting…' : 'Pairing…')
            : device.connected
            ? context.tr('Connected')
            : null,
        // Both kinds connect on a tap; an unpaired one is paired and trusted
        // first by the same call.
        onTap: busy ? null : () => controller.toggleConnection(device),
      );
      // A paired device can be forgotten where it is listed: hold it on a
      // touch screen, right-click it with a pointer. A device that is only
      // nearby cannot.
      if (!paired) return row;
      return GestureDetector(
        onLongPress: busy ? null : () => _forgetDevice(context, ref, device),
        onSecondaryTap: busy ? null : () => _forgetDevice(context, ref, device),
        child: row,
      );
    }

    return _Popover(
      children: <Widget>[
        MacHeader(
          title: context.tr('Bluetooth'),
          onBack: widget.onBack,
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
              MacSection(context.tr(known.isEmpty ? 'Devices' : 'My Devices')),
              if (known.isEmpty)
                _Note(context.tr('No paired devices'))
              else
                _Scroll(
                  maxHeight: 168,
                  children: <Widget>[
                    for (final device in known) row(device, paired: true),
                  ],
                ),
              const MacDivider(),
              MacRow(
                title: context.tr(
                  state.scanning ? 'Scanning…' : 'Nearby Devices',
                ),
                height: 32,
                trailing: state.scanning
                    ? const SizedBox(width: 13, height: 13, child: _Spinner())
                    : BarGlyph(
                        BarIcons.arrowClockwise,
                        size: 12,
                        color: context.shellTheme.colors.textSecondary,
                      ),
                onTap: state.scanning ? null : controller.scan,
              ),
              Reveal(
                open: found.isNotEmpty || state.scanning,
                child: found.isEmpty
                    ? _Note(context.tr('Looking for devices…'))
                    : _Scroll(
                        maxHeight: 168,
                        children: <Widget>[
                          for (final device in found)
                            row(device, paired: false),
                        ],
                      ),
              ),
            ],
          ),
        ),
        if (on && state.pairingRequest != null)
          _PairingPrompt(
            request: state.pairingRequest!,
            onRespond: controller.respondToPairing,
          ),
        const MacDivider(),
        MacRow(
          title: context.tr('Bluetooth Settings…'),
          height: 32,
          onTap: widget.onSettings,
        ),
      ],
    );
  }
}

/// BlueZ's question, asked in place: a confirmation or authorization needs a
/// yes; a passkey may want the number checked, or typed when this side is the
/// keyboard.
class _PairingPrompt extends StatefulWidget {
  const _PairingPrompt({required this.request, required this.onRespond});

  final BluetoothPairingRequest request;
  final void Function({required bool accepted, String? response}) onRespond;

  @override
  State<_PairingPrompt> createState() => _PairingPromptState();
}

class _PairingPromptState extends State<_PairingPrompt> {
  final TextEditingController _typed = TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void dispose() {
    _typed.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _accept() {
    final text = _typed.text.trim();
    widget.onRespond(accepted: true, response: text.isEmpty ? null : text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final request = widget.request;
    final wantsText = request.kind.needsTextInput;
    final showsNumber =
        request.passkey != null || (request.pinCode?.isNotEmpty ?? false);
    final number = request.pinCode?.isNotEmpty ?? false
        ? request.pinCode!
        : request.passkey?.toString().padLeft(6, '0');
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            context.tr('Pair with “{}”?', request.deviceName),
            style: BarType.title.copyWith(color: theme.colors.textPrimary),
          ),
          if (showsNumber && number != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                context.tr(
                  'Check that the device shows this number: {}',
                  number,
                ),
                style: BarType.caption.copyWith(
                  color: theme.colors.textSecondary,
                ),
              ),
            ),
          if (showsNumber && number != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                number,
                style: BarType.display.copyWith(
                  fontSize: 26,
                  letterSpacing: 6,
                  color: theme.colors.textPrimary,
                ),
              ),
            ),
          if (wantsText)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Container(
                height: 34,
                decoration: BoxDecoration(
                  color: theme.colors.textPrimary.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(
                    kitStyle.value.radius(theme, 10),
                  ),
                  border: KitStyle.of(context).controlLine(theme),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                // A text field draws on a Material, and nothing above a
                // popover supplies one.
                child: Material(
                  type: MaterialType.transparency,
                  child: TextField(
                    controller: _typed,
                    focusNode: _focus,
                    keyboardType: TextInputType.number,
                    style: BarType.caption.copyWith(
                      color: theme.colors.textPrimary,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: context.tr('Code from the device'),
                      hintStyle: BarType.caption.copyWith(
                        color: theme.colors.textTertiary,
                      ),
                    ),
                    onSubmitted: (_) => _accept(),
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                DialogButton(
                  label: context.tr('Cancel'),
                  onTap: () => widget.onRespond(accepted: false),
                ),
                const SizedBox(width: 8),
                DialogButton(
                  label: context.tr(wantsText ? 'OK' : 'Pair'),
                  primary: true,
                  onTap: _accept,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Asks before forgetting a device, the way the reference does: the title
/// names it, the body says what it costs, and Forget is the second button.
void _forgetDevice(
  BuildContext context,
  WidgetRef ref,
  BluetoothDeviceInfo device,
) {
  final controller = ref.read(bluetoothProvider.notifier);
  showKitDialog(
    ref: ref,
    width: 320,
    builder: (context, close) => ConfirmDialog(
      mark: const SizedBox.shrink(),
      title: context.tr('Forget “{}”?', device.name),
      detail: context.tr('The device will need to be paired again to be used.'),
      action: context.tr('Forget Device'),
      onClose: close,
      onConfirm: () => controller.remove(device),
    ),
  );
}

/// A small ring that turns while a scan runs. Its period follows the shell's
/// speed like every other loop.
class _Spinner extends StatefulWidget {
  const _Spinner();

  @override
  State<_Spinner> createState() => _SpinnerState();
}

class _SpinnerState extends State<_Spinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _turn = AnimationController(
    vsync: this,
    duration: KitMotion.now.scaled(KitMotion.spin),
  )..repeat();

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    return RotationTransition(
      turns: _turn,
      child: CustomPaint(painter: _RingPainter(theme.colors.textSecondary)),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter(this.colour);

  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..color = colour.withValues(alpha: 0.75);
    canvas.drawArc(rect.deflate(1), 0, 4.4, false, paint);
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) => oldDelegate.colour != colour;
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
    final audible = ref.watch(services.volumeAvailable);
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
            enabled: audible,
            leading: volume <= 0.001
                ? BarIcons.speakerSlashFill
                : BarIcons.speaker1Fill,
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
                        inList: true,
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
                    wash: true,
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
                      scale: Pressable.small,
                      wash: true,
                      shape: KitStyle.of(context).disc(22),
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

/// Compact downward-floating tray shelf anchored beneath the bar toggle.
class TrayPopover extends ConsumerStatefulWidget {
  const TrayPopover({
    required this.services,
    required this.settings,
    required this.onClose,
    super.key,
  });

  final ShellServices services;
  final BarSettings settings;
  final VoidCallback onClose;

  @override
  ConsumerState<TrayPopover> createState() => _TrayPopoverState();
}

class _TrayPopoverState extends ConsumerState<TrayPopover> {
  Timer? _autoClose;
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    _arm();
  }

  @override
  void didUpdateWidget(TrayPopover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings.collapseAutoSeconds !=
        widget.settings.collapseAutoSeconds) {
      _arm();
    }
  }

  @override
  void dispose() {
    _autoClose?.cancel();
    super.dispose();
  }

  void _arm() {
    _autoClose?.cancel();
    final seconds =
        (ref.read(barSettingsProvider).value ?? widget.settings)
            .collapseAutoSeconds;
    if (seconds <= 0 || _hovered) return;
    _autoClose = Timer(Duration(seconds: seconds), () {
      if (mounted && !_hovered) widget.onClose();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final style = KitStyle.of(context);
    final density = style.density.clamp(0.75, 1.35);
    final trayIds = ref.watch(widget.services.trayItemIds);
    trayNames.resolve(trayIds);
    // The panel outlives the settings it was opened with.
    final settings =
        ref.watch(barSettingsProvider).value ?? widget.settings;
    final folded = partitionTrayIds(
      trayIds,
      settings: settings,
      resolveKey: (id) => trayNames.of(id).key,
    ).folded;
    final ink = theme.colors.textPrimary;
    final capsule = settings.trayFoldInForce == BarTrayFold.floatingBar;
    return MouseRegion(
      onEnter: (_) {
        _hovered = true;
        _autoClose?.cancel();
      },
      onExit: (_) {
        _hovered = false;
        _arm();
      },
      child: Listener(
        onPointerDown: (_) => _arm(),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: (capsule ? 10 : 8) * density,
            vertical: (capsule ? 5 : 6) * density,
          ),
          child: folded.isEmpty
              ? _Note(context.tr('No folded tray icons.'))
              : capsule
              ? SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      for (var i = 0; i < folded.length; i++) ...<Widget>[
                        if (i > 0) SizedBox(width: 4 * density),
                        Tooltip(
                          message: trayNames.of(folded[i]).title,
                          child: SizedBox(
                            width: 28,
                            height: 28,
                            child: Center(
                              child: buildTrayIcons(
                                context,
                                services: widget.services,
                                settings: settings,
                                ink: ink,
                                itemIds: <String>[folded[i]],
                                maxExtent: 22,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                )
              : Wrap(
                  spacing: 6 * density,
                  runSpacing: 6 * density,
                  alignment: WrapAlignment.center,
                  children: <Widget>[
                    for (final id in folded)
                      Tooltip(
                        message: trayNames.of(id).title,
                        child: Container(
                          width: 30,
                          height: 30,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: ink.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(
                              style.corner(8),
                            ),
                          ),
                          child: buildTrayIcons(
                            context,
                            services: widget.services,
                            settings: settings,
                            ink: ink,
                            itemIds: <String>[id],
                            maxExtent: 24,
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}
