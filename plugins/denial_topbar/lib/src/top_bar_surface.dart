import 'dart:async';
import 'dart:math' as math;

import 'package:denial_flutter_sdk/effects.dart';
import 'package:denial_flutter_sdk/input.dart';
import 'package:denial_flutter_sdk/models.dart';
import 'package:denial_flutter_sdk/state.dart';
import 'package:denial_flutter_sdk/surfaces.dart';
import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'island/island_activity.dart';
import 'island/island_view.dart';
import 'panels/battery_panel.dart';
import 'panels/calendar_panel.dart';
import 'panels/media_panel.dart';
import 'panels/notifications_panel.dart';
import 'panels/settings_panel.dart';
import 'top_bar_modules.dart';
import 'top_bar_popups.dart';
import 'top_bar_preferences.dart';

/// Extra surface past the reserved strip so the capsule can cast a shadow.
const double topBarShadowExtent = 12;

class TopBarSurface extends ConsumerStatefulWidget {
  const TopBarSurface({
    required this.monitorId,
    required this.environment,
    required this.services,
    super.key,
  });

  final int monitorId;
  final ShellSurfaceEnvironment environment;
  final ShellServices services;

  @override
  ConsumerState<TopBarSurface> createState() => _TopBarSurfaceState();
}

class _TopBarSurfaceState extends ConsumerState<TopBarSurface> {
  final GlobalKey _clockKey = GlobalKey();
  final GlobalKey _mediaKey = GlobalKey();
  final GlobalKey _batteryKey = GlobalKey();
  final GlobalKey _notificationsKey = GlobalKey();
  final GlobalKey _settingsKey = GlobalKey();
  final GlobalKey _islandKey = GlobalKey();

  PanelEdge get _side {
    final side = widget.environment.settings.layout.systemBarSide;
    return side == null || side == PanelEdge.hidden ? PanelEdge.top : side;
  }

  bool get _horizontal => _side.isHorizontal;

