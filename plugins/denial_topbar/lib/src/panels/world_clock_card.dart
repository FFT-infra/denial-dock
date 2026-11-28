import 'dart:async';
import 'dart:math' as math;

import 'package:denial_flutter_sdk/theme.dart';
import 'package:denial_shell_kit/detached_run.dart';
import 'package:denial_shell_kit/kit_store.dart';
import 'package:denial_shell_kit/kit_widgets.dart';
import 'package:flutter/widgets.dart';

import '../bar_type.dart';
import '../l10n.dart';
import 'nc_parts.dart';

/// Curated city catalog users can cycle/toggle for World Clock.
const List<(String, String)> worldClockCatalog = <(String, String)>[
  ('Cupertino', 'America/Los_Angeles'),
  ('New York', 'America/New_York'),
  ('London', 'Europe/London'),
  ('Beijing', 'Asia/Shanghai'),
  ('Tokyo', 'Asia/Tokyo'),
  ('Paris', 'Europe/Paris'),
  ('Berlin', 'Europe/Berlin'),
  ('Singapore', 'Asia/Singapore'),
  ('Sydney', 'Australia/Sydney'),
  ('Seoul', 'Asia/Seoul'),
  ('Dubai', 'Asia/Dubai'),
  ('Toronto', 'America/Toronto'),
];

/// Persisted list of `(city, zone)` pairs shown by World Clock (max 4).
final ValueNotifier<List<(String, String)>> worldClockCities =
    ValueNotifier<List<(String, String)>>(_loadStoredWorldCities());

List<(String, String)> _loadStoredWorldCities() {
  final raw = kitStore.read()['widgetWorldCities'];
  if (raw is List) {
    final parsed = <(String, String)>[];
    for (final entry in raw) {
      if (entry is Map && entry['c'] is String && entry['z'] is String) {
        parsed.add((entry['c'] as String, entry['z'] as String));
      }
    }
    if (parsed.isNotEmpty) return parsed.take(4).toList(growable: false);
  }
  return WorldClock.defaultCities;
}

void setWorldClockCities(List<(String, String)> next) {
  final list = next.isEmpty
      ? WorldClock.defaultCities
      : next.take(4).toList(growable: false);
  worldClockCities.value = list;
  WorldClock.invalidate();
  kitStore.put('widgetWorldCities', <Map<String, String>>[
    for (final (city, zone) in list) <String, String>{'c': city, 'z': zone},
  ]);
}

/// One city's local time, read through the host's own zoneinfo.
@immutable
class WorldClock {
  const WorldClock({
    required this.city,
    required this.zone,
    required this.time,
    required this.dayDelta,
  });

  final String city;
  final String zone;
  final String time;

  /// −1 for yesterday, 1 for tomorrow, 0 for the same day.
  final int dayDelta;

  static const List<(String, String)> defaultCities = <(String, String)>[
    ('Cupertino', 'America/Los_Angeles'),
    ('New York', 'America/New_York'),
    ('London', 'Europe/London'),
    ('Beijing', 'Asia/Shanghai'),
  ];

  static List<(String, String)> get cities => worldClockCities.value;

  /// What the last read found, so a card that opens again shows its rows
  /// in its first frame.
  static List<WorldClock> last = const <WorldClock>[];
  static int _lastMinuteKey = -1;

  static void invalidate() {
    last = const <WorldClock>[];
    _lastMinuteKey = -1;
  }

  /// Reads all configured cities in one batched detached `sh` command (cached
  /// per wall-clock minute; never caches an empty failure result).
  static Future<List<WorldClock>> read(DateTime now) async {
    final minuteKey = now.millisecondsSinceEpoch ~/ 60000;
    if (last.isNotEmpty && minuteKey == _lastMinuteKey) return last;
    final list = cities;
    final localDay = DateTime(now.year, now.month, now.day);
    final script = <String>[
      for (final (_, zone) in list)
        'TZ=${_shQuote(zone)} date "+%H:%M %Y-%m-%d" || echo ""',
    ].join('; ');
    final res = await runDetached(
      'sh',
      <String>['-c', script],
      timeout: const Duration(seconds: 3),
    );
    final clocks = <WorldClock>[];
    if (res.exitCode == 0) {
      final lines = res.stdout.split('\n');
      for (var i = 0; i < list.length && i < lines.length; i++) {
        final parts = lines[i].trim().split(' ');
        if (parts.length != 2) continue;
        final day = DateTime.tryParse(parts[1]);
        clocks.add(
          WorldClock(
            city: list[i].$1,
            zone: list[i].$2,
            time: parts[0],
            dayDelta: day == null ? 0 : day.difference(localDay).inDays,
          ),
        );
      }
    }
    if (clocks.isNotEmpty) {
      _lastMinuteKey = minuteKey;
      last = clocks;
    }
    return last;
  }

  static String _shQuote(String value) =>
      "'${value.replaceAll("'", "'\\''")}'";
}

/// The World Clock widget: Small (1×1) shows the primary city dial; Medium
/// (2×1) shows up to 4 compact dials in a row; Large (2×2) shows a 2×2 grid.
class WorldClockCard extends StatefulWidget {
  const WorldClockCard({
    this.size = KitWidgetSize.medium,
    this.glass = false,
    super.key,
  });

  final KitWidgetSize size;
  final bool glass;

  @override
  State<WorldClockCard> createState() => _WorldClockCardState();
}

