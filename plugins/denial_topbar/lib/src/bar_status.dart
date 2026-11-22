import 'package:denial_flutter_sdk/services.dart';
import 'package:denial_flutter_sdk/state.dart';
import 'package:denial_flutter_sdk/theme.dart';
import 'package:denial_sdk/system.dart' show BatteryStatus;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'bar_button.dart';
import 'bar_glyphs.dart';
import 'bar_icons.dart';
import 'bar_settings.dart';
import 'bar_tokens.dart';
import 'bar_type.dart';
import 'signal.dart';

/// One status item.
///
/// shell27 gives every status item a 24-wide box on the 28-high bar and
/// MacShell does the same; the glyph inside is 15–16. The hover plate is the
/// bar's own item plate, so a status item reads exactly like a menu title.
class BarStatusCell extends StatelessWidget {
  const BarStatusCell({
    required this.child,
    required this.ink,
    this.onTap,
    this.tooltip,
    this.open = false,
    super.key,
  });

  final Widget child;

  /// The bar's ink; the plate lightens under white and darkens under black.
  final Color ink;
  final VoidCallback? onTap;
  final String? tooltip;
  final bool open;

  @override
  Widget build(BuildContext context) {
    return BarButton(
      onTap: onTap,
      open: open,
      ink: ink,
      minWidth: BarTokens.statusCellWidth,
      padding: EdgeInsets.zero,
      tooltip: tooltip,
      child: child,
    );
  }
}

/// The right-hand cluster.
///
/// Order follows macOS 27's menu bar extras: tray, then the connectivity
/// glyph, the battery, notifications, Control Centre and the bar's own
/// settings button. NextKDE's `BarStatusArea.qml` supplies the order and the
/// trailing table; the swap puts Control Centre where macOS keeps it.
class BarStatusCluster extends ConsumerWidget {
  const BarStatusCluster({
    required this.services,
    required this.settings,
    required this.openPanel,
    required this.ink,
    required this.onWifi,
    required this.onBattery,
    required this.onNotifications,
    required this.onControlCenter,
    required this.onSettings,
    super.key,
  });

  final ShellServices services;
  final BarSettings settings;

  /// The panel currently open, so its cell keeps its plate.
  final String? openPanel;

  final Color ink;
  final VoidCallback onWifi;
  final VoidCallback onBattery;
  final VoidCallback onNotifications;
  final VoidCallback onControlCenter;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = services.strings(context);
    final trayVisible = ref.watch(services.trayVisible);
    final trayIds = ref.watch(services.trayItemIds);
    final wifi = ref.watch(services.connectedWifi);
    final battery = ref.watch(services.battery);
    final unread = ref.watch(
      desktopNotificationsProvider.select((state) => state.unreadCount),
    );

    final cells = <Widget>[
      if (settings.showTray && trayVisible && trayIds.isNotEmpty)
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 240),
          child: services.buildSystemTray(
            context,
            horizontal: true,
            foregroundColor: ink,
          ),
        ),
      if (settings.showWifi)
        BarStatusCell(
          ink: ink,
          tooltip: wifi?.ssid ?? strings.wifiTitle,
          onTap: onWifi,
          open: openPanel == 'wifi',
          child: wifi == null
              ? BarGlyph(
                  BarIcons.wifiSlash,
                  size: BarTokens.statusGlyphSize,
                  color: ink.withValues(alpha: 0.5),
                )
              : WifiGlyph(
                  size: BarTokens.statusIconSize,
                  color: ink,
                  strength: wifiSignalArcs(wifi.strength),
                ),
        ),
      if (settings.showBattery && battery.capacity != null)
        BarStatusCell(
          ink: ink,
          tooltip: '${strings.batteryTitle} · ${battery.capacity}%',
          onTap: onBattery,
          open: openPanel == 'battery',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (settings.showBatteryPercent)
                Padding(
                  padding: const EdgeInsets.only(right: 3),
                  child: Text(
                    '${battery.capacity}%',
                    style: BarType.caption.copyWith(color: ink),
                  ),
                ),
              BarGlyph(
                batteryIconFor(battery),
                size: BarTokens.statusGlyphSize,
                color: ink,
              ),
            ],
          ),
        ),
      if (settings.showNotifications)
        BarStatusCell(
          ink: ink,
          tooltip: 'Notifications',
          onTap: onNotifications,
          open: openPanel == 'notifications',
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              BarGlyph(
                unread > 0 ? BarIcons.bellFill : BarIcons.bell,
                size: BarTokens.statusIconSize,
                color: ink,
              ),
              if (unread > 0)
                Positioned(
                  right: -1,
                  top: -1,
                  child: Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      color: context.shellTheme.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      if (settings.showControlCenter)
        BarStatusCell(
          ink: ink,
          tooltip: 'Control Center',
          onTap: onControlCenter,
          open: openPanel == 'controlcenter',
          child: ControlCentreGlyph(
            size: BarTokens.statusGlyphSize,
            color: ink,
          ),
        ),
      if (settings.showSettingsButton)
        BarStatusCell(
          ink: ink,
          tooltip: 'Bar Settings',
          onTap: onSettings,
          open: openPanel == 'settings',
          child: BarGlyph(
            BarIcons.gear,
            size: BarTokens.statusIconSize,
            color: ink,
          ),
        ),
    ];

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (var index = 0; index < cells.length; index++) ...<Widget>[
          if (index > 0) const SizedBox(width: BarTokens.statusSpacing),
          cells[index],
        ],
      ],
    );
  }
}

/// NextKDE `Battery.qml` picks a level icon and overlays the bolt while
/// charging; the thresholds follow the vendored icon set (full, 75, 25, empty).
IconData batteryIconFor(BatteryStatus battery) {
  if (battery.charging) return BarIcons.batteryCharging;
  final capacity = battery.capacity ?? 0;
  if (capacity >= 88) return BarIcons.batteryFull;
  if (capacity >= 50) return BarIcons.battery75;
  if (capacity >= 13) return BarIcons.battery25;
  return BarIcons.batteryEmpty;
}
