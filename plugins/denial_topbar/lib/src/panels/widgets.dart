import 'dart:async';
import 'dart:math' as math;

import 'package:denial_flutter_sdk/localization.dart';
import 'package:denial_flutter_sdk/services.dart';
import 'package:denial_flutter_sdk/state.dart';
import 'package:denial_flutter_sdk/theme.dart';
import 'package:denial_shell_kit/kit_motion.dart';
import 'package:denial_shell_kit/kit_style.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bar_icons.dart';
import '../bar_type.dart';
import '../l10n.dart';
import '../media_art.dart';
import 'calendar_widget.dart';
import 'mac_kit.dart';
import 'tile_grid.dart';
import 'world_clock_card.dart';

const double widgetGap = 10;
const double widgetCellHeight = 158;

const List<TileChoice> widgetLibrary = <TileChoice>[
  TileChoice(id: 'calendar', icon: BarIcons.calendar, label: 'Calendar'),
  TileChoice(id: 'worldclock', icon: BarIcons.globe, label: 'World Clock'),
  TileChoice(id: 'date', icon: BarIcons.calendar, label: 'Date'),
  TileChoice(id: 'clock', icon: BarIcons.clock, label: 'Clock'),
  TileChoice(id: 'battery', icon: BarIcons.batteryFull, label: 'Battery'),
  TileChoice(id: 'cpu', icon: BarIcons.cpu, label: 'Processor'),
  TileChoice(id: 'media', icon: BarIcons.playFill, label: 'Now Playing'),
];

/// Widgets that come in a small and a wide size.
bool widgetResizable(String id) =>
    id == 'clock' || id == 'battery' || id == 'cpu';

/// The key a widget's chosen size is stored under.
String widgetSizeKey(String id) => 'w.$id';

TileSize? widgetSize(String id, {bool wide = false}) => switch (id) {
  'calendar' || 'worldclock' || 'media' => const TileSize(2, 1),
  'clock' || 'battery' || 'cpu' => TileSize(wide ? 2 : 1, 1),
  'date' => const TileSize(1, 1),
  _ => null,
};

Widget buildBarWidget(
  String id,
  ShellServices services,
  double fullWidth, {
  bool wide = false,
}) => switch (id) {
  'calendar' => CalendarWidget(width: fullWidth, height: widgetCellHeight),
  'worldclock' => const WorldClockCard(),
  'date' => const _DateWidget(),
  'clock' => _ClockWidget(wide: wide),
  'battery' => _BatteryWidget(services: services, wide: wide),
  'cpu' => _CpuWidget(services: services, wide: wide),
  'media' => _MediaWidget(services: services),
  _ => const SizedBox.shrink(),
};

