import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show PointerDeviceKind;

import 'package:denial_flutter_sdk/input.dart';
import 'package:denial_flutter_sdk/localization.dart';
import 'package:denial_flutter_sdk/models.dart';
import 'package:denial_flutter_sdk/services.dart';
import 'package:denial_flutter_sdk/state.dart';
import 'package:denial_flutter_sdk/surfaces.dart';
import 'package:denial_flutter_sdk/system_services.dart' show WifiNetwork;
import 'package:denial_flutter_sdk/theme.dart';
import 'package:denial_flutter_sdk/wallpaper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_menu.dart';
import 'app_menus.dart';
import 'bar_button.dart';
import 'bar_ground.dart';
import 'debug_remote.dart';
import 'bar_icons.dart';
import 'bar_menu.dart';
import 'bar_panel.dart';
import 'bar_preferences.dart';
import 'bar_settings.dart';
import 'bar_status.dart';
import 'bar_tokens.dart';
import 'clock_label.dart';
import 'island/island.dart';
import 'l10n.dart';
import 'panels/about_dialog.dart';
import 'panels/bar_settings_panel.dart';
import 'panels/control_center.dart';
import 'panels/dialogs.dart';
import 'panels/notification_center.dart';
import 'panels/popovers.dart';
import 'panels/wifi_join_dialog.dart';
import 'system_menu.dart';
import 'workspaces.dart';

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
  final GlobalKey _clipboardKey = GlobalKey();
  final GlobalKey _bluetoothKey = GlobalKey();
  final GlobalKey _batteryKey = GlobalKey();
  final GlobalKey _notificationsKey = GlobalKey();
  final GlobalKey _controlCenterKey = GlobalKey();
  final GlobalKey _settingsKey = GlobalKey();

  final GlobalKey _appKey = GlobalKey();

  String? get _openPanelId => barOpenPanel.value;

  void _panelChanged() {
    if (!mounted) return;
    setState(() {});
    if (barOpenPanel.value == null) _hover();
  }

  @override
  void initState() {
    super.initState();
    barOpenPanel.addListener(_panelChanged);
    startDebugRemote();
    debugCommand.addListener(_debug);
  }

  final ValueNotifier<double> _islandReserved = ValueNotifier<double>(58);

  bool _hidden = false;
  bool _overBar = false;
  bool _overIsland = false;
  bool _overSensor = false;
  Timer? _hideTimer;
  Timer? _revealTimer;

  bool get _autoHide =>
      (ref.read(barSettingsProvider).value ?? BarSettings.defaults).autoHide;

  void _armHide([Duration after = const Duration(milliseconds: 700)]) {
    _hideTimer?.cancel();
    if (!_autoHide || _hidden) return;
    _hideTimer = Timer(after, () {
      if (!mounted || !_autoHide) return;
      if (_overBar || _overIsland || barOpenPanel.value != null) return;
      setState(() => _hidden = true);
    });
  }

  void _reveal({bool touch = false}) {
    _revealTimer?.cancel();
    if (!_hidden) return;
    final settings =
        ref.read(barSettingsProvider).value ?? BarSettings.defaults;
    void show() {
      if (!mounted) return;
      setState(() => _hidden = false);
      if (touch) _armHide(const Duration(seconds: 4));
    }

    if (touch || settings.autoHideDelayMs <= 0) {
      show();
    } else {
      _revealTimer = Timer(
        Duration(milliseconds: settings.autoHideDelayMs),
        show,
      );
    }
  }

  void _hover() {
    if (_overBar || _overIsland) {
      _hideTimer?.cancel();
    } else if (_overSensor) {
      _reveal();
    } else {
      _revealTimer?.cancel();
      _armHide();
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _revealTimer?.cancel();
    barOpenPanel.removeListener(_panelChanged);
    debugCommand.removeListener(_debug);
    _islandReserved.dispose();
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
  }

  /// Shows the "Join “SSID”" dialog for a secured network with no saved
  /// profile.
  ///
  /// The reference closes the Wi-Fi list before opening it, because the dialog
  /// is a system modal that has to own the keyboard; the list would otherwise
  /// keep focus. `showBarDialog` puts the card on its own surface for the same
  /// reason.
  void _openWifiJoin(WifiNetwork network) {
    showBarDialog(
      ref: ref,
      width: WifiJoinDialog.width,
      builder: (_, close) => WifiJoinDialog(network: network, onClose: close),
    );
  }

  void _openBarSettings({int page = 0}) {
    showBarDialog(
      ref: ref,
      width: barSettingsWidth,
      keyName: 'denial_topbar.settings',
      builder: (context, close) => BarSettingsPanel(
        services: _services,
        initialPage: page,
        onClose: close,
        maxHeight: MediaQuery.sizeOf(context).height - 96,
      ),
    );
  }

  BarStatusCluster? _status;
  VoidCallback? _clockTap;

  void _debug() {
    final words = debugWords();
    final status = _status;
    if (words.isEmpty || status == null || !mounted) return;
    final number = words.length > 1 ? int.tryParse(words[1]) ?? 0 : 0;
    switch (words.first) {
      case 'close':
        closeBarPanel();
      case 'cc':
        status.onControlCenter();
      case 'clock':
        _clockTap?.call();
      case 'wifi':
        status.onWifi();
      case 'bluetooth':
        status.onBluetooth();
      case 'volume':
        status.onVolume();
      case 'battery':
        status.onBattery();
      case 'clipboard':
        status.onClipboard();
      case 'system':
        _openSystemMenu();
      case 'about':
        _openAbout();
      case 'settings':
        _openBarSettings(page: number);
    }
  }

  void _openAbout() {
    showBarDialog(
      ref: ref,
      width: AboutSystemDialog.width,
      builder: (context, close) => AboutSystemDialog(
        mark: _DistroGlyph(
          ink: context.shellTheme.colors.textPrimary,
          size: 64,
        ),
        onClose: close,
      ),
    );
  }

  void _openForceQuit() {
    showBarDialog(
      ref: ref,
      width: ForceQuitDialog.width,
      builder: (context, close) =>
          ForceQuitDialog(services: _services, onClose: close),
    );
  }

  void _confirmPower(SessionPowerAction action) {
    final (title, label) = switch (action) {
      SessionPowerAction.reboot => (
        'Are you sure you want to restart now?',
        'Restart',
      ),
      SessionPowerAction.logout => (
        'Are you sure you want to log out now?',
        'Log Out',
      ),
      _ => ('Are you sure you want to shut down now?', 'Shut Down'),
    };
    final power = ref.read(sessionPowerProvider.notifier);
    showBarDialog(
      ref: ref,
      width: ConfirmDialog.width,
      builder: (context, close) => ConfirmDialog(
        mark: _DistroGlyph(
          ink: context.shellTheme.colors.textPrimary,
          size: 52,
        ),
        title: context.tr(title),
        detail: context.tr('Open windows will be closed.'),
        action: context.tr(label),
        onClose: close,
        onConfirm: () async {
          await power.request(action);
          await power.confirm();
        },
      ),
    );
  }

  void _openSystemMenu() {
    final window = ref.read(shellControllerProvider).foregroundWindow;
    final frontName = window == null
        ? null
        : _displayAppName(context, window, watch: false);
    showBarMenu(
      ref: ref,
      panelId: 'system',
      anchor: _systemKey,
      vertical: !_horizontal,
      fromRight: _side == PanelEdge.right,
      entries: (context) => systemMenuEntries(
        context,
        ref,
        services: _services,
        frontAppName: frontName,
        onAbout: _openAbout,
        onBarSettings: _openBarSettings,
        onForceQuit: _openForceQuit,
        onForceQuitFront: window == null
            ? null
            : () => closeApplication(ref, window.appId),
        onConfirm: _confirmPower,
      ),
    );
  }

  Widget _controlCenterBody(VoidCallback close) {
    return ControlCenterPanel(
      onClose: close,
      services: _services,
      output: widget.environment.output,
      onSettings: () {
        close();
        _services.openPowerSettings();
      },
      onJoinNetwork: (network) {
        close();
        _openWifiJoin(network);
      },
    );
  }

  void _openNotificationCenter(String id, {required bool merged}) {
    showNotificationCenter(
      ref: ref,
      services: _services,
      side: _side,
      barHeight: _bodyHeight,
      panelId: id,
      notifications: merged || id == 'notifications',
      widgets: id == 'clock',
    );
  }

  void _openSettingsApp(VoidCallback close) {
    close();
    _services.openPowerSettings();
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
    final workspacePlacement = settings.workspacePlacement;
    final islandAvailable = _side == PanelEdge.top && settings.islandEnabled;
    final showWorkspaces =
        workspacePlacement != BarWorkspacePlacement.hidden &&
        (workspacePlacement != BarWorkspacePlacement.island ||
            !islandAvailable);

    final workspace = BarWorkspaces(
      services: _services,
      monitorId: widget.monitorId,
      ink: ink,
      settings: settings,
      vertical: !_horizontal,
      side: _side,
      barHeight: bodyHeight,
    );
    final workspaceStatus = ref.watch(_services.workspace(widget.monitorId));
    final workspaceEnabled = ref.watch(_services.workspacesEnabled);
    final islandWorkspaceWidth = workspaceEnabled && workspaceStatus.count > 0
        ? workspacesExtent(workspaceStatus.count, settings.workspaceStyle) + 4.0
        : 0.0;

    final systemMenu = settings.showSystemMenu
        ? BarSystemMenu(
            key: _systemKey,
            glyph: _DistroGlyph(ink: ink),
            open: _openPanelId == 'system',
            ink: ink,
            onToggle: _openSystemMenu,
          )
        : null;

    final appMenu = settings.showAppMenu
        ? _appMenu(context, ink, settings)
        : null;

    final clock = BarClock(
      key: _clockKey,
      time: strings.time(now),
      date: clockDateLabel(
        weekday: settings.clockWeekday
            ? localizedWeekday(context.l10n, now.weekday)
            : '',
        month: localizedMonth(context.l10n, now.month),
        day: now.day,
        monthNumber: now.month,
      ).trim(),
      showDate: settings.showClockDate,
      vertical: !_horizontal,
      crossExtent: bodyHeight,
      ink: ink,
      open: _openPanelId == 'clock',
      onTap: () => _openNotificationCenter(
        'clock',
        merged: settings.mergedNotificationCenter,
      ),
    );

    BarButton.tips = settings.tooltips && _horizontal;
    _clockTap = clock.onTap;
    final status = BarStatusCluster(
      services: _services,
      settings: settings,
      openPanel: _openPanelId,
      ink: ink,
      horizontal: _horizontal,
      crossExtent: bodyHeight,
      wifiKey: _wifiKey,
      volumeKey: _volumeKey,
      batteryKey: _batteryKey,
      bluetoothKey: _bluetoothKey,
      notificationsKey: _notificationsKey,
      controlCenterKey: _controlCenterKey,
      settingsKey: _settingsKey,
      onWifi: () => _openPanel(
        'wifi',
        _wifiKey,
        (_, close) => WifiPopover(
          onSettings: () => _openSettingsApp(close),
          onJoin: (network) {
            close();
            _openWifiJoin(network);
          },
        ),
        width: popoverWidth,
        placement: BarPanelAnchor.centred,
      ),
      onBluetooth: () => _openPanel(
        'bluetooth',
        _bluetoothKey,
        (_, close) =>
            BluetoothPopover(onSettings: () => _openSettingsApp(close)),
        width: popoverWidth,
        placement: BarPanelAnchor.centred,
      ),
      onVolume: () => _openPanel(
        'volume',
        _volumeKey,
        (_, close) => SoundPopover(
          services: _services,
          onSettings: () => _openSettingsApp(close),
        ),
        width: popoverWidth,
        placement: BarPanelAnchor.centred,
      ),
      onBattery: () => _openPanel(
        'battery',
        _batteryKey,
        (_, close) => BatteryPopover(
          services: _services,
          onSettings: () => _openSettingsApp(close),
        ),
        width: popoverWidth,
        placement: BarPanelAnchor.centred,
      ),
      onSearch: _services.toggleLauncher,
      clipboardKey: _clipboardKey,
      onClipboard: () => _openPanel(
        'clipboard',
        _clipboardKey,
        (_, close) => ClipboardPopover(onClose: close),
        width: popoverWidth,
        placement: BarPanelAnchor.centred,
      ),
      onNotifications: () =>
          _openNotificationCenter('notifications', merged: false),
      onControlCenter: () => _openPanel(
        'controlcenter',
        _controlCenterKey,
        (_, close) => _controlCenterBody(close),
        width: controlCenterWidth,
        placement: BarPanelAnchor.trailing,
      ),
      onSettings: _openBarSettings,
    );

    // macOS measures 31 pt on a machine whose bar is taller than 24; on a
    // 24 pt strip the capsule takes the strip's own height, capped so the
    // pill never fills it edge to edge.
    final islandHeight = math.max(
      BarTokens.islandMinHeight,
      math.min(BarTokens.islandHeight, bodyHeight - 5),
    );

    _status = status;
    final island = islandAvailable
        ? Island(
            services: _services,
            monitorId: widget.monitorId,
            settings: settings,
            height: islandHeight,
            reserved: _islandReserved,
            timeLabel: strings.time(now),
            dateLabel: clock.date,
            onControlCenter: status.onControlCenter,
            onNotifications: clock.onTap,
            workspace: workspacePlacement == BarWorkspacePlacement.island
                ? BarWorkspaces(
                    services: _services,
                    monitorId: widget.monitorId,
                    ink: const Color(0xffffffff),
                    settings: settings.copyWith(workspacePreview: false),
                    barHeight: bodyHeight,
                  )
                : null,
            workspaceWidth: workspacePlacement == BarWorkspacePlacement.island
                ? islandWorkspaceWidth
                : 0.0,
          )
        : null;

    final leading = <Widget>[
      ?systemMenu,
      if (settings.workspacePlacement == BarWorkspacePlacement.leading &&
          showWorkspaces) ...<Widget>[
        const SizedBox.square(dimension: BarTokens.clusterGap),
        workspace,
      ],
      ?appMenu,
    ];
    final trailing = <Widget>[
      if (settings.workspacePlacement == BarWorkspacePlacement.trailing &&
          showWorkspaces) ...<Widget>[
        workspace,
        const SizedBox.square(dimension: BarTokens.statusSpacing),
      ],
      status,
      const SizedBox.square(dimension: BarTokens.statusSpacing),
      clock,
    ];

    final content = _BarRow(
      horizontal: _horizontal,
      leading: leading,
      centre: island == null
          ? null
          : ValueListenableBuilder<double>(
              valueListenable: _islandReserved,
              builder: (context, width, _) => AnimatedContainer(
                duration: const Duration(milliseconds: 420),
                curve: BarTokens.spring,
                width: width,
              ),
            ),
      trailing: trailing,
      bodyHeight: bodyHeight,
    );

    final radius = attached
        ? BorderRadius.zero
        : BorderRadius.circular(BarTokens.floatingRadius);
    // shell27: `leftRow.x: 8`, `rightRow.rightMargin: 6`.
    final padding = !_horizontal
        ? const EdgeInsets.symmetric(vertical: BarTokens.insetLeft)
        : attached
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
      child: MouseRegion(
        onEnter: (_) {
          _overBar = true;
          _hover();
        },
        onExit: (_) {
          _overBar = false;
          _hover();
        },
        child: Listener(
          onPointerDown: (event) {
            if (event.kind != PointerDeviceKind.mouse) {
              _armHide(const Duration(seconds: 4));
            }
          },
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onSecondaryTapUp: (details) => showBarMenu(
              ref: ref,
              panelId: 'context',
              at: details.globalPosition,
              entries: (context) => <BarMenuEntry>[
                BarMenuItem(
                  label: context.tr('Menu Bar Settings…'),
                  onSelected: _openBarSettings,
                ),
              ],
            ),
            child: bar,
          ),
        ),
      ),
    );

    // shell27's `barFeather`: with no veil the type can land on a busy
    // wallpaper, so a short gradient sits under the strip.
    final feather = BarFeather(
      tint: BarGroundLayer.plateFor(wallpaper),
      height: bodyHeight,
      visible: settings.ground == BarGround.none && _horizontal,
    );

    final stripAlignment = switch (_side) {
      PanelEdge.bottom => Alignment.bottomCenter,
      PanelEdge.left => Alignment.centerLeft,
      PanelEdge.right => Alignment.centerRight,
      _ => Alignment.topCenter,
    };
    final strip = Align(
      alignment: stripAlignment,
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
    final body = Stack(
      children: <Widget>[
        Positioned.fill(child: strip),
        if (island != null)
          Positioned(
            left: 0,
            right: 0,
            top:
                (attached ? 0 : BarTokens.floatingMargin) +
                (bodyHeight - islandHeight) / 2,
            child: Align(
              alignment: Alignment.topCenter,
              child: MouseRegion(
                opaque: false,
                onEnter: (_) {
                  _overIsland = true;
                  _hover();
                },
                onExit: (_) {
                  _overIsland = false;
                  _hover();
                },
                child: island,
              ),
            ),
          ),
      ],
    );

    final hidden = settings.autoHide && _hidden;
    if (settings.autoHide && !_hidden && _hideTimer == null) _armHide();
    final away = thickness + barShadowExtent;
    final direction = switch (_side) {
      PanelEdge.bottom => const Offset(0, 1),
      PanelEdge.left => const Offset(-1, 0),
      PanelEdge.right => const Offset(1, 0),
      _ => const Offset(0, -1),
    };
    return Stack(
      children: <Widget>[
        Align(
          alignment: stripAlignment,
          child: IgnorePointer(
            ignoring: !hidden,
            child: ShellInputRegion(
              debugLabel: 'denial_topbar.reveal',
              active: hidden,
              child: MouseRegion(
                onEnter: (_) {
                  _overSensor = true;
                  _hover();
                },
                onExit: (_) {
                  _overSensor = false;
                  _hover();
                },
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (event) =>
                      _reveal(touch: event.kind != PointerDeviceKind.mouse),
                  child: SizedBox(
                    width: _horizontal ? double.infinity : thickness,
                    height: _horizontal ? thickness : double.infinity,
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(end: hidden ? 1 : 0),
            duration: const Duration(milliseconds: 340),
            curve: Curves.easeOutCubic,
            builder: (context, t, child) => Transform.translate(
              offset: direction * (away * t),
              child: Opacity(opacity: 1 - t * 0.6, child: child),
            ),
            child: body,
          ),
        ),
      ],
    );
  }

  /// The focused application's name in bold, and nothing after it: the
  /// compositor exposes no application menus, so the bar draws no titles it
  /// could not open.
  Widget _appMenu(BuildContext context, Color ink, BarSettings settings) {
    final window = ref.watch(shellControllerProvider).foregroundWindow;
    if (window == null) {
      return _horizontal
          ? BarTitle(label: 'Denial', ink: ink, bold: true)
          : const SizedBox.shrink();
    }
    final appName = _displayAppName(context, window);
    return KeyedSubtree(
      key: _appKey,
      child: BarTitle(
        label: appName,
        ink: ink,
        bold: true,
        icon: _horizontal
            ? null
            : _services.buildApplicationIcon(context, window.appId),
        open: _openPanelId == 'app',
        onTap: () => showBarMenu(
          ref: ref,
          panelId: 'app',
          anchor: _appKey,
          vertical: !_horizontal,
          fromRight: _side == PanelEdge.right,
          entries: (context) => appMenuEntries(
            context,
            ref,
            window: window,
            appName: appName,
            services: _services,
          ),
        ),
      ),
    );
  }

  /// The app's own name from the shell's catalog, falling back to the id's
  /// last segment the way revo-shell does.
  String _displayAppName(
    BuildContext context,
    DenialWindow window, {
    bool watch = true,
  }) {
    final appId = window.appId;
    if (appId.isEmpty) return 'Denial';
    final name =
        (watch
                ? ref.watch(_services.applications)
                : ref.read(_services.applications))
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
                // Without an explicit minimum the box passes the Expanded's
                // tight width through, the Row stretches to it, and the
                // alignment has nothing left to move.
                minWidth: 0,
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
                minWidth: 0,
                maxWidth: double.infinity,
                child: Row(mainAxisSize: MainAxisSize.min, children: trailing),
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
  const _DistroGlyph({
    required this.ink,
    this.size = BarTokens.systemMenuGlyph,
  });

  final Color ink;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/distro-fedora.png',
      width: size,
      height: size,
      color: ink,
      filterQuality: FilterQuality.high,
      package: 'denial_topbar',
      errorBuilder: (context, error, stack) =>
          BarGlyph(BarIcons.circleFill, size: size, color: ink),
    );
  }
}
