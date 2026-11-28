import 'package:denial_flutter_sdk/localization.dart';
import 'package:denial_flutter_sdk/state.dart';
import 'package:denial_flutter_sdk/theme.dart';
import 'package:denial_shell_kit/kit_style.dart';
import 'package:denial_shell_kit/kit_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bar_icons.dart';
import '../bar_type.dart';
import '../l10n.dart';
import 'mac_kit.dart';

/// The red of the weekday and of today's date.
const Color calendarRed = Color(0xffff453a);

/// Calendar widget supporting Small (1×1), Medium (2×1), and Large (2×2):
/// - Small: Today's weekday, large day numeral, month & year.
/// - Medium: Left today summary + vertical hairline + right compact month grid.
/// - Large: Full interactive month calendar with week numbers, prev/next month,
///   and a quick Today reset pill.
class CalendarWidget extends ConsumerStatefulWidget {
  const CalendarWidget({
    this.size = KitWidgetSize.medium,
    this.onTap,
    super.key,
  });

  final KitWidgetSize size;
  final VoidCallback? onTap;

  @override
  ConsumerState<CalendarWidget> createState() => _CalendarWidgetState();
}

class _CalendarWidgetState extends ConsumerState<CalendarWidget> {
  int _monthOffset = 0;

  int _isoWeekNumber(DateTime date) {
    final thursday = date.add(Duration(days: 4 - date.weekday));
    final firstJan = DateTime(thursday.year, 1, 1);
    return ((thursday.difference(firstJan).inDays) ~/ 7) + 1;
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final (year, month, day) = ref.watch(
      clockProvider.select((async) {
        final d = async.value ?? DateTime.now();
        return (d.year, d.month, d.day);
      }),
    );
    final now = DateTime(year, month, day);

    if (widget.size == KitWidgetSize.small) {
      return GestureDetector(
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  localizedWeekday(context.l10n, now.weekday).toUpperCase(),
                  maxLines: 1,
                  style: BarType.section.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: calendarRed,
                  ),
                ),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  '${now.day}',
                  style: BarType.display.copyWith(
                    fontSize: 58,
                    height: 1.05,
                    fontWeight: FontWeight.w300,
                    letterSpacing: -2,
                    color: theme.colors.textPrimary,
                  ),
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
        ),
      );
    }

    final shown = DateTime(now.year, now.month + _monthOffset);
    final first = DateTime(shown.year, shown.month);
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

    if (widget.size == KitWidgetSize.large) {
      final rows = cells.length ~/ 7;
      return GestureDetector(
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '${localizedMonth(context.l10n, shown.month)} ${shown.year}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: BarType.title.copyWith(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: theme.colors.textPrimary,
                          ),
                        ),
                        Text(
                          '${localizedWeekday(context.l10n, now.weekday)} · ${now.month}/${now.day}',
                          style: BarType.caption.copyWith(
                            fontSize: 11,
                            color: calendarRed,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_monthOffset != 0)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Pressable(
                        onTap: () => setState(() => _monthOffset = 0),
                        scale: Pressable.small,
                        wash: true,
                        shape: BorderRadius.circular(
                          KitStyle.of(context).pill(22),
                        ),
                        child: Container(
                          height: 22,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: theme.colors.textPrimary.withValues(
                              alpha: 0.1,
                            ),
                            borderRadius: BorderRadius.circular(
                              KitStyle.of(context).pill(22),
                            ),
                          ),
                          child: Text(
                            context.tr('Today'),
                            style: BarType.caption.copyWith(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: theme.colors.textPrimary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  _ChevronBtn(
                    icon: BarIcons.chevronLeft,
                    onTap: () => setState(() => _monthOffset--),
                  ),
                  const SizedBox(width: 4),
                  _ChevronBtn(
                    icon: BarIcons.chevronRight,
                    onTap: () => setState(() => _monthOffset++),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  SizedBox(
                    width: 24,
                    child: Center(
                      child: Text(
                        '#',
                        style: BarType.bare(10, FontWeight.w600).copyWith(
                          color: theme.colors.textTertiary,
                        ),
                      ),
                    ),
                  ),
                  for (var i = 1; i <= 7; i++)
                    Expanded(
                      child: Center(
                        child: Text(
                          _shortWeekday(context, i),
                          style: BarType.bare(11, FontWeight.w700).copyWith(
                            color: i >= 6
                                ? calendarRed.withValues(alpha: 0.8)
                                : theme.colors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, box) {
                    final size = (box.maxHeight / rows).clamp(18.0, 28.0);
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: <Widget>[
                        for (var r = 0; r < rows; r++)
                          Row(
                            children: <Widget>[
                              SizedBox(
                                width: 24,
                                child: Center(
                                  child: Text(
                                    '${_isoWeekNumber(cells.sublist(r * 7, r * 7 + 7).whereType<DateTime>().first)}',
                                    style: BarType.bare(10, FontWeight.w500)
                                        .copyWith(
                                          color: theme.colors.textTertiary,
                                          fontFeatures: const <FontFeature>[
                                            FontFeature.tabularFigures(),
                                          ],
                                        ),
                                  ),
                                ),
                              ),
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
      );
    }

    // Medium (2×1): left day summary + right compact month grid.
    return GestureDetector(
      onTap: widget.onTap,
      child: SizedBox.expand(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SizedBox(
                width: 116,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      localizedWeekday(context.l10n, now.weekday).toUpperCase(),
                      style: BarType.bare(
                        13,
                        FontWeight.w700,
                      ).copyWith(color: calendarRed, letterSpacing: 0.5),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${now.day}',
                      style: BarType.bare(52, FontWeight.w700).copyWith(
                        letterSpacing: -1.5,
                        height: 1.0,
                        color: theme.colors.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${localizedMonth(context.l10n, now.month)} ${now.year}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: BarType.bare(
                        13,
                        FontWeight.w600,
                      ).copyWith(color: theme.colors.textSecondary),
                    ),
                  ],
                ),
              ),
              Container(
                width: 1,
                margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                color: theme.colors.hairlineSoft.withValues(alpha: 0.6),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    SizedBox(
                      height: 20,
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: GestureDetector(
                              onTap: _monthOffset == 0
                                  ? null
                                  : () => setState(() => _monthOffset = 0),
                              child: Text(
                                '${localizedMonth(context.l10n, shown.month)} ${shown.year}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: BarType.bare(
                                  12,
                                  FontWeight.w700,
                                ).copyWith(color: theme.colors.textPrimary),
                              ),
                            ),
                          ),
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
                    Row(
                      children: <Widget>[
                        for (var i = 1; i <= 7; i++)
                          Expanded(
                            child: Center(
                              child: Text(
                                _shortWeekday(context, i),
                                style: BarType.bare(10.5, FontWeight.w600)
                                    .copyWith(
                                      color: theme.colors.textPrimary
                                          .withValues(alpha: 0.5),
                                    ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
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

class _ChevronBtn extends StatelessWidget {
  const _ChevronBtn({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    return Pressable(
      onTap: onTap,
      scale: Pressable.small,
      wash: true,
      shape: KitStyle.of(context).disc(18),
      child: SizedBox(
        width: 18,
        height: 18,
        child: Center(
          child: Icon(icon, size: 11, color: theme.colors.textPrimary),
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
        borderRadius: KitStyle.of(context).disc(size),
        color: isToday
            ? KitStyle.of(context).plate(theme, calendarRed)
            : Colors.transparent,
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          '${value.day}',
          maxLines: 1,
          style:
              BarType.bare(
                size < 16 ? 10 : (size > 22 ? 12 : 11),
                isToday ? FontWeight.w700 : FontWeight.w400,
              ).copyWith(
                height: 1,
                color: isToday
                    ? KitStyle.of(context).onPlate(theme)
                    : theme.colors.textPrimary,
              ),
        ),
      ),
    );
  }
}
