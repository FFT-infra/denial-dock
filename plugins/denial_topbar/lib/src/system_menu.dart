import 'package:denial_flutter_sdk/services.dart';
import 'package:denial_flutter_sdk/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'bar_button.dart';
import 'bar_menu.dart';
import 'bar_tokens.dart';

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
class SystemMenuBody extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionPowerProvider);
    final controller = ref.read(sessionPowerProvider.notifier);
    final busy = session.busyAction != null;

    bool can(SessionPowerAction action) =>
        !busy && session.availabilityFor(action).enabled;

    void run(SessionPowerAction action) {
      onClose();
      controller.request(action);
    }

    return SizedBox(
      width: BarTokens.menuWidth,
      child: BarMenuColumn(
        children: <Widget>[
          BarMenuRow(
            label: 'About This System…',
            onTap: () {
              onClose();
              services.openDashboard();
            },
          ),
          const BarMenuDivider(),
          BarMenuRow(
            label: 'System Settings…',
            shortcut: '⌘,',
            onTap: () {
              onClose();
              services.openPowerSettings();
            },
          ),
          BarMenuRow(
            label: 'Menu Bar Settings…',
            onTap: () {
              onClose();
              onBarSettings?.call();
            },
          ),
          BarMenuRow(label: 'App Store…', enabled: false, onTap: null),
          BarMenuRow(
            label: 'Recent Items ▸',
            enabled: false,
            onTap: null,
          ),
          const BarMenuDivider(),
          BarMenuRow(label: 'Force Quit…', enabled: false, onTap: null),
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
}
