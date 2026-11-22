import 'package:denial_flutter_sdk/models.dart';
import 'package:denial_flutter_sdk/state.dart';
import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class TopBarNotificationsPanel extends ConsumerWidget {
  const TopBarNotificationsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(desktopNotificationsProvider);
    final controller = ref.read(desktopNotificationsProvider.notifier);
    final theme = context.shellTheme;
    final records = state.history.reversed.take(24).toList();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 10, 8),
          child: Row(
            children: <Widget>[
              Text(
                'Notifications',
                style: theme.text.systemBarValue.copyWith(
                  color: theme.colors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              if (records.isNotEmpty)
                _HeaderAction(label: 'Clear', onTap: controller.clearAll),
              const SizedBox(width: 4),
              _HeaderAction(
                label: state.doNotDisturb ? 'Do Not Disturb' : 'DND',
                active: state.doNotDisturb,
                onTap: controller.toggleDoNotDisturb,
              ),
            ],
          ),
        ),
        if (records.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 22),
            child: Text(
              'No notifications',
              style: theme.text.systemBarValue.copyWith(
                color: theme.colors.textSecondary,
              ),
            ),
          )
        else
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
              child: Column(
                children: <Widget>[
                  for (final record in records)
                    _NotificationRow(
                      notification: record.notification,
                      unread: record.unread,
                      onDismiss: () =>
                          controller.dismissFromHistory(record.notification.id),
                      onOpen: () => controller.invokeDefaultAction(
                        record.notification.id,
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _HeaderAction extends StatefulWidget {
  const _HeaderAction({
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  State<_HeaderAction> createState() => _HeaderActionState();
}

class _HeaderActionState extends State<_HeaderAction> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final color = widget.active
        ? theme.accent
        : _hovered
        ? theme.colors.textPrimary
        : theme.colors.textSecondary;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: widget.active
                ? theme.accent.withValues(alpha: 0.14)
                : _hovered
                ? theme.colors.textPrimary.withValues(alpha: 0.06)
                : Colors.transparent,
            borderRadius: theme.borderRadius(7),
          ),
          child: Text(
            widget.label,
            style: theme.text.systemBarCaption.copyWith(color: color),
          ),
        ),
      ),
    );
  }
}

class _NotificationRow extends StatefulWidget {
  const _NotificationRow({
    required this.notification,
    required this.unread,
    required this.onDismiss,
    required this.onOpen,
  });

  final DesktopNotification notification;
  final bool unread;
  final VoidCallback onDismiss;
  final VoidCallback onOpen;

  @override
  State<_NotificationRow> createState() => _NotificationRowState();
}

class _NotificationRowState extends State<_NotificationRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final notification = widget.notification;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onOpen,
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.fromLTRB(10, 9, 6, 9),
          decoration: BoxDecoration(
            color: _hovered
                ? theme.colors.textPrimary.withValues(alpha: 0.055)
                : theme.colors.textPrimary.withValues(alpha: 0.025),
            borderRadius: theme.borderRadius(11),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: widget.unread
                        ? theme.accent
                        : theme.colors.textTertiary.withValues(alpha: 0.4),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            notification.appName.isEmpty
                                ? notification.sender
                                : notification.appName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.text.systemBarCaption.copyWith(
                              color: theme.colors.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (_hovered)
                          GestureDetector(
                            onTap: widget.onDismiss,
                            child: Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: Icon(
                                Icons.close,
                                size: 13,
                                color: theme.colors.textTertiary,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      notification.summary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.text.systemBarValue.copyWith(
                        color: theme.colors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (notification.body.trim().isNotEmpty) ...<Widget>[
                      const SizedBox(height: 1),
                      Text(
                        notification.body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.text.systemBarCaption.copyWith(
                          color: theme.colors.textSecondary,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
