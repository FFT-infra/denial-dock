import 'dart:io';

import 'package:denial_topbar/src/clock_label.dart';

/// Checks the clock's date against shell27's `ddd d MMM` in both scripts.
void main() {
  _expect(
    clockDateLabel(weekday: '星期一', month: '十一月', day: 23, monthNumber: 11) ==
        '11月23日 周一',
    'Chinese date keeps macOS order',
  );
  _expect(
    clockDateLabel(
          weekday: 'Monday',
          month: 'November',
          day: 23,
          monthNumber: 11,
        ) ==
        'Mon 23 Nov',
    'English date is ddd d MMM',
  );
  _expect(abbreviateWeekday('星期日') == '周日', 'Sunday short form');
  _expect(abbreviateWeekday('Friday') == 'Fri', 'short weekday is 3 letters');
  _expect(abbreviateMonth('五月', 5) == '5月', 'single-digit month');
  _expect(abbreviateMonth('December', 12) == 'Dec', 'short month is 3 letters');
  stdout.writeln('All clock label tests passed.');
}

void _expect(bool condition, String label) {
  if (!condition) {
    stderr.writeln('FAILED: $label');
    exit(1);
  }
}
