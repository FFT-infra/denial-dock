import 'package:denial_flutter_sdk/state.dart';
import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bar_icons.dart';
import '../bar_type.dart';

/// The rest of the system menu: window actions for the focused app and the
/// session sheet the power rows open.
///
/// macOS puts these under the Apple menu and the app menu; Denial has neither
/// a Finder nor per-app menus, so the window actions live in their own card
/// and the destructive actions go through `sessionPowerProvider`'s own
/// confirmation, which the SDK already gates per logind capability.
class SessionMenuPanel extends ConsumerWidget {
  const SessionMenuPanel({required this.onClose, super.key});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.shellTheme;
    final session = ref.watch(sessionPowerProvider);
    final controller = ref.read(sessionPowerProvider.notifier);
    final confirmation = session.confirmationAction;

    if (confirmation != null) {
      return _ConfirmCard(
        action: confirmation,
        busy: session.busy,
        error: session.error,
        onCancel: controller.cancelConfirmation,
        onConfirm: controller.confirm,
      );
    }

    final actions = <SessionPowerAction>[
      SessionPowerAction.lock,
      SessionPowerAction.suspend,
      SessionPowerAction.restartDenial,
      SessionPowerAction.reboot,
      SessionPowerAction.powerOff,
      SessionPowerAction.logout,
    ];

    return SizedBox(
      width: 232,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final action in actions)
              _SessionRow(
                icon: _iconFor(action),
                label: _labelFor(action),
                enabled:
                    !session.busy && session.availabilityFor(action).enabled,
                busy: session.busyAction == action,
                danger: action == SessionPowerAction.powerOff,
                onTap: () => controller.request(action),
              ),
            if (session.error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 2),
                child: Text(
                  session.error!,
                  style: BarType.caption.copyWith(
                    color: theme.colors.performanceBad,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static IconData _iconFor(SessionPowerAction action) => switch (action) {
    SessionPowerAction.lock => BarIcons.lock,
    SessionPowerAction.logout => BarIcons.person,
    SessionPowerAction.restartDenial => BarIcons.arrowClockwise,
    SessionPowerAction.suspend => BarIcons.moon,
    SessionPowerAction.hibernate => BarIcons.moonFill,
    SessionPowerAction.reboot => BarIcons.arrowClockwise,
    SessionPowerAction.powerOff => BarIcons.power,
  };

  static String _labelFor(SessionPowerAction action) => switch (action) {
    SessionPowerAction.lock => 'Lock Screen',
    SessionPowerAction.logout => 'Log Out…',
    SessionPowerAction.restartDenial => 'Restart Denial…',
    SessionPowerAction.suspend => 'Sleep',
    SessionPowerAction.hibernate => 'Hibernate',
    SessionPowerAction.reboot => 'Restart…',
    SessionPowerAction.powerOff => 'Shut Down…',
  };
}

class _SessionRow extends StatefulWidget {
  const _SessionRow({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.busy,
    required this.danger,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final bool busy;
  final bool danger;
  final VoidCallback onTap;

  @override
  State<_SessionRow> createState() => _SessionRowState();
}

class _SessionRowState extends State<_SessionRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final active = _hovered && widget.enabled;
    final ink = !widget.enabled
        ? theme.colors.textTertiary.withValues(alpha: 0.55)
        : active
        ? const Color(0xffffffff)
        : widget.danger
        ? theme.colors.performanceBad
        : theme.colors.textPrimary;
    return MouseRegion(
      cursor: widget.enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.enabled ? widget.onTap : null,
        child: Container(
          height: 28,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: active
                ? theme.accent.withValues(alpha: 0.85)
                : const Color(0x00000000),
            borderRadius: theme.borderRadius(6),
          ),
          child: Row(
            children: <Widget>[
              BarGlyph(widget.icon, size: 13, color: ink),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: BarType.menuRow.copyWith(color: ink),
                ),
              ),
              if (widget.busy)
                SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.4,
                    color: ink,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The confirmation the SDK requires for logout, restart and shut down.
class _ConfirmCard extends StatelessWidget {
  const _ConfirmCard({
    required this.action,
    required this.busy,
    required this.error,
    required this.onCancel,
    required this.onConfirm,
  });

  final SessionPowerAction action;
  final bool busy;
  final String? error;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    return SizedBox(
      width: 262,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              SessionMenuPanel._labelFor(action).replaceAll('…', ''),
              style: BarType.title.copyWith(color: theme.colors.textPrimary),
            ),
            const SizedBox(height: 6),
            Text(
              'Open windows will close. Continue?',
              style: BarType.caption.copyWith(
                color: theme.colors.textSecondary,
              ),
            ),
            if (error != null) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                error!,
                style: BarType.caption.copyWith(
                  color: theme.colors.performanceBad,
                ),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                _DialogButton(label: 'Cancel', onTap: onCancel),
                const SizedBox(width: 8),
                _DialogButton(
                  label: busy ? 'Working…' : 'Continue',
                  primary: true,
                  onTap: busy ? null : onConfirm,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DialogButton extends StatefulWidget {
  const _DialogButton({
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool primary;

  @override
  State<_DialogButton> createState() => _DialogButtonState();
}

class _DialogButtonState extends State<_DialogButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final enabled = widget.onTap != null;
    final fill = widget.primary
        ? theme.accent.withValues(alpha: enabled ? (_hovered ? 1 : 0.9) : 0.4)
        : theme.colors.textPrimary.withValues(alpha: _hovered ? 0.12 : 0.07);
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: Motion.pill,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: theme.borderRadius(7),
          ),
          child: Text(
            widget.label,
            style: BarType.caption.copyWith(
              fontWeight: FontWeight.w600,
              color: widget.primary
                  ? const Color(0xffffffff)
                  : theme.colors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
