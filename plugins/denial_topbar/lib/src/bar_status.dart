import 'dart:async';

import 'package:denial_flutter_sdk/services.dart';
import 'package:denial_flutter_sdk/state.dart';
import 'package:denial_flutter_sdk/theme.dart';
import 'package:denial_shell_kit/kit_motion.dart';
import 'package:denial_shell_kit/kit_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'bar_button.dart';
import 'bar_glyphs.dart';
import 'bar_icons.dart';
import 'bar_settings.dart';
import 'bar_tokens.dart';
import 'bar_type.dart';
import 'island/island_parts.dart' show BatteryGlyph;
import 'l10n.dart';
import 'clipboard_watch.dart';
import 'mic_watch.dart';
import 'panels/popovers.dart';
import 'signal.dart';
import 'tray_names.dart';

/// One status item.
///
/// shell27 sizes each item by its own content: tray 26, Wi-Fi / bell / volume /
/// Bluetooth 28, Control Centre 38, the clock `implicitWidth + 16`. The glyph
/// inside is 15–16 and the plate is the bar's own `width - 2 × height - 6`
/// wash, so a status item reads exactly like a menu title.
class BarStatusCell extends StatelessWidget {
  const BarStatusCell({
    required this.child,
    required this.ink,
    required this.width,
    this.onTap,
    this.tooltip,
    this.open = false,
    super.key,
  });

  final Widget child;

  /// The bar's ink; the plate lightens under white and darkens under black.
  final Color ink;
  final double width;
  final VoidCallback? onTap;
  final String? tooltip;
  final bool open;

  @override
  Widget build(BuildContext context) {
    return BarButton(
      onTap: onTap,
      open: open,
      ink: ink,
      width: width,
      tooltip: tooltip,
      padding: EdgeInsets.zero,
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
    required this.onVolume,
    required this.onBluetooth,
    required this.onSearch,
    required this.onClipboard,
    this.clipboardKey,
    required this.onBattery,
    required this.onNotifications,
    required this.onControlCenter,
    required this.onSettings,
    this.onTray,
    this.onTraySettings,
    this.trayKey,
    this.wifiKey,
    this.volumeKey,
    this.bluetoothKey,
    this.batteryKey,
    this.notificationsKey,
    this.controlCenterKey,
    this.settingsKey,
    this.horizontal = true,
    this.crossExtent = BarTokens.height,
    this.only,
    this.omit = const <String>{},
    this.spacing = BarTokens.statusSpacing,
    super.key,
  });

  /// The same cluster drawn another way: in another [ink], as the one item
  /// [only], or without the items in [omit] because the bar places those on
  /// their own. Every view shares the anchors, so an item's popup opens from
  /// wherever that item is drawn.
  BarStatusCluster view({
    required Color ink,
    String? only,
    Set<String> omit = const <String>{},
  }) => BarStatusCluster(
    services: services,
    settings: settings,
    openPanel: openPanel,
    ink: ink,
    onWifi: onWifi,
    onVolume: onVolume,
    onBluetooth: onBluetooth,
    onSearch: onSearch,
    onClipboard: onClipboard,
    clipboardKey: clipboardKey,
    onBattery: onBattery,
    onNotifications: onNotifications,
    onControlCenter: onControlCenter,
    onSettings: onSettings,
    onTray: onTray,
    onTraySettings: onTraySettings,
    trayKey: trayKey,
    wifiKey: wifiKey,
    volumeKey: volumeKey,
    bluetoothKey: bluetoothKey,
    batteryKey: batteryKey,
    notificationsKey: notificationsKey,
    controlCenterKey: controlCenterKey,
    settingsKey: settingsKey,
    horizontal: horizontal,
    crossExtent: crossExtent,
    only: only,
    omit: omit,
    spacing: spacing,
  );

  /// Draws this one item and nothing else, indicators included.
  final String? only;

  /// Items left out of the cluster.
  final Set<String> omit;

  /// Room between two items.
  final double spacing;

  final ShellServices services;
  final BarSettings settings;
  final bool horizontal;

  /// The bar's thickness; on a vertical bar every cell is this wide.
  final double crossExtent;

