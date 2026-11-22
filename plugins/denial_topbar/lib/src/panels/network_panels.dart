import 'package:denial_flutter_sdk/state.dart';
import 'package:denial_flutter_sdk/system_services.dart' show WifiNetwork;
import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bar_icons.dart';
import 'panel_parts.dart';

/// The Wi-Fi list.
///
/// Ports shell27 `MacBar.qml`'s `wifiContent` component verbatim: a 32 pt
/// header holding the title and the on/off switch, a hairline, the connected
/// network's SSID and signal, then the network list, then Wi-Fi Settings….
/// The same column serves the bar's own popover and the Control Centre's
/// Wi-Fi page, which is why it takes [showBack] instead of owning a frame.
class WifiContent extends ConsumerStatefulWidget {
  const WifiContent({
    required this.onOpenSettings,
    this.showBack = false,
    this.onBack,
    super.key,
  });

  final VoidCallback onOpenSettings;
  final bool showBack;
  final VoidCallback? onBack;

  @override
  ConsumerState<WifiContent> createState() => _WifiContentState();
}

class _WifiContentState extends ConsumerState<WifiContent> {
  /// The network whose password field is open. shell27 keeps this in its
  /// popup state (`ui.wifiPrompt`); one field at a time is the whole rule.
  String? _prompting;
  final TextEditingController _password = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  void _submit(WidgetRef ref, WifiNetwork network) {
    final password = _password.text;
    setState(() {
      _prompting = null;
      _password.clear();
    });
    ref
        .read(networkConnectivityProvider.notifier)
        .connect(network, password: password.isEmpty ? null : password);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final state = ref.watch(networkConnectivityProvider);
    final controller = ref.read(networkConnectivityProvider.notifier);
    final snapshot = state.snapshot;
    final on = snapshot.wirelessEnabled;
    final connected = snapshot.connectedNetwork;
    final networks = snapshot.networks
        .where((network) => network.ssid.isNotEmpty)
        .toList(growable: false);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        PanelHeader(
          title: 'Wi-Fi',
          showBack: widget.showBack,
          onBack: widget.onBack,
          trailing: PanelSwitch(
            value: on,
            onChanged: (value) => controller.setWirelessEnabled(value),
          ),
        ),
        PanelDivider(color: theme.colors.hairlineSoft),
        if (connected != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 0, 6, 2),
            child: Text(
              '${connected.ssid} · ${connected.strength}%',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: PanelText.detail(theme),
            ),
          ),
        if (!on)
          const PanelEmpty('Wi-Fi is turned off')
        else if (networks.isEmpty)
          PanelEmpty(state.scanning ? 'Searching…' : 'No networks found')
        else ...<Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 4, 6, 0),
            child: Text('Networks', style: PanelText.section(theme)),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 300),
            child: ListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: networks.length,
              itemBuilder: (context, index) {
                final network = networks[index];
                final busy = state.busyNetworks.contains(network.identity);
                final prompting = _prompting == network.identity;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    PanelRow(
                      height: 38,
                      selected: network.connected,
                      onTap: busy || prompting
                          ? null
                          : () {
                              if (network.connected) {
                                controller.disconnect(network);
                                return;
                              }
                              if (network.saved || !network.security.requiresPassword) {
                                controller.connect(network);
                                return;
                              }
                              setState(() {
                                _prompting = network.identity;
                                _password.clear();
                              });
                            },
                      leading: network.connected
                          ? BarIcons.checkmark
                          : null,
                      label: network.ssid,
                      bold: network.connected,
                      trailing: _WifiRowTrailing(
                        busy: busy,
                        connected: network.connected,
                        secured: network.security.requiresPassword,
                        strength: network.strength,
                      ),
                    ),
                    if (prompting)
                      _PasswordField(
                        controller: _password,
                        onCancel: () => setState(() {
                          _prompting = null;
                          _password.clear();
                        }),
                        onSubmit: () => _submit(ref, network),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
        if (state.error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 4, 6, 0),
            child: Text(
              state.error!,
              style: PanelText.detail(theme).copyWith(
                color: const Color(0xffff6961),
              ),
            ),
          ),
        PanelDivider(color: theme.colors.hairlineSoft),
        PanelAction(label: 'Wi-Fi Settings…', onTap: widget.onOpenSettings),
      ],
    );
  }
}

class _WifiRowTrailing extends StatelessWidget {
  const _WifiRowTrailing({
    required this.busy,
    required this.connected,
    required this.secured,
    required this.strength,
  });

