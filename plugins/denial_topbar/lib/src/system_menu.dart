import 'package:denial_flutter_sdk/services.dart';
import 'package:denial_flutter_sdk/state.dart';
import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'bar_button.dart';
import 'bar_icons.dart';
import 'bar_menu.dart';
import 'bar_tokens.dart';
import 'bar_type.dart';

/// The leftmost logo slot.
///
/// shell27 gives it 30 × 28 with a 15 pt mark; MacShell the same. macOS puts
/// the Apple mark there, so this holds the host's own distro mark instead.
class BarSystemMenu extends StatelessWidget {
  const BarSystemMenu({
    required this.glyph,
    required this.open,
    required this.ink,
    required this.onToggle,
    super.key,
  });

  /// Distribution mark, e.g. the Fedora logo.
  final Widget glyph;
  final bool open;
  final Color ink;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return BarButton(
      width: BarTokens.systemMenuWidth,
      padding: EdgeInsets.zero,
      open: open,
      ink: ink,
      onTap: onToggle,
      tooltip: 'System',
      child: SizedBox(
        width: BarTokens.systemMenuGlyph,
        height: BarTokens.systemMenuGlyph,
        child: glyph,
      ),
    );
  }
}

/// Rows of the system menu, in macOS's order.
///
/// shell27 `MacBar.qml` builds the same list: About, Settings, Force Quit,
/// Sleep, Restart, Shut Down, Lock Screen, Log Out. Entries the shell cannot
/// honour stay visible but disabled, the way shell27 leaves unimplemented
/// items greyed instead of hiding them.
///
/// The bar's own settings live here rather than on a gear button, because
/// macOS has no separate bar settings item: its System Settings is the only
/// door, so this menu is where Denial's equivalent belongs.
class SystemMenuBody extends ConsumerStatefulWidget {
  const SystemMenuBody({
    required this.services,
    required this.onClose,
    this.onBarSettings,
    super.key,
  });

  final ShellServices services;
  final VoidCallback onClose;
  final VoidCallback? onBarSettings;

  @override
  ConsumerState<SystemMenuBody> createState() => _SystemMenuBodyState();
}

class _SystemMenuBodyState extends ConsumerState<SystemMenuBody> {
  /// shell27 shows a submenu in place of the parent list with a `‹` header that
  /// steps back one level; `''` is the root menu.
  String _page = '';

  ShellServices get _services => widget.services;

