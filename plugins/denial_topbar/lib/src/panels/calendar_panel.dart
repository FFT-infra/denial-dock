import 'package:denial_flutter_sdk/localization.dart';
import 'package:denial_flutter_sdk/state.dart';
import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bar_icons.dart';
import 'panel_parts.dart';

/// The clock's calendar popover.
///
/// Ports shell27 `MacBar.qml`'s `cal`: 310 wide, a 24-radius glass card, and a
/// column at `x: 16; y: 14` holding the weekday at 12 DemiBold, the date at 22
/// DemiBold, the month and year at 14 DemiBold with a chevron pair on the same
/// line, a 7-column weekday header at 11 DemiBold, and a 32-high day grid whose
/// today marker is a 28 pt accent circle.
class CalendarPanel extends ConsumerStatefulWidget {
  const CalendarPanel({
    required this.onClose,
    this.width = PanelWidth.calendar,
    super.key,
  });

  final VoidCallback onClose;

  /// 310 as a popover; wider when it is the widget inside the notification
  /// centre, which is 380 wide.
  final double width;

  @override
  ConsumerState<CalendarPanel> createState() => _CalendarPanelState();
}

class _CalendarPanelState extends ConsumerState<CalendarPanel> {
  /// The month on screen, as an offset from the current month.
  int _monthOffset = 0;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    final shown = DateTime(now.year, now.month + _monthOffset);
    final first = DateTime(shown.year, shown.month);
    // shell27 uses Qt's dayOfWeek with Monday first, so the leading blanks are
    // `(weekday of the 1st) - 1`.
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

    return SizedBox(
      width: widget.width,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              localizedWeekday(context.l10n, now.weekday),
              style: PanelText.detail(theme).copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              localizedLongDate(context, now),
              style: PanelText.title(
                theme,
              ).copyWith(fontSize: 22, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: 26,
              child: Row(
                children: <Widget>[
                  Text(
                    _monthTitle(context, shown),
                    style: PanelText.body(
                      theme,
                    ).copyWith(fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  _MonthChevron(
                    icon: BarIcons.chevronLeft,
                    onTap: () => setState(() => _monthOffset--),
                  ),
                  const SizedBox(width: 2),
                  _MonthChevron(
                    icon: BarIcons.chevronRight,
                    onTap: () => setState(() => _monthOffset++),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: <Widget>[
                for (var index = 0; index < 7; index++)
                  Expanded(
                    child: Center(
                      child: Text(
                        _shortWeekday(context, index + 1),
                        style: PanelText.section(theme).copyWith(fontSize: 11),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            for (var row = 0; row < cells.length ~/ 7; row++)
              Row(
                children: <Widget>[
                  for (var column = 0; column < 7; column++)
                    Expanded(
                      child: SizedBox(
                        height: 32,
                        child: Center(
                          child: _DayCell(
                            date: cells[row * 7 + column],
                            today: now,
                            onTap: widget.onClose,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  /// shell27 asks Qt for the month name in long form and appends the year.
  String _monthTitle(BuildContext context, DateTime month) =>
      '${localizedMonth(context.l10n, month.month)} ${month.year}';

  /// shell27 takes the localized day name's first two characters.
  String _shortWeekday(BuildContext context, int weekday) {
    final name = localizedWeekday(context.l10n, weekday);
    if (name.startsWith('星期') && name.length > 2) return name.substring(2);
    return name.length <= 2 ? name : name.substring(0, 2);
  }
}

class _MonthChevron extends StatefulWidget {
  const _MonthChevron({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  State<_MonthChevron> createState() => _MonthChevronState();
}

class _MonthChevronState extends State<_MonthChevron> {
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
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _hovered
                ? theme.colors.textPrimary.withValues(alpha: 0.1)
                : const Color(0x00000000),
          ),
          child: Center(
            child: BarGlyph(
              widget.icon,
              size: 13,
              color: theme.colors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.date,
    required this.today,
    required this.onTap,
  });

  final DateTime? date;
  final DateTime today;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final value = date;
    if (value == null) return const SizedBox.shrink();
    final isToday =
        value.year == today.year &&
        value.month == today.month &&
        value.day == today.day;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isToday ? theme.accent : const Color(0x00000000),
        ),
        child: Text(
          '${value.day}',
          style: PanelText.body(theme).copyWith(
            fontWeight: isToday ? FontWeight.w600 : FontWeight.w400,
            color: isToday
                ? const Color(0xffffffff)
                : theme.colors.textPrimary,
          ),
        ),
      ),
    );
  }
}
