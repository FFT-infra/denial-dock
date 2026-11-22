import 'package:denial_flutter_sdk/state.dart';
import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bar_icons.dart';
import '../bar_tokens.dart';
import '../bar_type.dart';

/// Notification history.
///
/// Ports NextKDE `NotificationHistoryPanel.qml`: width `min(336, screen - 24)`,
/// 20 side margins, 8 top, a 560 maximum height inside the screen, and one
/// grouped card per app with a Clear all row above the list.
class NotificationHistoryPanel extends ConsumerWidget {
  const NotificationHistoryPanel({
    required this.onClose,
    this.width = BarTokens.controlCenterWidth,
    super.key,
  });

  final VoidCallback onClose;
  final double width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.shellTheme;
    final state = ref.watch(desktopNotificationsProvider);
    final controller = ref.read(desktopNotificationsProvider.notifier);
    final groups = state.groups;
    final height = MediaQuery.sizeOf(context).height;

    return SizedBox(
      width: width,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: (height - 110).clamp(208, 576)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Text(
                    'Notifications',
                    style: BarType.title.copyWith(
                      fontSize: 15,
                      color: theme.colors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  if (groups.isNotEmpty)
                    _TextButton(
                      label: 'Clear All',
                      onTap: () {
                        controller.clearAll();
                        onClose();
                      },
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (groups.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 28),
                  child: Column(
                    children: <Widget>[
                      BarGlyph(
                        BarIcons.bellSlash,
                        size: 26,
                        color: theme.colors.textTertiary,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'No Notifications',
                        style: BarType.item.copyWith(
                          color: theme.colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: groups.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final group = groups[index];
                      return _NotificationCard(
                        group: group,
                        onDismiss: () =>
                            controller.dismissGroupFromHistory(group.key),
                        onActivate: () {
                          controller.invokeDefaultAction(
                            group.newest.notification.id,
                          );
                          onClose();
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.group,
    required this.onDismiss,
    required this.onActivate,
  });

  final DesktopNotificationGroup group;
  final VoidCallback onDismiss;
  final VoidCallback onActivate;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final newest = group.newest.notification;
    final title = newest.summary.replaceAll(RegExp(r'\s*\n\s*'), ' ');
    final body = newest.body.replaceAll(RegExp(r'\s*\n\s*'), ' ');
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onActivate,
      child: Container(
        decoration: BoxDecoration(
          color: theme.colors.surfaceContainer.withValues(alpha: 0.62),
          borderRadius: theme.borderRadius(19),
        ),
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: theme.colors.textPrimary.withValues(alpha: 0.08),
                borderRadius: theme.borderRadius(10),
              ),
              child: BarGlyph(
                BarIcons.bellFill,
                size: 16,
                color: theme.colors.textSecondary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          newest.appName.isEmpty
                              ? newest.sender
                              : newest.appName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: BarType.caption.copyWith(
                            fontWeight: FontWeight.w600,
                            color: theme.colors.textSecondary,
                          ),
                        ),
                      ),
                      if (group.stacked)
                        Text(
                          '${group.members.length}',
                          style: BarType.caption.copyWith(
                            color: theme.colors.textTertiary,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: BarType.value.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colors.textPrimary,
                    ),
                  ),
                  if (body.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 2),
                    Text(
                      body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: BarType.caption.copyWith(
                        color: theme.colors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (group.clearable)
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: onDismiss,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: BarGlyph(
                      BarIcons.xmark,
                      size: 11,
                      color: theme.colors.textTertiary,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TextButton extends StatelessWidget {
  const _TextButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Text(
            label,
            style: BarType.caption.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.accent,
            ),
          ),
        ),
      ),
    );
  }
}
