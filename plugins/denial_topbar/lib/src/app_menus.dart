import 'package:denial_flutter_sdk/models.dart';
import 'package:denial_flutter_sdk/services.dart';
import 'package:denial_flutter_sdk/settings.dart';
import 'package:denial_flutter_sdk/state.dart';
import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_menu.dart';
import 'bar_icons.dart';
import 'bar_menu.dart';
import 'bar_tokens.dart';

/// The menu bar's title row.
///
/// shell27 `MacBar.qml` ships a fixed list — `apple | app | File | Edit | View |
/// Window | Help` — because Wayland has no global-menu protocol and most
/// toolkits export nothing. This mirrors it: the app's name is the only bold
/// title, the five menu titles follow, and every entry that this shell cannot
/// honour stays visible but disabled, the way macOS greys out an unavailable
/// command instead of hiding it.
enum AppMenuId { app, file, edit, view, window, help }

class AppMenuTitle {
  const AppMenuTitle({
    required this.id,
    required this.label,
    this.bold = false,
  });

  final AppMenuId id;
  final String label;
  final bool bold;
}

/// The titles in shell27's order, with the focused app's own name first.
List<AppMenuTitle> appMenuTitles(String appName) => <AppMenuTitle>[
  AppMenuTitle(id: AppMenuId.app, label: appName, bold: true),
  const AppMenuTitle(id: AppMenuId.file, label: 'File'),
  const AppMenuTitle(id: AppMenuId.edit, label: 'Edit'),
  const AppMenuTitle(id: AppMenuId.view, label: 'View'),
  const AppMenuTitle(id: AppMenuId.window, label: 'Window'),
  const AppMenuTitle(id: AppMenuId.help, label: 'Help'),
];

/// One menu's body.
///
/// The rows come from shell27's `menuModelFor`, restricted to commands Denial
/// can actually carry out: window management through `ShellWindowServices`,
/// appearance through the settings controller, and the clipboard and session
/// through their own providers. Anything with no counterpart is drawn disabled
/// so the menu keeps macOS's shape rather than collapsing to two live rows.
class AppMenuBody extends ConsumerWidget {
  const AppMenuBody({
    required this.id,
    required this.services,
    required this.monitorId,
    required this.onClose,
    this.onBarSettings,
    super.key,
  });

  final AppMenuId id;
  final ShellServices services;
  final int monitorId;
  final VoidCallback onClose;

  /// Opens the bar's own settings sheet from View ▸ Menu Bar Settings….
  final VoidCallback? onBarSettings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(shellControllerProvider);
    final window = state.foregroundWindow;
    final windows = ref.watch(services.windows(monitorId));
    final dark = context.shellTheme.colors.brightness == Brightness.dark;
    final appName = window == null
        ? 'Denial'
        : _applicationName(ref, window.appId);

    final rows = switch (id) {
      AppMenuId.app => _appRows(ref, window, appName),
      AppMenuId.file => _fileRows(ref, window),
      AppMenuId.edit => _editRows(ref),
      AppMenuId.view => _viewRows(ref, window, dark),
      AppMenuId.window => _windowRows(ref, window, windows),
      AppMenuId.help => _helpRows(ref, appName),
    };

