import 'dart:convert';
import 'dart:io';

import 'package:denial_topbar/src/bar_settings.dart';

Future<void> main() async {
  const defaults = BarSettings.defaults;
  _expect(defaults.layout == BarLayout.attached, 'default layout');
  // macOS 27 draws no bar background by default.
  _expect(defaults.ground == BarGround.none, 'default ground');
  _expect(defaults.groundOpacity == 0.55, 'default opacity');
  _expect(defaults.islandEnabled, 'default island');
  _expect(!defaults.islandHoverFade, 'default island hover fade off');
  _expect(defaults.islandCursorAbsorb, 'default island cursor absorb on');
  _expect(
    defaults.workspacePlacement == BarWorkspacePlacement.island,
    'default workspace placement',
  );
  _expect(!defaults.showBatteryPercent, 'default battery percent');
    _expect(defaults.showVolume, 'default volume item');
    _expect(!defaults.autoHide, 'default auto hide');
    _expect(defaults.trayFold == BarTrayFold.inline, 'default tray fold');

    _expect(
      BarTrayFold.parse('popover') == BarTrayFold.popover &&
          BarTrayFold.parse('floatingBar') == BarTrayFold.floatingBar &&
          BarTrayFold.parse('controlCenter') == BarTrayFold.controlCenter &&
          BarTrayFold.parse('hover') == BarTrayFold.hover &&
          BarTrayFold.parse('nonsense') == BarTrayFold.inline,
      'tray fold parsing and fallback',
    );
    final partAll = partitionTrayIds(
      const <String>['a', 'b', 'c'],
      settings: const BarSettings(collapseItems: true, trayNever: <String>['c']),
      resolveKey: (id) => id,
    );
    _expect(
      partAll.visible.isEmpty &&
          partAll.folded.length == 2 &&
          !partAll.folded.contains('c'),
      'collapseItems folds all non-never icons when none set to hidden',
    );
    final partMixed = partitionTrayIds(
      const <String>['a', 'b', 'c'],
      settings: const BarSettings(
        collapseItems: true,
        trayHidden: <String>['b'],
        trayNever: <String>['c'],
      ),
      resolveKey: (id) => id,
    );
    _expect(
      partMixed.visible.isEmpty &&
          partMixed.folded.length == 2 &&
          partMixed.folded.contains('a') &&
          partMixed.folded.contains('b') &&
          !partMixed.folded.contains('c'),
      'collapseItems folds all non-never icons even when trayHidden is set',
    );
    final partHiddenOnly = partitionTrayIds(
      const <String>['a', 'b', 'c'],
      settings: const BarSettings(
        collapseItems: false,
        trayHidden: <String>['b'],
        trayNever: <String>['c'],
      ),
      resolveKey: (id) => id,
    );
    _expect(
      partHiddenOnly.visible.single == 'a' &&
          partHiddenOnly.folded.single == 'b',
      'explicit trayHidden keeps other icons visible when collapseItems is off',
    );

  // Every value that comes from outside is clamped on the way in, so a hand
  // edit or an older build cannot put the bar in a state the UI cannot draw.
  _expect(
    BarSettings.fromJson(<String, dynamic>{'groundOpacity': 3}).groundOpacity ==
        1,
    'opacity ceiling',
  );
  _expect(
    BarSettings.fromJson(<String, dynamic>{'groundOpacity': -1})
            .groundOpacity ==
        0.05,
    'opacity floor',
  );
  _expect(
    BarSettings.fromJson(<String, dynamic>{'islandNoticeSeconds': 400})
            .islandNoticeSeconds ==
        12,
    'notice seconds ceiling',
  );
  _expect(
    BarSettings.fromJson(<String, dynamic>{}).islandFadeDelayMs == 600 &&
        BarSettings.fromJson(<String, dynamic>{}).islandLongPressMs == 280,
    'island timings default in an older save',
  );
  _expect(
    BarSettings.fromJson(<String, dynamic>{
              'islandFadeDelayMs': 5,
              'islandLongPressMs': 9000,
            }).islandFadeDelayMs ==
            200 &&
        BarSettings.fromJson(<String, dynamic>{
              'islandFadeDelayMs': 5,
              'islandLongPressMs': 9000,
            }).islandLongPressMs ==
            600,
    'island timings stay in range',
  );
  final timings = <String, dynamic>{};
  const BarSettings(
    islandFadeDelayMs: 900,
    islandLongPressMs: 400,
  ).writeJson(timings);
  _expect(
    BarSettings.fromJson(timings).islandFadeDwell ==
            const Duration(milliseconds: 900) &&
        BarSettings.fromJson(timings).islandLongPress ==
            const Duration(milliseconds: 400),
    'island timings round trip',
  );
  _expect(
    BarSettings.fromJson(<String, dynamic>{'autoHideDelayMs': -5})
            .autoHideDelayMs ==
        barAutoHideDelayMin,
    'auto hide delay floor',
  );
  _expect(
    BarSettings.fromJson(<String, dynamic>{'layout': 'nonsense'}).layout ==
        BarLayout.attached,
    'unknown layout falls back',
  );

  final root = _scratchRoot();
  final directory = Directory(
    '${root.path}/topbar-settings-${DateTime.now().microsecondsSinceEpoch}',
  )..createSync(recursive: true);
  try {
    final file = File('${directory.path}/denial_topbar.json');
    final store = BarPreferencesStore(file);

    // Unknown keys survive a write so an older build cannot erase a setting
    // that a newer one added.
    file.writeAsStringSync(
      jsonEncode(<String, dynamic>{'futureKey': 42, 'layout': 'floating'}),
    );
    final loaded = await store.read();
    _expect(loaded.layout == BarLayout.floating, 'read floating layout');
    final settings = loaded.copyWith(
      ground: BarGround.glass,
      workspacePlacement: BarWorkspacePlacement.trailing,
      showBatteryPercent: true,
      showVolume: false,
    );
    await store.write(settings);

    final written = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    _expect(written['futureKey'] == 42, 'unknown key preserved');
    _expect(written['layout'] == 'floating', 'round-trip layout');
    _expect(written['ground'] == 'glass', 'round-trip ground');
    _expect(
      written['workspacePlacement'] == 'trailing',
      'round-trip workspace placement',
    );
    _expect(
      written['showBatteryPercent'] == true,
      'round-trip battery percent',
    );
    _expect(written['showVolume'] == false, 'round-trip volume item');

    final reread = await BarPreferencesStore(file).read();
    _expect(reread.ground == BarGround.glass, 'read back ground');
    _expect(reread.islandEnabled, 'read back island');
    _expect(!reread.showVolume, 'read back volume item');
    _expect(
      reread.workspacePlacement == BarWorkspacePlacement.trailing,
      'read back workspace placement',
    );
    _expect(reread.islandSplit && reread.islandHome, 'new island defaults');
    _expect(reread.trayHidden.isEmpty && reread.showMic, 'new item defaults');
    await BarPreferencesStore(file).write(
      reread.copyWith(
        islandHome: false,
        islandHoverFade: true,
        islandCursorAbsorb: false,
        activityTimer: false,
        collapseItems: true,
        trayFold: BarTrayFold.controlCenter,
        overviewShowMinimised: false,
        overviewMiddleClickCloses: false,
        overviewLiveOtherWorkspaces: false,
        overviewLiveLimit: 9,
        trayHidden: const <String>['nm-applet'],
        trayNever: const <String>['magpie'],
        tileSizes: const <String>['cc.wifi:1x1'],
      ),
    );
    final again = await BarPreferencesStore(file).read();
    _expect(
      !again.islandHome &&
          !again.activityTimer &&
          again.islandHoverFade &&
          !again.islandCursorAbsorb,
      'island switches persist',
    );
    _expect(
      !again.overviewShowMinimised &&
          !again.overviewMiddleClickCloses &&
          !again.overviewLiveOtherWorkspaces &&
          again.overviewLiveLimit == 9,
      'overview settings persist',
    );
    _expect(
      again.trayFold == BarTrayFold.controlCenter &&
          again.trayHidden.single == 'nm-applet' &&
          again.trayNever.single == 'magpie' &&
          again.tileSizes.single == 'cc.wifi:1x1',
      'tray sections and tile sizes persist',
    );
    stdout.writeln('All top bar settings tests passed.');
  } finally {
    directory.deleteSync(recursive: true);
  }
}

/// Scratch space, kept out of `/tmp` so nothing leaks into a shared volume.
Directory _scratchRoot() {
  final home = Platform.environment['HOME'];
  final root = home == null || !home.startsWith('/')
      ? Directory.current
      : Directory('$home/Lab/Bridge/tmp');
  if (root.existsSync()) return root;
  return Directory.current;
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
