import 'package:denial_flutter_sdk/controls.dart';
import 'package:denial_flutter_sdk/effects.dart';
import 'package:denial_flutter_sdk/models.dart';
import 'package:denial_flutter_sdk/services.dart';
import 'package:denial_flutter_sdk/state.dart';
import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bar_icons.dart';
import '../bar_tokens.dart';
import '../bar_type.dart';
import '../island.dart' show IslandExpandedBody, IslandMode;
import 'media_card.dart';

/// Control Centre.
///
/// Ports NextKDE `ControlCenterPanel.qml`'s grid verbatim: panel width
/// `clamp(296, 336, screen - 24)`, 20 margins, connectivity column
/// `round((controls - 8) * 137 / 288)`, media card `controls - connectivity - 8`,
/// five quick cells of `(controls - 36) / 5` with 9 gaps, two half cells of
/// `(controls - 8) / 2`, then the two 57-high slider cards. Card radii follow
/// `AppearanceTokens.shape`: 29.5 for the connectivity pills, 25 for media,
/// 26 for the square cells, 19 for the sliders.
class ControlCenterPanel extends ConsumerWidget {
  const ControlCenterPanel({
    required this.services,
    required this.monitorId,
    required this.output,
    required this.onOpenSettings,
    required this.onOpenNotifications,
    required this.onOpenIsland,
    required this.onOpenDisplaySettings,
    super.key,
  });

  final ShellServices services;
  final int monitorId;
  final DisplayOutput output;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenNotifications;
  final VoidCallback onOpenIsland;
  final VoidCallback onOpenDisplaySettings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = BarTokens.controlCenterMaxWidth;
    const padding = BarTokens.controlCenterMargin;
    final controls = width - padding * 2;
    final connectivityWidth = (controls - 8) * 137 / 288;
    final mediaWidth = controls - connectivityWidth - 8;
    final quickWidth = (controls - 36) / 5;
    final halfWidth = (controls - 8) / 2;