  /// The panel currently open, so its cell keeps its plate.
  final String? openPanel;

  final Color ink;
  final VoidCallback onWifi;
  final VoidCallback onVolume;
  final VoidCallback onBluetooth;
  final VoidCallback onSearch;
  final VoidCallback onClipboard;
  final GlobalKey? clipboardKey;
  final VoidCallback onBattery;
  final VoidCallback onNotifications;
  final VoidCallback onControlCenter;
  final VoidCallback onSettings;
  final VoidCallback? onTray;
  final VoidCallback? onTraySettings;
  final GlobalKey? trayKey;

  /// Anchors the popup's scene rectangle. Without one the panel falls back to
  /// the screen edge instead of hanging under its own cell.
  final GlobalKey? wifiKey;
  final GlobalKey? volumeKey;
  final GlobalKey? bluetoothKey;
  final GlobalKey? batteryKey;
  final GlobalKey? notificationsKey;
  final GlobalKey? controlCenterKey;
  final GlobalKey? settingsKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trayVisible = ref.watch(services.trayVisible);
    final trayIds = ref.watch(services.trayItemIds);
    final wifi = ref.watch(services.connectedWifi);
    final volume = ref.watch(services.volume);
    final battery = ref.watch(services.battery);
    final plugged = ref.watch(
      upowerProvider.select((state) => state.snapshot?.onBattery == false),
    );
    final bluetooth = ref.watch(bluetoothProvider);
    final headphones = ref.watch(
      audioDevicesProvider.select((state) {
        final active = state.activeDevice;
        return active != null &&
            outputDeviceIcon(active) == BarIcons.headphones;
      }),
    );
    final unread = ref.watch(
      desktopNotificationsProvider.select((state) => state.unreadCount),
    );

    double span(double width) => horizontal ? width : crossExtent;
    final percent = settings.showBatteryPercent && horizontal;
    final sorting =
        settings.trayNever.isNotEmpty || settings.trayHidden.isNotEmpty;
    if (sorting) {
      trayNames.resolve(trayIds);
      ref.watch(_trayNamesProvider);
    }
    final part = partitionTrayIds(
      trayIds,
      settings: settings,
      resolveKey: (id) => trayNames.of(id).key,
    );
    final hasFolded = part.folded.isNotEmpty;
    final inBarFold =
        hasFolded &&
        (settings.trayFold == BarTrayFold.inline ||
            settings.trayFold == BarTrayFold.hover);
    final popoverFold = hasFolded && settings.trayFold == BarTrayFold.popover;
    final showTrayCell =
        settings.showTray &&
        trayVisible &&
        (part.visible.isNotEmpty || inBarFold || popoverFold);
    Widget tray(List<String> ids) => buildTrayIcons(
      context,
      services: services,
      settings: settings,
      ink: ink,
      itemIds: ids,
      horizontal: horizontal,
      crossExtent: crossExtent,
    );

