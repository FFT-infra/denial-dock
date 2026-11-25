import 'package:denial_flutter_sdk/localization.dart';
import 'package:denial_flutter_sdk/state.dart';
import 'package:denial_flutter_sdk/theme.dart';
import 'package:denial_shell_kit/kit_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bar_icons.dart';

/// The red of the weekday and of today's date.
const Color calendarRed = Color(0xffff453a);

/// The medium calendar widget, filling the card it is given:
/// - Left column: the weekday in red, the day's number large, and the month
///   and year at the bottom.
/// - A hairline between the columns.
/// - Right column: a compact month grid under seven weekday headers, with
///   today in a filled circle.
class CalendarWidget extends ConsumerStatefulWidget {
  const CalendarWidget({this.onTap, super.key});

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

    // The card under it is the grid's: this draws no plate of its own.
    return GestureDetector(
      onTap: widget.onTap,
      child: SizedBox.expand(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
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
                    const SizedBox(height: 6),
                    Text(
                      '${now.day}',
                      style: TextStyle(
                        fontSize: 52,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -1.5,
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
                                  color: theme.colors.textPrimary.withValues(
                                    alpha: 0.5,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    // Day rows (up to 6 rows)
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, box) {
                          final rows = cells.length ~/ 7;
                          final size = (box.maxHeight / rows).clamp(10.0, 18.0);
                          return Column(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: <Widget>[
                              for (var r = 0; r < rows; r++)
                                Row(
                                  children: <Widget>[
                                    for (var c = 0; c < 7; c++)
                                      Expanded(
                                        child: Center(
                                          child: _CompactDay(
                                            date: cells[r * 7 + c],
                                            today: now,
                                            size: size,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
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
          child: Icon(widget.icon, size: 11, color: theme.colors.textPrimary),
        ),
      ),
    );
  }
}

class _CompactDay extends StatelessWidget {
  const _CompactDay({required this.date, required this.today, this.size = 18});

  final DateTime? date;
  final DateTime today;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final value = date;
    if (value == null) return SizedBox(width: size, height: size);
    final isToday =
        value.year == today.year &&
        value.month == today.month &&
        value.day == today.day;

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isToday
            ? KitStyle.of(context).plate(theme, calendarRed)
            : Colors.transparent,
      ),
      child: Text(
        '${value.day}',
        style: TextStyle(
          fontSize: size < 16 ? 10 : 11,
          height: 1,
          fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
          color: isToday
              ? KitStyle.of(context).onPlate(theme)
              : theme.colors.textPrimary,
        ),
      ),
    );
  }
}
