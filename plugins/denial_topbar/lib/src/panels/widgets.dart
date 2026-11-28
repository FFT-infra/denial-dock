import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:denial_flutter_sdk/localization.dart';
import 'package:denial_flutter_sdk/services.dart';
import 'package:denial_flutter_sdk/settings.dart';
import 'package:denial_flutter_sdk/state.dart';
import 'package:denial_flutter_sdk/system_services.dart'
    show systemActionsServiceProvider;
import 'package:denial_flutter_sdk/theme.dart';
import 'package:denial_shell_kit/detached_run.dart';
import 'package:denial_shell_kit/kit_motion.dart';
import 'package:denial_shell_kit/kit_settings.dart';
import 'package:denial_shell_kit/kit_store.dart';
import 'package:denial_shell_kit/kit_style.dart';
import 'package:denial_shell_kit/kit_widgets.dart';
import 'package:flutter/material.dart'
    show InputBorder, InputDecoration, Material, MaterialType, TextField;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bar_icons.dart';
import '../bar_type.dart';
import '../island/island_timer.dart';
import '../l10n.dart';
import '../media_art.dart';
import '../night_light.dart';
import 'calendar_widget.dart';
import 'mac_kit.dart';
import 'nc_parts.dart';
import 'popovers.dart';
import 'tile_grid.dart';
import 'weather_widget.dart';
import 'world_clock_card.dart';

bool _customLoaded = false;

/// Ensures custom widgets stored in `denial_shell_kit.json` are loaded into
/// [kitWidgetRegistry] once per session without firing build-time listeners.
void ensureCustomWidgetsLoaded() {
  if (_customLoaded) return;
  _customLoaded = true;
  kitWidgetRegistry.loadCustomJson(
    kitStore.read()['customWidgets'],
    notify: false,
  );
}

/// Persists the current custom widgets from [kitWidgetRegistry] to `kitStore`.
void persistCustomWidgets() {
  kitStore.put('customWidgets', kitWidgetRegistry.exportCustomJson());
}

/// Whether the Clock widget draws a digital face instead of analog hands.
final ValueNotifier<bool> widgetClockDigital = ValueNotifier<bool>(
  kitStore.read()['widgetClockDigital'] == true,
);

void setWidgetClockDigital(bool digital) {
  widgetClockDigital.value = digital;
  kitStore.put('widgetClockDigital', digital);
}

IconData widgetIconFor(String id) => switch (id) {
  'calendar' || 'date' => BarIcons.calendar,
  'worldclock' => BarIcons.globe,
  'weather' => BarIcons.sunMaxFill,
  'clock' => BarIcons.clock,
  'battery' => BarIcons.batteryFull,
  'cpu' => BarIcons.cpu,
  'media' => BarIcons.playFill,
  'timer' => BarIcons.timer,
  'reminders' => BarIcons.checkmark,
  'quickactions' => BarIcons.squareGrid,
  _ => BarIcons.doc,
};

/// The key a widget's chosen size is stored under.
String widgetSizeKey(String id) => 'w.$id';

List<TileSize> widgetSupportedTileSizes(String id) {
  ensureCustomWidgetsLoaded();
  final spec = kitWidgetRegistry.byId(id);
  if (spec == null) return const <TileSize>[];
  return <TileSize>[for (final s in spec.supportedSizes) TileSize(s.w, s.h)];
}

bool widgetResizable(String id) => widgetSupportedTileSizes(id).length > 1;

KitWidgetSize? resolveWidgetSize(String id, Map<String, TileSize> stored) {
  ensureCustomWidgetsLoaded();
  final spec = kitWidgetRegistry.byId(id);
  if (spec == null) return null;
  final saved = stored[widgetSizeKey(id)];
  if (saved == null) return spec.defaultSize;
  return spec.clampSize(saved.w, saved.h);
}

TileSize? widgetTileSize(String id, Map<String, TileSize> stored) {
  final sz = resolveWidgetSize(id, stored);
  return sz == null ? null : TileSize(sz.w, sz.h);
}

/// The colour of a widget's card when [KitWidgetStyle.color] is active; under
/// [KitWidgetStyle.glass] returns null so every widget renders with unified
/// [KitGlass] responding to all five [KitSurfaceMode]s.
Color? widgetPlate(
  String id,
  ShellThemeData theme, {
  KitWidgetStyle style = KitWidgetStyle.glass,
}) {
  if (style == KitWidgetStyle.glass) return null;
  ensureCustomWidgetsLoaded();
  final spec = kitWidgetRegistry.byId(id);
  if (spec?.custom?.accentRgb != null) {
    return Color(0xff000000 | spec!.custom!.accentRgb!);
  }
  return switch (id) {
    'calendar' || 'date' => NcLook.paper(theme),
    'worldclock' => NcLook.night,
    'weather' => const Color(0xff1e66b8),
    _ => null,
  };
}

/// Builds a widget for a grid whose cells are [cell] on a side.
Widget buildBarWidget(
  String id,
  ShellServices services,
  double cell, {
  required KitWidgetSize size,
  KitWidgetStyle widgetStyle = KitWidgetStyle.glass,
  VoidCallback? onClosePanel,
}) {
  ensureCustomWidgetsLoaded();
  final spec = kitWidgetRegistry.byId(id);
  if (spec?.custom != null) {
    return _CustomWidgetCard(
      def: spec!.custom!,
      size: size,
      onClosePanel: onClosePanel,
    );
  }
  return switch (id) {
    'calendar' => CalendarWidget(size: size),
    'date' => const CalendarWidget(size: KitWidgetSize.small),
    'worldclock' => WorldClockCard(
      size: size,
      glass: widgetStyle == KitWidgetStyle.glass,
    ),
    'weather' => WeatherWidget(
      size: size,
      glass: widgetStyle == KitWidgetStyle.glass,
    ),
    'clock' => _ClockWidget(size: size),
    'battery' => _BatteryWidget(services: services, size: size),
    'cpu' => _SystemWidget(services: services, size: size),
    'media' => _MediaWidget(
      services: services,
      art: size == KitWidgetSize.large ? cell * 0.72 : cell - 28,
      size: size,
    ),
    'timer' => _TimerWidget(size: size),
    'reminders' => _RemindersWidget(size: size),
    'quickactions' => _QuickActionsWidget(
      size: size,
      onClosePanel: onClosePanel,
    ),
    _ => const SizedBox.shrink(),
  };
}

