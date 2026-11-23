import 'dart:async';
import 'dart:math' as math;

import 'package:denial_flutter_sdk/input.dart';
import 'package:denial_flutter_sdk/localization.dart';
import 'package:denial_flutter_sdk/models.dart';
import 'package:denial_flutter_sdk/popups.dart';
import 'package:denial_flutter_sdk/services.dart';
import 'package:denial_flutter_sdk/state.dart';
import 'package:denial_flutter_sdk/surfaces.dart';
import 'package:denial_flutter_sdk/theme.dart';
import 'package:denial_flutter_sdk/wallpaper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_menu.dart';
import 'app_menus.dart';
import 'bar_ground.dart';
import 'bar_icons.dart';
import 'bar_panel.dart';
import 'bar_preferences.dart';
import 'bar_settings.dart';
import 'bar_status.dart';
import 'bar_tokens.dart';
import 'clock_label.dart';
import 'island.dart';
import 'panels/audio_panel.dart';
import 'panels/bar_settings_panel.dart';
import 'panels/notification_center_panel.dart';
import 'panels/control_center.dart';
import 'panels/media_card.dart';
import 'panels/network_panels.dart';
import 'panels/notifications_panel.dart';
import 'panels/panel_parts.dart';
import 'system_menu.dart';
import 'workspace_dots.dart';
import 'workspace_switcher.dart';

/// How much of the surface the floating capsule needs past the strip so its
/// shadow is not clipped.
const double barShadowExtent = BarTokens.shadowExtent;