class _WorldClockCardState extends State<WorldClockCard> {
  List<WorldClock> _clocks = WorldClock.last;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    worldClockCities.addListener(_onCitiesChanged);
    _refresh();
    // Minute resolution is enough: the dials have no second hand.
    _tick = Timer.periodic(const Duration(seconds: 30), (_) => _refresh());
  }

  @override
  void dispose() {
    worldClockCities.removeListener(_onCitiesChanged);
    _tick?.cancel();
    super.dispose();
  }

  void _onCitiesChanged() {
    if (mounted) unawaited(_refresh());
  }

  Future<void> _refresh() async {
    final clocks = await WorldClock.read(DateTime.now());
    if (!mounted) return;
    setState(() => _clocks = clocks);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final primary = widget.glass ? theme.colors.textPrimary : NcLook.onNight;
    final secondary = widget.glass
        ? theme.colors.textSecondary
        : NcLook.onNightDim;
    if (_clocks.isEmpty) {
      final now = DateTime.now();
      final placeholder = <WorldClock>[
        for (final (city, zone) in WorldClock.cities)
          WorldClock(
            city: city,
            zone: zone,
            time:
                '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
            dayDelta: 0,
          ),
      ];
      return Opacity(
        opacity: 0.45,
        child: _buildLayout(context, placeholder, primary, secondary),
      );
    }
    return _buildLayout(context, _clocks, primary, secondary);
  }

  Widget _buildLayout(
    BuildContext context,
    List<WorldClock> clocks,
    Color primary,
    Color secondary,
  ) {
    if (widget.size == KitWidgetSize.small) {
      return Padding(
        padding: const EdgeInsets.all(14),
        child: _Dial(
          clock: clocks.first,
          primary: primary,
          secondary: secondary,
          large: true,
        ),
      );
    }
    if (widget.size == KitWidgetSize.large) {
      return Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: <Widget>[
            Expanded(
              child: Row(
                children: <Widget>[
                  for (final clock in clocks.take(2))
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: _Dial(
                          clock: clock,
                          primary: primary,
                          secondary: secondary,
                          large: true,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Row(
                children: <Widget>[
                  for (final clock in clocks.skip(2).take(2))
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: _Dial(
                          clock: clock,
                          primary: primary,
                          secondary: secondary,
                          large: true,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final clock in clocks)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                child: _Dial(
                  clock: clock,
                  primary: primary,
                  secondary: secondary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One city: its dial, its name, and the time in figures.
class _Dial extends StatelessWidget {
  const _Dial({
    required this.clock,
    required this.primary,
    required this.secondary,
    this.large = false,
  });

  final WorldClock clock;
  final Color primary;
  final Color secondary;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final parts = clock.time.split(':');
    final hour = parts.length == 2 ? int.tryParse(parts[0]) ?? 0 : 0;
    final minute = parts.length == 2 ? int.tryParse(parts[1]) ?? 0 : 0;
    final day = hour >= 6 && hour < 18;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Flexible(
          child: AspectRatio(
            aspectRatio: 1,
            child: CustomPaint(
              painter: _DialPainter(
                hour: hour,
                minute: minute,
                face: day ? NcLook.dialDay : NcLook.dialNight,
                ink: day ? NcLook.dialDayInk : NcLook.onNight,
              ),
            ),
          ),
        ),
        SizedBox(height: large ? 10 : 8),
        Text(
          context.tr(clock.city),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: BarType.caption.copyWith(
            fontSize: large ? 13 : 12,
            fontWeight: FontWeight.w600,
            color: primary,
          ),
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            clock.dayDelta == 0
                ? clock.time
                : '${context.tr(clock.dayDelta < 0 ? 'Yesterday' : 'Tomorrow')} '
                      '${clock.time}',
            maxLines: 1,
            style: BarType.caption.copyWith(
              fontSize: large ? 12 : 11,
              color: secondary,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

class _DialPainter extends CustomPainter {
  const _DialPainter({
    required this.hour,
    required this.minute,
    required this.face,
    required this.ink,
  });

  final int hour;
  final int minute;
  final Color face;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    canvas.drawCircle(c, r, Paint()..color = face);
    Offset at(double turns, double length) =>
        c +
        Offset(math.sin(turns * 2 * math.pi), -math.cos(turns * 2 * math.pi)) *
            length;
    for (var i = 0; i < 12; i++) {
      final quarter = i % 3 == 0;
      canvas.drawLine(
        at(i / 12, r * (quarter ? 0.78 : 0.84)),
        at(i / 12, r * 0.91),
        Paint()
          ..color = ink.withValues(alpha: quarter ? 0.9 : 0.45)
          ..strokeWidth = quarter ? 1.6 : 1
          ..strokeCap = StrokeCap.round,
      );
    }
    void hand(double turns, double length, double width) => canvas.drawLine(
      c,
      at(turns, r * length),
      Paint()
        ..color = ink
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round,
    );
    hand((hour % 12 + minute / 60) / 12, 0.46, 3);
    hand(minute / 60, 0.68, 2.2);
    canvas.drawCircle(c, 2.4, Paint()..color = _pivot);
  }

  static const Color _pivot = Color(0xffff9f0a);

  @override
  bool shouldRepaint(_DialPainter old) =>
      old.hour != hour ||
      old.minute != minute ||
      old.face != face ||
      old.ink != ink;
}
