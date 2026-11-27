import 'dart:async';
import 'dart:math' as math;

import 'package:denial_shell_kit/detached_run.dart';
import 'package:flutter/widgets.dart';

import '../bar_type.dart';
import '../l10n.dart';
import 'nc_parts.dart';

/// One city's local time, read through the host's own zoneinfo.
///
/// Dart has no timezone database, so the clock asks `date` with `TZ` set —
/// the same source the rest of the session uses, DST included. A zone the
/// host does not ship is simply absent from the list.
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

  static const List<(String, String)> cities = <(String, String)>[
    ('Cupertino', 'America/Los_Angeles'),
    ('New York', 'America/New_York'),
    ('London', 'Europe/London'),
    ('Beijing', 'Asia/Shanghai'),
  ];

  /// What the last read found, so a card that opens again shows its rows
  /// in its first frame.
  static List<WorldClock> last = const <WorldClock>[];
  static int _lastMinuteKey = -1;

  /// Reads every city (cached per wall-clock minute), using detached helpers
  /// so opening Notification Centre repeatedly does not fork `date` 4× each
  /// time or spawn attached children.
  static Future<List<WorldClock>> read(DateTime now) async {
    final minuteKey = now.millisecondsSinceEpoch ~/ 60000;
    if (last.isNotEmpty && minuteKey == _lastMinuteKey) return last;
    final localDay = DateTime(now.year, now.month, now.day);
    final results = await Future.wait(<Future<DetachedResult>>[
      for (final (_, zone) in cities)
        runDetached(
          'date',
          const <String>['+%H:%M %Y-%m-%d'],
          environment: <String, String>{'TZ': zone},
        ),
    ]);
    final clocks = <WorldClock>[];
    for (var i = 0; i < cities.length; i++) {
      final result = results[i];
      if (result.exitCode != 0) continue;
      final parts = result.stdout.trim().split(' ');
      if (parts.length != 2) continue;
      final day = DateTime.tryParse(parts[1]);
      clocks.add(
        WorldClock(
          city: cities[i].$1,
          zone: cities[i].$2,
          time: parts[0],
          dayDelta: day == null ? 0 : day.difference(localDay).inDays,
        ),
      );
    }
    _lastMinuteKey = minuteKey;
    return last = clocks;
  }
}

/// The World Clock widget: four dials on a dark card, each with its city
/// and the time there under it. A dial is light while it is day in its city
/// and dark at night, so the row reads at a glance.
class WorldClockCard extends StatefulWidget {
  const WorldClockCard({super.key});

  @override
  State<WorldClockCard> createState() => _WorldClockCardState();
}

class _WorldClockCardState extends State<WorldClockCard> {
  List<WorldClock> _clocks = WorldClock.last;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _refresh();
    // Minute resolution is enough: the dials have no second hand.
    _tick = Timer.periodic(const Duration(seconds: 30), (_) => _refresh());
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final clocks = await WorldClock.read(DateTime.now());
    if (!mounted) return;
    setState(() => _clocks = clocks);
  }

  @override
  Widget build(BuildContext context) {
    if (_clocks.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final clock in _clocks)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                child: _Dial(clock: clock),
              ),
            ),
        ],
      ),
    );
  }
}

/// One city: its dial, its name, and the time in figures.
class _Dial extends StatelessWidget {
  const _Dial({required this.clock});

  final WorldClock clock;

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
        const SizedBox(height: 8),
        Text(
          context.tr(clock.city),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: BarType.caption.copyWith(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: NcLook.onNight,
          ),
        ),
        // Shrunk to the column rather than cut: the end of the line is the
        // time itself.
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            clock.dayDelta == 0
                ? clock.time
                : '${context.tr(clock.dayDelta < 0 ? 'Yesterday' : 'Tomorrow')} '
                      '${clock.time}',
            maxLines: 1,
            style: BarType.caption.copyWith(
              color: NcLook.onNightDim,
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
