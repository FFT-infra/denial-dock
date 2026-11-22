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
    this.onTap,
    this.open = false,
    super.key,
  });

  final String label;
  final Color ink;
  final bool bold;
  final VoidCallback? onTap;
  final bool open;

  @override
  Widget build(BuildContext context) {
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

/// The focused window's name, drawn where macOS puts the application menu.
///
/// The HIG requires the active app's name in bold so people can find it at a
/// glance; shell27 sets it DemiBold at 14. Wayland has no global-menu protocol
/// and most toolkits export nothing, so the name is followed by the window
/// title and the row opens the window actions instead of a menu tree.
class BarAppMenu extends StatelessWidget {
  const BarAppMenu({
    required this.appName,
    required this.title,
    required this.showTitle,
    required this.ink,
    this.onTap,
    this.open = false,
    super.key,
  });

  final String appName;

  /// Active window title, or empty when no user window is focused.
  final String title;
  final bool showTitle;
  final Color ink;
  final VoidCallback? onTap;
  final bool open;

  @override
  Widget build(BuildContext context) {
    final label = appName.isEmpty ? 'Desktop' : appName;
    final hasTitle = showTitle && title.isNotEmpty && title != label;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        BarTitle(label: label, ink: ink, bold: true, onTap: onTap, open: open),
        if (hasTitle)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: BarType.item.copyWith(
                  color: ink.withValues(alpha: 0.65),
                ),
              ),
            ),
          ),
      ],
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
    this.onTap,
    this.open = false,
    super.key,
  });

  final String time;
  final String date;
  final bool showDate;
  final Color ink;
  final VoidCallback? onTap;
  final bool open;

  @override
  Widget build(BuildContext context) {
    final style = BarType.clock.copyWith(color: ink);
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
