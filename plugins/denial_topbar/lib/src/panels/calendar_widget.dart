import 'package:denial_flutter_sdk/localization.dart';
import 'package:denial_flutter_sdk/state.dart';
import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bar_icons.dart';
import '../continuous_corners.dart';

/// Apple system red for the calendar widget.
const Color calendarRed = Color(0xffff453a);

/// A macOS Medium Calendar Widget (338x158 standard, fitted to 352x158).
///
/// Faithfully ports `0-ss/MacShell`'s `CalendarWidget.qml` (macOS Tahoe style):
/// - Left column: Weekday in red (Bold 13), huge day number (54 pt Light),
///   and month/year at the bottom.
/// - Vertical hairline divider.
/// - Right column: Compact month grid with 7 weekday headers, where today
///   sits in an accent red filled circle.
class CalendarWidget extends ConsumerStatefulWidget {
  const CalendarWidget({
    this.width = 352,
    this.height = 158,
    this.onTap,
    super.key,
  });

  final double width;
  final double height;
  final VoidCallback? onTap;

  @override
  ConsumerState<CalendarWidget> createState() => _CalendarWidgetState();
}

class _CalendarWidgetState extends ConsumerState<CalendarWidget> {
  int _monthOffset = 0;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    final shown = DateTime(now.year, now.month + _monthOffset);
    final first = DateTime(shown.year, shown.month);
    // Sunday = 0 or Monday = 1 based on locale; default Monday-first:
    final leading = (first.weekday - DateTime.monday) % 7;
    final daysInMonth = DateTime(shown.year, shown.month + 1, 0).day;
    final cells = <DateTime?>[
      for (var i = 0; i < leading; i++) null,
      for (var day = 1; day <= daysInMonth; day++)
        DateTime(shown.year, shown.month, day),
    ];
    while (cells.length % 7 != 0) {
      cells.add(null);
    }

    const radius = 20.0;
    return GestureDetector(
      onTap: widget.onTap,
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: DecoratedBox(
          decoration: ShapeDecoration(
            shape: ContinuousCorners(radius: radius),
            color: theme.colors.textPrimary.withValues(alpha: 0.05),
            shadows: <BoxShadow>[
              BoxShadow(
                color: theme.colors.shadow.withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                // ── Left Column: Day & Date summary ──
                SizedBox(
                  width: 120,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        localizedWeekday(context.l10n, now.weekday).toUpperCase(),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: calendarRed,
                          letterSpacing: 0.5,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${now.day}',
                        style: TextStyle(
                          fontSize: 52,
                          fontWeight: FontWeight.w300,
                          height: 1.0,
                          color: theme.colors.textPrimary,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${localizedMonth(context.l10n, now.month)} ${now.year}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: theme.colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Vertical Hairline Divider ──
                Container(
                  width: 1,
                  margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  color: theme.colors.hairlineSoft.withValues(alpha: 0.6),
                ),

                // ── Right Column: Compact Month Grid ──
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      // Month title + pagination arrows
                      SizedBox(
                        height: 20,
                        child: Row(
                          children: <Widget>[
                            Text(
                              '${localizedMonth(context.l10n, shown.month)} ${shown.year}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: theme.colors.textPrimary,
                              ),
                            ),
                            const Spacer(),
                            _ChevronBtn(
                              icon: BarIcons.chevronLeft,
                              onTap: () => setState(() => _monthOffset--),
                            ),
                            const SizedBox(width: 2),
                            _ChevronBtn(
                              icon: BarIcons.chevronRight,
                              onTap: () => setState(() => _monthOffset++),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      // Weekday headers
                      Row(
                        children: <Widget>[
                          for (var i = 1; i <= 7; i++)
                            Expanded(
                              child: Center(
                                child: Text(
                                  _shortWeekday(context, i),
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                    color: theme.colors.textPrimary.withValues(alpha: 0.5),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      // Day rows (up to 6 rows)
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: <Widget>[
                            for (var r = 0; r < cells.length ~/ 7; r++)
                              Row(
                                children: <Widget>[
                                  for (var c = 0; c < 7; c++)
                                    Expanded(
                                      child: Center(
                                        child: _CompactDay(
                                          date: cells[r * 7 + c],
                                          today: now,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _shortWeekday(BuildContext context, int weekday) {
    final name = localizedWeekday(context.l10n, weekday);
    if (name.startsWith('星期') && name.length > 2) return name.substring(2);
    return name.length <= 2 ? name : name.substring(0, 1);
  }
}

class _ChevronBtn extends StatefulWidget {
  const _ChevronBtn({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  State<_ChevronBtn> createState() => _ChevronBtnState();
}

class _ChevronBtnState extends State<_ChevronBtn> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          width: 18,
          height: 18,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _hovered
                ? theme.colors.textPrimary.withValues(alpha: 0.1)
                : Colors.transparent,
          ),
          child: Icon(
            widget.icon,
            size: 11,
            color: theme.colors.textPrimary,
          ),
        ),
      ),
    );
  }
}

class _CompactDay extends StatelessWidget {
  const _CompactDay({required this.date, required this.today});

  final DateTime? date;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final value = date;
    if (value == null) return const SizedBox(width: 18, height: 18);
    final isToday =
        value.year == today.year &&
        value.month == today.month &&
        value.day == today.day;

    return Container(
      width: 18,
      height: 18,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isToday ? calendarRed : Colors.transparent,
      ),
      child: Text(
        '${value.day}',
        style: TextStyle(
          fontSize: 11,
          fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
          color: isToday ? const Color(0xffffffff) : theme.colors.textPrimary,
        ),
      ),
    );
  }
}