  @override
  Widget build(BuildContext context) {
    final stored = ref.watch(topBarSettingsProvider).value;
    final settings = stored ?? TopBarSettings.defaults;
    final thickness = widget.environment.settings.layout.systemBarThickness;
    final islandAvailable =
        _side == PanelEdge.top && settings.islandEnabled && stored != null;
    final bodyHeight = math.max(
      26.0,
      thickness - (settings.appearance == TopBarAppearance.attached ? 0 : 8),
    );

    final clockPlacement = settings.resolveSlot(
      settings.clockPlacement,
      islandAvailable: islandAvailable,
    );
    final mediaPlacement = settings.resolveSlot(
      settings.mediaPlacement,
      islandAvailable: islandAvailable,
    );
    final notificationPlacement = settings.resolveSlot(
      settings.notificationPlacement,
      islandAvailable: islandAvailable,
    );

    final clock = TopBarClock(
      key: _clockKey,
      services: widget.services,
      showDate: _horizontal && settings.clockShowsDate,
      compact: !_horizontal,
      onTap: _openCalendar,
    );
    final media = TopBarMediaChip(
      key: _mediaKey,
      services: widget.services,
      compact: !_horizontal,
      onTap: _openMedia,
    );
    final battery = TopBarBattery(
      key: _batteryKey,
      services: widget.services,
      showPercent: settings.showBatteryPercent,
      onTap: _openBattery,
    );
    final notifications = TopBarNotifications(
      key: _notificationsKey,
      showBadge: settings.notificationBadge,
      onTap: _openNotifications,
    );
    final settingsButton = TopBarSettingsButton(
      key: _settingsKey,
      onTap: _openSettings,
    );

    final leading = <Widget>[
      if (_horizontal)
        TopBarWorkspaces(
          monitorId: widget.monitorId,
          services: widget.services,
          horizontal: _horizontal,
        ),
      if (_horizontal && settings.showWindowTitle)
        TopBarWindowTitle(
          monitorId: widget.monitorId,
          services: widget.services,
        ),
      if (clockPlacement == TopBarSlot.leading) clock,
    ];
    final trailing = <Widget>[
      if (mediaPlacement == TopBarSlot.trailing) media,
      if (settings.showTray)
        TopBarTray(services: widget.services, horizontal: _horizontal),
      if (settings.showBattery) battery,
      if (notificationPlacement == TopBarSlot.trailing) notifications,
      if (settings.showSettingsButton) settingsButton,
      if (clockPlacement == TopBarSlot.trailing) clock,
    ];

    final activity = resolveIslandActivity(
      mediaEnabled: settings.activityMedia,
      mediaAvailable: ref.watch(
        widget.services.media.select(
          (media) => media.value?.available ?? false,
        ),
      ),
      chargingEnabled: settings.activityCharging,
      charging: ref.watch(
        widget.services.battery.select((battery) => battery.charging),
      ),
      notificationsEnabled: settings.activityNotifications,
      notification: ref.watch(
        desktopNotificationsProvider.select(
          (state) => state.bannerNotifications.isNotEmpty,
        ),
      ),
    );

    ref.listen(desktopNotificationsProvider.select((s) => s.bannerQueue), (
      previous,
      next,
    ) {
      if (!settings.activityNotifications) return;
      final controller = ref.read(desktopNotificationsProvider.notifier);
      for (final id in next) {
        controller.hideBanner(id);
      }
    });

    final now = ref.watch(widget.services.clock).value ?? DateTime.now();
    final strings = widget.services.strings(context);
    final playback = ref.watch(widget.services.media).value;
    final batteryStatus = ref.watch(widget.services.battery);
    final latestBanner = ref.watch(
      desktopNotificationsProvider.select((state) => state.bannerNotification),
    );
    final island = islandAvailable
        ? Padding(
            key: const ValueKey('island-slot'),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: KeyedSubtree(
              key: _islandKey,
              child: TopBarIsland(
                activity: activity,
                bodyHeight: bodyHeight,
                clockInIsland: clockPlacement == TopBarSlot.island,
                showDate: settings.clockShowsDate,
                timeText: strings.time(now),
                dateText: strings.shortDate(now),
                mediaTitle: playback?.title.isNotEmpty == true
                    ? playback!.title
                    : (playback?.identity ?? ''),
                batteryText: batteryStatus.capacity == null
                    ? ''
                    : '${batteryStatus.capacity}%',
                notificationText: latestBanner?.summary ?? '',
                style: settings.islandStyle,
                hoverPeek: settings.islandHoverPeek,
                expanded: false,
                onOpen: _openIsland,
              ),
            ),
          )
        : null;
    final center =
        island ??
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: clockPlacement == TopBarSlot.island ? clock : const SizedBox(),
        );

    final content = _BarContent(
      horizontal: _horizontal,
      leading: leading,
      center: center,
      trailing: trailing,
    );

    final chrome = _chrome(
      context: context,
      settings: settings,
      bodyHeight: bodyHeight,
      horizontal: _horizontal,
      child: content,
      segmented: settings.appearance == TopBarAppearance.segmented
          ? (leading: leading, center: center, trailing: trailing)
          : null,
    );

