import 'package:denial_flutter_sdk/state.dart';
import 'package:denial_flutter_sdk/system_services.dart' show WifiNetwork;
import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bar_icons.dart';
import '../bar_tokens.dart';
import '../bar_type.dart';
import 'cc_card.dart';
import 'panel_parts.dart' show WifiStrengthGlyph;

/// The header a sub-page shares with the bar's own Wi-Fi popover.
///
/// NextKDE `SubmenuCard.qml`: a 26 pt back button, the title 8 pt after it, and
/// the 38 × 22 switch at the right, over a hairline 9 pt below the row.
class CcSubmenuHeader extends StatelessWidget {
  const CcSubmenuHeader({
    required this.title,
    this.onBack,
    this.trailing,
    super.key,
  });

  final String title;
  final VoidCallback? onBack;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final dark = theme.colors.brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SizedBox(
          height: BarTokens.ccSubmenuHeaderHeight,
          child: Row(
            children: <Widget>[
              if (onBack != null) ...<Widget>[
                CcBackButton(onTap: onBack!),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: BarType.title.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colors.textPrimary,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
        ),
        const SizedBox(height: BarTokens.ccSubmenuDividerGap),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: SizedBox(
            height: 1,
            child: ColoredBox(
              color: Colors.white.withValues(alpha: dark ? 0.10 : 0.08),
            ),
          ),
        ),
      ],
    );
  }
}


/// The Wi-Fi page.
///
/// Ports NextKDE `WifiPage.qml`: a 22 pt section heading, 42 pt rows with a
/// check for the connected network, a lock for a secured one and a Disconnect
/// pill, then a 38 pt "Network settings…" footer. The page is hosted either by
/// the bar's own popover or by the Control Centre's sub-page, which is why it
/// carries no frame or header of its own.
class WifiContent extends ConsumerStatefulWidget {
  const WifiContent({
    required this.onOpenSettings,
    required this.onJoinNetwork,
    this.onClose,
    super.key,
  });

  final VoidCallback onOpenSettings;

  /// Opens the join dialog for a secured network with no saved profile.
  ///
  /// The reference closes the Wi-Fi list before showing it, because the dialog
  /// is a system modal that owns the keyboard; the host passes a callback that
  /// can do that rather than the page opening a nested popup itself.
  final ValueChanged<WifiNetwork> onJoinNetwork;
  final VoidCallback? onClose;

  @override
  ConsumerState<WifiContent> createState() => _WifiContentState();
}

class _WifiContentState extends ConsumerState<WifiContent> {

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final state = ref.watch(networkConnectivityProvider);
    final snapshot = state.snapshot;
    final on = snapshot.wirelessEnabled;
    final networks = snapshot.networks
        .where((network) => network.ssid.isNotEmpty)
        .toList(growable: false);

    if (!on) {
      return _OffState(
        title: 'Wi‑Fi is off',
        detail: 'Turn on the switch above to see nearby networks',
        footer: CcFooter(
          label: 'Network settings…',
          icon: BarIcons.sliderHorizontal3,
          onTap: widget.onOpenSettings,
        ),
      );
    }

    // NextKDE lists every nearby network under one heading. A saved profile is
    // the one distinction the row cannot show, and Denial already knows it
    // (`WifiNetwork.saved`), so the list splits the way macOS splits it.
    final known = networks
        .where((network) => network.saved || network.connected)
        .toList(growable: false);
    final other = networks
        .where((network) => !network.saved && !network.connected)
        .toList(growable: false);
    final grouped = known.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 4),
            children: <Widget>[
              CcSectionHeader(
                title: grouped ? 'Known Networks' : 'Nearby Networks',
                trailing: state.scanning
                    ? Text(
                        'Scanning…',
                        style: BarType.caption.copyWith(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: theme.colors.textPrimary,
                        ),
                      )
                    : null,
              ),
              const SizedBox(height: 2),
              for (final network in grouped ? known : networks)
                _WifiRow(
                  network: network,
                  busy: state.busyNetworks.contains(network.identity),
                  onTap: () => _tap(network),
                ),
              if (grouped) ...<Widget>[
                CcSectionHeader(title: 'Other Networks'),
                const SizedBox(height: 2),
                for (final network in other)
                  _WifiRow(
                    network: network,
                    busy: state.busyNetworks.contains(network.identity),
                    onTap: () => _tap(network),
                  ),
              ],
              if (networks.isEmpty && !state.scanning)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      'No Wi‑Fi networks detected',
                      style: BarType.caption.copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: theme.colors.textPrimary,
                      ),
                    ),
                  ),
                ),
              if (state.error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
                  child: Text(
                    state.error!,
                    style: BarType.caption.copyWith(
                      fontSize: 11,
                      color: const Color(0xffff6961),
                    ),
                  ),
                ),
            ],
          ),
        ),
        CcFooter(
          label: 'Network settings…',
          icon: BarIcons.sliderHorizontal3,
          onTap: widget.onOpenSettings,
        ),
      ],
    );
  }

  void _tap(WifiNetwork network) {
    final controller = ref.read(networkConnectivityProvider.notifier);
    if (network.connected) {
      controller.disconnect(network);
      return;
    }
    // A saved profile and an open network both join straight away; only a new
    // secured network needs the join dialog. NextKDE splits it the same way.
    if (network.saved || !network.security.requiresPassword) {
      controller.connect(network);
      return;
    }
    widget.onJoinNetwork(network);
  }
}

