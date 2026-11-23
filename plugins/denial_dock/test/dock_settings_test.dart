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
  _expect(defaults.showBadges, 'default badges');
  _expect(defaults.iconOpacity == 1.0, 'default icon opacity');
  _expect(defaults.tintColor == null, 'default tint follows the accent');
  _expect(defaults.iconMode == DockIconMode.color, 'default icon mode');
  _expect(defaults.appearance == DockAppearance.macos, 'default appearance');
  _expect(defaults.revealIndicator, 'default reveal handle');
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
  _expect(
    DockSettings.fromJson({'iconOpacity': 0.01}).iconOpacity ==
        DockSettings.minIconOpacity,
    'opacity floor',
  );
  _expect(
    DockSettings.fromJson({'iconOpacity': 9}).iconOpacity == 1.0,
    'opacity ceiling',
  );

  // A tint is a lowercase #rrggbb; anything else falls back to the accent.
  _expect(
    DockSettings.fromJson({'tintColor': '#A855F7'}).tintColor == '#a855f7',
    'tint normalised',
  );
  for (final bad in ['a855f7', '#a85', '#gggggg', 7, null]) {
    _expect(
      DockSettings.fromJson({'tintColor': bad}).tintColor == null,
      'tint rejected: $bad',
    );
  }
  _expect(
    DockSettings.defaults.copyWith(tintColor: '#3b82f6').tintColor == '#3b82f6',
    'tint copyWith',
  );
  _expect(
    DockSettings.defaults
            .copyWith(tintColor: '#3b82f6')
            .copyWith(clearTint: true)
            .tintColor ==
        null,
    'tint cleared',
  );

  // A folder remembers whether its icon is a pile or a plain folder, and
  // defaults to a pile.
  final folder = DockFolder(path: '/tmp/x', label: 'x');
  _expect(folder.stacked, 'a folder stacks by default');
  _expect(
    DockFolder.fromJson(folder.toJson())!.stacked,
    'stacked survives JSON',
  );
  _expect(
    !DockFolder.fromJson({'path': '/tmp/x', 'stacked': false})!.stacked,
    'stacked false survives JSON',
  );
  _expect(
    defaults
            .withFolder(const DockFolder(path: '/tmp/x', label: 'x'))
            .withFolderStack('/tmp/x', stacked: false)
            .folders
            .single
            .stacked ==
        false,
    'withFolderStack clears stacked',
  );
  _expect(
    DockStackModeKey.parse('list') == DockStackMode.list,
    'list mode parses',
  );

  // A single file can be pinned beside the folders, and survives a reload.
  const file = DockFile(path: '/tmp/report.pdf', label: 'report.pdf');
  final withFile = defaults.withFile(file);
  _expect(withFile.files.length == 1, 'a file is pinned');
  _expect(withFile.hasExtras, 'a pinned file counts as an accessory');
  _expect(
    DockSettings.fromJson({
          'files': [file.toJson()],
        }).files.single.path ==
        '/tmp/report.pdf',
    'a pinned file survives JSON',
  );
  _expect(
    withFile.withFile(file).files.length == 1,
    'pinning the same file twice keeps one',
  );
  _expect(
    withFile.withoutFile('/tmp/report.pdf').files.isEmpty,
    'a pinned file can be removed',
  );
  _expect(
    DockSettings.fromJson({
      'files': [
        {'label': 'no path'},
      ],
    }).files.isEmpty,
    'a file without a path is dropped',
  );

  // The appearance setting reads back both ways and falls back to macOS.
  _expect(
    DockSettings.fromJson({'appearance': 'denial'}).appearance ==
        DockAppearance.denial,
    'appearance parses denial',
  );
  _expect(
    DockSettings.fromJson({'appearance': 'nonsense'}).appearance ==
        DockAppearance.macos,
    'unknown appearance falls back to macOS',
  );
  _expect(
    defaults.copyWith(appearance: DockAppearance.denial).appearance ==
        DockAppearance.denial,
    'appearance copies',
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
    showBadges: false,
    iconMode: DockIconMode.grayscale,
    iconOpacity: 0.5,
    tintColor: '#a855f7',
    revealIndicator: false,
    launchFeedback: DockLaunchFeedback.pulse,
    indicatorStyle: DockIndicatorStyle.line,
    previewStyle: DockPreviewStyle.stack,
    dimInactivePinned: true,
    hoverFocusPreview: true,
    scrollReversed: true,
    scrollWraps: true,
    folders: const [DockFolder(path: '/home/me/Documents', label: 'Documents')],
    dismissedSuggestions: const ['firefox'],
    recentCount: 5,
    recentsOrder: const ['firefox', 'org.gnome.nautilus'],
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
    'showBadges': settings.showBadges,
    'iconOpacity': settings.iconOpacity,
    'tintColor': settings.tintColor,
    'iconMode': settings.iconMode.key,
    'appearance': settings.appearance.key,
    'revealIndicator': settings.revealIndicator,
    'launchFeedback': settings.launchFeedback.key,
    'indicatorStyle': settings.indicatorStyle.key,
    'previewStyle': settings.previewStyle.key,
    'dimInactivePinned': settings.dimInactivePinned,
    'hoverFocusPreview': settings.hoverFocusPreview,
    'scrollReversed': settings.scrollReversed,
    'scrollWraps': settings.scrollWraps,
    'folders': settings.folders.map((folder) => folder.toJson()).toList(),
    'dismissedSuggestions': settings.dismissedSuggestions,
    'recentCount': settings.recentCount,
    'recentsOrder': settings.recentsOrder,
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
  _expect(!decoded.showBadges, 'round trip badges');
  _expect(decoded.iconOpacity == 0.5, 'round trip icon opacity');
  _expect(decoded.tintColor == '#a855f7', 'round trip tint');
  _expect(decoded.iconMode == DockIconMode.grayscale, 'round trip icon mode');
  _expect(!decoded.revealIndicator, 'round trip reveal handle');
  _expect(
    decoded.launchFeedback == DockLaunchFeedback.pulse,
    'round trip launch feedback',
  );
  _expect(
    decoded.indicatorStyle == DockIndicatorStyle.line,
    'round trip indicator style',
  );
  _expect(
    decoded.previewStyle == DockPreviewStyle.stack,
    'round trip preview style',
  );
  _expect(decoded.dimInactivePinned, 'round trip inactive dim');
  _expect(decoded.hoverFocusPreview, 'round trip hover focus');
  _expect(decoded.scrollReversed, 'round trip scroll reversed');
  _expect(decoded.scrollWraps, 'round trip scroll wraps');

  // The older boolean keys still read, so an existing file keeps its look.
  _expect(
    DockSettings.fromJson({'bounceOnLaunch': false}).launchFeedback ==
        DockLaunchFeedback.none,
    'legacy bounce off',
  );
  _expect(
    DockSettings.fromJson({'bounceOnLaunch': true}).launchFeedback ==
        DockLaunchFeedback.hop,
    'legacy bounce on',
  );
  _expect(
    DockSettings.fromJson({'showIndicators': false}).indicatorStyle ==
        DockIndicatorStyle.none,
    'legacy indicators off',
  );

  // Dragging a suggestion out of the dock records the app id here, normalized
  // and deduplicated, so the row stops showing it without the launcher
  // forgetting the launch.
  _expect(
    DockSettings.defaults.dismissedSuggestions.isEmpty,
    'no dismissed suggestions by default',
  );
  final dismissed = DockSettings.fromJson({
    'dismissedSuggestions': [
      'org.gnome.Nautilus.desktop',
      'ORG.GNOME.NAUTILUS',
      '  ',
      7,
      null,
      'firefox',
    ],
  });
  _expect(
    dismissed.dismissedSuggestions.join(',') == 'org.gnome.nautilus,firefox',
    'dismissed normalized: ${dismissed.dismissedSuggestions}',
  );
  _expect(
    DockSettings.fromJson({'dismissedSuggestions': 'nope'})
        .dismissedSuggestions
        .isEmpty,
    'dismissed rejects a non-list',
  );
  _expect(
    DockSettings.defaults
            .copyWith(dismissedSuggestions: const ['firefox'])
            .dismissedSuggestions
            .single ==
        'firefox',
    'dismissed copyWith',
  );
  _expect(
    DockSettings.defaults.indicatorStyle == DockIndicatorStyle.dot &&
        DockSettings.defaults.previewStyle == DockPreviewStyle.cards &&
        DockSettings.defaults.launchFeedback == DockLaunchFeedback.hop &&
        !DockSettings.defaults.dimInactivePinned &&
        DockSettings.defaults.hoverFocusPreview &&
        !DockSettings.defaults.scrollReversed &&
        !DockSettings.defaults.scrollWraps,
    'new defaults',
  );
  _expect(
    DockSettings.defaults.recentCount == DockSettings.defaultRecentCount &&
        DockSettings.defaultRecentCount == 3,
    'recent count defaults to three, as macOS show-recent-count does',
  );
  _expect(
    DockSettings.fromJson({'recentCount': 99}).recentCount ==
        DockSettings.maxRecentCount,
    'recent count ceiling',
  );
  _expect(
    DockSettings.fromJson({'recentCount': -4}).recentCount ==
        DockSettings.minRecentCount,
    'recent count floor',
  );
  _expect(
    DockSettings.fromJson({'recentCount': 'many'}).recentCount ==
        DockSettings.defaultRecentCount,
    'recent count rejects garbage',
  );
  _expect(
    DockSettings.defaults.copyWith(recentCount: 99).recentCount ==
        DockSettings.maxRecentCount,
    'recent count copyWith clamps',
  );
  _expect(
    DockSettings.defaults.recentsOrder.isEmpty,
    'no stored recents order by default',
  );
  _expect(
    decoded.folders.single.path == '/home/me/Documents' &&
        decoded.folders.single.label == 'Documents',
    'round trip folders',
  );
  _expect(
    decoded.dismissedSuggestions.single == 'firefox',
    'round trip dismissed suggestions',
  );
  _expect(decoded.recentCount == 5, 'round trip recent count');
  _expect(
    decoded.recentsOrder.join(',') == 'firefox,org.gnome.nautilus',
    'round trip recents order: ${decoded.recentsOrder}',
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
  _expect(garbage.showBadges, 'garbage badges');
  _expect(garbage.iconOpacity == 1.0, 'garbage icon opacity');
  _expect(garbage.tintColor == null, 'garbage tint');
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

  // A launcher's `desktop:` prefix and a pin's launch id both reduce to the
  // icon identity, so one application never takes two slots.
  _expect(
    appIdentity('desktop:org.gnome.Nautilus.desktop') == 'org.gnome.nautilus',
    'recent prefix strips',
  );
  _expect(
    appIdentity('local:firefox') == 'firefox' &&
        appIdentity('Firefox') == 'firefox',
    'launch prefix and case strip',
  );

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
    _expect(written['showBadges'] == false, 'written badges');
    _expect(written['iconOpacity'] == 0.5, 'written icon opacity');
    _expect(written['tintColor'] == '#a855f7', 'written tint');
    _expect(
      (written['dismissedSuggestions'] as List).join(',') == 'firefox',
      'written dismissed suggestions',
    );
    stdout.writeln('All dock settings tests passed.');
  } finally {
    directory.deleteSync(recursive: true);
  }
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