    final bar = SizedBox(
      width: _horizontal ? double.infinity : bodyHeight,
      height: _horizontal ? bodyHeight : double.infinity,
      child: ShellInputRegion(
        debugLabel: 'denial_topbar.bar',
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onSecondaryTap: _openSettings,
          child: chrome,
        ),
      ),
    );

    return Align(
      alignment: switch (_side) {
        PanelEdge.bottom => Alignment.bottomCenter,
        PanelEdge.left => Alignment.centerLeft,
        PanelEdge.right => Alignment.centerRight,
        _ => Alignment.topCenter,
      },
      child: Padding(
        padding: switch (settings.appearance) {
          TopBarAppearance.attached => EdgeInsets.zero,
          TopBarAppearance.floating => const EdgeInsets.all(4),
          TopBarAppearance.segmented => const EdgeInsets.all(4),
        },
        child: bar,
      ),
    );
  }

  Widget _chrome({
    required BuildContext context,
    required TopBarSettings settings,
    required double bodyHeight,
    required bool horizontal,
    required Widget child,
    required ({List<Widget> leading, Widget center, List<Widget> trailing})?
    segmented,
  }) {
    final theme = context.shellTheme;
    final attached = settings.appearance == TopBarAppearance.attached;
    final radius = attached ? BorderRadius.zero : theme.borderRadius(16);
    final fill = settings.showBackground
        ? theme.colors.panelBackground.withValues(alpha: 0.18)
        : Colors.transparent;
    Widget decorate(Widget value, BorderRadius shape, {bool edge = false}) {
      final content = Container(
        height: horizontal ? bodyHeight : null,
        padding: EdgeInsets.symmetric(horizontal: attached ? 12 : 8),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: shape,
          border: settings.hairline
              ? Border.all(color: theme.colors.hairline, width: 0.8)
              : null,
        ),
        child: value,
      );
      if (!settings.showBackground) return content;
      return ShellBackdropBlur(
        borderRadius: shape,
        blendMode: BlendMode.srcOver,
        child: content,
      );
    }

    if (segmented != null) {
      Widget segment(List<Widget> children) => decorate(
        Row(mainAxisSize: MainAxisSize.min, children: children),
        theme.borderRadius(12),
      );
      return Row(
        children: <Widget>[
          if (segmented.leading.isNotEmpty) segment(segmented.leading),
          const Spacer(),
          segment(<Widget>[segmented.center]),
          const Spacer(),
          if (segmented.trailing.isNotEmpty) segment(segmented.trailing),
        ],
      );
    }
    return decorate(child, radius);
  }

  void _openPanel(
    String panelId,
    GlobalKey anchor,
    Widget Function(BuildContext context, VoidCallback close) builder, {
    double width = 340,
  }) {
    showTopBarPanel(
      ref: ref,
      panelId: panelId,
      anchor: anchor,
      side: _side,
      width: width,
      builder: builder,
    );
  }

  void _openCalendar() => _openPanel(
    'clock',
    _clockKey,
    (_, _) => const TopBarCalendarPanel(),
    width: 300,
  );

  void _openMedia() => _openPanel(
    'media',
    _mediaKey,
    (_, _) => TopBarMediaPanel(services: widget.services),
    width: 360,
  );

  void _openBattery() => _openPanel(
    'battery',
    _batteryKey,
    (_, _) => TopBarBatteryPanel(services: widget.services),
    width: 300,
  );

  void _openNotifications() => _openPanel(
    'notifications',
    _notificationsKey,
    (_, _) => const TopBarNotificationsPanel(),
    width: 380,
  );

  void _openSettings() {
    showTopBarPanel(
      ref: ref,
      panelId: 'settings',
      anchor: _settingsKey,
      side: _side,
      settings: true,
      width: 380,
      builder: (_, close) => TopBarSettingsPanel(onClose: close),
    );
  }

  void _openIsland() {
    final settings =
        ref.read(topBarSettingsProvider).value ?? TopBarSettings.defaults;
    showTopBarPanel(
      ref: ref,
      panelId: 'island',
      anchor: _islandKey,
      side: _side,
      width: 380,
      builder: (_, close) => TopBarIslandExpanded(
        services: widget.services,
        monitorId: widget.monitorId,
        autoCollapseSeconds: settings.islandAutoCollapseSeconds,
        onClose: close,
      ),
    );
  }
}

class _BarContent extends StatelessWidget {
  const _BarContent({
    required this.horizontal,
    required this.leading,
    required this.center,
    required this.trailing,
  });

  final bool horizontal;
  final List<Widget> leading;
  final Widget center;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    Widget cluster(List<Widget> children) => Flex(
      direction: horizontal ? Axis.horizontal : Axis.vertical,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: children,
    );
    if (horizontal) {
      return Row(
        children: <Widget>[
          if (leading.isNotEmpty) cluster(leading),
          const Spacer(),
          center,
          const Spacer(),
          if (trailing.isNotEmpty) cluster(trailing),
        ],
      );
    }
    return Column(
      children: <Widget>[
        if (leading.isNotEmpty) cluster(leading),
        const Spacer(),
        center,
        const Spacer(),
        if (trailing.isNotEmpty) cluster(trailing),
      ],
    );
  }
}

