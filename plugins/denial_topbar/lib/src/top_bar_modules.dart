import 'package:denial_flutter_sdk/services.dart';
import 'package:denial_flutter_sdk/state.dart';
import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A bar control with the macOS-sized hit area and a short press wash.
class TopBarButton extends StatefulWidget {
  const TopBarButton({
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.symmetric(horizontal: 10),
    this.minWidth = 34,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final double minWidth;

  @override
  State<TopBarButton> createState() => _TopBarButtonState();
}

class _TopBarButtonState extends State<TopBarButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final wash =
        (_pressed
                ? 0.14
                : _hovered
                ? 0.09
                : 0.0)
            .toDouble();
    return MouseRegion(
      cursor: widget.onTap == null
          ? MouseCursor.defer
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: widget.onTap == null
            ? null
            : (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          constraints: BoxConstraints(minWidth: widget.minWidth, minHeight: 28),
          padding: widget.padding,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: theme.colors.textPrimary.withValues(alpha: wash),
            borderRadius: theme.borderRadius(8),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

class TopBarClock extends ConsumerWidget {
  const TopBarClock({
    required this.services,
    required this.showDate,
    required this.onTap,
    this.compact = false,
    super.key,
  });

  final ShellServices services;
  final bool showDate;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(services.clock).value ?? DateTime.now();
    final strings = services.strings(context);
    final theme = context.shellTheme;
    if (compact) {
      return TopBarButton(
        onTap: onTap,
        child: Icon(Icons.schedule, size: 16, color: theme.colors.textPrimary),
      );
    }
    final text = showDate
        ? '${strings.shortDate(now)}  ${strings.time(now)}'
        : strings.time(now);
    return TopBarButton(
      onTap: onTap,
      child: Text(
        text,
        maxLines: 1,
        style: theme.text.systemBarValue.copyWith(
          color: theme.colors.textPrimary,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class TopBarWorkspaces extends ConsumerWidget {
  const TopBarWorkspaces({
    required this.monitorId,
    required this.services,
    required this.horizontal,
    super.key,
  });

  final int monitorId;
  final ShellServices services;
  final bool horizontal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(services.workspacesEnabled);
    if (!enabled) return const SizedBox.shrink();
    final status = ref.watch(services.workspace(monitorId));
    final strings = services.strings(context);
    return Flex(
      direction: horizontal ? Axis.horizontal : Axis.vertical,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (var index = 1; index <= status.count; index++)
          _WorkspaceSlot(
            label: strings.workspaceLabel(index),
            active: status.active == index,
            occupied: status.occupied.contains(index),
            onTap: () => services.switchWorkspace(
              monitorId: monitorId,
              workspaceId: index,
            ),
          ),
      ],
    );
  }
}

class _WorkspaceSlot extends StatefulWidget {
  const _WorkspaceSlot({
    required this.label,
    required this.active,
    required this.occupied,
    required this.onTap,
  });

  final String label;
  final bool active;
  final bool occupied;
  final VoidCallback onTap;

  @override
  State<_WorkspaceSlot> createState() => _WorkspaceSlotState();
}

class _WorkspaceSlotState extends State<_WorkspaceSlot> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final color = widget.active
        ? theme.colors.textPrimary
        : theme.colors.textPrimary.withValues(
            alpha: widget.occupied
                ? (_hovered ? 0.85 : 0.62)
                : (_hovered ? 0.5 : 0.3),
          );
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          width: 20,
          height: 26,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            color: widget.active
                ? theme.accent.withValues(alpha: 0.18)
                : Colors.transparent,
            borderRadius: theme.borderRadius(6),
          ),
          alignment: Alignment.center,
          child: Text(
            widget.label,
            style: theme.text.systemBarCaption.copyWith(
              color: color,
              fontWeight: widget.active ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class TopBarBattery extends ConsumerWidget {
  const TopBarBattery({
    required this.services,
    required this.showPercent,
    required this.onTap,
    super.key,
  });

  final ShellServices services;
  final bool showPercent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final battery = ref.watch(services.battery);
    if (battery.capacity == null) return const SizedBox.shrink();
    final percent = battery.capacity!;
    final icon = battery.charging
        ? Icons.battery_charging_full
        : percent >= 95
        ? Icons.battery_full
        : percent >= 80
        ? Icons.battery_6_bar
        : percent >= 60
        ? Icons.battery_5_bar
        : percent >= 40
        ? Icons.battery_4_bar
        : percent >= 20
        ? Icons.battery_3_bar
        : Icons.battery_1_bar;
    final color = percent <= 15 && !battery.charging
        ? context.shellTheme.colors.performanceBad
        : context.shellTheme.colors.textPrimary;
    return TopBarButton(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 17, color: color),
          if (showPercent) ...<Widget>[
            const SizedBox(width: 5),
            Text(
              '$percent%',
              style: context.shellTheme.text.systemBarCaption.copyWith(
                color: color,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class TopBarMediaChip extends ConsumerWidget {
  const TopBarMediaChip({
    required this.services,
    required this.onTap,
    this.compact = false,
    super.key,
  });

  final ShellServices services;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playback = ref.watch(services.media).value;
    if (playback == null || !playback.available) {
      return const SizedBox.shrink();
    }
    final theme = context.shellTheme;
    final icon = Icon(
      playback.playing ? Icons.pause : Icons.play_arrow,
      size: 16,
      color: theme.colors.textPrimary,
    );
    if (compact) {
      return TopBarButton(onTap: onTap, child: icon);
    }
    return TopBarButton(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          icon,
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 132),
            child: Text(
              playback.title.isEmpty ? playback.identity : playback.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.text.systemBarCaption.copyWith(
                color: theme.colors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class TopBarNotifications extends ConsumerWidget {
  const TopBarNotifications({
    required this.showBadge,
    required this.onTap,
    super.key,
  });

  final bool showBadge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(
      desktopNotificationsProvider.select((state) => state.unreadCount),
    );
    final theme = context.shellTheme;
    return TopBarButton(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Icon(
            Icons.notifications_none,
            size: 17,
            color: theme.colors.textPrimary,
          ),
          if (showBadge && unread > 0)
            Positioned(
              right: -4,
              top: -3,
              child: Container(
                constraints: const BoxConstraints(minWidth: 12, minHeight: 12),
                padding: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color: theme.accent,
                  borderRadius: BorderRadius.circular(6),
                ),
                alignment: Alignment.center,
                child: Text(
                  unread > 9 ? '9+' : '$unread',
                  style: theme.text.systemBarCaption.copyWith(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class TopBarTray extends ConsumerWidget {
  const TopBarTray({
    required this.services,
    required this.horizontal,
    super.key,
  });

  final ShellServices services;
  final bool horizontal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visible = ref.watch(services.trayVisible);
    final ids = ref.watch(services.trayItemIds);
    if (!visible || ids.isEmpty) return const SizedBox.shrink();
    final theme = context.shellTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: horizontal ? 260 : 32),
        child: services.buildSystemTray(
          context,
          horizontal: horizontal,
          foregroundColor: theme.colors.textPrimary,
        ),
      ),
    );
  }
}

class TopBarWindowTitle extends ConsumerWidget {
  const TopBarWindowTitle({
    required this.monitorId,
    required this.services,
    super.key,
  });

  final int monitorId;
  final ShellServices services;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final windows = ref.watch(services.windows(monitorId));
    ApplicationWindow? active;
    for (final window in windows) {
      if (window.active) {
        active = window;
        break;
      }
    }
    if (active == null || active.title.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    final theme = context.shellTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 220),
        child: Text(
          active.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.text.systemBarValue.copyWith(
            color: theme.colors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class TopBarSettingsButton extends ConsumerWidget {
  const TopBarSettingsButton({required this.onTap, super.key});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TopBarButton(
      onTap: onTap,
      child: Icon(
        Icons.tune,
        size: 16,
        color: context.shellTheme.colors.textPrimary,
      ),
    );
  }
}