/// One network row.
class _WifiRow extends StatelessWidget {
  const _WifiRow({
    required this.network,
    required this.busy,
    required this.onTap,
  });

  final WifiNetwork network;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: CcListRow(
        onTap: busy ? null : onTap,
        leading: network.connected
            ? BarGlyph(
                BarIcons.checkmark,
                size: 13,
                color: theme.colors.textPrimary,
              )
            : SizedBox(
                width: 16,
                height: 16,
                child: Center(
                  child: WifiStrengthGlyph(
                    strength: network.strength,
                    size: 16,
                    color: theme.colors.textPrimary,
                  ),
                ),
              ),
        trailing: CcWifiTrailing(
          secured: network.security.requiresPassword,
          connected: network.connected,
          strength: network.strength,
          busy: busy,
        ),
        child: Text(
          network.ssid,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: BarType.caption.copyWith(
            fontSize: 12,
            fontWeight: network.connected ? FontWeight.w700 : FontWeight.w600,
            color: theme.colors.textPrimary,
          ),
        ),
      ),
    );
  }
}

/// The Bluetooth page.
///
/// Ports NextKDE `BluetoothPage.qml`: the same 22 pt heading, 42 pt rows with a
/// check for the connected device, the device glyph turning blue while it is
/// connected, a 9 pt state line under the name and a 38 pt footer.
class BluetoothContent extends ConsumerWidget {
  const BluetoothContent({
    required this.onOpenSettings,
    this.onClose,
    super.key,
  });

  final VoidCallback onOpenSettings;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.shellTheme;
    final state = ref.watch(bluetoothProvider);
    final controller = ref.read(bluetoothProvider.notifier);
    final on = state.available && state.powered;
    final devices = state.devices
        .where((device) => device.name.isNotEmpty)
        .toList(growable: false);

    if (!state.available) {
      return _OffState(
        title: 'Bluetooth is unavailable',
        detail: 'No Bluetooth adapter was found',
        footer: CcFooter(
          label: 'Bluetooth settings…',
          icon: BarIcons.sliderHorizontal3,
          labelSize: 11,
          onTap: onOpenSettings,
        ),
      );
    }
    if (!on) {
      return _OffState(
        title: 'Bluetooth is off',
        detail: 'Turn on the switch above to connect devices',
        footer: CcFooter(
          label: 'Bluetooth settings…',
          icon: BarIcons.sliderHorizontal3,
          labelSize: 11,
          onTap: onOpenSettings,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 4),
            children: <Widget>[
              CcSectionHeader(
                title: 'Devices',
                titleSize: 10,
                trailing: state.scanning
                    ? Text(
                        'Refreshing…',
                        style: BarType.caption.copyWith(
                          fontSize: 9,
                          color: theme.colors.textPrimary,
                        ),
                      )
                    : _ScanLink(onTap: controller.scan),
              ),
              const SizedBox(height: 2),
              for (final device in devices)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 1,
                  ),
                  child: CcListRow(
                    onTap: state.busyDevices.contains(device.objectPath)
                        ? null
                        : () => controller.toggleConnection(device),
                    leading: device.connected
                        ? BarGlyph(
                            BarIcons.checkmark,
                            size: 13,
                            color: theme.colors.textPrimary,
                          )
                        : BarGlyph(
                            BarIcons.bluetooth,
                            size: 16,
                            color: device.connected
                                ? ccBlue
                                : theme.colors.textPrimary,
                          ),
                    trailing: state.busyDevices.contains(device.objectPath)
                        ? Text(
                            device.connected
                                ? 'Disconnecting…'
                                : 'Connecting…',
                            style: BarType.caption.copyWith(
                              fontSize: 10,
                              color: theme.colors.textSecondary,
                            ),
                          )
                        : null,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          device.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: BarType.caption.copyWith(
                            fontSize: 11,
                            fontWeight: device.connected
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: theme.colors.textPrimary,
                          ),
                        ),
                        Text(
                          device.connected ? 'Connected' : 'Not connected',
                          style: BarType.caption.copyWith(
                            fontSize: 9,
                            color: theme.colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (devices.isEmpty && !state.scanning)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      'No paired devices found',
                      style: BarType.caption.copyWith(
                        fontSize: 11,
                        color: theme.colors.textPrimary,
                      ),
                    ),
                  ),
                ),
              if (state.error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
                  child: Text(
                    state.error!,
                    style: BarType.caption.copyWith(
                      fontSize: 11,
                      color: const Color(0xffff6961),
                    ),
                  ),
                ),
            ],
          ),
        ),
        CcFooter(
          label: 'Bluetooth settings…',
          icon: BarIcons.sliderHorizontal3,
          labelSize: 11,
          onTap: onOpenSettings,
        ),
      ],
    );
  }
}

/// The centred two-line state a page shows while its radio is off.
class _OffState extends StatelessWidget {
  const _OffState({
    required this.title,
    required this.detail,
    required this.footer,
  });

  final String title;
  final String detail;
  final Widget footer;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  title,
                  style: BarType.caption.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: theme.colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  detail,
                  textAlign: TextAlign.center,
                  style: BarType.caption.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: theme.colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
        footer,
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
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Text(
            'Scan',
            style: BarType.caption.copyWith(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: theme.accent,
            ),
          ),
        ),
      ),
    );
  }
}
