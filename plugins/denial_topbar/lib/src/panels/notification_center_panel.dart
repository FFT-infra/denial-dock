import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/material.dart';

import 'calendar_panel.dart';
import 'notifications_panel.dart';
import 'panel_parts.dart';
import 'world_clock_card.dart';

/// The panel the clock opens.
///
/// macOS opens Notification Centre from the menu bar's date: widgets across
/// the top, notifications under them. shell27 splits the same content into a
/// 310 pt calendar popover and a 380 pt notification popover; this joins them
/// the way macOS 27 presents them, at the notification popover's 380 width so
/// every card lines up.
///
/// The widgets that need a service Denial does not have (Weather, Stocks,
/// Screen Time) are left out instead of drawn as empty cards.
class NotificationCenterPanel extends StatelessWidget {
  const NotificationCenterPanel({required this.onClose, super.key});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    return SizedBox(
      width: PanelWidth.notifications,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colors.textPrimary.withValues(alpha: 0.06),
                borderRadius: theme.borderRadius(18),
                border: Border.all(
                  color: theme.colors.hairlineSoft.withValues(alpha: 0.4),
                ),
              ),
              child: CalendarPanel(
                onClose: onClose,
                width: PanelWidth.notifications - 28,
              ),
            ),
            const SizedBox(height: 8),
            const WorldClockCard(),
            const SizedBox(height: 8),
            NotificationHistoryPanel(onClose: onClose, compact: true),
          ],
        ),
      ),
    );
  }
}
