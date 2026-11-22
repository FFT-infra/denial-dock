/// The clock's date text.
///
/// shell27 `clockText` draws `ddd d MMM` — an abbreviated weekday, the day,
/// then an abbreviated month — because the strip is narrow and macOS keeps the
/// same order. Denial's localization returns full names (`星期一`, `十一月`),
/// so they are abbreviated here rather than dropped: Chinese keeps the
/// `11月23日 周一` shape macOS uses, and every other language gets the
/// three-letter forms.
library;

/// Abbreviates a weekday name.
///
/// `星期一` → `周一`, `Monday` → `Mon`, `Понедельник` → `Пон`.
String abbreviateWeekday(String weekday) {
  if (weekday.isEmpty) return weekday;
  const weekPrefix = '星期';
  if (weekday.startsWith(weekPrefix) && weekday.length > weekPrefix.length) {
    return '周${weekday.substring(weekPrefix.length)}';
  }
  return _abbreviate(weekday, 3);
}

/// Abbreviates a month name.
///
/// `十一月` → `11月`, `November` → `Nov`.
String abbreviateMonth(String month, int monthNumber) {
  if (month.isEmpty) return '$monthNumber';
  if (month.endsWith('月')) return '$monthNumber月';
  return _abbreviate(month, 3);
}

/// The date half of the clock, or an empty string when it should not show.
///
/// A month written with a `月` suffix belongs to a language that puts the month
/// first and adds 日 after the day, so that shape is kept whole; anything else
/// follows shell27's `ddd d MMM`.
String clockDateLabel({
  required String weekday,
  required String month,
  required int day,
  required int monthNumber,
}) {
  final shortWeekday = abbreviateWeekday(weekday);
  final shortMonth = abbreviateMonth(month, monthNumber);
  if (month.endsWith('月')) {
    return '$shortMonth$day日 $shortWeekday';
  }
  return '$shortWeekday $day $shortMonth';
}

String _abbreviate(String value, int length) =>
    value.length <= length ? value : value.substring(0, length);