// ── Clock Widget (S / M / L + Analog/Digital toggle) ──

class _ClockWidget extends StatefulWidget {
  const _ClockWidget({required this.size});

  final KitWidgetSize size;

  @override
  State<_ClockWidget> createState() => _ClockWidgetState();
}

class _ClockWidgetState extends State<_ClockWidget> {
  late final Timer _tick = Timer.periodic(
    const Duration(seconds: 1),
    (_) => setState(() {}),
  );

  @override
  void initState() {
    super.initState();
    _tick;
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  String _two(int v) => v.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final now = DateTime.now();
    return ValueListenableBuilder<bool>(
      valueListenable: widgetClockDigital,
      builder: (context, digital, _) {
        final face = RepaintBoundary(
          child: CustomPaint(
            painter: _ClockPainter(
              now: now,
              ink: theme.colors.textPrimary,
              dim: theme.colors.textSecondary,
            ),
            child: const SizedBox.expand(),
          ),
        );
        if (widget.size == KitWidgetSize.small) {
          if (digital) {
            return GestureDetector(
              onDoubleTap: () => setWidgetClockDigital(false),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      localizedWeekday(context.l10n, now.weekday).toUpperCase(),
                      maxLines: 1,
                      style: BarType.section.copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: calendarRed,
                      ),
                    ),
                    const Spacer(),
                    _Fit(
                      child: Text(
                        '${_two(now.hour)}:${_two(now.minute)}',
                        style: BarType.display.copyWith(
                          fontSize: 40,
                          height: 1.05,
                          fontWeight: FontWeight.w300,
                          letterSpacing: -1.5,
                          color: theme.colors.textPrimary,
                          fontFeatures: const <FontFeature>[
                            FontFeature.tabularFigures(),
                          ],
                        ),
                      ),
                    ),
                    Text(
                      ':${_two(now.second)} · ${now.timeZoneName}',
                      style: BarType.caption.copyWith(
                        fontSize: 11,
                        color: theme.colors.textSecondary,
                        fontFeatures: const <FontFeature>[
                          FontFeature.tabularFigures(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
          return GestureDetector(
            onDoubleTap: () => setWidgetClockDigital(true),
            child: Padding(padding: const EdgeInsets.all(12), child: face),
          );
        }

        if (widget.size == KitWidgetSize.large) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: <Widget>[
                Expanded(
                  flex: 3,
                  child: Center(child: AspectRatio(aspectRatio: 1, child: face)),
                ),
                const SizedBox(height: 12),
                Text(
                  '${_two(now.hour)}:${_two(now.minute)}:${_two(now.second)}',
                  style: BarType.display.copyWith(
                    fontSize: 32,
                    fontWeight: FontWeight.w300,
                    letterSpacing: -1,
                    color: theme.colors.textPrimary,
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${localizedWeekday(context.l10n, now.weekday)} · ${localizedMonth(context.l10n, now.month)} ${now.day} · ${now.timeZoneName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: BarType.caption.copyWith(
                    fontSize: 12,
                    color: theme.colors.textSecondary,
                  ),
                ),
              ],
            ),
          );
        }

        // Medium (2×1)
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
          child: Row(
            children: <Widget>[
              AspectRatio(aspectRatio: 1, child: face),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _Fit(
                      child: Text(
                        localizedWeekday(context.l10n, now.weekday)
                            .toUpperCase(),
                        maxLines: 1,
                        style: BarType.section.copyWith(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: calendarRed,
                        ),
                      ),
                    ),
                    _Fit(
                      child: Text(
                        '${_two(now.hour)}:${_two(now.minute)}',
                        style: BarType.display.copyWith(
                          fontSize: 40,
                          height: 1.15,
                          fontWeight: FontWeight.w300,
                          letterSpacing: -1,
                          color: theme.colors.textPrimary,
                          fontFeatures: const <FontFeature>[
                            FontFeature.tabularFigures(),
                          ],
                        ),
                      ),
                    ),
                    Text(
                      '${localizedMonth(context.l10n, now.month)} ${now.day} · ${now.timeZoneName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: BarType.caption.copyWith(
                        fontSize: 12,
                        color: theme.colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ClockPainter extends CustomPainter {
  const _ClockPainter({
    required this.now,
    required this.ink,
    required this.dim,
  });

  final DateTime now;
  final Color ink;
  final Color dim;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    canvas.drawCircle(c, r, Paint()..color = ink.withValues(alpha: 0.07));
    Offset at(double turns, double length) =>
        c +
        Offset(math.sin(turns * 2 * math.pi), -math.cos(turns * 2 * math.pi)) *
            length;
    for (var i = 0; i < 60; i++) {
      final hour = i % 5 == 0;
      canvas.drawLine(
        at(i / 60, r * (hour ? 0.84 : 0.90)),
        at(i / 60, r * 0.94),
        Paint()
          ..color = hour ? ink : dim.withValues(alpha: 0.5)
          ..strokeWidth = hour ? 1.6 : 0.8
          ..strokeCap = StrokeCap.round,
      );
    }
    void hand(double turns, double length, double width, Color colour) =>
        canvas.drawLine(
          at(turns, -r * 0.1),
          at(turns, r * length),
          Paint()
            ..color = colour
            ..strokeWidth = width
            ..strokeCap = StrokeCap.round,
        );
    final minutes = now.minute + now.second / 60;
    hand((now.hour % 12 + minutes / 60) / 12, 0.48, 4, ink);
    hand(minutes / 60, 0.72, 3, ink);
    hand(now.second / 60, 0.78, 1.2, macOrange);
    canvas.drawCircle(c, 2.6, Paint()..color = macOrange);
  }

  @override
  bool shouldRepaint(_ClockPainter old) =>
      old.now.second != now.second ||
      old.now.minute != now.minute ||
      old.now.hour != now.hour ||
      old.ink != ink ||
      old.dim != dim;
}

// ── Shared Ring & Gauge ──

class _Ring extends StatelessWidget {
  const _Ring({
    required this.level,
    required this.colour,
    required this.child,
    this.stroke = 7.0,
  });

  final double level;
  final Color colour;
  final double stroke;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: level.clamp(0.0, 1.0)),
      duration: KitMotion.duration(context, KitMotion.fillSlow),
      curve: KitMotion.outCubic,
      builder: (context, value, child) => CustomPaint(
        painter: _RingPainter(
          level: value,
          colour: colour,
          stroke: stroke,
          track: context.shellTheme.colors.textPrimary.withValues(alpha: 0.12),
        ),
        child: child,
      ),
      child: Center(child: child),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.level,
    required this.colour,
    required this.track,
    required this.stroke,
  });

  final double level;
  final Color colour;
  final Color track;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: size.shortestSide / 2 - stroke / 2,
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, 2 * math.pi, false, paint..color = track);
    if (level > 0) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        2 * math.pi * level,
        false,
        paint..color = colour,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.level != level || old.colour != colour || old.track != track;
}

class _Gauge extends StatelessWidget {
  const _Gauge({
    required this.level,
    required this.colour,
    required this.icon,
    required this.value,
    required this.caption,
    this.wide = false,
    this.lines = const <String>[],
    this.extra,
  });

  final bool wide;
  final List<String> lines;
  final Widget? extra;
  final double level;
  final Color colour;
  final IconData icon;
  final String value;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    if (wide) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 88,
              height: 88,
              child: _Ring(
                level: level,
                colour: colour,
                child: BarGlyph(
                  icon,
                  size: 26,
                  color: theme.colors.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _Fit(
                    child: Text(
                      value,
                      style: BarType.display.copyWith(
                        fontSize: 32,
                        height: 1.1,
                        fontWeight: FontWeight.w500,
                        color: theme.colors.textPrimary,
                        fontFeatures: const <FontFeature>[
                          FontFeature.tabularFigures(),
                        ],
                      ),
                    ),
                  ),
                  for (final line in <String>[caption, ...lines])
                    Text(
                      line,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: BarType.caption.copyWith(
                        fontSize: 12,
                        height: 1.35,
                        color: theme.colors.textSecondary,
                      ),
                    ),
                  if (extra != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: SizedBox(height: 30, child: extra),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 56,
            height: 56,
            child: _Ring(
              level: level,
              colour: colour,
              child: BarGlyph(icon, size: 20, color: theme.colors.textPrimary),
            ),
          ),
          const Spacer(),
          _Fit(
            child: Text(
              value,
              style: BarType.display.copyWith(
                fontSize: 28,
                height: 1.1,
                fontWeight: FontWeight.w500,
                color: theme.colors.textPrimary,
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          ),
          Text(
            caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: BarType.caption.copyWith(
              fontSize: 12,
              color: theme.colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Battery Widget (S / M / L — host + UPower peripherals + Energy Mode) ──

class _BatteryWidget extends ConsumerWidget {
  const _BatteryWidget({required this.services, required this.size});

  final ShellServices services;
  final KitWidgetSize size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.shellTheme;
    final style = KitStyle.of(context);
    final battery = ref.watch(services.battery);
    final upower = ref.watch(upowerProvider).snapshot;
    final plugged = battery.charging || (upower?.onBattery == false);
    final capacity = battery.capacity;
    final cells = upower?.batteries ?? const [];

    if (size == KitWidgetSize.small) {
      return _Gauge(
        level: (capacity ?? 0) / 100,
        colour: capacity != null && capacity <= 20 && !plugged
            ? macRed
            : macGreen,
        icon: plugged ? BarIcons.boltFill : BarIcons.batteryFull,
        value: capacity == null ? '--' : '$capacity%',
        caption: context.tr(plugged ? 'Charging' : 'On Battery'),
      );
    }

    if (size == KitWidgetSize.large) {
      final power = ref.watch(desktopPowerModesProvider);
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                BarGlyph(
                  plugged ? BarIcons.boltFill : BarIcons.batteryFull,
                  size: 16,
                  color: macGreen,
                ),
                const SizedBox(width: 6),
                Text(
                  context.tr('Battery'),
                  style: BarType.title.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: theme.colors.textPrimary,
                  ),
                ),
                const Spacer(),
                Text(
                  capacity == null ? '--' : '$capacity%',
                  style: BarType.title.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: theme.colors.textPrimary,
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: <Widget>[
                  if (cells.isEmpty)
                    _BatteryDeviceRow(
                      name: context.tr('This Device'),
                      pct: capacity ?? 0,
                      charging: plugged,
                    )
                  else
                    for (final dev in cells.take(4))
                      _BatteryDeviceRow(
                        name: dev.displayName.isEmpty
                            ? context.tr('This Device')
                            : dev.displayName,
                        pct: (dev.percentage ?? capacity ?? 0).round(),
                        charging: dev.state.name == 'charging',
                        detail: dev.energyRate != null && dev.energyRate! > 0
                            ? '${dev.energyRate!.toStringAsFixed(1)} W'
                            : null,
                      ),
                ],
              ),
            ),
            if (power.systemAvailable) ...<Widget>[
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  for (final (profile, label) in const <(String, String)>[
                    ('power-save', 'Low Power'),
                    ('balanced', 'Automatic'),
                    ('performance', 'High Power'),
                  ]) ...<Widget>[
                    if (profile != 'power-save') const SizedBox(width: 6),
                    Expanded(
                      child: Pressable(
                        onTap: () => ref
                            .read(desktopPowerModesProvider.notifier)
                            .selectSystemProfile(profile),
                        scale: Pressable.small,
                        wash: true,
                        shape: BorderRadius.circular(style.pill(28)),
                        child: Container(
                          height: 28,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(style.pill(28)),
                            color: power.systemProfile == profile
                                ? style.accent(theme)
                                : theme.colors.textPrimary.withValues(
                                    alpha: 0.08,
                                  ),
                          ),
                          child: Text(
                            context.tr(label),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: BarType.caption.copyWith(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: power.systemProfile == profile
                                  ? style.onAccent(theme)
                                  : theme.colors.textPrimary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      );
    }

    // Medium (2×1): if multiple batteries exist, show macOS multi-ring grid;
    // otherwise show host gauge + time remaining & wattage.
    if (cells.length > 1) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: <Widget>[
            for (final dev in cells.take(4))
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    SizedBox(
                      width: 56,
                      height: 56,
                      child: _Ring(
                        level: (dev.percentage ?? 0) / 100,
                        stroke: 5.5,
                        colour: (dev.percentage ?? 100) <= 20 ? macRed : macGreen,
                        child: Text(
                          '${(dev.percentage ?? 0).round()}%',
                          style: BarType.caption.copyWith(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: theme.colors.textPrimary,
                            fontFeatures: const <FontFeature>[
                              FontFeature.tabularFigures(),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      dev.displayName.isEmpty
                          ? context.tr('Battery')
                          : dev.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: BarType.caption.copyWith(
                        fontSize: 11,
                        color: theme.colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
    }

    final cell = cells.firstOrNull;
    final left = plugged ? cell?.timeToFull : cell?.timeToEmpty;
    final rate = cell?.energyRate;
    return _Gauge(
      wide: true,
      lines: <String>[
        if (left != null && left > Duration.zero)
          context.tr(
            plugged ? '{} until full' : '{} remaining',
            _span(context, left),
          ),
        if (rate != null && rate > 0) '${rate.toStringAsFixed(1)} W',
      ],
      level: (capacity ?? 0) / 100,
      colour: capacity != null && capacity <= 20 && !plugged
          ? macRed
          : macGreen,
      icon: plugged ? BarIcons.boltFill : BarIcons.batteryFull,
      value: capacity == null ? '--' : '$capacity%',
      caption: context.tr(plugged ? 'Charging' : 'On Battery'),
    );
  }
}

class _BatteryDeviceRow extends StatelessWidget {
  const _BatteryDeviceRow({
    required this.name,
    required this.pct,
    required this.charging,
    this.detail,
  });

  final String name;
  final int pct;
  final bool charging;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colour = pct <= 20 && !charging ? macRed : macGreen;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: BarType.caption.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: theme.colors.textPrimary,
                  ),
                ),
              ),
              if (detail != null)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Text(
                    detail!,
                    style: BarType.caption.copyWith(
                      fontSize: 11,
                      color: theme.colors.textSecondary,
                    ),
                  ),
                ),
              Text(
                '$pct%',
                style: BarType.caption.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: theme.colors.textPrimary,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 6,
              child: Stack(
                children: <Widget>[
                  ColoredBox(
                    color: theme.colors.textPrimary.withValues(alpha: 0.12),
                    child: const SizedBox.expand(),
                  ),
                  FractionallySizedBox(
                    widthFactor: (pct / 100).clamp(0.0, 1.0),
                    child: ColoredBox(
                      color: colour,
                      child: const SizedBox.expand(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── System Monitor Widget (S / M / L — async cached /proc/meminfo & /proc/loadavg) ──

class _SysStats {
  const _SysStats({this.memRatio = 0, this.memText = '--', this.loadText = '--'});

  final double memRatio;
  final String memText;
  final String loadText;

  static _SysStats cached = const _SysStats();
  static DateTime _lastRead = DateTime.fromMillisecondsSinceEpoch(0);

  static Future<_SysStats> read() async {
    final now = DateTime.now();
    if (now.difference(_lastRead).inMilliseconds < 2500) return cached;
    _lastRead = now;
    double memRatio = 0;
    String memText = '--';
    String loadText = '--';
    try {
      final memLines = await File('/proc/meminfo').readAsLines();
      int totalKb = 0;
      int availKb = 0;
      for (final line in memLines) {
        if (line.startsWith('MemTotal:')) {
          totalKb = int.tryParse(line.split(RegExp(r'\s+'))[1]) ?? 0;
        } else if (line.startsWith('MemAvailable:')) {
          availKb = int.tryParse(line.split(RegExp(r'\s+'))[1]) ?? 0;
        }
      }
      if (totalKb > 0) {
        final usedKb = math.max(0, totalKb - availKb);
        memRatio = (usedKb / totalKb).clamp(0.0, 1.0);
        memText =
            '${(usedKb / 1048576).toStringAsFixed(1)}/${(totalKb / 1048576).toStringAsFixed(0)}G';
      }
    } catch (_) {}
    try {
      final raw = (await File('/proc/loadavg').readAsString()).trim();
      final parts = raw.split(' ');
      if (parts.length >= 2) loadText = '${parts[0]} · ${parts[1]}';
    } catch (_) {}
    return cached = _SysStats(
      memRatio: memRatio,
      memText: memText,
      loadText: loadText,
    );
  }
}

class _SystemWidget extends ConsumerStatefulWidget {
  const _SystemWidget({required this.services, required this.size});

  final ShellServices services;
  final KitWidgetSize size;

  @override
  ConsumerState<_SystemWidget> createState() => _SystemWidgetState();
}

class _SystemWidgetState extends ConsumerState<_SystemWidget> {
  _SysStats _stats = _SysStats.cached;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _poll();
    _tick = Timer.periodic(const Duration(seconds: 3), (_) => _poll());
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    final next = await _SysStats.read();
    if (mounted) setState(() => _stats = next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final style = KitStyle.of(context);
    final cpu = ref.watch(widget.services.cpu);
    final load = cpu.current;
    final temperature = cpu.temperatureC;
    final accent = style.accent(theme);
    final colour = (load ?? 0) > 0.8 ? macRed : accent;

    if (widget.size == KitWidgetSize.small) {
      return _Gauge(
        level: load ?? 0,
        colour: colour,
        icon: BarIcons.cpu,
        value: load == null ? '--' : '${(load * 100).round()}%',
        caption: temperature == null
            ? context.tr('Processor')
            : '${temperature.round()}°C',
      );
    }

    if (widget.size == KitWidgetSize.large) {
      Widget quad(String label, String val, double? pct, Color c) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: theme.colors.textPrimary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(style.corner(14)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              label,
              style: BarType.caption.copyWith(
                fontSize: 11,
                color: theme.colors.textSecondary,
              ),
            ),
            const Spacer(),
            _Fit(
              child: Text(
                val,
                style: BarType.title.copyWith(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: theme.colors.textPrimary,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ),
            if (pct != null) ...<Widget>[
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: SizedBox(
                  height: 4,
                  child: Stack(
                    children: <Widget>[
                      ColoredBox(
                        color: theme.colors.textPrimary.withValues(alpha: 0.12),
                        child: const SizedBox.expand(),
                      ),
                      FractionallySizedBox(
                        widthFactor: pct.clamp(0.0, 1.0),
                        child: ColoredBox(
                          color: c,
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      );
      return Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                BarGlyph(BarIcons.cpu, size: 15, color: accent),
                const SizedBox(width: 6),
                Text(
                  context.tr('System Monitor'),
                  style: BarType.title.copyWith(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: theme.colors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: quad(
                      context.tr('Processor'),
                      load == null ? '--' : '${(load * 100).round()}%',
                      load ?? 0,
                      colour,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: quad(
                      context.tr('Memory'),
                      _stats.memText,
                      _stats.memRatio,
                      macPurple,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: quad(
                      context.tr('Temperature'),
                      temperature == null ? '--' : '${temperature.round()}°C',
                      temperature == null ? null : (temperature / 100).clamp(0, 1),
                      (temperature ?? 0) > 75 ? macRed : macOrange,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: quad(
                      context.tr('Load'),
                      _stats.loadText,
                      null,
                      macGreen,
                    ),
                  ),
                ],
              ),
            ),
            if (cpu.history.length > 1) ...<Widget>[
              const SizedBox(height: 10),
              SizedBox(
                height: 36,
                child: CustomPaint(
                  painter: _SparkPainter(samples: cpu.history, colour: colour),
                  child: const SizedBox.expand(),
                ),
              ),
            ],
          ],
        ),
      );
    }

    // Medium (2×1)
    return _Gauge(
      wide: true,
      lines: <String>[
        '${context.tr('Memory')}: ${_stats.memText}',
      ],
      extra: cpu.history.length > 1
          ? CustomPaint(
              painter: _SparkPainter(samples: cpu.history, colour: colour),
              child: const SizedBox.expand(),
            )
          : null,
      level: load ?? 0,
      colour: colour,
      icon: BarIcons.cpu,
      value: load == null ? '--' : '${(load * 100).round()}%',
      caption: temperature == null
          ? context.tr('Processor')
          : '${context.tr('Processor')} · ${temperature.round()}°C',
    );
  }
}

// ── Media Widget (M / L + Audio Output switcher) ──

class _MediaWidget extends ConsumerWidget {
  const _MediaWidget({
    required this.services,
    required this.art,
    required this.size,
  });

  final ShellServices services;
  final double art;
  final KitWidgetSize size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.shellTheme;
    final style = KitStyle.of(context);
    final ink = theme.colors.textPrimary;
    final playback = ref.watch(services.media).value;
    final commands = ref.watch(services.mediaCommands);
    final has = playback != null && playback.title.isNotEmpty;

    Widget control(IconData icon, bool enabled, VoidCallback onTap, double s) =>
        Pressable(
          onTap: enabled ? onTap : null,
          scale: 0.82,
          wash: true,
          darken: true,
          shape: BorderRadius.circular(style.pill(36)),
          child: SizedBox(
            width: 44,
            height: 36,
            child: BarGlyph(
              icon,
              size: s,
              color: ink.withValues(alpha: enabled ? 1 : 0.3),
            ),
          ),
        );

    if (size == KitWidgetSize.large) {
      final devices = ref
          .watch(audioDevicesProvider)
          .devices
          .where((d) => d.available || d.active)
          .toList();
      final activeOut = devices.where((d) => d.active).firstOrNull;
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(
              child: Row(
                children: <Widget>[
                  MediaArtwork(
                    url: playback?.artUrl ?? '',
                    size: art,
                    radius: style.corner(16),
                    fallback: Container(
                      width: art,
                      height: art,
                      decoration: BoxDecoration(
                        color: ink.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(style.corner(16)),
                      ),
                      child: BarGlyph(
                        BarIcons.playFill,
                        size: 38,
                        color: theme.colors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          has ? playback.title : context.tr('Not Playing'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: BarType.title.copyWith(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: has ? ink : theme.colors.textSecondary,
                          ),
                        ),
                        if (has && playback.artistLabel.isNotEmpty) ...<Widget>[
                          const SizedBox(height: 4),
                          Text(
                            playback.artistLabel,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: BarType.menuRow.copyWith(
                              color: theme.colors.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: <Widget>[
                control(
                  BarIcons.backward,
                  playback?.canGoPrevious ?? false,
                  commands.previous,
                  22,
                ),
                control(
                  playback?.playing == true
                      ? BarIcons.pauseFill
                      : BarIcons.playFill,
                  playback?.available ?? false,
                  commands.playPause,
                  30,
                ),
                control(
                  BarIcons.forward,
                  playback?.canGoNext ?? false,
                  commands.next,
                  22,
                ),
              ],
            ),
            if (devices.isNotEmpty) ...<Widget>[
              const SizedBox(height: 10),
              Pressable(
                onTap: devices.length <= 1
                    ? null
                    : () {
                        final idx = devices.indexWhere((d) => d.active);
                        final next = devices[(idx + 1) % devices.length];
                        ref
                            .read(audioDevicesProvider.notifier)
                            .select(next.name);
                      },
                scale: Pressable.large,
                wash: true,
                shape: BorderRadius.circular(style.pill(30)),
                child: Container(
                  height: 30,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: ink.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(style.pill(30)),
                  ),
                  child: Row(
                    children: <Widget>[
                      BarGlyph(
                        activeOut != null
                            ? outputDeviceIcon(activeOut)
                            : BarIcons.speaker3Fill,
                        size: 13,
                        color: style.accent(theme),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          activeOut?.description.isNotEmpty == true
                              ? activeOut!.description
                              : (activeOut?.name ?? context.tr('Output')),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: BarType.caption.copyWith(
                            fontSize: 11.5,
                            color: ink,
                          ),
                        ),
                      ),
                      if (devices.length > 1)
                        BarGlyph(
                          BarIcons.chevronRight,
                          size: 10,
                          color: theme.colors.textSecondary,
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: <Widget>[
          MediaArtwork(
            url: playback?.artUrl ?? '',
            size: art,
            radius: style.corner(14),
            fallback: Container(
              width: art,
              height: art,
              decoration: BoxDecoration(
                color: ink.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(style.corner(14)),
              ),
              child: BarGlyph(
                BarIcons.playFill,
                size: 34,
                color: theme.colors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const SizedBox(height: 4),
                Text(
                  has ? playback.title : context.tr('Not Playing'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: BarType.title.copyWith(
                    fontSize: 15,
                    color: has ? ink : theme.colors.textSecondary,
                  ),
                ),
                if (has && playback.artistLabel.isNotEmpty)
                  Text(
                    playback.artistLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: BarType.menuRow.copyWith(
                      color: theme.colors.textSecondary,
                    ),
                  ),
                const Spacer(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    control(
                      BarIcons.backward,
                      playback?.canGoPrevious ?? false,
                      commands.previous,
                      20,
                    ),
                    control(
                      playback?.playing == true
                          ? BarIcons.pauseFill
                          : BarIcons.playFill,
                      playback?.available ?? false,
                      commands.playPause,
                      27,
                    ),
                    control(
                      BarIcons.forward,
                      playback?.canGoNext ?? false,
                      commands.next,
                      20,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Timer Widget (S / M — synced with Dynamic Island islandTimer) ──

class _TimerWidget extends StatefulWidget {
  const _TimerWidget({required this.size});

  final KitWidgetSize size;

  @override
  State<_TimerWidget> createState() => _TimerWidgetState();
}

class _TimerWidgetState extends State<_TimerWidget> {
  Timer? _tick;

  void _syncTimer() {
    final running = islandTimer.active && !islandTimer.paused;
    if (running && _tick == null) {
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!running && _tick != null) {
      _tick?.cancel();
      _tick = null;
    }
  }

  void _changed() {
    _syncTimer();
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _syncTimer();
    islandTimer.addListener(_changed);
  }

  @override
  void dispose() {
    _tick?.cancel();
    islandTimer.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final style = KitStyle.of(context);
    final now = DateTime.now();
    final active = islandTimer.active;
    final paused = islandTimer.paused;
    final rem = islandTimer.remaining(now);
    final total = islandTimer.total.inSeconds;
    final progress = active && total > 0
        ? (rem.inSeconds / total).clamp(0.0, 1.0)
        : 0.0;

    if (widget.size == KitWidgetSize.small) {
      return Pressable(
        onTap: () => active
            ? islandTimer.toggle(now)
            : islandTimer.start(const Duration(minutes: 5), now),
        scale: Pressable.large,
        wash: true,
        child: _Gauge(
          level: progress,
          colour: macOrange,
          icon: active && !paused ? BarIcons.pauseFill : BarIcons.timer,
          value: active ? clockSpan(rem) : '5:00',
          caption: context.tr(
            active ? (paused ? 'Paused' : 'Running') : 'Tap for 5m',
          ),
        ),
      );
    }

    Widget pill(String label, VoidCallback onTap, {bool primary = false}) =>
        Pressable(
          onTap: onTap,
          scale: Pressable.small,
          wash: true,
          shape: BorderRadius.circular(style.pill(28)),
          child: Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(style.pill(28)),
              color: primary
                  ? style.plate(theme, macOrange)
                  : theme.colors.textPrimary.withValues(alpha: 0.09),
            ),
            child: Text(
              label,
              style: BarType.caption.copyWith(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: primary
                    ? style.onPlate(theme)
                    : theme.colors.textPrimary,
              ),
            ),
          ),
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              BarGlyph(BarIcons.timer, size: 15, color: macOrange),
              const SizedBox(width: 6),
              Text(
                context.tr('Timer'),
                style: BarType.section.copyWith(
                  color: theme.colors.textSecondary,
                ),
              ),
              const Spacer(),
              if (active)
                pill(
                  context.tr(paused ? 'Resume' : 'Pause'),
                  () => islandTimer.toggle(now),
                  primary: true,
                ),
              if (active) ...<Widget>[
                const SizedBox(width: 6),
                pill(context.tr('Cancel'), islandTimer.cancel),
              ],
            ],
          ),
          const Spacer(),
          Text(
            active ? clockSpan(rem) : '0:00',
            style: BarType.display.copyWith(
              fontSize: 34,
              height: 1.05,
              fontWeight: FontWeight.w400,
              color: active ? macOrange : theme.colors.textPrimary,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              for (final mins in const <int>[1, 5, 10, 15]) ...<Widget>[
                if (mins != 1) const SizedBox(width: 6),
                Expanded(
                  child: pill(
                    context.tr('{}m', mins),
                    () => islandTimer.start(Duration(minutes: mins), now),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ── Reminders / Todo Widget (M / L — persisted in kitStore) ──

class _TodoItem {
  const _TodoItem({required this.text, this.done = false});

  final String text;
  final bool done;

  Map<String, Object?> toJson() => <String, Object?>{'t': text, 'd': done};
}

class _RemindersWidget extends StatefulWidget {
  const _RemindersWidget({required this.size});

  final KitWidgetSize size;

  @override
  State<_RemindersWidget> createState() => _RemindersWidgetState();
}

class _RemindersWidgetState extends State<_RemindersWidget> {
  List<_TodoItem> _items = const <_TodoItem>[];
  bool _adding = false;
  int? _editingIndex;
  final TextEditingController _input = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _load() {
    final raw = kitStore.read()['widgetReminders'];
    if (raw is List) {
      _items = <_TodoItem>[
        for (final entry in raw)
          if (entry is Map && entry['t'] is String)
            _TodoItem(text: entry['t'] as String, done: entry['d'] == true),
      ];
    }
  }

  void _save(List<_TodoItem> next) {
    setState(() => _items = next);
    kitStore.put('widgetReminders', <Map<String, Object?>>[
      for (final item in next) item.toJson(),
    ]);
  }

  void _commitInput() {
    final text = _input.text.trim();
    final editIdx = _editingIndex;
    _input.clear();
    setState(() {
      _adding = false;
      _editingIndex = null;
    });
    if (text.isEmpty) return;
    if (editIdx != null && editIdx >= 0 && editIdx < _items.length) {
      final copy = List<_TodoItem>.of(_items);
      copy[editIdx] = _TodoItem(text: text, done: copy[editIdx].done);
      _save(copy);
    } else {
      _save(<_TodoItem>[_TodoItem(text: text), ..._items]);
    }
  }

  void _startEdit(int index) {
    _input.text = _items[index].text;
    setState(() {
      _editingIndex = index;
      _adding = true;
    });
  }

  void _deleteAt(int index) {
    final copy = List<_TodoItem>.of(_items)..removeAt(index);
    if (_editingIndex == index) {
      _editingIndex = null;
      _adding = false;
      _input.clear();
    }
    _save(copy);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final style = KitStyle.of(context);
    final accent = style.accent(theme);
    final pendingCount = _items.where((e) => !e.done).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              BarGlyph(BarIcons.checkmark, size: 14, color: accent),
              const SizedBox(width: 6),
              Text(
                context.tr('Reminders'),
                style: BarType.title.copyWith(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: theme.colors.textPrimary,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '$pendingCount',
                style: BarType.caption.copyWith(
                  fontSize: 12,
                  color: theme.colors.textSecondary,
                ),
              ),
              const Spacer(),
              if (_items.any((e) => e.done))
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Pressable(
                    onTap: () => _save(
                      <_TodoItem>[
                        for (final item in _items)
                          if (!item.done) item,
                      ],
                    ),
                    scale: Pressable.small,
                    wash: true,
                    child: Text(
                      context.tr('Clear'),
                      style: BarType.caption.copyWith(
                        fontSize: 11,
                        color: theme.colors.textSecondary,
                      ),
                    ),
                  ),
                ),
              Pressable(
                onTap: () {
                  setState(() {
                    _adding = !_adding;
                    _editingIndex = null;
                    if (!_adding) _input.clear();
                  });
                },
                scale: Pressable.small,
                wash: true,
                shape: style.disc(22),
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    borderRadius: style.disc(22),
                    color: accent.withValues(alpha: 0.18),
                  ),
                  child: BarGlyph(
                    _adding ? BarIcons.xmark : BarIcons.plus,
                    size: 11,
                    color: accent,
                  ),
                ),
              ),
            ],
          ),
          if (_adding)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Container(
                height: 30,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: theme.colors.textPrimary.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(style.corner(8)),
                ),
                child: Material(
                  type: MaterialType.transparency,
                  child: TextField(
                    controller: _input,
                    autofocus: true,
                    style: BarType.caption.copyWith(
                      fontSize: 12,
                      color: theme.colors.textPrimary,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: context.tr('New reminder…'),
                      hintStyle: BarType.caption.copyWith(
                        fontSize: 12,
                        color: theme.colors.textTertiary,
                      ),
                    ),
                    onSubmitted: (_) => _commitInput(),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 8),
          Expanded(
            child: _items.isEmpty
                ? Center(
                    child: Text(
                      context.tr('No reminders'),
                      style: BarType.caption.copyWith(
                        color: theme.colors.textTertiary,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: _items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final item = _items[index];
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          final copy = List<_TodoItem>.of(_items);
                          copy[index] = _TodoItem(
                            text: item.text,
                            done: !item.done,
                          );
                          _save(copy);
                        },
                        child: Row(
                          children: <Widget>[
                            Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                borderRadius: style.disc(16),
                                color: item.done ? accent : null,
                                border: Border.all(
                                  color: item.done
                                      ? accent
                                      : theme.colors.textSecondary,
                                  width: 1.5,
                                ),
                              ),
                              child: item.done
                                  ? BarGlyph(
                                      BarIcons.checkmark,
                                      size: 10,
                                      color: style.onAccent(theme),
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: GestureDetector(
                                onDoubleTap: () => _startEdit(index),
                                child: Text(
                                  item.text,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: BarType.caption.copyWith(
                                    fontSize: 12.5,
                                    decoration: item.done
                                        ? TextDecoration.lineThrough
                                        : null,
                                    color: item.done
                                        ? theme.colors.textTertiary
                                        : theme.colors.textPrimary,
                                  ),
                                ),
                              ),
                            ),
                            Pressable(
                              onTap: () => _startEdit(index),
                              scale: Pressable.small,
                              wash: true,
                              shape: BorderRadius.circular(6),
                              child: Padding(
                                padding: const EdgeInsets.all(3),
                                child: BarGlyph(
                                  BarIcons.gear,
                                  size: 11,
                                  color: theme.colors.textTertiary,
                                ),
                              ),
                            ),
                            Pressable(
                              onTap: () => _deleteAt(index),
                              scale: Pressable.small,
                              wash: true,
                              shape: BorderRadius.circular(6),
                              child: Padding(
                                padding: const EdgeInsets.all(3),
                                child: BarGlyph(
                                  BarIcons.xmark,
                                  size: 10,
                                  color: theme.colors.textTertiary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Quick Actions Widget (S / M) ──

class _QuickActionsWidget extends ConsumerWidget {
  const _QuickActionsWidget({required this.size, this.onClosePanel});

  final KitWidgetSize size;
  final VoidCallback? onClosePanel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.shellTheme;
    final style = KitStyle.of(context);
    final dark = ref.watch(shellSettingsProvider.select(kitSystemIsDark));

    Widget btn(
      IconData icon,
      String label,
      bool on,
      Color colour,
      VoidCallback onTap,
    ) => Pressable(
      onTap: onTap,
      scale: Pressable.small,
      wash: true,
      shape: BorderRadius.circular(style.corner(12)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(style.corner(12)),
          color: on
              ? style.plate(theme, colour)
              : theme.colors.textPrimary.withValues(alpha: 0.08),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            BarGlyph(
              icon,
              size: size == KitWidgetSize.small ? 18 : 16,
              color: on ? style.onPlate(theme) : theme.colors.textPrimary,
            ),
            if (size != KitWidgetSize.small) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: BarType.caption.copyWith(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: on ? style.onPlate(theme) : theme.colors.textPrimary,
                ),
              ),
            ],
          ],
        ),
      ),
    );

    return ValueListenableBuilder<bool>(
      valueListenable: NightLight.enabled,
      builder: (context, night, _) {
        final actions = <Widget>[
          btn(
            BarIcons.circleHalf,
            context.tr('Dark Mode'),
            dark,
            const Color(0xff636366),
            () => setKitSystemDarkMode(ref, !dark),
          ),
          btn(
            night ? BarIcons.sunMaxFill : BarIcons.sunMax,
            context.tr('Night Light'),
            night,
            macOrange,
            NightLight.toggle,
          ),
          btn(
            BarIcons.camera,
            context.tr('Screenshot'),
            false,
            macBlue,
            () {
              onClosePanel?.call();
              ref.read(systemActionsServiceProvider).takeScreenshot();
            },
          ),
          btn(
            BarIcons.gear,
            context.tr('Settings'),
            false,
            macBlue,
            () {
              onClosePanel?.call();
              showKitSettings(ref: ref);
            },
          ),
        ];

        return Padding(
          padding: const EdgeInsets.all(10),
          child: size == KitWidgetSize.small
              ? Column(
                  children: <Widget>[
                    Expanded(
                      child: Row(
                        children: <Widget>[
                          Expanded(child: actions[0]),
                          const SizedBox(width: 6),
                          Expanded(child: actions[1]),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Expanded(
                      child: Row(
                        children: <Widget>[
                          Expanded(child: actions[2]),
                          const SizedBox(width: 6),
                          Expanded(child: actions[3]),
                        ],
                      ),
                    ),
                  ],
                )
              : Row(
                  children: <Widget>[
                    for (var i = 0; i < actions.length; i++) ...<Widget>[
                      if (i > 0) const SizedBox(width: 8),
                      Expanded(child: actions[i]),
                    ],
                  ],
                ),
        );
      },
    );
  }
}

// ── Extensible Custom Widget Card (Command / Shortcut / Note) ──

class _CustomWidgetCard extends StatefulWidget {
  const _CustomWidgetCard({
    required this.def,
    required this.size,
    this.onClosePanel,
  });

  final KitCustomWidgetDef def;
  final KitWidgetSize size;
  final VoidCallback? onClosePanel;

  @override
  State<_CustomWidgetCard> createState() => _CustomWidgetCardState();
}

class _CustomWidgetCardState extends State<_CustomWidgetCard> {
  static final Map<String, String> _outputCache = <String, String>{};
  static const Duration _commandTimeout = Duration(seconds: 3);
  static const int _commandMaxBytes = 16384;

  String _output = '';
  bool _failed = false;
  bool _running = false;
  int? _runningPid;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _output = _outputCache[widget.def.id] ?? '';
    _startIfCommand();
  }

  @override
  void didUpdateWidget(covariant _CustomWidgetCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.def.id != widget.def.id ||
        oldWidget.def.kind != widget.def.kind ||
        oldWidget.def.command != widget.def.command ||
        oldWidget.def.refreshSeconds != widget.def.refreshSeconds) {
      _tick?.cancel();
      _tick = null;
      _killRunning();
      _output = _outputCache[widget.def.id] ?? '';
      _failed = false;
      _startIfCommand();
    }
  }

  void _startIfCommand() {
    if (widget.def.kind == KitCustomWidgetKind.command &&
        widget.def.command.isNotEmpty) {
      _runCommand();
      final refresh = widget.def.refreshSeconds;
      if (refresh > 0) {
        _tick = Timer.periodic(
          Duration(seconds: math.max(5, refresh)),
          (_) => _runCommand(),
        );
      }
    }
  }

  void _killRunning() {
    final pid = _runningPid;
    _runningPid = null;
    if (pid == null) return;
    try {
      Process.killPid(pid, ProcessSignal.sigterm);
    } catch (_) {}
  }

  @override
  void dispose() {
    _tick?.cancel();
    _killRunning();
    super.dispose();
  }

  Future<void> _onTap() async {
    final def = widget.def;
    if (def.kind == KitCustomWidgetKind.shortcut) {
      if (def.command.isEmpty) return;
      await spawnDetachedFireAndForget('sh', <String>['-c', def.command]);
      widget.onClosePanel?.call();
      return;
    }
    if (def.kind == KitCustomWidgetKind.command) {
      await _runCommand();
    }
  }

  Future<void> _runCommand() async {
    if (widget.def.command.isEmpty || _running) return;
    _running = true;
    final id = widget.def.id;
    try {
      final res = await runDetached(
        'sh',
        <String>['-c', widget.def.command],
        timeout: _commandTimeout,
        maxOutputBytes: _commandMaxBytes,
        onStart: (pid) => _runningPid = pid,
      );
      _runningPid = null;
      if (!mounted || widget.def.id != id) return;
      if (res.exitCode == 124) {
        setState(() {
          _failed = true;
          _output = res.stdout.trim().isNotEmpty
              ? res.stdout.trim()
              : context.tr('Timed out');
        });
        return;
      }
      final text = res.stdout.trim();
      final ok = res.exitCode == 0;
      if (ok && text.isNotEmpty) {
        _outputCache[id] = text;
      }
      setState(() {
        _failed = !ok;
        _output = text.isNotEmpty
            ? text
            : (ok ? '' : 'exit ${res.exitCode}');
      });
    } catch (_) {
      _runningPid = null;
    } finally {
      _running = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final style = KitStyle.of(context);
    final accent = style.accent(theme);
    final def = widget.def;
    final bodyText = switch (def.kind) {
      KitCustomWidgetKind.command =>
        _output.isEmpty ? context.tr('Tap to run') : _output,
      KitCustomWidgetKind.shortcut =>
        def.subtitle.isNotEmpty ? def.subtitle : def.command,
      KitCustomWidgetKind.note =>
        def.noteText.isNotEmpty ? def.noteText : context.tr('Empty note'),
    };
    return Pressable(
      onTap: def.kind == KitCustomWidgetKind.note ? null : _onTap,
      scale: Pressable.large,
      wash: def.kind != KitCustomWidgetKind.note,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                BarGlyph(
                  def.kind == KitCustomWidgetKind.shortcut
                      ? BarIcons.playFill
                      : def.kind == KitCustomWidgetKind.command
                      ? BarIcons.cpu
                      : BarIcons.doc,
                  size: 14,
                  color: accent,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    def.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: BarType.title.copyWith(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: theme.colors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Text(
                bodyText,
                maxLines: widget.size == KitWidgetSize.large ? 8 : 4,
                overflow: TextOverflow.ellipsis,
                style: BarType.caption.copyWith(
                  fontSize: 12.5,
                  height: 1.35,
                  color: _failed
                      ? const Color(0xffff453a)
                      : theme.colors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _span(BuildContext context, Duration span) {
  final hours = span.inHours, minutes = span.inMinutes % 60;
  final short = context.tr('{} min', minutes);
  return hours > 0 ? '${context.tr('{} h', hours)} $short' : short;
}

class _SparkPainter extends CustomPainter {
  const _SparkPainter({required this.samples, required this.colour});

  final List<double> samples;
  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final step = size.width / (LoadSeries.capacity - 1);
    final start = size.width - step * (samples.length - 1);
    final line = Path();
    for (var i = 0; i < samples.length; i++) {
      final x = start + step * i;
      final y =
          size.height - 1 - samples[i].clamp(0.0, 1.0) * (size.height - 2);
      i == 0 ? line.moveTo(x, y) : line.lineTo(x, y);
    }
    final area = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(start, size.height)
      ..close();
    canvas
      ..drawPath(area, Paint()..color = colour.withValues(alpha: 0.18))
      ..drawPath(
        line,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..strokeJoin = StrokeJoin.round
          ..color = colour,
      );
  }

  @override
  bool shouldRepaint(_SparkPainter old) =>
      old.samples != samples || old.colour != colour;
}

class _Fit extends StatelessWidget {
  const _Fit({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    alignment: Alignment.centerLeft,
    child: child,
  );
}
