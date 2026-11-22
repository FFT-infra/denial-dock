import 'package:flutter/widgets.dart';

import 'bar_button.dart';
import 'bar_tokens.dart';
import 'bar_type.dart';

/// The focused window's name, drawn where macOS puts the application menu.
///
/// The HIG says the active app's name is bold so people can find it at a
/// glance [S2]; shell27 and MacShell both set it DemiBold at 14 and pad the
/// title `width + 20`. Wayland has no global-menu protocol and most toolkits
/// export nothing, so the name is followed by the window title and the row
/// opens the window actions instead of a menu tree.
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
    final label = appName.isEmpty ? 'Finder' : appName;
    final hasTitle = showTitle && title.isNotEmpty && title != label;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        BarButton(
          onTap: onTap,
          open: open,
          ink: ink,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: BarType.appName.copyWith(color: ink),
          ),
        ),
        if (hasTitle)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: Padding(
              padding: const EdgeInsets.only(left: BarTokens.menuItemPadding),
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
/// macOS shows `Mon 24 Nov 9:41` when the date is on; shell27's `clockText`
/// builds exactly that with `ddd d MMM` then the time. The digits are
/// tabular so the row does not shift as the minute changes.
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
      child: Text(
        showDate && date.isNotEmpty ? '$date  $time' : time,
        maxLines: 1,
        style: style,
      ),
    );
  }
}