    final bluetooth = ref.watch(bluetoothProvider);
    final wifi = ref.watch(services.connectedWifi);
    final brightness = ref.watch(displayBrightnessProvider);
    final level = brightness.levels[output.monitorId] ?? 1;
    final volume = ref.watch(services.volume);
    final unread = ref.watch(
      desktopNotificationsProvider.select((state) => state.unreadCount),
    );
    final playing = ref.watch(
      services.media.select((media) => media.value?.playing ?? false),
    );

    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.all(padding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SizedBox(
              height: 127,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  SizedBox(
                    width: connectivityWidth,
                    child: Column(
                      children: <Widget>[
                        _ConnectivityCard(
                          icon: wifi == null
                              ? BarIcons.wifiSlash
                              : BarIcons.wifi,
                          title: services.strings(context).wifiTitle,
                          detail:
                              wifi?.ssid ??
                              services.strings(context).notConnected,
                          on: wifi != null,
                          radius: BarTokens.controlCenterWideRadius,
                          onTap: onOpenSettings,
                        ),
                        const SizedBox(height: 8),
                        _ConnectivityCard(
                          icon: BarIcons.bluetooth,
                          title: 'Bluetooth',
                          detail: !bluetooth.available
                              ? 'Unavailable'
                              : bluetooth.powered
                              ? 'On'
                              : 'Off',
                          on: bluetooth.available && bluetooth.powered,
                          radius: BarTokens.controlCenterWideRadius,
                          onTap: () => ref
                              .read(bluetoothProvider.notifier)
                              .togglePower(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: mediaWidth,
                    child: MediaCard(services: services),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                for (final (index, cell) in <Widget>[
                  _QuickCell(
                    icon: BarIcons.moonFill,
                    label: 'Focus',
                    on: ref.watch(
                      desktopNotificationsProvider.select(
                        (state) => state.doNotDisturb,
                      ),
                    ),
                    onTap: () => ref
                        .read(desktopNotificationsProvider.notifier)
                        .toggleDoNotDisturb(),
                  ),
                  _QuickCell(
                    icon: BarIcons.bolt,
                    label: 'Island',
                    on: playing,
                    onTap: onOpenIsland,
                  ),
                  _QuickCell(
                    icon: BarIcons.bell,
                    label: 'Notifications',
                    on: unread > 0,
                    onTap: onOpenNotifications,
                  ),
                  _QuickCell(
                    icon: BarIcons.sunMax,
                    label: 'Display',
                    on: false,
                    onTap: onOpenDisplaySettings,
                  ),
                  _QuickCell(
                    icon: BarIcons.gear,
                    label: 'Settings',
                    on: false,
                    onTap: onOpenSettings,
                  ),
                ].indexed)
                  Padding(
                    padding: EdgeInsets.only(left: index == 0 ? 0 : 9),
                    child: SizedBox(
                      width: quickWidth,
                      height: quickWidth,
                      child: cell,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                SizedBox(
                  width: halfWidth,
                  height: 44,
                  child: _HalfCell(
                    icon: BarIcons.grid,
                    label: 'Desktop',
                    onTap: () => services.toggleDesktop(),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: halfWidth,
                  height: 44,
                  child: _HalfCell(
                    icon: BarIcons.house,
                    label: 'Dashboard',
                    onTap: () => services.toggleDashboard(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 57,
              child: _SliderCard(
                icon: BarIcons.sunMaxFill,
                value: level,
                onChangeStart: () {},
                onChanged: (value) => ref
                    .read(displayBrightnessProvider.notifier)
                    .setLevel(output, value),
                onChangeEnd: (value) => ref
                    .read(displayBrightnessProvider.notifier)
                    .commitLevel(output, value),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 57,
              child: _SliderCard(
                icon: volume == 0 ? BarIcons.volumeMute : BarIcons.volumeUp,
                value: volume,
                onChangeStart: services.beginVolumeInteraction,
                onChanged: services.setVolume,
                onChangeEnd: services.commitVolume,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One glass card in the grid.
///
/// NextKDE gives every card its own compositor blur region; here one
/// [ShellBackdropBlur] per card reproduces the hollow look, with the gaps
/// between cards left crisp.
class _Card extends StatefulWidget {
  const _Card({
    required this.radius,
    required this.child,
    this.onTap,
    this.on = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 14),
  });

  final double radius;
  final Widget child;
  final VoidCallback? onTap;
  final bool on;
  final EdgeInsets padding;

  @override
  State<_Card> createState() => _CardState();
}

class _CardState extends State<_Card> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final shape = BorderRadius.circular(widget.radius);
    final fill = widget.on
        ? theme.accent.withValues(alpha: 0.9)
        : theme.colors.surfaceContainer.withValues(alpha: 0.62);
    Widget content = AnimatedContainer(
      duration: Motion.pill,
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: _hovered
            ? Color.lerp(fill, theme.colors.textPrimary, 0.06)
            : fill,
        borderRadius: shape,
      ),
      padding: widget.padding,
      child: widget.child,
    );
    content = ShellBackdropBlur(
      borderRadius: shape,
      blendMode: BlendMode.srcOver,
      child: content,
    );
    if (widget.onTap != null) {
      content = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: content,
        ),
      );
    }
    return content;
  }
}

class _ConnectivityCard extends StatelessWidget {
  const _ConnectivityCard({
    required this.icon,
    required this.title,
    required this.detail,
    required this.on,
    required this.radius,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String detail;
  final bool on;
  final double radius;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final ink = on ? const Color(0xffffffff) : theme.colors.textPrimary;
    return _Card(
      radius: radius,
      on: on,
      onTap: onTap,
      child: Row(
        children: <Widget>[
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: on
                  ? const Color(0xffffffff).withValues(alpha: 0.24)
                  : theme.colors.textPrimary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: BarGlyph(icon, size: 15, color: ink),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: BarType.value.copyWith(
                    fontWeight: FontWeight.w600,
                    color: ink,
                  ),
                ),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: BarType.caption.copyWith(
                    color: on
                        ? ink.withValues(alpha: 0.78)
                        : theme.colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickCell extends StatelessWidget {
  const _QuickCell({
    required this.icon,
    required this.label,
    required this.on,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final ink = on ? const Color(0xffffffff) : theme.colors.textPrimary;
    return _Card(
      radius: BarTokens.controlCenterCardRadius,
      on: on,
      onTap: onTap,
      padding: EdgeInsets.zero,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          BarGlyph(icon, size: 20, color: ink),
          const SizedBox(height: 5),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: BarType.cellLabel.copyWith(
              color: on ? ink : theme.colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _HalfCell extends StatelessWidget {
  const _HalfCell({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    return _Card(
      radius: BarTokens.controlCenterSmallRadius,
      onTap: onTap,
      child: Row(
        children: <Widget>[
          BarGlyph(icon, size: 15, color: theme.colors.textPrimary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: BarType.value.copyWith(color: theme.colors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _SliderCard extends StatelessWidget {
  const _SliderCard({
    required this.icon,
    required this.value,
    required this.onChangeStart,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final IconData icon;
  final double value;
  final VoidCallback onChangeStart;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    return _Card(
      radius: BarTokens.controlCenterSmallRadius,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: <Widget>[
          BarGlyph(icon, size: 16, color: theme.colors.textPrimary),
          const SizedBox(width: 12),
          Expanded(
            child: RangeBar(
              value: value,
              activeColor: theme.colors.textPrimary,
              inactiveColor: theme.colors.textPrimary.withValues(alpha: 0.16),
              height: 22,
              onChangeStart: onChangeStart,
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            ),
          ),
        ],
      ),
    );
  }
}

/// The island's expanded card, shown from Control Centre and from the pill.
class IslandPanel extends ConsumerWidget {
  const IslandPanel({
    required this.mode,
    required this.services,
    required this.notification,
    required this.onDismiss,
    super.key,
  });

  final IslandMode mode;
  final ShellServices services;
  final DesktopNotification? notification;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IslandExpandedBody(
      mode: mode,
      notification: notification,
      playback: ref.watch(services.media).value,
      artwork: null,
      commands: ref.watch(services.mediaCommands),
      onDismissNotice: onDismiss,
      onActivateNotice: onDismiss,
    );
  }
}