    final byId = <String, Widget>{
      if (showTrayCell)
        'tray': Flex(
          direction: horizontal ? Axis.horizontal : Axis.vertical,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (inBarFold)
              _TrayFold(
                ink: ink,
                enabled: true,
                expandOnHover: settings.trayFold == BarTrayFold.hover,
                autoSeconds: settings.collapseAutoSeconds,
                horizontal: horizontal,
                crossExtent: crossExtent,
                child: tray(part.folded),
              ),
            if (popoverFold)
              GestureDetector(
                behavior: HitTestBehavior.translucent,
                onSecondaryTapUp: onTraySettings == null
                    ? null
                    : (_) => onTraySettings!(),
                child: BarStatusCell(
                  key: trayKey,
                  ink: ink,
                  width: span(24),
                  onTap: onTray,
                  open: openPanel == 'tray',
                  tooltip: context.tr('Tray items'),
                  child: AnimatedRotation(
                    duration: KitMotion.duration(context, KitMotion.travel),
                    curve: KitMotion.outCubic,
                    turns: (horizontal ? 0 : -0.25) +
                        (openPanel == 'tray' ? 0.5 : 0),
                    child: BarGlyph(
                      BarIcons.chevronDown,
                      size: 12,
                      color: ink.withValues(alpha: 0.85),
                    ),
                  ),
                ),
              ),
            if (part.visible.isNotEmpty) tray(part.visible),
          ],
        ),
      if (settings.showWifi)
        'wifi': BarStatusCell(
          key: wifiKey,
          ink: ink,
          width: span(BarTokens.statusCellWidth),
          onTap: onWifi,
          tooltip: wifi?.ssid ?? 'Wi-Fi',
          open: openPanel == 'wifi',
          child: wifi == null
              ? BarGlyph(
                  BarIcons.wifiSlash,
                  size: BarTokens.statusGlyphSize,
                  color: ink.withValues(alpha: 0.55),
                )
              : WifiGlyph(
                  size: BarTokens.statusIconSize,
                  color: ink,
                  strength: wifiSignalArcs(wifi.strength),
                ),
        ),
      if (settings.showBluetooth && bluetooth.available)
        'bluetooth': BarStatusCell(
          key: bluetoothKey,
          ink: ink,
          width: span(BarTokens.statusCellWidth),
          onTap: onBluetooth,
          tooltip: context.tr('Bluetooth'),
          open: openPanel == 'bluetooth',
          child: BarGlyph(
            BarIcons.bluetooth,
            size: BarTokens.statusIconSize,
            color: ink.withValues(alpha: bluetooth.powered ? 1 : 0.45),
          ),
        ),
      if (settings.showVolume)
        'volume': BarStatusCell(
          key: volumeKey,
          ink: ink,
          width: span(BarTokens.statusCellWidth),
          onTap: onVolume,
          tooltip: '${context.tr('Sound')} ${(volume * 100).round()}%',
          open: openPanel == 'volume',
          child: BarGlyph(
            headphones
                ? BarIcons.headphones
                : volume <= 0.001
                ? BarIcons.speakerSlashFill
                : (volume < 0.34 ? BarIcons.volumeDown : BarIcons.volumeUp),
            size: BarTokens.statusIconSize,
            color: ink,
          ),
        ),
      if (settings.showBattery && battery.capacity != null)
        'battery': BarStatusCell(
          key: batteryKey,
          ink: ink,
          width: span(percent ? 63 : 39),
          onTap: onBattery,
          tooltip: '${context.tr('Battery')} ${battery.capacity}%',
          open: openPanel == 'battery',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (percent)
                Padding(
                  padding: const EdgeInsets.only(right: 5),
                  child: Text(
                    '${battery.capacity}%',
                    style: BarType.batteryPercent.copyWith(color: ink),
                  ),
                ),
              BatteryGlyph(
                level: (battery.capacity ?? 0) / 100,
                colour: ink,
                charging: battery.charging || plugged,
              ),
            ],
          ),
        ),
      if (settings.showSearch)
        'search': BarStatusCell(
          ink: ink,
          width: span(BarTokens.statusCellWidth),
          onTap: onSearch,
          tooltip: context.tr('Search'),
          child: BarGlyph(
            BarIcons.search,
            size: BarTokens.statusIconSize - 1,
            color: ink,
          ),
        ),
      if (settings.showClipboard)
        'clipboard': BarStatusCell(
          key: clipboardKey,
          ink: ink,
          width: span(BarTokens.statusCellWidth),
          onTap: onClipboard,
          tooltip: context.tr('Clipboard History'),
          open: openPanel == 'clipboard',
          child: BarGlyph(
            BarIcons.clipboard,
            size: BarTokens.statusIconSize - 1,
            color: ink,
          ),
        ),
      if (settings.showNotifications && !settings.mergedNotificationCenter)
        'notifications': BarStatusCell(
          key: notificationsKey,
          ink: ink,
          width: span(BarTokens.statusCellWidth),
          onTap: onNotifications,
          tooltip: context.tr('Notifications'),
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
                  right: -3,
                  top: -2,
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: const Color(0xffff453a),
                      borderRadius: KitStyle.of(context).disc(7),
                    ),
                  ),
                ),
            ],
          ),
        ),
      if (settings.showControlCenter)
        'controlcenter': BarStatusCell(
          key: controlCenterKey,
          ink: ink,
          width: span(BarTokens.controlCentreWidth),
          onTap: onControlCenter,
          tooltip: context.tr('Control Centre'),
          open: openPanel == 'controlcenter',
          child: Align(
            alignment: horizontal ? Alignment.centerLeft : Alignment.center,
            child: Padding(
              padding: EdgeInsets.only(left: horizontal ? 10 : 0),
              child: ControlCentreGlyph(
                size: BarTokens.statusGlyphSize,
                color: ink,
              ),
            ),
          ),
        ),
      if (settings.showSettingsButton)
        'settings': BarStatusCell(
          key: settingsKey,
          ink: ink,
          width: span(BarTokens.statusCellWidth),
          onTap: onSettings,
          tooltip: context.tr('Menu Bar Settings…'),
          open: openPanel == 'settings',
          child: BarGlyph(
            BarIcons.gear,
            size: BarTokens.statusIconSize,
            color: ink,
          ),
        ),
    };
    final recording = ref.watch(screenRecordingProvider);
    if (settings.showMic) micWatch.start();
    unawaited(clipboardWatch.setRunning(settings.showClipboard));
    final micUsers = settings.showMic
        ? ref.watch(_micProvider)
        : const <String>[];
    final only = this.only;
    final cells = only != null
        ? <Widget>[?byId[only]]
        : <Widget>[
      if (micUsers.isNotEmpty)
        BarStatusCell(
          ink: ink,
          width: span(20),
          tooltip: '${context.tr('Microphone in use')}: ${micUsers.join(', ')}',
          child: Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: const Color(0xffff9f0a),
              borderRadius: KitStyle.of(context).disc(7),
            ),
          ),
        ),
      if (settings.showRecording && recording.recording)
        BarStatusCell(
          ink: ink,
          width: span(BarTokens.statusCellWidth),
          tooltip: context.tr('Stop Recording'),
          onTap: () => ref.read(screenRecordingProvider.notifier).toggle(),
          child: Container(
            width: 16,
            height: 16,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xffff453a),
              borderRadius: KitStyle.of(context).disc(16),
            ),
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: const Color(0xffffffff),
                borderRadius: BorderRadius.circular(
                  KitStyle.of(context).corner(1.5),
                ),
              ),
            ),
          ),
        ),
      for (final id in <String>{...settings.statusOrder, ...byId.keys})
        if (byId[id] != null && !omit.contains(id)) byId[id]!,
    ];

    return Flex(
      direction: horizontal ? Axis.horizontal : Axis.vertical,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (var index = 0; index < cells.length; index++) ...<Widget>[
          if (index > 0) SizedBox.square(dimension: spacing),
          cells[index],
        ],
      ],
    );
  }
}

