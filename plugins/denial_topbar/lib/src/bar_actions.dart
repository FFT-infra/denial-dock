part of 'bar_surface.dart';

/// What the bar's parts do when they are pressed: the panels, menus and
/// dialogs they open, and the anchors those hang from. A bar has them, and
/// so has a part drawn on its own in another plugin's host, so both open the
/// same things from wherever they stand.
mixin _BarActions<T extends ConsumerStatefulWidget> on ConsumerState<T> {
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
  final GlobalKey _trayKey = GlobalKey();

  ShellServices get _services;
  ShellSurfaceEnvironment get _environment;

  /// The screen edge of the host the parts are drawn in.
  PanelEdge get _side;

  /// How far that host reaches in from its edge; panels open beyond it.
  double get _bodyHeight;

  bool get _horizontal => _side.isHorizontal;

  String? get _openPanelId => kitOpenPanel.value;

  void _openPanel(
    String id,
    GlobalKey anchor,
    Widget Function(BuildContext context, VoidCallback close) builder, {
    double width = BarTokens.panelMaxWidth,
    PanelEdge? side,
    bool glass = true,
    bool frameless = false,
    double? gap,
    BarPanelAnchor placement = BarPanelAnchor.dropdown,
    Color? fill,
    double? radius,
  }) {
    showBarPanel(
      ref: ref,
      panelId: id,
      anchor: anchor,
      width: width,
      side: side ?? _side,
      glass: glass,
      frameless: frameless,
      gap: gap,
      placement: placement,
      fill: fill,
      radius: radius,
      barHeight: _bodyHeight,
      builder: builder,
    );
  }

  /// Shows the "Join “SSID”" dialog for a secured network with no saved
  /// profile.
  ///
  /// The reference closes the Wi-Fi list before opening it, because the dialog
  /// is a system modal that has to own the keyboard; the list would otherwise
  /// keep focus. `showKitDialog` puts the card on its own surface for the same
  /// reason.
  void _openWifiJoin(WifiNetwork network) {
    showKitDialog(
      ref: ref,
      width: WifiJoinDialog.width,
      builder: (_, close) => WifiJoinDialog(network: network, onClose: close),
    );
  }

  /// Opens the shell's settings window at one of the bar's pages.
  void _openBarSettings({int page = 0}) => showKitSettings(
    ref: ref,
    page: barSettingsPageIds[page.clamp(0, barSettingsPageIds.length - 1)],
  );

  void _openAbout() {
    showKitDialog(
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
    showKitDialog(
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
    showKitDialog(
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
        : _TopBarSurfaceState._appName(ref.read(_services.applications), window);
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
      output: _environment.output,
      onSettings: () {
        close();
        _services.openPowerSettings();
      },
      onJoinNetwork: (network) {
        close();
        _openWifiJoin(network);
      },
      onConfirmPower: _confirmPower,
    );
  }

  void _openNotificationCenter(String id, {required bool merged}) {
    showNotificationCenter(
      ref: ref,
      services: _services,
      side: _side,
      barHeight: _bodyHeight,
      panelId: id,
      // A look that hangs the centre under its item hangs it from this one,
      // away from the edge the host is on.
      anchor: id == 'notifications' ? _notificationsKey : _clockKey,
      notifications: merged || id == 'notifications',
      widgets: id == 'clock',
    );
  }

  void _openSettingsApp(VoidCallback close) {
    close();
    _services.openPowerSettings();
  }

  /// Whether [key]'s item sits in the half of the bar nearer the screen's
  /// trailing side, where a sheet may keep to the screen's edge.
  bool _nearTrailingSide(GlobalKey key) {
    if (!_horizontal) return true;
    final rect = kitSceneRect(key);
    final bar = context.findRenderObject();
    if (rect == null || bar is! RenderBox || !bar.hasSize) return true;
    return rect.center.dx >= kitScreenRect(bar).center.dx;
  }

  /// The clock in [ink], opening the notification column.
  BarClock _clockFor(
    BuildContext context, {
    required BarSettings settings,
    required Color ink,
    required DateTime now,
    required double crossExtent,
  }) => BarClock(
    key: _clockKey,
    time: _services.strings(context).time(now),
    date: _dateLabel(context, settings, now),
    showDate: settings.showClockDate,
    vertical: !_horizontal,
    crossExtent: crossExtent,
    ink: ink,
    open: _openPanelId == 'clock',
    onTap: () => _openClock(settings),
  );

  String _dateLabel(BuildContext context, BarSettings settings, DateTime now) =>
      clockDateLabel(
        weekday: settings.clockWeekday
            ? localizedWeekday(context.l10n, now.weekday)
            : '',
        month: localizedMonth(context.l10n, now.month),
        day: now.day,
        monthNumber: now.month,
      ).trim();

  void _openClock(BarSettings settings) => _openNotificationCenter(
    'clock',
    merged: settings.mergedNotificationCenter,
  );

  /// The status items in [ink], each opening its own panel.
  BarStatusCluster _statusFor({
    required BarSettings settings,
    required Color ink,
    required double crossExtent,
    required double spacing,
    bool? horizontal,
  }) {
    return BarStatusCluster(
      services: _services,
      settings: settings,
      openPanel: _openPanelId,
      ink: ink,
      horizontal: horizontal ?? _horizontal,
      crossExtent: crossExtent,
      spacing: spacing,
      wifiKey: _wifiKey,
      volumeKey: _volumeKey,
      batteryKey: _batteryKey,
      bluetoothKey: _bluetoothKey,
      notificationsKey: _notificationsKey,
      controlCenterKey: _controlCenterKey,
      settingsKey: _settingsKey,
      trayKey: _trayKey,
      onTraySettings: () => _openBarSettings(page: 4),
      onTray: () {
        final trayIds = ref.read(_services.trayItemIds);
        trayNames.resolve(trayIds);
        final count = partitionTrayIds(
          trayIds,
          settings: settings,
          resolveKey: (id) => trayNames.of(id).key,
          usageCounts: trayUsage.counts,
        ).folded.length;
        final capsule = settings.trayFoldInForce == BarTrayFold.floatingBar;
        final density = KitStyle.of(context).density.clamp(0.75, 1.35);
        final width = count == 0
            ? 196.0
            : capsule
            ? math.min(
                640.0,
                math.max(
                  52.0,
                  count * 28.0 +
                      math.max(0, count - 1) * 4.0 * density +
                      22.0 * density,
                ),
              )
            // Six to a row: thirty-pixel cells, the gaps between them and
            // the padding either side, all of which follow the density.
            : math.min(count, 6) * 30.0 +
                  (math.min(count, 6) - 1) * 6.0 * density +
                  16.0 * density +
                  2.0;
        _openPanel(
          'tray',
          _trayKey,
          (_, close) => TrayPopover(
            services: _services,
            settings: settings,
            onClose: close,
          ),
          width: width,
          radius: capsule ? 22 : null,
          placement: BarPanelAnchor.centred,
        );
      },
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
      onSearch: () => KitRequests.triggerSearch(
        fallback: _services.toggleLauncher,
        monitorId: _environment.output.monitorId,
      ),
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
      onControlCenter: () {
        final style = kitStyle.value;
        final archetype = style.archetype;
        final useCustomShell =
            archetype != KitShellArchetype.macos &&
            archetype != KitShellArchetype.denial &&
            archetype != KitShellArchetype.cutefish;
        final panelStyle = style.panelStyle;
        final floating =
            !useCustomShell && panelStyle == KitPanelStyle.floating;
        final attached = panelStyle == KitPanelStyle.attached;
        _openPanel(
          'controlcenter',
          _controlCenterKey,
          (_, close) => _controlCenterBody(close),
          width: controlCenterWidthFor(archetype),
          frameless: floating,
          gap: attached ? 0 : null,
          // The sheet keeps its place at the screen's trailing side while its
          // item is on that side, and hangs under the item anywhere else.
          placement: panelStyle == KitPanelStyle.anchored &&
                  archetype != KitShellArchetype.windows
              ? BarPanelAnchor.centred
              : _nearTrailingSide(_controlCenterKey)
              ? BarPanelAnchor.trailing
              : BarPanelAnchor.centred,
        );
      },
      onSettings: _openBarSettings,
    );
  }
}

/// One of the bar's parts drawn where there is no bar: in the dock, or in
/// any host of another plugin. It keeps its own anchors and opens its panels
/// away from the edge its host says it is on.
class _HostedBarPart extends ConsumerStatefulWidget {
  const _HostedBarPart({
    required this.id,
    required this.part,
    required this.services,
    required this.environment,
    super.key,
  });

  final String id;
  final KitPartContext part;
  final ShellServices services;
  final ShellSurfaceEnvironment environment;

  @override
  ConsumerState<_HostedBarPart> createState() => _HostedBarPartState();
}

class _HostedBarPartState extends ConsumerState<_HostedBarPart>
    with _BarActions<_HostedBarPart> {
  @override
  void initState() {
    super.initState();
    kitOpenPanel.addListener(_panelChanged);
  }

  @override
  void dispose() {
    kitOpenPanel.removeListener(_panelChanged);
    super.dispose();
  }

  void _panelChanged() {
    if (mounted) setState(() {});
  }

  @override
  ShellServices get _services => widget.services;

  @override
  ShellSurfaceEnvironment get _environment => widget.environment;

  @override
  PanelEdge get _side => switch (widget.part.edge) {
    KitEdge.bottom => PanelEdge.bottom,
    KitEdge.left => PanelEdge.left,
    KitEdge.right => PanelEdge.right,
    KitEdge.top => PanelEdge.top,
  };

  @override
  double get _bodyHeight => widget.part.panelExtent;

  @override
  Widget build(BuildContext context) {
    final part = widget.part;
    final id = widget.id;
    final settings =
        ref.watch(barSettingsProvider).value ?? BarSettings.defaults;
    final ink = part.ink;
    final tile = part.density == KitDensity.tile;
    // A row of status items keeps the bar's own height inside a taller cell;
    // down a side dock each item takes the dock's width.
    final cross = _horizontal
        ? math.min(part.crossExtent, BarTokens.height)
        : part.crossExtent;
    final monitorId = part.monitorId ?? _environment.output.monitorId;

    if (id == BarPart.system) {
      return BarSystemMenu(
        key: _systemKey,
        glyph: _DistroGlyph(ink: ink),
        open: _openPanelId == 'system',
        ink: ink,
        onToggle: _openSystemMenu,
      );
    }
    if (id == BarPart.workspaces) {
      return BarWorkspaces(
        services: _services,
        monitorId: monitorId,
        ink: ink,
        settings: settings,
        vertical: !_horizontal,
        side: _side,
        barHeight: _bodyHeight,
      );
    }
    if (id == BarPart.clock) {
      final now = ref.watch(_services.clock).value ?? DateTime.now();
      if (tile && _horizontal && part.crossExtent >= 34) {
        return _TileClock(
          key: _clockKey,
          time: _services.strings(context).time(now),
          date: settings.showClockDate
              ? _dateLabel(context, settings, now)
              : '',
          ink: ink,
          height: math.min(part.crossExtent, 44),
          open: _openPanelId == 'clock',
          onTap: () => _openClock(settings),
        );
      }
      return _clockFor(
        context,
        settings: settings,
        ink: ink,
        now: now,
        crossExtent: cross,
      );
    }
    final status = _statusFor(
      settings: settings,
      ink: ink,
      crossExtent: cross,
      spacing: settings.partGap,
    );
    if (id == BarPart.status) {
      return status.view(
        ink: ink,
        omit: <String>{
          for (final item in barStatusItems)
            if (part.siblings.contains(BarPart.statusItem(item))) item,
        },
      );
    }
    for (final item in barStatusItems) {
      if (id == BarPart.statusItem(item)) {
        return status.view(ink: ink, only: item);
      }
    }
    return const SizedBox.shrink();
  }
}

/// The clock in a cell as tall as a dock's icons: the time over the date.
class _TileClock extends StatelessWidget {
  const _TileClock({
    required this.time,
    required this.date,
    required this.ink,
    required this.height,
    required this.open,
    required this.onTap,
    super.key,
  });

  final String time;
  final String date;
  final Color ink;
  final double height;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final style = BarType.clock.copyWith(color: ink, height: 1.15);
    return BarButton(
      onTap: onTap,
      open: open,
      ink: ink,
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: BarTokens.clockPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Text(time, maxLines: 1, style: style),
          if (date.isNotEmpty)
            Text(
              date,
              maxLines: 1,
              style: style.copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w400,
                color: ink.withValues(alpha: 0.72),
              ),
            ),
        ],
      ),
    );
  }
}

/// Draws part [id] outside a bar, or nothing when the host did not hand
/// over what the part needs to reach the system.
Widget _hostedBarPart(String id, KitPartContext part) {
  final services = part.services;
  final environment = part.environment;
  if (services == null || environment == null) return const SizedBox.shrink();
  return _HostedBarPart(
    key: ValueKey<String>('denial_topbar.hosted.$id'),
    id: id,
    part: part,
    services: services,
    environment: environment,
  );
}