  final bool busy;
  final bool connected;
  final bool secured;
  final int strength;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    if (busy) {
      return Text(
        'Connecting…',
        style: PanelText.detail(theme).copyWith(fontSize: 12),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (secured)
          Padding(
            padding: const EdgeInsets.only(right: 7),
            child: BarGlyph(
              BarIcons.lock,
              size: 13,
              color: theme.colors.textSecondary,
            ),
          ),
        WifiStrengthGlyph(
          strength: strength,
          size: 16,
          color: theme.colors.textPrimary,
        ),
      ],
    );
  }
}

class _PasswordField extends StatelessWidget {
  const _PasswordField({
    required this.controller,
    required this.onCancel,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final VoidCallback onCancel;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(30, 3, 4, 3),
      child: SizedBox(
        height: 32,
        child: Row(
          children: <Widget>[
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.colors.tileOff,
                  borderRadius: theme.borderRadius(10),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: TextField(
                    controller: controller,
                    autofocus: true,
                    obscureText: true,
                    style: PanelText.body(theme),
                    cursorColor: theme.accent,
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: 'Password',
                      hintStyle: PanelText.body(theme).copyWith(
                        color: theme.colors.textTertiary,
                      ),
                    ),
                    onSubmitted: (_) => onSubmit(),
                    onTapOutside: (_) => onCancel(),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onSubmit,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 6,
                  ),
                  child: Text(
                    'Join',
                    style: PanelText.body(
                      theme,
                    ).copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The Bluetooth list. Ports shell27's `btContent`: the same 32 pt header with
/// a power switch, the device list, and a Scan link that only appears while
/// nothing is being discovered.
class BluetoothContent extends ConsumerWidget {
  const BluetoothContent({
    required this.onOpenSettings,
    this.showBack = false,
    this.onBack,
    super.key,
  });

  final VoidCallback onOpenSettings;
  final bool showBack;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.shellTheme;
    final state = ref.watch(bluetoothProvider);
    final controller = ref.read(bluetoothProvider.notifier);
    final on = state.available && state.powered;
    final devices = state.devices
        .where((device) => device.name.isNotEmpty)
        .toList(growable: false);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        PanelHeader(
          title: 'Bluetooth',
          showBack: showBack,
          onBack: onBack,
          trailing: PanelSwitch(
            value: on,
            onChanged: state.available
                ? (value) => controller.togglePower()
                : null,
          ),
        ),
        PanelDivider(color: theme.colors.hairlineSoft),
        if (!state.available)
          const PanelEmpty('Bluetooth is unavailable')
        else if (!on)
          const PanelEmpty('Bluetooth is turned off')
        else if (devices.isEmpty)
          PanelEmpty(state.scanning ? 'Searching for devices…' : 'No devices found')
        else ...<Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 4, 6, 0),
            child: Row(
              children: <Widget>[
                Text('Devices', style: PanelText.section(theme)),
                const Spacer(),
                if (state.scanning)
                  Text(
                    'Scanning…',
                    style: PanelText.detail(theme).copyWith(fontSize: 11),
                  )
                else
                  _ScanLink(onTap: controller.scan),
              ],
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 300),
            child: ListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: devices.length,
              itemBuilder: (context, index) {
                final device = devices[index];
                final busy = state.busyDevices.contains(device.objectPath);
                return PanelRow(
                  height: 38,
                  selected: device.connected,
                  onTap: busy ? null : () => controller.toggleConnection(device),
                  leading: device.connected ? BarIcons.checkmark : null,
                  label: device.name,
                  bold: device.connected,
                  trailing: Text(
                    busy
                        ? (device.connected
                              ? 'Disconnecting…'
                              : 'Connecting…')
                        : device.connected
                        ? 'Connected'
                        : device.paired
                        ? 'Paired'
                        : '',
                    style: PanelText.detail(theme).copyWith(fontSize: 12),
                  ),
                );
              },
            ),
          ),
        ],
        if (state.error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 4, 6, 0),
            child: Text(
              state.error!,
              style: PanelText.detail(
                theme,
              ).copyWith(color: const Color(0xffff6961)),
            ),
          ),
        PanelDivider(color: theme.colors.hairlineSoft),
        PanelAction(label: 'Bluetooth Settings…', onTap: onOpenSettings),
      ],
    );
  }
}

class _ScanLink extends StatelessWidget {
  const _ScanLink({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Text(
            'Scan',
            style: PanelText.section(
              theme,
            ).copyWith(color: theme.accent),
          ),
        ),
      ),
    );
  }
}

