import 'package:denial_flutter_sdk/models.dart';
import 'package:denial_flutter_sdk/state.dart';
import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bar_icons.dart';
import 'panel_parts.dart';

/// The notification centre.
///
/// Ports shell27 `MacBar.qml`'s `notifPop`: 380 wide, an 18 pt inset, a 17
/// DemiBold title with a Clear All pill on the same line, a 36-high Do Not
/// Disturb tile with its own switch, then one 18-radius card per notification
/// with a 44 pt app tile at `x: 14; y: 15`, the app name at 14 DemiBold, the
/// summary at 14 Bold, the body at 13, and an age stamp or close button in the
/// top-right corner.
class NotificationHistoryPanel extends ConsumerWidget {
  const NotificationHistoryPanel({
    required this.onClose,
    this.compact = false,
    super.key,
  });

  final VoidCallback onClose;

  /// Drops the outer inset and width so the list can sit inside the
  /// notification centre under its widgets.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.shellTheme;
    final state = ref.watch(desktopNotificationsProvider);
    final controller = ref.read(desktopNotificationsProvider.notifier);
    final groups = state.groups;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final inset = compact
        ? EdgeInsets.zero
        : const EdgeInsets.fromLTRB(18, 14, 18, 14);

    return SizedBox(
      width: compact ? null : PanelWidth.notifications,
      child: Padding(
        padding: inset,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SizedBox(
              height: 26,
              child: Row(
                children: <Widget>[
                  Text(
                    compact ? 'Notifications' : 'Notification Center',
                    style: PanelText.title(theme).copyWith(fontSize: 17),
                  ),
                  const Spacer(),
                  if (groups.isNotEmpty)
                    _ClearAllButton(
                      onTap: () => controller.clearAll(),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            _DoNotDisturbRow(
              value: state.doNotDisturb,
              onChanged: (value) => controller.setDoNotDisturb(value),
            ),
            const SizedBox(height: 10),
            if (groups.isEmpty)
              SizedBox(
                height: 70,
                child: Center(
                  child: Text(
                    'No Notifications',
                    style: PanelText.body(theme).copyWith(
                      color: theme.colors.textSecondary,
                    ),
                  ),
                ),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: (screenHeight - 260).clamp(160.0, 440.0),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: groups.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final group = groups[index];
                    return NotificationCard(
                      group: group,
                      onActivate: () {
                        controller.invokeDefaultAction(
                          group.newest.notification.id,
                        );
                        onClose();
                      },
                      onDismiss: () =>
                          controller.dismissGroupFromHistory(group.key),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// shell27's Clear All pill: `implicitWidth + 20` wide, 24 high, radius 12.
class _ClearAllButton extends StatefulWidget {
  const _ClearAllButton({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_ClearAllButton> createState() => _ClearAllButtonState();
}

class _ClearAllButtonState extends State<_ClearAllButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: theme.colors.textPrimary.withValues(
              alpha: _hovered ? 0.14 : 0.08,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            'Clear All',
            style: PanelText.detail(
              theme,
            ).copyWith(color: theme.colors.textPrimary),
          ),
        ),
      ),
    );
  }
}

/// The Do Not Disturb tile: `height: 36`, radius 12, a moon at `x: 12`, the
/// label at `x: 36`, and the switch at `rightMargin: 8`.
class _DoNotDisturbRow extends StatelessWidget {
  const _DoNotDisturbRow({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    return SizedBox(
      height: 36,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colors.textPrimary.withValues(alpha: 0.06),
          borderRadius: theme.borderRadius(12),
          border: Border.all(
            color: theme.colors.hairlineSoft.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          children: <Widget>[
            const SizedBox(width: 12),
            BarGlyph(
              BarIcons.moon,
              size: 15,
              color: theme.colors.textPrimary,
            ),
            const SizedBox(width: 9),
            Text('Do Not Disturb', style: PanelText.body(theme)),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: PanelSwitch(value: value, onChanged: onChanged),
            ),
          ],
        ),
      ),
    );
  }
}

/// One notification card: shell27's 18-radius tile with a 44 pt app icon.
class NotificationCard extends StatefulWidget {
  const NotificationCard({
    required this.group,
    required this.onActivate,
    required this.onDismiss,
    super.key,
  });

  final DesktopNotificationGroup group;
  final VoidCallback onActivate;
  final VoidCallback onDismiss;

  @override
  State<NotificationCard> createState() => _NotificationCardState();
}

class _NotificationCardState extends State<NotificationCard> {
  bool _hovered = false;

  /// shell27's `agoText`: `now`, `12m ago`, `3h ago`, `2d ago`.
  String _ago(int timeMs) {
    if (timeMs <= 0) return '';
    final minutes =
        (DateTime.now().millisecondsSinceEpoch - timeMs) ~/ 60000;
    if (minutes < 1) return 'now';
    if (minutes < 60) return '${minutes}m ago';
    if (minutes < 1440) return '${minutes ~/ 60}h ago';
    return '${minutes ~/ 1440}d ago';
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final newest = widget.group.newest.notification;
    final app = newest.appName.isEmpty ? newest.sender : newest.appName;
    final summary = newest.summary.replaceAll(RegExp(r'\s*\n\s*'), ' ');
    final body = newest.body.replaceAll(RegExp(r'\s*\n\s*'), ' ');
    final timeSensitive = newest.urgency == DesktopNotificationUrgency.critical;
    final age = _ago(newest.timeMs);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onActivate,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colors.textPrimary.withValues(alpha: 0.07),
            borderRadius: theme.borderRadius(18),
            border: Border.all(
              color: theme.colors.hairlineSoft.withValues(alpha: 0.4),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 15, 14, 15),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: theme.accent,
                    borderRadius: theme.borderRadius(10),
                  ),
                  child: Center(
                    child: BarGlyph(
                      BarIcons.bell,
                      size: 24,
                      color: const Color(0xffffffff),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      if (app.isNotEmpty)
                        Text(
                          timeSensitive ? 'TIME SENSITIVE' : app,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: PanelText.body(theme).copyWith(
                            fontSize: timeSensitive ? 12 : 14,
                            fontWeight: FontWeight.w600,
                            letterSpacing: timeSensitive ? 0.4 : 0,
                            color: timeSensitive
                                ? theme.colors.textSecondary
                                : theme.colors.textPrimary,
                          ),
                        ),
                      if (summary.isNotEmpty)
                        Text(
                          summary,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: PanelText.body(theme).copyWith(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      if (body.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 1),
                        Text(
                          body,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: PanelText.body(theme),
                        ),
                      ],
                      if (widget.group.stacked) ...<Widget>[
                        const SizedBox(height: 3),
                        Text(
                          '${widget.group.members.length} notifications',
                          style: PanelText.detail(theme),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 44,
                  child: Align(
                    alignment: Alignment.topRight,
                    child: _hovered && widget.group.clearable
                        ? _CloseButton(onTap: widget.onDismiss)
                        : (age.isEmpty
                              ? const SizedBox.shrink()
                              : Text(age, style: PanelText.detail(theme))),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// shell27's close chip: 22 × 22 at radius 11, `rightMargin: 10`, `y: 10`.
class _CloseButton extends StatefulWidget {
  const _CloseButton({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_CloseButton> createState() => _CloseButtonState();
}

class _CloseButtonState extends State<_CloseButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: theme.colors.textPrimary.withValues(
              alpha: _hovered ? 0.18 : 0.1,
            ),
          ),
          child: Center(
            child: BarGlyph(
              BarIcons.xmark,
              size: 12,
              color: theme.colors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
