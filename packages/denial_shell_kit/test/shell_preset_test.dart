import 'dart:convert';
import 'dart:io';

import 'package:denial_shell_kit/kit_store.dart';
import 'package:denial_shell_kit/shell_preset.dart';

void _expect(bool ok, String what) {
  if (!ok) throw StateError(what);
}

Directory _scratchRoot() {
  final home = Platform.environment['HOME'];
  final root = home == null || !home.startsWith('/')
      ? Directory.current
      : Directory('$home/Lab/Bridge/tmp');
  return root.existsSync() ? root : Directory.current;
}

void main() {
  // Presets: unique ids, a fallback, and every one names the same keys, so
  // going from any preset to any other leaves nothing of the first behind.
  final ids = ShellPreset.all.map((preset) => preset.id).toSet();
  _expect(ids.length == ShellPreset.all.length, 'preset ids are unique');
  _expect(ShellPreset.byId('nope') == ShellPreset.denial, 'unknown falls back');
  _expect(ShellPreset.byId(null) == ShellPreset.denial, 'missing falls back');
  _expect(ShellPreset.byId('omarchy') == ShellPreset.omarchy, 'found by id');
  final keys = ShellPreset.denial.bar.keys.toSet();
  for (final preset in ShellPreset.all) {
    _expect(
      preset.bar.keys.toSet().containsAll(keys) &&
          keys.containsAll(preset.bar.keys),
      '${preset.id} names every layout key',
    );
  }

  final dockKeys = ShellPreset.denial.dock.keys.toSet();
  for (final preset in ShellPreset.all) {
    _expect(
      preset.dock.keys.toSet().containsAll(dockKeys) &&
          dockKeys.containsAll(preset.dock.keys),
      '${preset.id} names every dock key',
    );
    _expect(
      const <String>{'shown', 'islandOnly', 'hidden'}.contains(preset.barMode),
      '${preset.id} names a bar mode',
    );
  }
  // The presets that were there before the dock had zones keep the dock and
  // the bar as they were.
  for (final id in const <String>['denial', 'mac', 'omarchy', 'compact']) {
    final old = ShellPreset.byId(id);
    _expect(old.barMode == 'shown', '$id shows the bar');
    _expect(identical(old.dock, ShellPreset.denial.dock), '$id keeps the dock');
  }
  final denialDock = ShellPreset.denial.dock;
  _expect(
    (denialDock['leading']! as List).single == 'dock.launcher' &&
        (denialDock['trailing']! as List).join(',') ==
            'dock.stacks,dock.trash' &&
        denialDock['shape'] == 'floating' &&
        denialDock['align'] == 'packed',
    'the usual dock is the dock as it was',
  );
  _expect(ShellPreset.taskbar.barMode == 'hidden', 'a taskbar has no bar');
  _expect(
    ShellPreset.taskbar.dock['shape'] == 'bar' &&
        ShellPreset.taskbar.dock['visibility'] == 'always',
    'a taskbar lies on its edge and stays',
  );
  _expect(ShellPreset.unified.barMode == 'islandOnly', 'unified keeps the island');

  // The dock and the bar mode count only when they are given.
  final task = ShellPreset.taskbar;
  final taskBar = Map<String, Object?>.of(task.bar);
  _expect(task.matches(look: 'soft', bar: taskBar), 'no dock, no bar mode');
  _expect(
    task.matches(
      look: 'soft',
      bar: taskBar,
      dock: <String, Object?>{...task.dock, 'iconSize': 40},
      barMode: 'hidden',
    ),
    'own dock and bar mode match, other keys do not count',
  );
  _expect(
    !task.matches(look: 'soft', bar: taskBar, barMode: 'shown'),
    'another bar mode differs',
  );
  _expect(
    !task.matches(
      look: 'soft',
      bar: taskBar,
      dock: <String, Object?>{...task.dock, 'align': 'center'},
    ),
    'a changed dock key differs',
  );
  _expect(
    !task.matches(
      look: 'soft',
      bar: taskBar,
      dock: <String, Object?>{
        ...task.dock,
        'trailing': <String>['clock', 'status'],
      },
    ),
    'a reordered dock zone differs',
  );

  // Matching: the look and the preset's own keys decide, by value.
  final preset = ShellPreset.omarchy;
  final bar = Map<String, Object?>.of(preset.bar);
  _expect(preset.matches(look: 'omarchy', bar: bar), 'own data matches');
  _expect(!preset.matches(look: 'denial', bar: bar), 'another look differs');
  _expect(
    preset.matches(
      look: 'omarchy',
      bar: <String, Object?>{...bar, 'showWifi': false, 'groundOpacity': 1.0},
    ),
    'other keys do not count, and 1 is 1.0',
  );
  _expect(
    preset.matches(
      look: 'omarchy',
      bar: <String, Object?>{
        ...bar,
        'start': List<Object?>.of(bar['start']! as List),
      },
    ),
    'lists compare by content',
  );
  _expect(
    !preset.matches(
      look: 'omarchy',
      bar: <String, Object?>{
        ...bar,
        'end': <String>['status', 'clock'],
      },
    ),
    'a moved part differs',
  );
  _expect(
    !preset.matches(
      look: 'omarchy',
      bar: <String, Object?>{...bar, 'contentPadding': 9},
    ),
    'a changed measure differs',
  );
  _expect(
    !preset.matches(look: 'omarchy', bar: bar..remove('shape')),
    'a missing key differs',
  );
  _expect(
    ShellPreset.denial.matches(
      look: 'denial',
      bar: Map<String, Object?>.of(ShellPreset.denial.bar)..remove('endInset'),
    ),
    'an unset key is the same as a missing one',
  );

  // The store: versions and unknown keys.
  final directory = Directory(
    '${_scratchRoot().path}/kit-store-${DateTime.now().microsecondsSinceEpoch}',
  )..createSync(recursive: true);
  try {
    final file = File('${directory.path}/denial_shell_kit.json');
    Map<String, dynamic> onDisk() =>
        jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;

    _expect(KitStore(file).read().isEmpty, 'no file reads as empty');
    _expect(KitStore.dockOf(KitStore(file).read()), 'the dock shows by default');

    // A version 1 file holds only the look.
    file.writeAsStringSync(jsonEncode({'style': 'mac', 'later': [1, 2]}));
    final store = KitStore(file);
    _expect(store.mayWrite, 'an unversioned file may be written');
    store.put('dock', false);
    _expect(onDisk()['version'] == KitStore.version, 'a write stamps the version');
    _expect(onDisk()['style'] == 'mac', 'a write keeps the look');
    _expect((onDisk()['later'] as List).length == 2, 'and keys it does not know');
    _expect(!KitStore.dockOf(store.read()), 'the dock switch is read back');
    store.put('preset', 'omarchy');
    _expect(
      KitStore.textOf(store.read(), 'preset') == 'omarchy' &&
          onDisk()['dock'] == false,
      'keys are written one at a time',
    );
    _expect(KitStore.textOf(store.read(), 'dock') == null, 'not text');
    _expect(KitStore.dockOf({'dock': 'no'}), 'only false hides the dock');

    // A newer file is read and left alone.
    file.writeAsStringSync(
      jsonEncode({'version': KitStore.version + 1, 'dock': false}),
    );
    final newer = KitStore(file);
    _expect(!newer.mayWrite, 'a newer file is read only');
    newer.put('dock', true);
    _expect(onDisk()['dock'] == false, 'and is not written');
    _expect(!KitStore.dockOf(newer.read()), 'but still read');

    // A broken file reads as empty and is replaced on the next write.
    file.writeAsStringSync('{ not json');
    final broken = KitStore(file);
    _expect(broken.read().isEmpty, 'a broken file reads as empty');
    broken.put('speed', 2);
    _expect(onDisk()['speed'] == 2, 'and can be written over');

    KitStore(null).put('dock', false);
    _expect(KitStore(null).read().isEmpty, 'no file, nothing kept');
    // Every preset comes back whole from no memory, from junk, and from its
    // own memory; and one preset's memory never leaks into another.
    for (final preset in ShellPreset.all) {
      for (final junk in <Object?>[null, 3, 'x', <String, Object?>{'bar': 4}]) {
        final plain = preset.recall(junk);
        _expect(
          preset.matches(
            look: plain.look,
            bar: plain.bar,
            dock: plain.dock,
            barMode: plain.barMode,
          ),
          '${preset.id} as shipped from $junk',
        );
      }
      final changed = <String, Object?>{...preset.bar, 'partGap': 11};
      final memory = preset.remember(
        look: 'terminal',
        barMode: 'shown',
        bar: <String, Object?>{...changed, 'showWifi': false},
        dock: <String, Object?>{...preset.dock, 'align': 'center', 'extra': 1},
      );
      final back = preset.recall(memory);
      _expect(back.look == 'terminal', '${preset.id} keeps its look');
      _expect(back.bar['partGap'] == 11, '${preset.id} keeps a change');
      _expect(!back.bar.containsKey('showWifi'), 'only layout keys are kept');
      _expect(back.dock['align'] == 'center', '${preset.id} keeps the dock');
      _expect(!back.dock.containsKey('extra'), 'only the dock layout keys');
      _expect(
        back.bar.length == preset.bar.length &&
            back.dock.length == preset.dock.length,
        '${preset.id} comes back whole',
      );
      // No dock running: the dock's earlier memory stays.
      final later = preset.remember(
        look: 'mac',
        barMode: 'shown',
        bar: changed,
        before: memory,
      );
      _expect(
        preset.recall(later).dock['align'] == 'center',
        '${preset.id} keeps the dock while none runs',
      );
      // A value of the wrong kind falls back to what ships.
      final wrong = preset.recall(<String, Object?>{
        'diff': true,
        'bar': <String, Object?>{'shape': 5, 'start': 'x', 'partGap': 'wide'},
        'dock': <String, Object?>{'leading': <Object?>[1, 2]},
      });
      _expect(
        wrong.bar['shape'] == preset.bar['shape'] &&
            wrong.bar['partGap'] == preset.bar['partGap'] &&
            wrong.dock['leading'] == preset.dock['leading'],
        '${preset.id} ignores values of the wrong kind',
      );
      // Unmodified preset remembers an empty map (no clutter stored).
      final clean = preset.remember(
        look: preset.look,
        barMode: preset.barMode,
        bar: preset.bar,
        dock: preset.dock,
        dockVisible: preset.dockVisible,
      );
      _expect(clean.isEmpty, '${preset.id} stores nothing when unchanged');
    }

    // Legacy snapshot migration (pre-diff): keeps user's real edits and drops
    // keys that merely matched old (668cd0d) or current shipped defaults.
    final legacyOmarchy = <String, Object?>{
      'look': 'terminal', // old 668cd0d default -> should migrate to 'omarchy'
      'barMode': 'shown',
      'bar': <String, Object?>{
        'endInset': 0, // old 668cd0d default -> should migrate to 8
        'barHeight': null, // old 668cd0d default -> should migrate to 26
        'partGap': 14, // real user edit -> MUST survive!
      },
      'dock': <String, Object?>{'align': 'center'}, // real user edit -> MUST survive!
    };
    final migrated = ShellPreset.omarchy.recall(legacyOmarchy);
    _expect(
      migrated.look == ShellPreset.omarchy.look &&
          migrated.bar['endInset'] == ShellPreset.omarchy.bar['endInset'] &&
          migrated.bar['barHeight'] == ShellPreset.omarchy.bar['barHeight'] &&
          migrated.bar['partGap'] == 14 &&
          migrated.dock['align'] == 'center',
      'legacy snapshot drops obsolete defaults while preserving genuine user edits',
    );
    // Diff memory only stores changed keys, so future shipped default updates
    // flow automatically to untouched keys.
    final diffMemory = ShellPreset.noctalia.remember(
      look: ShellPreset.noctalia.look,
      barMode: ShellPreset.noctalia.barMode,
      bar: <String, Object?>{...ShellPreset.noctalia.bar, 'partGap': 12},
      dock: ShellPreset.noctalia.dock,
      dockVisible: ShellPreset.noctalia.dockVisible,
    );
    _expect(
      diffMemory['diff'] == true &&
          !diffMemory.containsKey('look') &&
          !diffMemory.containsKey('dock') &&
          (diffMemory['bar']! as Map).length == 1 &&
          (diffMemory['bar']! as Map)['partGap'] == 12,
      'diff memory stores only keys differing from shipped defaults',
    );
    final userPreset = ShellPreset.fromJson(<String, Object?>{
      'id': 'custom-user',
      'label': 'User',
      'look': 'mac',
      'bar': ShellPreset.denial.bar,
      'dock': ShellPreset.denial.dock,
    })!;
    final keptUser = userPreset.recall(legacyOmarchy);
    _expect(
      keptUser.look == 'terminal' &&
          keptUser.bar['partGap'] == 14 &&
          keptUser.dock['align'] == 'center',
      'user preset legacy memory is preserved',
    );
    stdout.writeln('All shell preset and store tests passed.');
  } finally {
    directory.deleteSync(recursive: true);
  }
}