/// The macOS 27 menu bar.
///
/// Ports NextKDE `BarWindow.qml`'s composition — system menu, app menu, status
/// cluster, clock — with revo-shell's Dynamic Island in the centre. The strip
/// itself keeps macOS's own treatment: no plate by default, type drawn
/// straight on the wallpaper with the ink chosen against it.
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
  final GlobalKey _systemKey = GlobalKey();
  final GlobalKey _clockKey = GlobalKey();
  final GlobalKey _wifiKey = GlobalKey();
  final GlobalKey _volumeKey = GlobalKey();
  final GlobalKey _batteryKey = GlobalKey();
  final GlobalKey _notificationsKey = GlobalKey();
  final GlobalKey _controlCenterKey = GlobalKey();
  final GlobalKey _settingsKey = GlobalKey();
  final GlobalKey _islandKey = GlobalKey();

  /// One anchor per application-menu title, so each dropdown hangs under its
  /// own title instead of the bar's left edge.
  final Map<AppMenuId, GlobalKey> _appMenuKeys = <AppMenuId, GlobalKey>{};

  String? _openPanelId;
  String _lastIslandKey = '';
  Timer? _islandCollapse;
  bool _islandHovered = false;
  bool _islandExpanded = false;

  /// The charger's last seen state, so the pill can flash on the change
  /// rather than on every frame the battery provider rebuilds.
  bool? _wasCharging;
  Timer? _chargeFlash;
  bool _charging = false;

  @override
  void dispose() {
    _islandCollapse?.cancel();
    _islandIntent?.cancel();
    _islandLeave?.cancel();
    _chargeFlash?.cancel();
    super.dispose();
  }

  PanelEdge get _side {
    final side = widget.environment.settings.layout.systemBarSide;
    return side == null || side == PanelEdge.hidden ? PanelEdge.top : side;
  }

  bool get _horizontal => _side.isHorizontal;

  /// The strip's height as laid out, so a panel hangs from its real bottom
  /// edge rather than the reference token.
  double get _bodyHeight {
    final settings =
        ref.read(barSettingsProvider).value ?? BarSettings.defaults;
    final thickness = widget.environment.settings.layout.systemBarThickness;
    return math.max(
      BarTokens.height,
      thickness -
          (settings.layout == BarLayout.attached
              ? 0
              : BarTokens.floatingMargin * 2),
    );
  }

  ShellServices get _services => widget.services;

  void _openPanel(
    String id,
    GlobalKey anchor,
    Widget Function(BuildContext context, VoidCallback close) builder, {
    double width = BarTokens.panelMaxWidth,
    PanelEdge? side,
    bool glass = true,
    BarPanelAnchor placement = BarPanelAnchor.dropdown,
    Color? fill,
    double? height,
  }) {
    showBarPanel(
      ref: ref,
      panelId: id,
      anchor: anchor,
      width: width,
      side: side ?? _side,
      glass: glass,
      placement: placement,
      fill: fill,
      barHeight: _bodyHeight,
      height: height,
      builder: builder,
    );
    // showBarPanel toggles; mirror the resulting state so the cell wash and
    // the island border agree with the popup list.
    final open = ref
        .read(shellPopupControllerProvider)
        .any((popup) => popup.keyName == barPanelKey && !popup.closing);
    setState(() => _openPanelId = open ? id : null);
  }

  void _openIsland() {
    final note = ref.read(
      desktopNotificationsProvider.select((state) => state.bannerNotification),
    );
    final mode = _currentIslandMode;
    if (mode == IslandMode.quiet && note == null) {
      _openPanel(
        'controlcenter',
        _islandKey,
        (_, _) => _controlCenterBody(),
        width: BarTokens.controlCenterWidth + BarTokens.controlCenterMargin * 2,
      );
      return;
    }
    _openPanel(
      'island',
      _islandKey,
      (_, close) => IslandPanel(
        mode: mode,
        services: _services,
        notification: note,
        onDismiss: close,
        chargePercent: ref.read(_services.battery).capacity,
      ),
      width: IslandExpandedBody.widthFor(mode),
      height: IslandExpandedBody.heightFor(mode),
      placement: BarPanelAnchor.island,
      // The card is the pill grown, so it keeps the pill's black.
      fill: const Color(BarTokens.islandFill),
    );
  }

  /// Opens the bar's settings sheet, from the system menu and View ▸ Menu Bar
  /// Settings…. It hangs off the system menu's anchor because the sheet has no
  /// cell of its own.
  void _openBarSettings() {
    _openPanel(
      'settings',
      _systemKey,
      (_, dismiss) => BarSettingsPanel(
        onClose: dismiss,
        width: BarTokens.panelMaxWidth,
        maxHeight: MediaQuery.sizeOf(context).height - 120,
      ),
      width: BarTokens.panelMaxWidth,
      placement: BarPanelAnchor.centred,
    );
  }

  Widget _controlCenterBody() {
    return ControlCenterPanel(
      services: _services,
      monitorId: widget.monitorId,
      output: widget.environment.output,
      onOpenSettings: () {
        _openPanel(
          'settings',
          _settingsKey,
          (_, dismiss) => BarSettingsPanel(
            onClose: dismiss,
            width: BarTokens.panelMaxWidth,
            maxHeight: MediaQuery.sizeOf(context).height - 120,
          ),
        );
      },
      onOpenNotifications: () {
        _openPanel(
          'notifications',
          _notificationsKey,
          (_, dismiss) => NotificationHistoryPanel(onClose: dismiss),
          width: PanelWidth.notifications,
          placement: BarPanelAnchor.trailing,
        );
      },
      onOpenIsland: _openIsland,
      onOpenDisplaySettings: () => _services.openPowerSettings(),
      onOpenNowPlaying: () => _openPanel(
        'nowplaying',
        _controlCenterKey,
        (_, close) => Padding(
          padding: const EdgeInsets.all(BarTokens.panelPadding),
          child: NowPlayingPanel(services: _services),
        ),
        width: BarTokens.panelMaxWidth,
        placement: BarPanelAnchor.trailing,
      ),
    );
  }

  /// The island's mode for this frame. `ref.watch` is only legal inside
  /// [build], so [build] resolves it once and the event handlers read the
  /// cached value.
  IslandMode _currentIslandMode = IslandMode.quiet;

  void _armIslandCollapse() {
    _islandCollapse?.cancel();
    if (!_islandExpanded) return;
    _islandCollapse = Timer(BarTokens.islandAutoCollapse, () {
      if (!mounted || _islandHovered) return;
      setState(() => _islandExpanded = false);
    });
  }

  /// meniscus's hover intent [S35]: the pointer must rest 180 ms before the
  /// island opens, so a cursor crossing the notch cannot flash it open, and
  /// leaving gives 120 ms of grace before it folds back.
  Timer? _islandIntent;
  Timer? _islandLeave;

  void _onIslandHover(bool hovered) {
    _islandHovered = hovered;
    if (hovered) {
      _islandLeave?.cancel();
      _islandCollapse?.cancel();
      final peek = ref.read(barSettingsProvider).value?.islandHoverPeek ?? true;
      if (!peek || _islandExpanded) return;
      _islandIntent?.cancel();
      _islandIntent = Timer(BarTokens.islandHoverIntent, () {
        if (!mounted || !_islandHovered) return;
        if (_currentIslandMode != IslandMode.quiet) {
          setState(() => _islandExpanded = true);
        }
      });
      return;
    }
    _islandIntent?.cancel();
    _islandLeave?.cancel();
    _islandLeave = Timer(BarTokens.islandLeaveGrace, () {
      if (mounted) _armIslandCollapse();
    });
  }

  /// Expands the pill when the track changes or a notice lands, matching
  /// revo-shell's `onTrackTitleChanged` and `Notifications.onNotify`.
  void _onIslandContentChanged(String key) {
    if (key == _lastIslandKey) return;
    _lastIslandKey = key;
    if (key.isEmpty) {
      // Playback stopped or the notice went away: fold back immediately.
      _islandCollapse?.cancel();
      if (_islandExpanded) setState(() => _islandExpanded = false);
      return;
    }
    setState(() => _islandExpanded = true);
    _armIslandCollapse();
  }

  /// Holds the charge face for a moment when the charger goes in or out.
  ///
  /// macOS shows the banner on every plug and unplug with no way to turn it
  /// off [S28], so this follows the edge rather than the level: the first
  /// frame only records the state, and a later change flashes. A build cannot
  /// call `setState`, so the flash is armed through a zero-delay timer.
  void _syncChargeFlash(BarSettings settings, bool charging) {
    final previous = _wasCharging;
    _wasCharging = charging;
    if (previous == null || previous == charging) return;
    if (!settings.activityCharging) return;
    _chargeFlash?.cancel();
    _chargeFlash = Timer(Duration.zero, () {
      if (!mounted) return;
      setState(() => _charging = true);
      _chargeFlash = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _charging = false);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings =
        ref.watch(barSettingsProvider).value ?? BarSettings.defaults;
    final thickness = widget.environment.settings.layout.systemBarThickness;
    final attached = settings.layout == BarLayout.attached;
    final bodyHeight = math.max(
      BarTokens.height,
      thickness - (attached ? 0 : BarTokens.floatingMargin * 2),
    );
    final wallpaper = ref.watch(wallpaperAccentProvider).color;
    final ink = BarGroundLayer.inkFor(wallpaper, settings);
    final now = ref.watch(_services.clock).value ?? DateTime.now();
    final strings = _services.strings(context);
    final playback = ref.watch(_services.media).value;
    final battery = ref.watch(_services.battery);
    final banner = ref.watch(
      desktopNotificationsProvider.select((state) => state.bannerNotification),
    );
    _syncChargeFlash(settings, battery.charging);
    final islandMode = _currentIslandMode = resolveIslandMode(
      mediaEnabled: settings.activityMedia,
      mediaPlaying: playback?.playing ?? false,
      notificationsEnabled: settings.activityNotifications,
      hasNotice: ref.watch(
        desktopNotificationsProvider.select(
          (state) => state.bannerNotifications.isNotEmpty,
        ),
      ),
      charging: _charging,
    );
    final islandKey = switch (islandMode) {
      IslandMode.media => 'media:${playback?.serviceName}:${playback?.title}',
      IslandMode.notice => 'notice:${banner?.id}',
      // The flash expands once per plug event and folds back when it ends.
      IslandMode.charging => 'charge',
      IslandMode.quiet => '',
    };
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _onIslandContentChanged(islandKey);
    });

    final workspacePlacement = settings.workspacePlacement;
    final islandAvailable = _side == PanelEdge.top && settings.islandEnabled;
    final showWorkspaces =
        workspacePlacement != BarWorkspacePlacement.hidden &&
        (workspacePlacement != BarWorkspacePlacement.island ||
            !islandAvailable);

    final workspace = WorkspaceSwitcher(
      services: _services,
      monitorId: widget.monitorId,
      ink: ink,
    );
    // The island sizes itself from the dots it hosts, so it needs their
    // width before layout. A dark pill always needs white dots.
    final workspaceStatus = ref.watch(_services.workspace(widget.monitorId));
    final workspaceEnabled = ref.watch(_services.workspacesEnabled);
    final islandWorkspaceWidth = workspaceEnabled && workspaceStatus.count > 0
        ? workspaceDotsWidth(workspaceStatus.count) + 4.0
        : 0.0;

    final systemMenu = settings.showSystemMenu
        ? BarSystemMenu(
            key: _systemKey,
            glyph: _DistroGlyph(ink: ink),
            open: _openPanelId == 'system',
            ink: ink,
            onToggle: () => _openPanel(
              'system',
              _systemKey,
              (_, close) => SystemMenuBody(
                services: _services,
                onClose: close,
                onBarSettings: _openBarSettings,
              ),
              width: BarTokens.menuWidth,
              glass: false,
            ),
          )
        : null;

    final appMenu = settings.showAppMenu
        ? _appMenu(context, ink, settings)
        : null;

    final clock = BarClock(
      key: _clockKey,
      time: strings.time(now),
      date: clockDateLabel(
        weekday: localizedWeekday(context.l10n, now.weekday),
        month: localizedMonth(context.l10n, now.month),
        day: now.day,
        monthNumber: now.month,
      ),
      showDate: settings.showClockDate && _horizontal,
      ink: ink,
      onTap: () => _openPanel(
        'clock',
        _clockKey,
        (_, close) => NotificationCenterPanel(onClose: close),
        width: PanelWidth.notifications,
        placement: BarPanelAnchor.clock,
      ),
    );

    final status = BarStatusCluster(
      services: _services,
      settings: settings,
      openPanel: _openPanelId,
      ink: ink,
      wifiKey: _wifiKey,
      volumeKey: _volumeKey,
      batteryKey: _batteryKey,
      notificationsKey: _notificationsKey,
      controlCenterKey: _controlCenterKey,
      settingsKey: _settingsKey,
      onWifi: () => _openPanel(
        'wifi',
        _wifiKey,
        (_, close) => _PopoverShell(
          child: WifiContent(
            onOpenSettings: () {
              close();
              _services.openPowerSettings();
            },
          ),
        ),
        width: PanelWidth.wifi,
        placement: BarPanelAnchor.centred,
      ),
      onVolume: () => _openPanel(
        'volume',
        _volumeKey,
        (_, close) => _PopoverShell(child: SoundPopover(services: _services)),
        width: PanelWidth.volume,
        placement: BarPanelAnchor.centred,
      ),
      onBattery: () => _openPanel(
        'battery',
        _batteryKey,
        (_, close) => _PopoverShell(
          child: _BatteryContent(services: _services),
        ),
        width: PanelWidth.wifi,
        placement: BarPanelAnchor.centred,
      ),
      onNotifications: () => _openPanel(
        'notifications',
        _notificationsKey,
        (_, close) => NotificationHistoryPanel(onClose: close),
        width: PanelWidth.notifications,
        placement: BarPanelAnchor.trailing,
      ),
      onControlCenter: () => _openPanel(
        'controlcenter',
        _controlCenterKey,
        (_, _) => _controlCenterBody(),
        width: BarTokens.controlCenterWidth,
        placement: BarPanelAnchor.trailing,
      ),
      onSettings: () => _openPanel(
        'settings',
        _settingsKey,
        (_, close) => BarSettingsPanel(
          onClose: close,
          width: BarTokens.panelMaxWidth,
          maxHeight: MediaQuery.sizeOf(context).height - 120,
        ),
        width: BarTokens.panelMaxWidth,
        placement: BarPanelAnchor.centred,
      ),
    );

    // macOS measures 31 pt on a machine whose bar is taller than 24; on a
    // 24 pt strip the capsule takes the strip's own height, capped so the
    // pill never fills it edge to edge.
    final islandHeight = math.max(
      BarTokens.islandMinHeight,
      math.min(BarTokens.islandHeight, bodyHeight - 4),
    );

    final island = islandAvailable
        ? TopBarIsland(
            key: _islandKey,
            mode: islandMode,
            showClock: settings.islandShowsClock,
            timeText: strings.time(now),
            dateText: settings.showClockDate
                ? clockDateLabel(
                    weekday: localizedWeekday(context.l10n, now.weekday),
                    month: localizedMonth(context.l10n, now.month),
                    day: now.day,
                    monthNumber: now.month,
                  )
                : '',
            mediaTitle: playback?.title ?? '',
            noticeSummary: banner?.summary ?? '',
            expanded: _islandExpanded,
            height: islandHeight,
            onOpen: _openIsland,
            onHover: _onIslandHover,
            artworkUrl: playback?.artUrl ?? '',
            chargePercent: battery.capacity,
            workspace: workspacePlacement == BarWorkspacePlacement.island
                ? WorkspaceSwitcher(
                    services: _services,
                    monitorId: widget.monitorId,
                    ink: const Color(0xffffffff),
                  )
                : null,
            workspaceWidth: workspacePlacement == BarWorkspacePlacement.island
                ? islandWorkspaceWidth
                : 0.0,
            onNoticeClose: banner == null
                ? null
                : () => ref
                      .read(desktopNotificationsProvider.notifier)
                      .hideBanner(banner.id),
          )
        : null;

    final leading = <Widget>[
      ?systemMenu,
      if (settings.workspacePlacement == BarWorkspacePlacement.leading &&
          showWorkspaces) ...<Widget>[
        const SizedBox(width: BarTokens.clusterGap),
        workspace,
      ],
      ?appMenu,
    ];
    final trailing = <Widget>[
      if (settings.workspacePlacement == BarWorkspacePlacement.trailing &&
          showWorkspaces) ...<Widget>[
        workspace,
        const SizedBox(width: BarTokens.statusSpacing),
      ],
      status,
      const SizedBox(width: BarTokens.statusSpacing),
      clock,
    ];

    final content = _BarRow(
      horizontal: _horizontal,
      leading: leading,
      centre: island,
      trailing: trailing,
      bodyHeight: bodyHeight,
    );

    final radius = attached
        ? BorderRadius.zero
        : BorderRadius.circular(BarTokens.floatingRadius);
    // shell27: `leftRow.x: 8`, `rightRow.rightMargin: 6`.
    final padding = attached
        ? const EdgeInsets.only(
            left: BarTokens.insetLeft,
            right: BarTokens.insetRight,
          )
        : const EdgeInsets.symmetric(horizontal: BarTokens.insetFloating);

    Widget bar = Padding(
      padding: padding,
      child: BarGroundLayer(
        settings: settings,
        borderRadius: radius,
        backdrop: wallpaper,
        child: content,
      ),
    );

    bar = ShellInputRegion(
      debugLabel: 'denial_topbar.bar',
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onSecondaryTap: () => _openPanel(
          'settings',
          _settingsKey,
          (_, close) => BarSettingsPanel(
            onClose: close,
            width: BarTokens.panelMaxWidth,
            maxHeight: MediaQuery.sizeOf(context).height - 120,
          ),
        ),
        child: bar,
      ),
    );

    // shell27's `barFeather`: with no veil the type can land on a busy
    // wallpaper, so a short gradient sits under the strip.
    final feather = BarFeather(
      tint: BarGroundLayer.plateFor(wallpaper),
      height: bodyHeight,
      visible: settings.ground == BarGround.none && _horizontal,
    );

    return Align(
      alignment: switch (_side) {
        PanelEdge.bottom => Alignment.bottomCenter,
        PanelEdge.left => Alignment.centerLeft,
        PanelEdge.right => Alignment.centerRight,
        _ => Alignment.topCenter,
      },
      child: Padding(
        padding: attached
            ? EdgeInsets.zero
            : const EdgeInsets.all(BarTokens.floatingMargin),
        child: KeyedSubtree(
          child: SizedBox(
            width: _horizontal ? double.infinity : bodyHeight,
            height: _horizontal ? bodyHeight : double.infinity,
            child: Stack(
              fit: StackFit.expand,
              // The feather fades past the strip into the shadow margin the
              // surface already reserves.
              clipBehavior: Clip.none,
              children: <Widget>[
                Positioned(left: 0, right: 0, top: 0, child: feather),
                bar,
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The title row: the focused app's name, then File / Edit / View / Window /
  /// Help, exactly the list shell27 ships.
  ///
  /// Wayland has no global-menu protocol, so each title opens the menu this
  /// shell can build itself; the app name opens the window list.
  Widget _appMenu(BuildContext context, Color ink, BarSettings settings) {
    final state = ref.watch(shellControllerProvider);
    final window = state.foregroundWindow;
    final appName = window == null
        ? 'Denial'
        : _displayAppName(context, window);
    final titles = appMenuTitles(appName);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (final title in titles)
          Builder(
            builder: (context) {
              final id = switch (title.id) {
                AppMenuId.app => 'app',
                AppMenuId.file => 'file',
                AppMenuId.edit => 'edit',
                AppMenuId.view => 'view',
                AppMenuId.window => 'window',
                AppMenuId.help => 'help',
              };
              final anchor = _appMenuKeys[title.id] ??= GlobalKey();
              return KeyedSubtree(
                key: anchor,
                child: BarTitle(
                  label: title.label,
                  ink: ink,
                  bold: title.bold,
                  open: _openPanelId == id,
                  onTap: () => _openPanel(
                    id,
                    anchor,
                    (_, close) => AppMenuBody(
                      id: title.id,
                      services: _services,
                      monitorId: widget.monitorId,
                      onClose: close,
                      onBarSettings: _openBarSettings,
                    ),
                    width: BarTokens.menuWidth,
                    glass: false,
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  /// The app's own name from the shell's catalog, falling back to the id's
  /// last segment the way revo-shell does.
  String _displayAppName(BuildContext context, DenialWindow window) {
    final appId = window.appId;
    if (appId.isEmpty) return 'Denial';
    final name = ref
        .watch(_services.applications)
        .firstWhere(
          (application) =>
              application.appId == appId ||
              application.windowAppIds.contains(appId),
          orElse: () => LaunchableApplication(
            id: appId,
            appId: appId,
            name: '',
            windowAppIds: const <String>[],
          ),
        );
    if (name.name.isNotEmpty) return name.name;
    final segment = appId.split('.').last;
    if (segment.isEmpty) return 'Denial';
    return segment[0].toUpperCase() + segment.substring(1);
  }
}

class _BarRow extends StatelessWidget {
  const _BarRow({
    required this.horizontal,
    required this.leading,
    required this.centre,
    required this.trailing,
    required this.bodyHeight,
  });

  final bool horizontal;
  final List<Widget> leading;
  final Widget? centre;
  final List<Widget> trailing;
  final double bodyHeight;

  @override
  Widget build(BuildContext context) {
    if (!horizontal) {
      return Column(
        children: <Widget>[
          ...leading,
          const Spacer(),
          ?centre,
          const Spacer(),
          ...trailing,
        ],
      );
    }
    // macOS centres the island on the camera housing, which is the middle of
    // the strip — not the middle of whatever space the two clusters leave.
    // Equal flex on both sides puts the centre at the strip's own midpoint,
    // and each cluster is clipped to its half so a long title list cannot run
    // under the island.
    return SizedBox(
      height: bodyHeight,
      child: Row(
        children: <Widget>[
          Expanded(
            child: ClipRect(
              child: OverflowBox(
                alignment: Alignment.centerLeft,
                maxWidth: double.infinity,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  // shell27's left row has no explicit spacing; the titles
                  // butt up against each other and each carries its own
                  // 20 pt of padding.
                  children: leading,
                ),
              ),
            ),
          ),
          ?centre,
          Expanded(
            child: ClipRect(
              child: OverflowBox(
                alignment: Alignment.centerRight,
                maxWidth: double.infinity,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: trailing,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The distribution mark in the system-menu slot.
///
/// macOS puts the Apple logo there; Denial puts the host's own mark, which is
/// the Fedora logo on this machine. `/etc/os-release` decides which asset to
/// use, so a differently-branded image is a one-line change.
class _DistroGlyph extends StatelessWidget {
  const _DistroGlyph({required this.ink});

  final Color ink;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/distro-fedora.png',
      width: BarTokens.systemMenuGlyph,
      height: BarTokens.systemMenuGlyph,
      color: ink,
      filterQuality: FilterQuality.high,
      package: 'denial_topbar',
      errorBuilder: (context, error, stack) => BarGlyph(
        BarIcons.circleFill,
        size: BarTokens.systemMenuGlyph,
        color: ink,
      ),
    );
  }
}


/// The padding shell27 gives every popover's content: loaded at `x: 11; y: 11`
/// inside a 320-wide shape, which leaves 11 pt on each side and 11 at the top.
class _PopoverShell extends StatelessWidget {
  const _PopoverShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        panelInset,
        panelInset,
        panelInset,
        panelInset - 2,
      ),
      child: child,
    );
  }
}

/// The battery popover: the charge, the charging state and the time left.
///
/// macOS keeps this card short — a large percentage, a state line, and one
/// button into the battery settings — so it follows that shape rather than the
/// Wi-Fi list's.
class _BatteryContent extends ConsumerWidget {
  const _BatteryContent({required this.services});

  final ShellServices services;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.shellTheme;
    final battery = ref.watch(services.battery);
    final strings = services.strings(context);
    final capacity = battery.capacity;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 2, 4, 0),
          child: Row(
            children: <Widget>[
              BarGlyph(
                batteryIconFor(battery),
                size: 18,
                color: theme.colors.textPrimary,
              ),
              const SizedBox(width: 8),
              Text(
                capacity == null ? strings.batteryTitle : '$capacity%',
                style: PanelText.title(theme),
              ),
              const Spacer(),
              if (battery.charging)
                Text(
                  'Charging',
                  style: PanelText.detail(theme),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Container(
            height: 6,
            decoration: BoxDecoration(
              color: theme.colors.textPrimary.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(3),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: ((capacity ?? 0) / 100).clamp(0.0, 1.0),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: battery.charging
                      ? theme.accent
                      : theme.colors.textPrimary,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        PanelDivider(color: theme.colors.hairlineSoft),
        PanelAction(
          label: 'Battery Settings…',
          onTap: () => services.openPowerSettings(),
        ),
      ],
    );
  }
}
