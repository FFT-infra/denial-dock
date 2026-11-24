import 'package:denial_flutter_sdk/models.dart';
import 'package:denial_flutter_sdk/services.dart';
import 'package:denial_flutter_sdk/state.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'bar_menu.dart';
import 'l10n.dart';

void closeApplication(WidgetRef ref, String appId) {
  final controller = ref.read(shellControllerProvider.notifier);
  final windows = ref
      .read(shellControllerProvider)
      .openAppWindows
      .where((window) => window.appId == appId)
      .toList();
  for (final window in windows) {
    controller.closeWindow(window);
  }
}

/// What the shell can do to the focused application. The compositor exposes
/// no application menus, so this is the whole menu.
List<BarMenuEntry> appMenuEntries(
  BuildContext context,
  WidgetRef ref, {
  required DenialWindow window,
  required String appName,
  required ShellServices services,
}) => <BarMenuEntry>[
  BarMenuItem(
    label: context.tr('Hide {}', appName),
    onSelected: () => services.minimizeWindow(window.windowId),
  ),
  BarMenuItem(
    label: context.tr('Close Window'),
    onSelected: () =>
        ref.read(shellControllerProvider.notifier).closeWindow(window),
  ),
  const BarMenuSeparator(),
  BarMenuItem(
    label: context.tr('Quit {}', appName),
    onSelected: () => closeApplication(ref, window.appId),
  ),
];