final _micProvider = Provider.autoDispose<List<String>>((ref) {
  void changed() => ref.invalidateSelf();
  micWatch.addListener(changed);
  ref.onDispose(() => micWatch.removeListener(changed));
  return micWatch.value;
});

final _trayNamesProvider = Provider.autoDispose<Map<String, TrayIdentity>>((
  ref,
) {
  void changed() => ref.invalidateSelf();
  trayNames.addListener(changed);
  ref.onDispose(() => trayNames.removeListener(changed));
  return trayNames.value;
});

/// A colour matrix that paints every pixel in [ink] at the source's own alpha,
/// the way macOS renders a template image in a menu-bar extra.
List<double> _templateMatrix(Color ink) {
  // Luminance keeps antialiased edges smooth before the tint replaces the
  // colour; the last row leaves the source alpha untouched.
  const lr = 0.2126, lg = 0.7152, lb = 0.0722;
  final r = ink.r, g = ink.g, b = ink.b, a = ink.a;
  return <double>[
    lr * r,
    lg * r,
    lb * r,
    0,
    0,
    lr * g,
    lg * g,
    lb * g,
    0,
    0,
    lr * b,
    lg * b,
    lb * b,
    0,
    0,
    0,
    0,
    0,
    a,
    0,
  ];
}