  void _close() => widget.onClose();

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionPowerProvider);
    final controller = ref.read(sessionPowerProvider.notifier);
    final busy = session.busyAction != null;

    bool can(SessionPowerAction action) =>
        !busy && session.availabilityFor(action).enabled;

    void run(SessionPowerAction action) {
      // Logout, restart and shut down need the SDK's own confirmation. macOS
      // shows an alert; this shows the confirmation in place of the menu, so
      // the popover stays open and the user can still cancel.
      if (action.requiresConfirmation) {
        controller.request(action);
        setState(() => _page = 'power');
        return;
      }
      _close();
      controller.request(action);
    }

    if (_page == 'power') {
      return SizedBox(
        width: BarTokens.menuWidth,
        child: BarMenuColumn(children: _powerRows(context)),
      );
    }
    if (_page == 'recent') {
      return SizedBox(
        width: BarTokens.menuWidth,
        child: BarMenuColumn(children: _recentRows(context)),
      );
    }
    if (_page == 'forceQuit') {
      return SizedBox(
        width: BarTokens.menuWidth,
        child: BarMenuColumn(children: _forceQuitRows(context)),
      );
    }

    return SizedBox(
      width: BarTokens.menuWidth,
      child: BarMenuColumn(
        children: <Widget>[
          BarMenuRow(
            label: 'About This System…',
            onTap: () {
              _close();
              _services.openDashboard();
            },
          ),
          const BarMenuDivider(),
          BarMenuRow(
            label: 'System Settings…',
            shortcut: '⌘,',
            onTap: () {
              _close();
              _services.openPowerSettings();
            },
          ),
          BarMenuRow(
            label: 'Menu Bar Settings…',
            onTap: () {
              _close();
              widget.onBarSettings?.call();
            },
          ),
          BarMenuRow(label: 'App Store…', enabled: false, onTap: null),
          BarMenuRow(
            label: 'Recent Items',
            chevron: true,
            onTap: () => setState(() => _page = 'recent'),
          ),
          const BarMenuDivider(),
          BarMenuRow(
            label: 'Force Quit…',
            shortcut: '⌥⌘⎋',
            onTap: () => setState(() => _page = 'forceQuit'),
          ),
          const BarMenuDivider(),
          BarMenuRow(
            label: 'Sleep',
            enabled: can(SessionPowerAction.suspend),
            onTap: () => run(SessionPowerAction.suspend),
          ),
          BarMenuRow(
            label: 'Restart…',
            enabled: can(SessionPowerAction.reboot),
            onTap: () => run(SessionPowerAction.reboot),
          ),
          BarMenuRow(
            label: 'Shut Down…',
            enabled: can(SessionPowerAction.powerOff),
            destructive: true,
            onTap: () => run(SessionPowerAction.powerOff),
          ),
          const BarMenuDivider(),
          BarMenuRow(
            label: 'Lock Screen',
            shortcut: '⌃⌘Q',
            enabled: can(SessionPowerAction.lock),
            onTap: () => run(SessionPowerAction.lock),
          ),
          BarMenuRow(
            label: 'Log Out…',
            shortcut: '⇧⌘Q',
            enabled: can(SessionPowerAction.logout),
            onTap: () => run(SessionPowerAction.logout),
          ),
        ],
      ),
    );
  }

  /// The `‹ Recent Items` page: one row per running application, newest
  /// window first, each row raising that app's window.
  ///
  /// macOS lists recently opened documents here. Denial has no document
  /// registry, so the closest real thing is the applications the session is
  /// running; an empty list says so instead of showing dead rows.
  List<Widget> _recentRows(BuildContext context) {
    final windows = ref.watch(shellControllerProvider).openAppWindows;
    final names = <String, String>{
      for (final application in ref.watch(_services.applications))
        application.appId: application.name,
    };
    final seen = <String>{};
    final rows = <Widget>[
      _SubmenuHeader(
        label: 'Recent Items',
        onBack: () => setState(() => _page = ''),
      ),
      const BarMenuDivider(),
    ];
    for (final window in windows.reversed) {
      final key = window.appId.isEmpty ? '${window.objectId}' : window.appId;
      if (!seen.add(key)) continue;
      final name = names[window.appId];
      rows.add(
        BarMenuRow(
          label: name == null || name.isEmpty
              ? (window.title.isEmpty ? 'Untitled' : window.title)
              : name,
          onTap: () {
            _close();
            _services.activateWindow(window.windowId);
          },
        ),
      );
      if (seen.length == 8) break;
    }
    if (seen.isEmpty) {
      rows.add(const BarMenuRow(label: 'No Recent Items', enabled: false));
    }
    return rows;
  }

  /// The confirmation page the SDK requires before logout, restart or shut
  /// down. It replaces the menu list the way macOS replaces a menu with its
  /// own alert, and steps back to the list on Cancel.
  List<Widget> _powerRows(BuildContext context) {
    final session = ref.watch(sessionPowerProvider);
    final controller = ref.read(sessionPowerProvider.notifier);
    final action = session.confirmationAction;
    final theme = context.shellTheme;
    if (action == null) {
      // The request finished (or was cleared elsewhere): fall back to the
      // list rather than showing an empty card.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _page == 'power') setState(() => _page = '');
      });
      return <Widget>[
        _SubmenuHeader(
          label: 'Restart',
          onBack: () => setState(() => _page = ''),
        ),
      ];
    }
    final label = switch (action) {
      SessionPowerAction.logout => 'Log Out',
      SessionPowerAction.reboot => 'Restart',
      SessionPowerAction.powerOff => 'Shut Down',
      SessionPowerAction.restartDenial => 'Restart Denial',
      _ => 'Continue',
    };
    return <Widget>[
      _SubmenuHeader(
        label: label,
        onBack: () => setState(() => _page = ''),
      ),
      const BarMenuDivider(),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
        child: Text(
          'Open windows will close. Continue?',
          style: BarType.caption.copyWith(color: theme.colors.textSecondary),
        ),
      ),
      if (session.error != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
          child: Text(
            session.error!,
            style: BarType.caption.copyWith(
              color: theme.colors.performanceBad,
            ),
          ),
        ),
      BarMenuRow(
        label: session.busy ? 'Working…' : '$label…',
        destructive: action == SessionPowerAction.powerOff,
        enabled: !session.busy,
        onTap: () {
          controller.confirm();
          setState(() => _page = '');
        },
      ),
    ];
  }

  /// The `‹ Force Quit` page: every open application window, each row closing
  /// that window the way macOS's Force Quit list ends the process.
  // ignore: unused_element_parameter
  List<Widget> _forceQuitRows(BuildContext context) {
    final state = ref.watch(shellControllerProvider);
    final windows = state.openAppWindows;
    final rows = <Widget>[
      _SubmenuHeader(
        label: 'Force Quit',
        onBack: () => setState(() => _page = ''),
      ),
      const BarMenuDivider(),
    ];
    if (windows.isEmpty) {
      rows.add(const BarMenuRow(label: 'No Open Windows', enabled: false));
      return rows;
    }
    final controller = ref.read(shellControllerProvider.notifier);
    for (final window in windows.take(10)) {
      rows.add(
        BarMenuRow(
          label: window.title.isEmpty ? 'Untitled' : window.title,
          onTap: () {
            _close();
            controller.closeWindow(window);
          },
        ),
      );
    }
    return rows;
  }
}

/// The `‹ Title` row shell27 puts at the top of a submenu.
class _SubmenuHeader extends StatefulWidget {
  const _SubmenuHeader({required this.label, required this.onBack});

  final String label;
  final VoidCallback onBack;

  @override
  State<_SubmenuHeader> createState() => _SubmenuHeaderState();
}

class _SubmenuHeaderState extends State<_SubmenuHeader> {
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
        onTap: widget.onBack,
        child: SizedBox(
          height: BarTokens.menuRowHeight,
          child: Stack(
            children: <Widget>[
              if (_hovered)
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: theme.accent,
                      borderRadius: BorderRadius.circular(
                        BarTokens.menuRowRadius,
                      ),
                    ),
                  ),
                ),
              Positioned(
                left: 12,
                right: 12,
                top: 0,
                bottom: 0,
                child: Row(
                  children: <Widget>[
                    BarGlyph(
                      BarIcons.chevronLeft,
                      size: 11,
                      color: _hovered
                          ? const Color(0xffffffff)
                          : theme.colors.textPrimary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        widget.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: BarType.menuRow.copyWith(
                          fontSize: BarTokens.menuRowFontSize,
                          fontWeight: FontWeight.w600,
                          color: _hovered
                              ? const Color(0xffffffff)
                              : theme.colors.textPrimary,
                        ),
                      ),
                    ),
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
