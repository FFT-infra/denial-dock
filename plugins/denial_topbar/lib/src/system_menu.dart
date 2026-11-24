import 'package:denial_flutter_sdk/services.dart';
import 'package:denial_flutter_sdk/state.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'bar_button.dart';
import 'bar_icons.dart';
import 'bar_menu.dart';
import 'bar_preferences.dart';
import 'bar_tokens.dart';
import 'l10n.dart';
import 'recent_items.dart';

class BarSystemMenu extends StatelessWidget {
  const BarSystemMenu({
    required this.glyph,
    required this.open,
    required this.ink,
    required this.onToggle,
    super.key,
  });

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
      child: SizedBox(
        width: BarTokens.systemMenuGlyph,
        height: BarTokens.systemMenuGlyph,
        child: glyph,
      ),
    );
  }
}

String _identity(String appId) {
  final lower = appId.toLowerCase();
  return lower.endsWith('.desktop')
      ? lower.substring(0, lower.length - 8)
      : lower;
}

List<BarMenuEntry> _recentEntries(
  BuildContext context,
  WidgetRef ref,
  ShellServices services,
) {
  final settings = ref.read(barSettingsProvider).value;
  final clearedAt = settings == null || settings.recentsClearedAt == 0
      ? null
      : DateTime.fromMillisecondsSinceEpoch(settings.recentsClearedAt);
  final catalog = ref.read(services.applications);
  final byIdentity = <String, LaunchableApplication>{};
  for (final application in catalog) {
    byIdentity.putIfAbsent(_identity(application.appId), () => application);
    for (final id in application.windowAppIds) {
      byIdentity.putIfAbsent(_identity(id), () => application);
    }
  }
  final applications = <LaunchableApplication>[];
  if (clearedAt == null) {
    for (final id in readRecentApplicationIds()) {
      final application = byIdentity[_identity(id)];
      if (application == null || applications.contains(application)) continue;
      applications.add(application);
      if (applications.length == 10) break;
    }
  }
  final documents = readRecentDocuments(clearedAt: clearedAt);
  final places = (settings?.recentPlaces ?? true)
      ? readPlaces()
      : const <Place>[];
  final folders = places.where((place) => !place.remote).toList();
  final servers = places.where((place) => place.remote).toList();
  if (applications.isEmpty && documents.isEmpty && places.isEmpty) {
    return <BarMenuEntry>[
      BarMenuItem(label: context.tr('No Recent Items'), enabled: false),
    ];
  }
  return <BarMenuEntry>[
    if (applications.isNotEmpty) BarMenuHeader(context.tr('Applications')),
    for (final application in applications)
      BarMenuItem(
        label: application.name,
        leading: services.buildApplicationIcon(context, application.appId),
        onSelected: () => services.launchApplication(application.id),
      ),
    if (applications.isNotEmpty && documents.isNotEmpty)
      const BarMenuSeparator(),
    if (documents.isNotEmpty) BarMenuHeader(context.tr('Documents')),
    for (final document in documents)
      BarMenuItem(
        label: document.name,
        icon: document.directory ? BarIcons.folder : BarIcons.doc,
        onSelected: () => openPath(document.path),
      ),
    for (final (title, group, icon) in <(String, List<Place>, IconData)>[
      ('Places', folders, BarIcons.folder),
      ('Servers', servers, BarIcons.globe),
    ])
      if (group.isNotEmpty) ...<BarMenuEntry>[
        if (applications.isNotEmpty ||
            documents.isNotEmpty ||
            icon == BarIcons.globe && folders.isNotEmpty)
          const BarMenuSeparator(),
        BarMenuHeader(context.tr(title)),
        for (final place in group)
          BarMenuItem(
            label: place.label,
            icon: icon,
            onSelected: () => openPath(place.uri),
          ),
      ],
    const BarMenuSeparator(),
    BarMenuItem(
      label: context.tr('Clear Menu'),
      onSelected: () => ref
          .read(barSettingsProvider.notifier)
          .save(
            (current) => current.copyWith(
              recentsClearedAt: DateTime.now().millisecondsSinceEpoch,
            ),
          ),
    ),
  ];
}

/// A malformed history file must not take the whole menu down with it.
List<BarMenuEntry> _safeRecentEntries(
  BuildContext context,
  WidgetRef ref,
  ShellServices services,
) {
  try {
    return _recentEntries(context, ref, services);
  } on Object {
    return <BarMenuEntry>[
      BarMenuItem(label: context.tr('No Recent Items'), enabled: false),
    ];
  }
}

/// The system menu in macOS's order. Holding Alt or Shift swaps in the
/// variants a Mac shows: actions without their confirmation, and Force Quit
/// aimed at the frontmost application.
List<BarMenuEntry> systemMenuEntries(
  BuildContext context,
  WidgetRef ref, {
  required ShellServices services,
  required String? frontAppName,
  required VoidCallback onAbout,
  required VoidCallback onBarSettings,
  required VoidCallback onForceQuit,
  required VoidCallback? onForceQuitFront,
  required ValueChanged<SessionPowerAction> onConfirm,
}) {
  final session = ref.read(sessionPowerProvider);
  final power = ref.read(sessionPowerProvider.notifier);
  bool can(SessionPowerAction action) =>
      session.busyAction == null && session.availabilityFor(action).enabled;

  BarMenuItem confirmed(
    String label,
    String direct,
    SessionPowerAction action,
  ) => BarMenuItem(
    label: context.tr(label),
    enabled: can(action),
    onSelected: () => onConfirm(action),
    alternate: BarMenuItem(
      label: context.tr(direct),
      enabled: can(action),
      onSelected: () async {
        await power.request(action);
        await power.confirm();
      },
    ),
  );

  return <BarMenuEntry>[
    BarMenuItem(
      label: context.tr('About This System'),
      icon: BarIcons.display,
      onSelected: onAbout,
    ),
    const BarMenuSeparator(),
    BarMenuItem(
      label: context.tr('System Settings…'),
      icon: BarIcons.gear,
      onSelected: services.openPowerSettings,
    ),
    BarMenuItem(
      label: context.tr('Menu Bar Settings…'),
      icon: BarIcons.sliderHorizontal3,
      onSelected: onBarSettings,
    ),
    const BarMenuSeparator(),
    BarMenuItem(
      label: context.tr('Recent Items'),
      submenu: _safeRecentEntries(context, ref, services),
    ),
    const BarMenuSeparator(),
    BarMenuItem(
      label: context.tr('Force Quit…'),
      onSelected: onForceQuit,
      alternate: frontAppName == null
          ? null
          : BarMenuItem(
              label: context.tr('Force Quit “{}”', frontAppName),
              onSelected: onForceQuitFront,
            ),
    ),
    const BarMenuSeparator(),
    BarMenuItem(
      label: context.tr('Sleep'),
      enabled: can(SessionPowerAction.suspend),
      onSelected: () => power.request(SessionPowerAction.suspend),
    ),
    confirmed('Restart…', 'Restart', SessionPowerAction.reboot),
    confirmed('Shut Down…', 'Shut Down', SessionPowerAction.powerOff),
    const BarMenuSeparator(),
    BarMenuItem(
      label: context.tr('Lock Screen'),
      enabled: can(SessionPowerAction.lock),
      onSelected: () => power.request(SessionPowerAction.lock),
    ),
    confirmed('Log Out…', 'Log Out', SessionPowerAction.logout),
  ];
}