/// Expanded island card. It lives in a managed popup so an outside click and
/// Escape close it without a second overlay.
class TopBarIslandExpanded extends ConsumerStatefulWidget {
  const TopBarIslandExpanded({
    required this.services,
    required this.monitorId,
    required this.autoCollapseSeconds,
    required this.onClose,
    super.key,
  });

  final ShellServices services;
  final int monitorId;
  final int autoCollapseSeconds;
  final VoidCallback onClose;

  @override
  ConsumerState<TopBarIslandExpanded> createState() =>
      _TopBarIslandExpandedState();
}

class _TopBarIslandExpandedState extends ConsumerState<TopBarIslandExpanded> {
  Timer? _collapse;
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    _arm();
  }

  @override
  void dispose() {
    _collapse?.cancel();
    super.dispose();
  }

  void _arm() {
    _collapse?.cancel();
    _collapse = Timer(Duration(seconds: widget.autoCollapseSeconds), () {
      if (mounted && !_hovered) widget.onClose();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final playback = ref.watch(widget.services.media).value;
    final battery = ref.watch(widget.services.battery);
    final now = ref.watch(widget.services.clock).value ?? DateTime.now();
    final strings = widget.services.strings(context);
    final activity = resolveIslandActivity(
      mediaEnabled: true,
      mediaAvailable: playback?.available ?? false,
      chargingEnabled: true,
      charging: battery.charging,
      notificationsEnabled: false,
      notification: false,
    );
    return MouseRegion(
      onEnter: (_) {
        _hovered = true;
        _collapse?.cancel();
      },
      onExit: (_) {
        _hovered = false;
        _arm();
      },
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Text(
                  strings.time(now),
                  style: theme.text.statusClock.copyWith(
                    color: theme.colors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  strings.shortDate(now),
                  style: theme.text.systemBarCaption.copyWith(
                    color: theme.colors.textSecondary,
                  ),
                ),
                const Spacer(),
                Icon(Icons.close, size: 15, color: theme.colors.textTertiary),
              ],
            ),
            const SizedBox(height: 14),
            if (activity == IslandActivity.media && playback != null)
              _IslandMedia(playback: playback, services: widget.services)
            else if (activity == IslandActivity.charging)
              Row(
                children: <Widget>[
                  Icon(Icons.bolt, size: 18, color: theme.accent),
                  const SizedBox(width: 6),
                  Text(
                    battery.capacity == null
                        ? 'Charging'
                        : 'Charging · ${battery.capacity}%',
                    style: theme.text.systemBarValue.copyWith(
                      color: theme.colors.textPrimary,
                    ),
                  ),
                ],
              )
            else
              Text(
                'No activity',
                style: theme.text.systemBarValue.copyWith(
                  color: theme.colors.textSecondary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _IslandMedia extends ConsumerWidget {
  const _IslandMedia({required this.playback, required this.services});

  final MprisPlaybackState playback;
  final ShellServices services;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.shellTheme;
    final commands = ref.read(services.mediaCommands);
    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                playback.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.text.systemBarValue.copyWith(
                  color: theme.colors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                playback.artistLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.text.systemBarCaption.copyWith(
                  color: theme.colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          onPressed: playback.canGoPrevious ? commands.previous : null,
          icon: const Icon(Icons.skip_previous),
          iconSize: 18,
          color: theme.colors.textPrimary,
          disabledColor: theme.colors.textTertiary.withValues(alpha: 0.5),
        ),
        IconButton(
          onPressed: playback.playing ? commands.playPause : null,
          icon: Icon(playback.playing ? Icons.pause : Icons.play_arrow),
          iconSize: 20,
          color: theme.colors.textPrimary,
          disabledColor: theme.colors.textTertiary.withValues(alpha: 0.5),
        ),
        IconButton(
          onPressed: playback.canGoNext ? commands.next : null,
          icon: const Icon(Icons.skip_next),
          iconSize: 18,
          color: theme.colors.textPrimary,
          disabledColor: theme.colors.textTertiary.withValues(alpha: 0.5),
        ),
      ],
    );
  }
}
