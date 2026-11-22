import 'dart:async';
import 'dart:io';

import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/widgets.dart';

import '../bar_type.dart';

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

  /// Reads every city, or returns an empty list when the host has no `date`.
  static List<WorldClock> read(DateTime now) {
    final localDay = DateTime(now.year, now.month, now.day);
    final clocks = <WorldClock>[];
    for (final (city, zone) in cities) {
      try {
        final result = Process.runSync(
          'date',
          <String>['+%H:%M %Y-%m-%d'],
          environment: <String, String>{'TZ': zone},
        );
        if (result.exitCode != 0) continue;
        final parts = (result.stdout as String).trim().split(' ');
        if (parts.length != 2) continue;
        final day = DateTime.tryParse(parts[1]);
        clocks.add(
          WorldClock(
            city: city,
            zone: zone,
            time: parts[0],
            dayDelta: day == null ? 0 : day.difference(localDay).inDays,
          ),
        );
      } on ProcessException {
        return const <WorldClock>[];
      }
    }
    return clocks;
  }
}

/// The World Clock card the notification centre shows under its list.
///
/// macOS puts a 4-row world clock beside the calendar; this keeps the same
/// two-line row: the city at 13, the offset hint at 11, and the time right
/// aligned in tabular digits so the column does not jitter as minutes pass.
class WorldClockCard extends StatefulWidget {
  const WorldClockCard({super.key});

  @override
  State<WorldClockCard> createState() => _WorldClockCardState();
}

class _WorldClockCardState extends State<WorldClockCard> {
  List<WorldClock> _clocks = const <WorldClock>[];
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _refresh();
    // Minute resolution is enough: the rows only show hours and minutes.
    _tick = Timer.periodic(const Duration(seconds: 30), (_) => _refresh());
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _refresh() {
    final clocks = WorldClock.read(DateTime.now());
    if (!mounted) return;
    setState(() => _clocks = clocks);
  }

  @override
  Widget build(BuildContext context) {
    if (_clocks.isEmpty) return const SizedBox.shrink();
    final theme = context.shellTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colors.textPrimary.withValues(alpha: 0.06),
        borderRadius: theme.borderRadius(12),
        border: Border.all(
          color: theme.colors.hairlineSoft.withValues(alpha: 0.4),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                'World Clock',
                style: BarType.caption.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colors.textSecondary,
                ),
              ),
            ),
            for (final clock in _clocks)
              SizedBox(
                height: 24,
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        clock.city,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: BarType.menuRow.copyWith(
                          color: theme.colors.textPrimary,
                        ),
                      ),
                    ),
                    if (clock.dayDelta != 0)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Text(
                          clock.dayDelta < 0 ? 'Yesterday' : 'Tomorrow',
                          style: BarType.caption.copyWith(
                            fontSize: 10,
                            color: theme.colors.textTertiary,
                          ),
                        ),
                      ),
                    Text(
                      clock.time,
                      style: BarType.menuRow.copyWith(
                        color: theme.colors.textPrimary,
                        fontFeatures: const <FontFeature>[
                          FontFeature.tabularFigures(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
