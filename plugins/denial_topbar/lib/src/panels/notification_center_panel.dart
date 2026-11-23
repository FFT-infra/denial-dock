import 'package:flutter/material.dart';

import 'calendar_widget.dart';
import 'notifications_panel.dart';
import 'panel_parts.dart';
import 'world_clock_card.dart';

/// The Notification Center panel that opens from the clock/date.
///
/// Follows macOS 27 and `0-ss/MacShell`'s Notification Center:
/// - 380 pt width.
/// - Top section: macOS widgets (Medium Calendar widget, World clock).
/// - Bottom section: Notification stream (app-grouped cards with dismiss/expand).
class NotificationCenterPanel extends StatelessWidget {
  const NotificationCenterPanel({required this.onClose, super.key});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: PanelWidth.notifications,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            CalendarWidget(
              width: PanelWidth.notifications - 28,
              onTap: onClose,
            ),
            const SizedBox(height: 10),
            const WorldClockCard(),
            const SizedBox(height: 10),
            NotificationHistoryPanel(onClose: onClose, compact: true),
          ],
        ),
      ),
    );
  }
}