class _DateWidget extends ConsumerWidget {
  const _DateWidget();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.shellTheme;
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            localizedWeekday(context.l10n, now.weekday).toUpperCase(),
            maxLines: 1,
            style: BarType.section.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: calendarRed,
            ),
          ),
          Text(
            '${now.day}',
            style: BarType.display.copyWith(
              fontSize: 60,
              height: 1.05,
              fontWeight: FontWeight.w300,
              letterSpacing: -2,
              color: theme.colors.textPrimary,
            ),
          ),
          const Spacer(),
          Text(
            '${localizedMonth(context.l10n, now.month)} ${now.year}',
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

class _ClockWidget extends StatefulWidget {
  const _ClockWidget({this.wide = false});

  final bool wide;

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

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final now = DateTime.now();
    final face = CustomPaint(
      painter: _ClockPainter(
        now: now,
        ink: theme.colors.textPrimary,
        dim: theme.colors.textSecondary,
      ),
      child: const SizedBox.expand(),
    );
    if (!widget.wide) {
      return Padding(padding: const EdgeInsets.all(12), child: face);
    }
    String two(int value) => value.toString().padLeft(2, '0');
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
                Text(
                  localizedWeekday(context.l10n, now.weekday).toUpperCase(),
                  maxLines: 1,
                  style: BarType.section.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: calendarRed,
                  ),
                ),
                Text(
                  '${two(now.hour)}:${two(now.minute)}',
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
      old.now.second != now.second || old.ink != ink;
}

class _Ring extends StatelessWidget {
  const _Ring({required this.level, required this.colour, required this.child});

  final double level;
  final Color colour;
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
  });

  final double level;
  final Color colour;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 7.0;
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

  /// The wide size puts the figures beside the ring, with [lines] under them
  /// and [extra] filling what is left.
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
              width: 92,
              height: 92,
              child: _Ring(
                level: level,
                colour: colour,
                child: BarGlyph(
                  icon,
                  size: 28,
                  color: theme.colors.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    value,
                    style: BarType.display.copyWith(
                      fontSize: 34,
                      height: 1.1,
                      fontWeight: FontWeight.w500,
                      color: theme.colors.textPrimary,
                      fontFeatures: const <FontFeature>[
                        FontFeature.tabularFigures(),
                      ],
                    ),
                  ),
                  for (final line in <String>[caption, ...lines])
                    Text(
                      line,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: BarType.caption.copyWith(
                        fontSize: 12,
                        height: 1.4,
                        color: theme.colors.textSecondary,
                      ),
                    ),
                  if (extra != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: SizedBox(height: 34, child: extra),
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
            width: 58,
            height: 58,
            child: _Ring(
              level: level,
              colour: colour,
              child: BarGlyph(icon, size: 20, color: theme.colors.textPrimary),
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: BarType.display.copyWith(
              fontSize: 28,
              height: 1.1,
              fontWeight: FontWeight.w500,
              color: theme.colors.textPrimary,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
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

class _BatteryWidget extends ConsumerWidget {
  const _BatteryWidget({required this.services, this.wide = false});

  final ShellServices services;
  final bool wide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final battery = ref.watch(services.battery);
    final plugged =
        battery.charging ||
        ref.watch(
          upowerProvider.select((state) => state.snapshot?.onBattery == false),
        );
    final capacity = battery.capacity;
    final cell = wide
        ? ref.watch(
            upowerProvider.select(
              (state) => state.snapshot?.batteries.firstOrNull,
            ),
          )
        : null;
    final left = plugged ? cell?.timeToFull : cell?.timeToEmpty;
    final rate = cell?.energyRate;
    return _Gauge(
      wide: wide,
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

class _CpuWidget extends ConsumerWidget {
  const _CpuWidget({required this.services, this.wide = false});

  final ShellServices services;
  final bool wide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cpu = ref.watch(services.cpu);
    final load = cpu.current;
    final temperature = cpu.temperatureC;
    final colour = (load ?? 0) > 0.8
        ? macRed
        : KitStyle.of(context).accent(context.shellTheme);
    return _Gauge(
      wide: wide,
      extra: wide && cpu.history.length > 1
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

class _MediaWidget extends ConsumerWidget {
  const _MediaWidget({required this.services});

  final ShellServices services;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.shellTheme;
    final ink = theme.colors.textPrimary;
    final playback = ref.watch(services.media).value;
    final commands = ref.watch(services.mediaCommands);
    final has = playback != null && playback.title.isNotEmpty;

    Widget control(IconData icon, bool enabled, VoidCallback onTap, double s) =>
        Pressable(
          onTap: enabled ? onTap : null,
          scale: 0.82,
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

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: <Widget>[
          MediaArtwork(
            url: playback?.artUrl ?? '',
            size: widgetCellHeight - 28,
            radius: 14,
            fallback: Container(
              width: widgetCellHeight - 28,
              height: widgetCellHeight - 28,
              decoration: BoxDecoration(
                color: ink.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(14),
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

String _span(BuildContext context, Duration span) {
  final hours = span.inHours, minutes = span.inMinutes % 60;
  final short = context.tr('{} min', minutes);
  return hours > 0 ? '${context.tr('{} h', hours)} $short' : short;
}

/// The last minute and a half of load as a filled line.
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
