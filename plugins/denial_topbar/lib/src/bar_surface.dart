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
import 'package:denial_shell_kit/kit_dock_link.dart';
import 'package:denial_shell_kit/kit_host.dart';
import 'package:denial_shell_kit/kit_look_motion.dart';
import 'package:denial_shell_kit/kit_springs.dart' show Sprung;
import 'package:denial_shell_kit/kit_style.dart'
    show
        KitScaleScope,
        KitStyle,
        KitThemeAccent,
        kitDockEnabled,
        kitShellScale,
        resolveKitScale;
import 'package:denial_shell_kit/shell_preset.dart';
import 'package:denial_shell_kit/kit_part.dart';
import 'package:denial_shell_kit/kit_requests.dart';
import 'package:denial_shell_kit/kit_settings.dart';
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
import 'bar_parts.dart';
import 'bar_preferences.dart';
import 'bar_reserve.dart';
import 'bar_segments.dart';
import 'bar_settings.dart';
import 'bar_status.dart';
import 'bar_tokens.dart';
import 'bar_type.dart';
import 'clock_label.dart';
import 'tray_names.dart';
import 'island/island.dart';
import 'island/island_motion.dart';
import 'island/island_options.dart';
import 'island/island_skin.dart';
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

part 'bar_actions.dart';

/// How much of the surface the floating capsule needs past the strip so its
/// shadow is not clipped.
const double barShadowExtent = BarTokens.shadowExtent;

/// The macOS 27 menu bar.
///
/// Ports NextKDE `KitWindow.qml`'s composition — system menu, app menu, status
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

