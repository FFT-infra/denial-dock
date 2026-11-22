import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/material.dart';

class TopBarCalendarPanel extends StatefulWidget {
  const TopBarCalendarPanel({super.key});

  @override
  State<TopBarCalendarPanel> createState() => _TopBarCalendarPanelState();
}

class _TopBarCalendarPanelState extends State<TopBarCalendarPanel> {
  late DateTime _month;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
  }

  void _step(int months) {
    setState(() {
      _month = DateTime(_month.year, _month.month + months);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final localizations = MaterialLocalizations.of(context);
    final today = DateTime.now();
    final first = DateTime(_month.year, _month.month);
    final days = DateUtils.getDaysInMonth(_month.year, _month.month);
    final leading =
        (first.weekday - 1 - localizations.firstDayOfWeekIndex + 7) % 7;
    final cells = <DateTime?>[
      for (var index = 0; index < leading; index++) null,
      for (var day = 1; day <= days; day++)
        DateTime(_month.year, _month.month, day),
    ];
    while (cells.length % 7 != 0) {
      cells.add(null);
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              _StepButton(icon: Icons.chevron_left, onTap: () => _step(-1)),
              Expanded(
                child: Center(
                  child: Text(
                    localizations.formatMonthYear(_month),
                    style: theme.text.systemBarValue.copyWith(
                      color: theme.colors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              _StepButton(icon: Icons.chevron_right, onTap: () => _step(1)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: <Widget>[
              for (var index = 0; index < 7; index++)
                Expanded(
                  child: Center(
                    child: Text(
                      localizations.narrowWeekdays[(localizations
                                  .firstDayOfWeekIndex +
                              index) %
                          7],
                      style: theme.text.systemBarCaption.copyWith(
                        color: theme.colors.textTertiary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          for (var row = 0; row < cells.length ~/ 7; row++)
            Row(
              children: <Widget>[
                for (var column = 0; column < 7; column++)
                  Expanded(
                    child: _DayCell(
                      date: cells[row * 7 + column],
                      today: today,
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: theme.colors.textPrimary.withValues(alpha: 0.05),
            borderRadius: theme.borderRadius(8),
          ),
          child: Icon(icon, size: 17, color: theme.colors.textSecondary),
        ),
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({required this.date, required this.today});

  final DateTime? date;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final value = date;
    if (value == null) return const SizedBox(height: 30);
    final isToday =
        value.year == today.year &&
        value.month == today.month &&
        value.day == today.day;
    return SizedBox(
      height: 30,
      child: Center(
        child: Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: isToday ? theme.accent : Colors.transparent,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            '${value.day}',
            style: theme.text.systemBarCaption.copyWith(
              color: isToday
                  ? Colors.white
                  : theme.colors.textPrimary.withValues(alpha: 0.86),
              fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