/// Draws [itemIds] from the system tray with the bar's icon tinting rule.
Widget buildTrayIcons(
  BuildContext context, {
  required ShellServices services,
  required BarSettings settings,
  required Color ink,
  required List<String> itemIds,
  bool horizontal = true,
  double maxExtent = 240,
  double crossExtent = BarTokens.height,
}) {
  final style = KitStyle.of(context);
  final Color tintColor = switch (style.look.iconTint) {
    KitIconTint.accent => style.accent(context.shellTheme),
    KitIconTint.original || KitIconTint.mono => ink,
  };
  Widget build({Color? foreground}) => services.buildSystemTray(
    context,
    horizontal: horizontal,
    foregroundColor: foreground,
    itemIds: itemIds,
  );
  return ConstrainedBox(
    constraints: horizontal
        ? BoxConstraints(maxWidth: maxExtent)
        : BoxConstraints(maxHeight: maxExtent, maxWidth: crossExtent),
    child: settings.trayColour
        ? build()
        : ColorFiltered(
            colorFilter: ColorFilter.matrix(_templateMatrix(tintColor)),
            child: build(foreground: tintColor),
          ),
  );
}

/// Folds the tray behind a chevron: one press (or hover when enabled) slides
/// the icons out, another (or the timer) slides them back.
class _TrayFold extends StatefulWidget {
  const _TrayFold({
    required this.ink,
    required this.enabled,
    required this.autoSeconds,
    required this.child,
    this.expandOnHover = false,
    this.horizontal = true,
    this.crossExtent = BarTokens.height,
  });

  final bool horizontal;
  final double crossExtent;

  final Color ink;
  final bool enabled;
  final bool expandOnHover;
  final int autoSeconds;
  final Widget child;

  @override
  State<_TrayFold> createState() => _TrayFoldState();
}

class _TrayFoldState extends State<_TrayFold> {
  bool _open = false;
  Timer? _refold;
  Timer? _hoverTimer;

  @override
  void dispose() {
    _refold?.cancel();
    _hoverTimer?.cancel();
    super.dispose();
  }

  void _arm() {
    _refold?.cancel();
    if (!_open || widget.autoSeconds <= 0) return;
    _refold = Timer(Duration(seconds: widget.autoSeconds), () {
      if (mounted) setState(() => _open = false);
    });
  }

  void _toggle() {
    _hoverTimer?.cancel();
    setState(() => _open = !_open);
    _arm();
  }

  void _hover(bool inside) {
    if (!widget.expandOnHover) return;
    _hoverTimer?.cancel();
    if (inside) {
      if (!_open) setState(() => _open = true);
      _arm();
    } else if (_open) {
      _hoverTimer = Timer(const Duration(milliseconds: 500), () {
        if (mounted) setState(() => _open = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    final horizontal = widget.horizontal;
    return MouseRegion(
      onEnter: (_) => _hover(true),
      onExit: (_) => _hover(false),
      child: Flex(
        direction: horizontal ? Axis.horizontal : Axis.vertical,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ClipRect(
            child: AnimatedAlign(
              duration: KitMotion.duration(context, KitMotion.travel),
              curve: KitMotion.outCubic,
              alignment: horizontal
                  ? Alignment.centerRight
                  : Alignment.bottomCenter,
              widthFactor: horizontal ? (_open ? 1 : 0) : null,
              heightFactor: horizontal ? null : (_open ? 1 : 0),
              child: AnimatedOpacity(
                duration: KitMotion.duration(context, KitMotion.enter),
                opacity: _open ? 1 : 0,
                child: Listener(
                  onPointerDown: (_) => _arm(),
                  child: Padding(
                    padding: horizontal
                        ? const EdgeInsets.only(right: 2)
                        : const EdgeInsets.only(bottom: 2),
                    child: widget.child,
                  ),
                ),
              ),
            ),
          ),
          BarStatusCell(
            ink: widget.ink,
            width: horizontal ? 22 : widget.crossExtent,
            onTap: _toggle,
            child: AnimatedRotation(
              duration: KitMotion.duration(context, KitMotion.travel),
              curve: KitMotion.outCubic,
              turns: (horizontal ? 0 : 0.25) + (_open ? 0.5 : 0),
              child: BarGlyph(
                BarIcons.chevronLeft,
                size: 12,
                color: widget.ink.withValues(alpha: 0.8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