class _TopBarSurfaceState extends ConsumerState<TopBarSurface>
    with _BarActions<TopBarSurface> {
  final GlobalKey _appKey = GlobalKey();

  void _panelChanged() {
    if (!mounted) return;
    setState(() {});
    if (kitOpenPanel.value == null) _hover();
  }

  @override
  void initState() {
    super.initState();
    kitOpenPanel.addListener(_panelChanged);
    registerBarParts(outside: _hostedBarPart);
    registerBarSettingsPages(widget.services);
    // Another plugin asks for the about box by name; it opens on the output
    // the request names, or on every bar's when it names none.
    _requests = KitRequests.stream.listen((request) {
      if (!mounted) return;
      final monitor = request.monitorId;
      if (monitor != null && monitor != widget.monitorId) return;
      switch (request.name) {
        case KitRequests.about:
          _openAbout();
        case KitRequests.controlCentre:
          if (KitRequests.take(request)) _status?.onControlCenter();
        case KitRequests.notificationCentre:
          if (KitRequests.take(request)) _clockTap?.call();
        case KitRequests.settings:
          if (KitRequests.take(request)) _openBarSettings();
      }
    });
    startDebugRemote();
    debugCommand.addListener(_debug);
    kitBarMode.addListener(_shellChanged);
    kitHosts.addListener(_shellChanged);
    kitDockEnabled.addListener(_shellChanged);
    kitDock.addListener(_shellChanged);
    kitDockAwaited.addListener(_shellChanged);
    kitShellScale.addListener(_shellChanged);
    if (kitDockAwaited.value) {
      Timer(const Duration(seconds: 3), () => kitDockAwaited.value = false);
    }
    _syncReservation();
  }

  /// The bar's mode, the dock's switch or what the dock reports changed:
  /// draw the new mode and have the shell keep the right edge free.
  void _shellChanged() {
    if (!mounted) return;
    setState(() {});
    _syncReservation();
  }

  bool _reserveQueued = false;

  /// One bar speaks for the shell, the one on the main output. Queued, so
  /// several changes at once are handed over as one.
  void _syncReservation() {
    if (!widget.environment.isMainOutput || _reserveQueued) return;
    _reserveQueued = true;
    scheduleMicrotask(() {
      _reserveQueued = false;
      if (!mounted) return;
      syncBarReservation(ref, widget.environment.settings.layout);
    });
  }

  StreamSubscription<KitRequest>? _requests;

  final ValueNotifier<double> _islandReserved = ValueNotifier<double>(58);

  bool _hidden = false;

  /// The plates the pointer is over; a bar of islands has one per zone.
  final Set<int> _overPlates = <int>{};
  bool get _overBar => _overPlates.isNotEmpty;
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
      if (_overBar || _overIsland || kitOpenPanel.value != null) return;
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
    _requests?.cancel();
    kitOpenPanel.removeListener(_panelChanged);
    debugCommand.removeListener(_debug);
    kitBarMode.removeListener(_shellChanged);
    kitHosts.removeListener(_shellChanged);
    kitDockEnabled.removeListener(_shellChanged);
    kitDock.removeListener(_shellChanged);
    kitDockAwaited.removeListener(_shellChanged);
    kitShellScale.removeListener(_shellChanged);
    _islandReserved.dispose();
    super.dispose();
  }

  @override
  PanelEdge get _side {
    final side = widget.environment.settings.layout.systemBarSide;
    return side == null || side == PanelEdge.hidden ? PanelEdge.top : side;
  }

  /// How far the bar reaches from its screen edge as laid out, so a panel
  /// hangs from the bar's real inner face: a floating bar stands its margin
  /// off the edge, and that margin is under the panel too.
  @override
  double get _bodyHeight {
    final settings =
        ref.read(barSettingsProvider).value ?? BarSettings.defaults;
    final thickness =
        settings.barHeight ?? widget.environment.settings.layout.systemBarThickness;
    final margin = _marginOf(settings);
    return margin + math.max(BarTokens.height, thickness - margin * 2);
  }

  /// Room between the bar and the screen edge it sits on; a strip has none.
  static double _marginOf(BarSettings settings) =>
      settings.shape == BarShape.strip ? 0 : settings.edgeMargin;

  @override
  ShellServices get _services => widget.services;

  @override
  ShellSurfaceEnvironment get _environment => widget.environment;

  BarStatusCluster? _status;
  VoidCallback? _clockTap;

  void _debug() {
    final words = debugWords();
    final status = _status;
    if (words.isEmpty || status == null || !mounted) return;
    final number = words.length > 1 ? int.tryParse(words[1]) ?? 0 : 0;
    switch (words.first) {
      case 'close':
        closeKitPanel();
      case 'ask':
        if (words.length > 1) {
          KitRequests.send(words[1], monitorId: widget.monitorId);
        }
      case 'preset':
        if (words.length > 1) {
          applyShellPreset(ref, ShellPreset.byId(words[1]));
        }
      case 'dock':
        kitDockEnabled.value = words.length < 2 || words[1] != 'off';
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
      case 'tray':
        status.onTray?.call();
      case 'trayfold':
        final fold = words.length > 1
            ? BarTrayFold.parse(words[1])
            : BarTrayFold.floatingBar;
        ref
            .read(barSettingsProvider.notifier)
            .save((s) => s.copyWith(collapseItems: true, trayFold: fold));
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings =
        ref.watch(barSettingsProvider).value ?? BarSettings.defaults;
    final thickness =
        settings.barHeight ?? widget.environment.settings.layout.systemBarThickness;
    final theme = context.shellTheme;
    final attached = settings.shape == BarShape.strip;
    final margin = _marginOf(settings);
    final bodyHeight = math.max(BarTokens.height, thickness - margin * 2);
    final wallpaper = ref.watch(wallpaperAccentProvider).color;
    final ink = BarGroundLayer.inkFor(wallpaper, settings, theme);
    final now = ref.watch(_services.clock).value ?? DateTime.now();
    final strings = _services.strings(context);
    final zones = settings.zones;
    // A bar that draws only its island has one whatever the layout says.
    final mode = kitBarModeInForce;
    // What the island's switches come to as things stand is decided in one
    // place, which the settings page draws from too.
    final islandOptions = IslandOptions(
      settings,
      mode: mode,
      top: _side == PanelEdge.top,
    );
    final islandAvailable = islandOptions.present;
    final style = KitStyle.of(context);
    final density = style.density.clamp(0.75, 1.35);
    final workspaceInIsland = settings.workspacesInIsland;
    final gap = settings.partGap * density;

    final workspaceStatus = ref.watch(_services.workspace(widget.monitorId));
    final workspaceEnabled = ref.watch(_services.workspacesEnabled);
    final islandWorkspaceWidth = workspaceEnabled && workspaceStatus.count > 0
        ? workspacesExtent(workspaceStatus.count, settings.workspaceStyle) + 4.0
        : 0.0;

    BarClock clockIn(Color ink) => _clockFor(
      context,
      settings: settings,
      ink: ink,
      now: now,
      crossExtent: bodyHeight,
    );
    final clock = clockIn(ink);

    BarButton.tips = settings.tooltips && _horizontal;
    _clockTap = clock.onTap;
    final status = _statusFor(
      settings: settings,
      ink: ink,
      crossExtent: bodyHeight,
      spacing: gap,
    );

    // macOS measures 31 pt on a machine whose bar is taller than 24; on a
    // 24 pt strip the capsule takes the strip's own height, capped so the
    // pill never fills it edge to edge.
    final islandHeight = settings.islandNotch && _side == PanelEdge.top
        ? math.max(BarTokens.islandMinHeight, bodyHeight)
        : math.max(
            BarTokens.islandMinHeight,
            math.min(BarTokens.islandHeight, bodyHeight - 5),
          );

    _status = status;
    final island = islandAvailable
        ? Island(
            services: _services,
            monitorId: widget.monitorId,
            settings: islandOptions.effective,
            height: islandHeight,
            reserved: _islandReserved,
            timeLabel: strings.time(now),
            dateLabel: clock.date,
            onControlCenter: status.onControlCenter,
            onNotifications: clock.onTap,
            notch: settings.islandNotch && _side == PanelEdge.top,
            workspace: workspaceInIsland
                ? BarWorkspaces(
                    services: _services,
                    monitorId: widget.monitorId,
                    ink: IslandSkin.of(context).ink,
                    settings: settings,
                    barHeight: bodyHeight,
                  )
                : null,
            workspaceWidth: workspaceInIsland ? islandWorkspaceWidth : 0.0,
          )
        : null;

    if (mode != KitBarMode.shown) {
      // No strip, so nothing to hide, nothing under the pointer and no room
      // kept free: the island floats where it always sat, or nothing shows.
      _hideTimer?.cancel();
      _hideTimer = null;
      _hidden = false;
      _overPlates.clear();
      if (island == null || mode == KitBarMode.hidden) {
        return const SizedBox.shrink();
      }
      return Stack(
        children: <Widget>[
          Positioned(
            left: 0,
            right: 0,
            top: margin + (bodyHeight - islandHeight) / 2,
            child: Align(alignment: Alignment.topCenter, child: island),
          ),
        ],
      );
    }

    // What each part draws in this bar. A part is given the ink of the spot
    // it lands on, and keeps its anchor wherever that is.
    final loneStatus = zones.loneStatusItems;
    final builders = <String, BarPartBuilder>{
      BarPart.system: (part) => BarSystemMenu(
        key: _systemKey,
        glyph: _DistroGlyph(ink: part.ink),
        open: _openPanelId == 'system',
        ink: part.ink,
        onToggle: _openSystemMenu,
      ),
      BarPart.workspaces: (part) => BarWorkspaces(
        services: _services,
        monitorId: widget.monitorId,
        ink: part.ink,
        settings: settings,
        vertical: !_horizontal,
        side: _side,
        barHeight: bodyHeight,
      ),
      BarPart.app: (part) => _AppMenuPart(bar: this, ink: part.ink),
      BarPart.clock: (part) => part.ink == ink ? clock : clockIn(part.ink),
      BarPart.status: (part) => status.view(ink: part.ink, omit: loneStatus),
      for (final item in barStatusItems)
        BarPart.statusItem(item): (part) =>
            status.view(ink: part.ink, only: item),
      // The island itself floats over the bar; in the row it only holds its
      // width open.
      BarPart.island: (_) => ValueListenableBuilder<double>(
        valueListenable: _islandReserved,
        // The slot follows the pill on a spring of the same family, dead
        // beat, so the parts beside it give way as the pill grows.
        builder: (context, width, _) => Sprung(
          target: width,
          tuning: IslandFeel.of(KitStyle.of(context)).slot,
          tolerance: 0.05,
          builder: (context, value, _) =>
              SizedBox(width: math.max(0.0, value)),
        ),
      ),
    };

    /// The widgets of one zone, in order, with the bar's gaps between them.
    /// [flexible] lets a spacer take the room left; a zone that sizes itself
    /// to its content has none to give, so there a spacer is a wide gap.
    List<Widget> row(
      List<String> ids,
      Color ink, {
      required bool flexible,
    }) {
      final pillActive = settings.partPill != BarPartPill.none;
      final part = KitPartContext(
        edge: _side.kitEdge,
        axis: _horizontal ? Axis.horizontal : Axis.vertical,
        crossExtent: bodyHeight,
        ink: pillActive ? theme.colors.textPrimary : ink,
      );
      final widgets = <Widget>[];
      for (var index = 0; index < ids.length; index++) {
        final id = ids[index];
        if (index > 0 && BarPart.gapBetween(ids[index - 1], id)) {
          widgets.add(SizedBox.square(dimension: gap));
        }
        widgets.add(switch (id) {
          BarPart.spacer =>
            flexible
                ? const Spacer()
                : SizedBox.square(dimension: math.max(gap, 6) * 2),
          BarPart.gap => SizedBox.square(dimension: gap),
          BarPart.separator => _BarSeparator(
            ink: ink,
            horizontal: _horizontal,
          ),
          BarPart.island => KitPartView(id: id, part: part),
          _ => pillActive
              ? _partPill(
                  settings: settings,
                  theme: theme,
                  style: style,
                  id: id,
                  bodyHeight: bodyHeight,
                  child: KitPartView(id: id, part: part),
                )
              : KitPartView(id: id, part: part),
        });
      }
      return widgets;
    }

    // The island takes the centre for itself: it grows from the middle of
    // the screen, and a neighbour would push it off that line.
    final centreIds = islandAvailable
        ? const <String>[BarPart.island]
        : <String>[
            for (final id in zones.center)
              if (id != BarPart.island) id,
          ];

    final axis = _horizontal ? Axis.horizontal : Axis.vertical;
    // Points are cut along a horizontal bar; a side bar keeps its corners.
    final arrow = settings.cap == BarCap.arrow && _horizontal && !attached;
    final radius = attached || settings.cap == BarCap.square
        ? BorderRadius.zero
        : BorderRadius.circular(settings.cornerRadius);
    final pad = settings.contentPadding * density;
    EdgeInsets along(double before, double after) => _horizontal
        ? EdgeInsets.only(left: before, right: after)
        : EdgeInsets.only(top: before, bottom: after);

    /// Reports the pointer and takes the bar's own menu over one plate.
    Widget interactive(int plate, String label, Widget child) =>
        ShellInputRegion(
          debugLabel: label,
          child: MouseRegion(
            onEnter: (_) {
              _overPlates.add(plate);
              _hover();
            },
            onExit: (_) {
              _overPlates.remove(plate);
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
                child: child,
              ),
            ),
          ),
        );

    final separate = settings.shape == BarShape.islands;
    // A plate that went away under the pointer never reported it leaving.
    _overPlates.removeWhere(
      (plate) => separate
          ? (plate == 1 ? centreIds : zones.zone(plate)).isEmpty
          : plate != 0,
    );
    final Widget content;
    if (separate) {
      final base = BarGroundLayer.baseFor(wallpaper, settings, theme);
      final alternate = BarGroundLayer.alternateFor(base, theme);
      final plain = settings.ground == BarGround.none;

      /// One zone on a plate of its own, or on a run of pointed segments
      /// that its separators cut it into.
      Widget? zonePlate(int zone, List<String> ids) {
        if (ids.isEmpty) return null;
        final Widget plate;
        if (arrow) {
          final runs = BarZones.segments(ids);
          if (runs.isEmpty) return null;
          final edges = barZoneEdges(zone, runs.length);
          final depth = barArrowDepth(bodyHeight);
          plate = Row(
            mainAxisSize: MainAxisSize.min,
            // Every segment is as tall as the bar, so the points meet.
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (var index = 0; index < runs.length; index++)
                BarGroundLayer(
                  settings: settings,
                  borderRadius: BorderRadius.zero,
                  backdrop: wallpaper,
                  edges: edges[index],
                  fill: index.isOdd ? alternate : null,
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: pad + barEdgeInset(edges[index].left, depth),
                      right: pad + barEdgeInset(edges[index].right, depth),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: row(
                        runs[index],
                        index.isOdd && !plain
                            ? BarGroundLayer.inkOn(alternate)
                            : ink,
                        flexible: false,
                      ),
                    ),
                  ),
                ),
            ],
          );
        } else {
          plate = BarGroundLayer(
            settings: settings,
            borderRadius: radius,
            backdrop: wallpaper,
            child: Padding(
              padding: along(pad, pad),
              child: Flex(
                direction: axis,
                mainAxisSize: MainAxisSize.min,
                children: row(ids, ink, flexible: false),
              ),
            ),
          );
        }
        return interactive(
          zone,
          'denial_topbar.bar.$zone',
          SizedBox(
            width: _horizontal ? null : bodyHeight,
            height: _horizontal ? bodyHeight : null,
            child: plate,
          ),
        );
      }

      content = _BarRow(
        horizontal: _horizontal,
        leading: <Widget>[?zonePlate(0, zones.start)],
        // The island is its own plate.
        centre: islandAvailable
            ? row(centreIds, ink, flexible: false).single
            : zonePlate(1, centreIds),
        trailing: <Widget>[?zonePlate(2, zones.end)],
        bodyHeight: bodyHeight,
      );
    } else {
      final centre = row(centreIds, ink, flexible: false);
      content = _BarRow(
        horizontal: _horizontal,
        leading: row(zones.start, ink, flexible: true),
        centre: centre.isEmpty
            ? null
            : centre.length == 1
            ? centre.single
            : Flex(
                direction: axis,
                mainAxisSize: MainAxisSize.min,
                children: centre,
              ),
        trailing: row(zones.end, ink, flexible: true),
        bodyHeight: bodyHeight,
      );
    }

    // shell27: `leftRow.x: 8`, `rightRow.rightMargin: 6`.
    final inset = settings.endInset;
    final padding = !_horizontal
        ? EdgeInsets.symmetric(vertical: inset ?? BarTokens.insetLeft)
        : attached
        ? EdgeInsets.only(
            left: inset ?? BarTokens.insetLeft,
            right: inset ?? BarTokens.insetRight,
          )
        : EdgeInsets.symmetric(
            horizontal: inset ?? BarTokens.insetFloating,
          );

    Widget hosted = BarHost(builders: builders, child: content);
    if (settings.textScale != 1) {
      hosted = MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(settings.textScale)),
        child: hosted,
      );
    }

    Widget bar;
    if (separate) {
      bar = Padding(padding: padding, child: hosted);
    } else {
      // One plate under the whole bar; pointed ends keep the content clear
      // of the cut.
      final ends = arrow
          ? const (left: BarEdge.point, right: BarEdge.point)
          : null;
      final clear = arrow
          ? barEdgeInset(BarEdge.point, barArrowDepth(bodyHeight))
          : 0.0;
      bar = interactive(
        0,
        'denial_topbar.bar',
        Padding(
          padding: padding,
          child: BarGroundLayer(
            settings: settings,
            borderRadius: radius,
            backdrop: wallpaper,
            edges: ends,
            concaveEdge:
                settings.concaveEdge && attached && _horizontal && _side == PanelEdge.top,
            child: pad + clear == 0
                ? hosted
                : Padding(
                    padding: along(pad + clear, pad + clear),
                    child: hosted,
                  ),
          ),
        ),
      );
    }

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
        padding: EdgeInsets.all(margin),
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
            top: settings.islandNotch && _side == PanelEdge.top
                ? 0
                : margin + (bodyHeight - islandHeight) / 2,
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
    final surfaceStack = Stack(
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
          child: Sprung(
            target: hidden ? 1 : 0,
            tuning: _statusBarSpringTuning(),
            builder: (context, t, child) => Transform.translate(
              offset: direction * (away * t),
              child: Opacity(
                opacity: (1 - t * 0.6).clamp(0.0, 1.0),
                child: child,
              ),
            ),
            child: body,
          ),
        ),
      ],
    );
    final hostScale = widget.environment.shellScale > 0
        ? widget.environment.shellScale
        : 1.0;
    final effectiveScale = resolveKitScale(hostScale, kitShellScale.value);
    final relativeScale = effectiveScale / hostScale;
    final scoped = KitScaleScope(
      effectiveScale: effectiveScale,
      child: surfaceStack,
    );
    return (relativeScale - 1.0).abs() > 1e-4
        ? ShellScaleViewport(scale: relativeScale, child: scoped)
        : scoped;
  }

  static KitSpringTuning _statusBarSpringTuning() {
    const d = Motion.snappy;
    return KitSpringTuning(
      d.stiffness / d.mass,
      d.damping / (2 * math.sqrt(d.stiffness * d.mass)),
    );
  }

  Widget _partPill({
    required BarSettings settings,
    required ShellThemeData theme,
    required KitStyle style,
    required String id,
    required double bodyHeight,
    required Widget child,
  }) {
    final dark = theme.brightness == Brightness.dark;
    final base = theme.colors.surfaceContainerHigh;
    final radius = switch (settings.partPill) {
      BarPartPill.uniform => style.pill(bodyHeight - 4),
      BarPartPill.tinted => style.corner(9),
      BarPartPill.split => style.corner(8),
      BarPartPill.none => 0.0,
    };
    final tint = switch (settings.partPill) {
      BarPartPill.tinted => _moduleTint(id, dark),
      BarPartPill.split => theme.kitAccent,
      _ => null,
    };
    final fill = tint == null
        ? base.withValues(alpha: dark ? 0.72 : 0.78)
        : Color.alphaBlend(
            tint.withValues(alpha: dark ? 0.22 : 0.18),
            base,
          ).withValues(alpha: dark ? 0.84 : 0.88);
    return Padding(
      padding: _horizontal
          ? const EdgeInsets.symmetric(vertical: 2)
          : const EdgeInsets.symmetric(horizontal: 2),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(radius),
          border: tint == null
              ? null
              : Border.all(
                  width: 0.7,
                  color: tint.withValues(alpha: dark ? 0.36 : 0.30),
                ),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: _horizontal ? 6 : 2,
            vertical: _horizontal ? 0 : 4,
          ),
          child: child,
        ),
      ),
    );
  }

  static Color _moduleTint(String id, bool dark) {
    const darkSwatches = <Color>[
      Color(0xffb4befe), // Lavender
      Color(0xff74c7ec), // Sapphire
      Color(0xfffab387), // Peach
      Color(0xffcba6f7), // Mauve
      Color(0xffa6e3a1), // Green
      Color(0xfff5c2e7), // Pink
    ];
    const lightSwatches = <Color>[
      Color(0xff7287fd),
      Color(0xff209fb5),
      Color(0xfffe640b),
      Color(0xff8839ef),
      Color(0xff40a02b),
      Color(0xffea76cb),
    ];
    final palette = dark ? darkSwatches : lightSwatches;
    return palette[id.hashCode.abs() % palette.length];
  }

  /// The app's own name from the shell's catalog, falling back to the id's
  /// last segment the way revo-shell does.
  static String _appName(
    Iterable<LaunchableApplication> applications,
    DenialWindow window,
  ) {
    final appId = window.appId;
    if (appId.isEmpty) return 'Denial';
    final name = applications.firstWhere(
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

/// The focused application's name in bold, and nothing after it: the
/// compositor exposes no application menus, so the bar draws no titles it
/// could not open.
class _AppMenuPart extends ConsumerWidget {
  const _AppMenuPart({required this.bar, required this.ink});

  final _TopBarSurfaceState bar;
  final Color ink;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final services = bar._services;
    final horizontal = bar._horizontal;
    final window = ref.watch(shellControllerProvider).foregroundWindow;
    if (window == null) {
      return horizontal
          ? BarTitle(label: 'Denial', ink: ink, bold: true)
          : const SizedBox.shrink();
    }
    final appName = _TopBarSurfaceState._appName(
      ref.watch(services.applications),
      window,
    );
    return KeyedSubtree(
      key: bar._appKey,
      child: BarTitle(
        label: appName,
        ink: ink,
        bold: true,
        icon: horizontal
            ? null
            : services.buildApplicationIcon(context, window.appId),
        open: bar._openPanelId == 'app',
        onTap: () => showBarMenu(
          ref: ref,
          panelId: 'app',
          anchor: bar._appKey,
          vertical: !horizontal,
          fromRight: bar._side == PanelEdge.right,
          entries: (context) => appMenuEntries(
            context,
            ref,
            window: window,
            appName: appName,
            services: services,
          ),
        ),
      ),
    );
  }
}

/// A thin divider between two parts.
class _BarSeparator extends StatelessWidget {
  const _BarSeparator({required this.ink, required this.horizontal});

  final Color ink;
  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    final dark = BarGroundLayer.isDark(ink);
    final line = ColoredBox(
      color: ink.withValues(
        alpha: dark ? BarTokens.separatorLight : BarTokens.separatorDark,
      ),
    );
    return Padding(
      padding: horizontal
          ? const EdgeInsets.symmetric(horizontal: 6)
          : const EdgeInsets.symmetric(vertical: 6),
      child: SizedBox(
        width: horizontal ? 1 : 14,
        height: horizontal ? 14 : 1,
        child: line,
      ),
    );
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

  /// One side of the strip, clipped to its half so a long title list cannot
  /// run under the centre.
  Widget _side(List<Widget> children, Alignment alignment) {
    // A spacer shares out the half's own width, so the row has to fill it.
    if (children.any((child) => child is Spacer)) {
      return Expanded(
        child: ClipRect(child: Row(children: children)),
      );
    }
    return Expanded(
      child: ClipRect(
        child: OverflowBox(
          alignment: alignment,
          // Without an explicit minimum the box passes the Expanded's
          // tight width through, the Row stretches to it, and the
          // alignment has nothing left to move.
          minWidth: 0,
          maxWidth: double.infinity,
          // shell27's left row has no explicit spacing; the titles butt up
          // against each other and each carries its own 20 pt of padding.
          child: Row(mainAxisSize: MainAxisSize.min, children: children),
        ),
      ),
    );
  }

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
    // Equal flex on both sides puts the centre at the strip's own midpoint.
    return SizedBox(
      height: bodyHeight,
      child: Row(
        children: <Widget>[
          _side(leading, Alignment.centerLeft),
          ?centre,
          _side(trailing, Alignment.centerRight),
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