    return SizedBox(
      width: BarTokens.menuWidth,
      child: BarMenuColumn(children: rows),
    );
  }

  String _applicationName(WidgetRef ref, String appId) {
    if (appId.isEmpty) return 'Denial';
    for (final application in ref.watch(services.applications)) {
      if (application.appId == appId) return application.name;
    }
    final slash = appId.lastIndexOf('.');
    final tail = slash < 0 ? appId : appId.substring(slash + 1);
    if (tail.isEmpty) return appId;
    return tail[0].toUpperCase() + tail.substring(1);
  }

  List<Widget> _appRows(WidgetRef ref, DenialWindow? window, String name) {
    if (window == null) {
      return <Widget>[
        BarMenuRow(
          label: 'New Terminal',
          glyph: BarIcons.house,
          onTap: () {
            onClose();
            services.toggleLauncher();
          },
        ),
        BarMenuRow(
          label: 'Open Home Folder',
          glyph: BarIcons.house,
          onTap: onClose,
        ),
        const BarMenuDivider(),
        BarMenuRow(
          label: 'Search…',
          glyph: BarIcons.search,
          onTap: onClose,
        ),
      ];
    }
    return <Widget>[
      BarMenuRow(
        label: 'About $name',
        enabled: false,
        onTap: null,
      ),
      const BarMenuDivider(),
      BarMenuRow(
        label: 'Hide $name',
        enabled: false,
        onTap: null,
      ),
      const BarMenuDivider(),
      BarMenuRow(
        label: 'Quit $name',
        shortcut: '⌘Q',
        enabled: false,
        onTap: null,
      ),
      BarMenuRow(
        label: 'Force Quit $name',
        enabled: false,
        onTap: null,
      ),
    ];
  }

  List<Widget> _fileRows(WidgetRef ref, DenialWindow? window) {
    final rows = <Widget>[];
    if (window == null) {
      rows.addAll(<Widget>[
        BarMenuRow(
          label: 'New Terminal',
          onTap: () {
            onClose();
            services.toggleLauncher();
          },
        ),
        const BarMenuDivider(),
      ]);
    } else {
      rows.addAll(<Widget>[
        BarMenuRow(
          label: 'New Window',
          enabled: false,
          onTap: null,
        ),
        BarMenuRow(
          label: 'Open…',
          shortcut: '⌘O',
          enabled: false,
          onTap: null,
        ),
        const BarMenuDivider(),
        BarMenuRow(
          label: 'Close Window',
          shortcut: '⌘W',
          onTap: () {
            onClose();
            ref.read(shellControllerProvider.notifier).closeWindow(window);
          },
        ),
        const BarMenuDivider(),
      ]);
    }
    rows.addAll(<Widget>[
      BarMenuRow(
        label: 'Screenshot…',
        enabled: false,
        onTap: null,
      ),
      BarMenuRow(
        label: 'Pick Color',
        enabled: false,
        onTap: null,
      ),
    ]);
    return rows;
  }

  List<Widget> _editRows(WidgetRef ref) {
    return <Widget>[
      BarMenuRow(
        label: 'Undo',
        shortcut: '⌘Z',
        enabled: false,
        onTap: null,
      ),
      BarMenuRow(
        label: 'Redo',
        shortcut: '⇧⌘Z',
        enabled: false,
        onTap: null,
      ),
      const BarMenuDivider(),
      BarMenuRow(
        label: 'Cut',
        shortcut: '⌘X',
        enabled: false,
        onTap: null,
      ),
      BarMenuRow(
        label: 'Copy',
        shortcut: '⌘C',
        enabled: false,
        onTap: null,
      ),
      BarMenuRow(
        label: 'Paste',
        shortcut: '⌘V',
        enabled: false,
        onTap: null,
      ),
      BarMenuRow(
        label: 'Select All',
        shortcut: '⌘A',
        enabled: false,
        onTap: null,
      ),
      const BarMenuDivider(),
      BarMenuRow(
        label: 'Clipboard History…',
        glyph: BarIcons.sliderHorizontal3,
        enabled: false,
        onTap: null,
      ),
    ];
  }

  List<Widget> _viewRows(WidgetRef ref, DenialWindow? window, bool dark) {
    return <Widget>[
      BarMenuRow(
        label: 'Enter Full Screen',
        enabled: false,
        onTap: null,
      ),
      const BarMenuDivider(),
      BarMenuRow(
        label: 'Show Desktop',
        glyph: BarIcons.grid,
        onTap: () {
          onClose();
          services.toggleDesktop();
        },
      ),
      BarMenuRow(
        label: 'Show Launcher',
        glyph: BarIcons.search,
        onTap: () {
          onClose();
          services.toggleLauncher();
        },
      ),
      const BarMenuDivider(),
      BarMenuRow(
        label: 'Dark Mode',
        checked: dark,
        onTap: () {
          onClose();
          ref
              .read(shellSettingsProvider.notifier)
              .setColorSchemePreference(
                dark
                    ? DesktopColorSchemePreference.preferLight
                    : DesktopColorSchemePreference.preferDark,
              );
        },
      ),
      const BarMenuDivider(),
      BarMenuRow(
        label: 'Menu Bar Settings…',
        glyph: BarIcons.gear,
        onTap: () {
          onClose();
          onBarSettings?.call();
        },
      ),
    ];
  }

  List<Widget> _windowRows(
    WidgetRef ref,
    DenialWindow? window,
    List<ApplicationWindow> windows,
  ) {
    final rows = <Widget>[];
    if (window != null) {
      rows.addAll(<Widget>[
        BarMenuRow(
          label: 'Minimize',
          onTap: () {
            onClose();
            services.minimizeWindow(window.windowId);
          },
        ),
        BarMenuRow(
          label: 'Close Window',
          onTap: () {
            onClose();
            ref.read(shellControllerProvider.notifier).closeWindow(window);
          },
        ),
        const BarMenuDivider(),
      ]);
    }
    for (final entry in windows.take(8)) {
      rows.add(
        BarMenuRow(
          label: entry.title.isEmpty ? 'Untitled' : entry.title,
          checked: entry.active,
          onTap: () {
            onClose();
            services.activateWindow(entry.id);
          },
        ),
      );
    }
    if (windows.isNotEmpty) rows.add(const BarMenuDivider());
    rows.add(
      BarMenuRow(
        label: window == null ? 'No window is focused' : 'All Windows',
        enabled: false,
        onTap: null,
      ),
    );
    return rows;
  }

  List<Widget> _helpRows(WidgetRef ref, String appName) {
    return <Widget>[
      BarMenuRow(
        label: 'Search…',
        glyph: BarIcons.search,
        onTap: () {
          onClose();
          services.toggleLauncher();
        },
      ),
      BarMenuRow(
        label: '$appName Help',
        enabled: false,
        onTap: null,
      ),
      const BarMenuDivider(),
      BarMenuRow(
        label: 'Denial Documentation',
        enabled: false,
        onTap: null,
      ),
    ];
  }
}

/// A title in the menu row: shell27 draws the active app DemiBold at 14 and
/// the five menus regular at 14, each box `implicitWidth + 20` wide.
class AppMenuTitleButton extends StatelessWidget {
  const AppMenuTitleButton({
    required this.title,
    required this.ink,
    required this.open,
    required this.onTap,
    super.key,
  });

  final AppMenuTitle title;
  final Color ink;
  final bool open;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return BarTitle(
      label: title.label,
      ink: ink,
      bold: title.bold,
      open: open,
      onTap: onTap,
    );
  }
}
