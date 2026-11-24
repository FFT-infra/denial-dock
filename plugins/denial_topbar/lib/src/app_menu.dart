import 'package:flutter/widgets.dart';

import 'bar_button.dart';
import 'bar_tokens.dart';
import 'bar_type.dart';

/// A menu bar title.
///
/// shell27 `MacBar.qml`: every title box is `tl.implicitWidth + 20` wide and
/// 28 high, with the text centred; the active app's title is DemiBold at 14
/// and the rest are regular at 14. `BarButton` draws the `width - 2` ×
/// `height - 6` hover plate inside that box.
class BarTitle extends StatelessWidget {
  const BarTitle({
    required this.label,
    required this.ink,
    this.bold = false,
    this.icon,
    this.onTap,
    this.open = false,
    super.key,
  });

  /// Stands in for the label on a vertical bar, which has no room for text.
  final Widget? icon;
  final String label;
  final Color ink;
  final bool bold;
  final VoidCallback? onTap;
  final bool open;

  @override
  Widget build(BuildContext context) {
    final icon = this.icon;
    if (icon != null) {
      return BarButton(
        onTap: onTap,
        open: open,
        ink: ink,
        width: 30,
        height: 30,
        padding: EdgeInsets.zero,
        child: SizedBox.square(dimension: 18, child: icon),
      );
    }
    return BarButton(
      onTap: onTap,
      open: open,
      ink: ink,
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: (bold ? BarType.appName : BarType.item).copyWith(color: ink),
      ),
    );
  }
}

/// The clock at the trailing edge.
///
/// shell27 `clockText`: `ddd d MMM` then two spaces then the time, in 14 pt
/// DemiBold with `letterSpacing: 0.1`. The box is `implicitWidth + 16`.
class BarClock extends StatelessWidget {
  const BarClock({
    required this.time,
    required this.date,
    required this.showDate,
    required this.ink,
    this.vertical = false,
    this.crossExtent = BarTokens.height,
    this.onTap,
    this.open = false,
    super.key,
  });

  final bool vertical;
  final double crossExtent;
  final String time;
  final String date;
  final bool showDate;
  final Color ink;
  final VoidCallback? onTap;
  final bool open;

  @override
  Widget build(BuildContext context) {
    final style = BarType.clock.copyWith(color: ink);
    if (vertical) {
      final parts = RegExp(r'(\d{1,2})\D(\d{2})').firstMatch(time);
      return BarButton(
        onTap: onTap,
        open: open,
        ink: ink,
        width: crossExtent,
        height: 42,
        padding: EdgeInsets.zero,
        child: Text(
          parts == null ? time : '${parts[1]}\n${parts[2]}',
          textAlign: TextAlign.center,
          maxLines: 2,
          style: style.copyWith(fontSize: 12.5, height: 1.15),
        ),
      );
    }
    return BarButton(
      onTap: onTap,
      open: open,
      ink: ink,
      padding: const EdgeInsets.symmetric(horizontal: BarTokens.clockPadding),
      child: Text(
        showDate && date.isNotEmpty ? '$date  $time' : time,
        maxLines: 1,
        style: style,
      ),
    );
  }
}
