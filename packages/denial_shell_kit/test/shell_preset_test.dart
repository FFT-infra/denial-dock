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

  // Matching: the look and the preset's own keys decide, by value.
  final preset = ShellPreset.omarchy;
  final bar = Map<String, Object?>.of(preset.bar);
  _expect(preset.matches(look: 'terminal', bar: bar), 'own data matches');
  _expect(!preset.matches(look: 'denial', bar: bar), 'another look differs');
  _expect(
    preset.matches(
      look: 'terminal',
      bar: <String, Object?>{...bar, 'showWifi': false, 'groundOpacity': 1.0},
    ),
    'other keys do not count, and 1 is 1.0',
  );
  _expect(
    preset.matches(
      look: 'terminal',
      bar: <String, Object?>{
        ...bar,
        'start': List<Object?>.of(bar['start']! as List),
      },
    ),
    'lists compare by content',
  );
  _expect(
    !preset.matches(
      look: 'terminal',
      bar: <String, Object?>{
        ...bar,
        'end': <String>['status', 'clock'],
      },
    ),
    'a moved part differs',
  );
  _expect(
    !preset.matches(
      look: 'terminal',
      bar: <String, Object?>{...bar, 'contentPadding': 9},
    ),
    'a changed measure differs',
  );
  _expect(
    !preset.matches(look: 'terminal', bar: bar..remove('shape')),
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
    stdout.writeln('All shell preset and store tests passed.');
  } finally {
    directory.deleteSync(recursive: true);
  }
}
