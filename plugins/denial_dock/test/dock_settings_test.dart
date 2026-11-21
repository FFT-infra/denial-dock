import 'dart:convert';
import 'dart:io';

import 'package:denial_dock/src/dock_settings.dart';

void main() {
  // Defaults: empty dock, smart hide, minimize, launcher leading, trash on.
  const defaults = DockSettings.defaults;
  _expect(defaults.pinned.isEmpty, 'default pins');
  _expect(defaults.visibility == DockVisibilityMode.smart, 'default hide');
  _expect(defaults.clickAction == DockClickAction.minimize, 'default click');
  _expect(defaults.iconSize == 48, 'default size');
  _expect(defaults.magnification, 'default magnification');
  _expect(defaults.launcherSide == DockSide.left, 'default launcher side');
  _expect(defaults.extrasSide == DockSide.right, 'default extras side');
  _expect(defaults.showTrash, 'default trash');
  _expect(defaults.folders.isEmpty, 'default folders');
  _expect(
    defaults.capsuleHeight ==
        DockSettings.defaultIconSize + DockSettings.padding * 2,
    'capsule ${defaults.capsuleHeight}',
  );
  _expect(defaults.hasExtras, 'trash counts as extras');

  // Icon size is clamped on every path that reads a value from outside: the
  // settings panel goes through copyWith, hand edits through fromJson.
  _expect(
    defaults.copyWith(iconSize: 4).iconSize == DockSettings.minIconSize,
    'size floor',
  );
  _expect(
    defaults.copyWith(iconSize: 400).iconSize == DockSettings.maxIconSize,
    'size ceiling',
  );
  _expect(
    defaults.copyWith(iconSize: double.nan).iconSize ==
        DockSettings.defaultIconSize,
    'size nan',
  );
  _expect(
    DockSettings.fromJson({'iconSize': 400}).iconSize ==
        DockSettings.maxIconSize,
    'parse size ceiling',
  );

  // A full round trip through JSON keeps every field.
  final settings = DockSettings(
    pinned: const [
      DockPin(
        id: 'org.gnome.Nautilus.desktop',
        appId: 'org.gnome.Nautilus.desktop',
        name: 'Files',
      ),
    ],
    visibility: DockVisibilityMode.always,
    clickAction: DockClickAction.cycle,
    iconSize: 56,
    magnification: false,
    launcherSide: DockSide.right,
    extrasSide: DockSide.left,
    showTrash: false,
    folders: const [DockFolder(path: '/home/me/Documents', label: 'Documents')],
  );
  final json = {
    'pinnedApplications': settings.pinned.map((pin) => pin.toJson()).toList(),
    'visibility': settings.visibility.key,
    'clickAction': settings.clickAction.key,
    'iconSize': settings.iconSize,
    'magnification': settings.magnification,
    'launcherSide': settings.launcherSide.key,
    'extrasSide': settings.extrasSide.key,
    'showTrash': settings.showTrash,
    'folders': settings.folders.map((folder) => folder.toJson()).toList(),
  };
  final decoded = DockSettings.fromJson(
    jsonDecode(jsonEncode(json)) as Map<String, dynamic>,
  );
  _expect(decoded.pinned.length == 1, 'round trip pins');
  _expect(decoded.visibility == DockVisibilityMode.always, 'round trip hide');
  _expect(decoded.clickAction == DockClickAction.cycle, 'round trip click');
  _expect(decoded.iconSize == 56, 'round trip size');
  _expect(!decoded.magnification, 'round trip magnification');
  _expect(decoded.launcherSide == DockSide.right, 'round trip launcher');
  _expect(decoded.extrasSide == DockSide.left, 'round trip extras');
  _expect(!decoded.showTrash, 'round trip trash');
  _expect(
    decoded.folders.single.path == '/home/me/Documents' &&
        decoded.folders.single.label == 'Documents',
    'round trip folders',
  );

  // Garbage falls back to the defaults instead of throwing.
  final garbage = DockSettings.fromJson({
    'pinnedApplications': 'nope',
    'visibility': 7,
    'clickAction': null,
    'iconSize': 'big',
    'launcherSide': 'sideways',
    'extrasSide': [],
    'showTrash': 'yes',
    'folders': [
      null,
      3,
      {'path': 'relative/dir'},
    ],
  });
  _expect(garbage.pinned.isEmpty, 'garbage pins');
  _expect(garbage.visibility == DockVisibilityMode.smart, 'garbage hide');
  _expect(garbage.clickAction == DockClickAction.minimize, 'garbage click');
  _expect(garbage.iconSize == 48, 'garbage size');
  _expect(garbage.magnification, 'garbage magnification');
  _expect(garbage.launcherSide == DockSide.left, 'garbage launcher');
  _expect(garbage.extrasSide == DockSide.right, 'garbage extras');
  _expect(garbage.showTrash, 'garbage trash');
  _expect(garbage.folders.isEmpty, 'garbage folders');

  // Folders deduplicate by normalized path and derive a label when missing.
  final folders = const DockSettings()
      .withFolder(
        const DockFolder(path: '/home/me/Projects/', label: 'Projects'),
      )
      .withFolder(const DockFolder(path: '/home/me/Projects', label: 'Again'))
      .withFolder(const DockFolder(path: '/home/me/Downloads', label: ''));
  _expect(
    folders.folders.length == 2,
    'folder dedupe ${folders.folders.length}',
  );
  _expect(
    folders.folders.firstWhere((f) => f.path == '/home/me/Projects').label ==
        'Again',
    'folder relabel',
  );
  _expect(
    folders.folders.firstWhere((f) => f.path == '/home/me/Downloads').label ==
        'Downloads',
    'folder label derived',
  );
  _expect(
    folders.withoutFolder('/home/me/Projects/').folders.length == 1,
    'folder remove',
  );
  _expect(
    folderLabel('/home/me', home: '/home/me', homeLabel: '主目录') == '主目录',
    'home label',
  );
  _expect(normalizeFolderPath('/a//b/') == '/a/b', 'normalize path');

  _storeRoundTrip(settings);
}

/// The store writes what the reader parses, and keeps unknown keys.
Future<void> _storeRoundTrip(DockSettings settings) async {
  final directory = Directory.systemTemp.createTempSync('dock_settings_test');
  try {
    final file = File('${directory.path}/denial_dock.json');
    await file.writeAsString(
      jsonEncode({'unrelated': 'keep me', 'visibility': 'always'}),
    );
    final store = DockPreferencesStore(file);
    final loaded = await store.read();
    _expect(loaded.visibility == DockVisibilityMode.always, 'store read');
    await store.write(settings);
    final written = jsonDecode(await file.readAsString()) as Map;
    _expect(written['unrelated'] == 'keep me', 'unknown key survives');
    _expect(written['clickAction'] == 'cycle', 'written click');
    _expect((written['folders'] as List).length == 1, 'written folders');
    _expect(written['iconSize'] == 56, 'written size');
    _expect(written['magnification'] == false, 'written magnification');
    stdout.writeln('All dock settings tests passed.');
  } finally {
    directory.deleteSync(recursive: true);
  }
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
