import 'dart:convert';
import 'dart:io';

import 'package:denial_shell_kit/kit_look.dart';
import 'package:denial_shell_kit/kit_store.dart';
import 'package:denial_shell_kit/shell_preset.dart';

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Directory _scratchRoot() {
  final home = Platform.environment['HOME'];
  final root = home == null || !home.startsWith('/')
      ? Directory.current
      : Directory('$home/Lab/Bridge/tmp');
  return root.existsSync() ? root : Directory.current;
}

/// The parts a bar zone or an end of the dock may name.
bool _part(String id) =>
    const <String>{
      'system',
      'workspaces',
      'app',
      'island',
      'clock',
      'status',
      'spacer',
      'separator',
      'gap',
      'dock.launcher',
      'dock.stacks',
      'dock.trash',
      'dock.divider',
    }.contains(id) ||
    RegExp(r'^status\.[a-z]+$').hasMatch(id);

ShellPresetFault? _fault(String text) {
  try {
    ShellPresetFile.decode(text);
    return null;
  } on ShellPresetException catch (error) {
    return error.fault;
  }
}

void main() {
  // Every preset that ships takes a look that ships and names only parts
  // that exist, and reads back from its own JSON unchanged.
  for (final preset in ShellPreset.all) {
    _expect(
      KitLook.builtin(preset.look) != null,
      '${preset.id} takes a look that ships',
    );
    _expect(
      ShellPreset.barModes.contains(preset.barMode),
      '${preset.id} has a bar mode',
    );
    for (final zone in <String>['start', 'center', 'end']) {
      final parts = preset.bar[zone];
      _expect(parts is List<String>, '${preset.id} lists its $zone');
      for (final part in parts! as List<String>) {
        _expect(!part.startsWith('dock.'), '${preset.id}: $part is the dock\'s');
        _expect(_part(part), '${preset.id} bar names $part');
      }
    }
    for (final end in <String>['leading', 'trailing']) {
      for (final part in preset.dock[end]! as List<String>) {
        _expect(_part(part), '${preset.id} dock names $part');
      }
    }
    final back = ShellPreset.fromJson(
      jsonDecode(jsonEncode(preset.toJson())),
    )!;
    _expect(
      back.matches(
        look: preset.look,
        bar: preset.bar,
        dock: preset.dock,
        barMode: preset.barMode,
      ),
      '${preset.id} survives its JSON',
    );
    _expect(back.group == ShellPresetGroup.user, 'what is read is the user\'s');
  }

  // The reference shelf: a preset for every reference look, under a label
  // that says "style".
  final references = ShellPreset.all
      .where((preset) => preset.group == ShellPresetGroup.reference)
      .toList();
  _expect(references.isNotEmpty, 'reference presets ship');
  _expect(
    references.length == KitLook.builtins.length - KitLook.core.length,
    'one preset to a reference look',
  );
  for (final preset in references) {
    _expect(preset.look == preset.id, '${preset.id} takes its own look');
    _expect(preset.label.endsWith(' style'), '${preset.id} is called a style');
    _expect(
      KitLook.builtin(preset.look)!.label == preset.label,
      '${preset.id}: look and preset share a label',
    );
  }

  // A preset from anywhere is put right, never thrown on.
  final odd = ShellPreset.fromJson(<String, Object?>{
    'label': '   ',
    'look': 7,
    'barMode': 'sideways',
    'bar': <String, Object?>{
      'groundOpacity': 40,
      'cornerRadius': -3,
      'partGap': double.nan,
      'shape': 12,
      'start': <Object?>['system', 3, ''],
      'center': 'clock',
      'stray': true,
    },
    'dock': <String, Object?>{'shape': 'sphere', 'align': 'center'},
  })!;
  _expect(odd.label == 'Preset' && odd.look == 'denial', 'name and look');
  _expect(odd.barMode == 'shown', 'an unknown bar mode is the usual one');
  _expect(odd.bar['groundOpacity'] == 1, 'opacity is clamped');
  _expect(odd.bar['cornerRadius'] == 0, 'radius is clamped');
  _expect(odd.bar['partGap'] == 6, 'not-a-number keeps the usual gap');
  _expect(odd.bar['shape'] == 'strip', 'a wrong kind keeps the usual shape');
  _expect((odd.bar['start']! as List).length == 2, 'a list of more than names');
  _expect((odd.bar['center']! as List).single == 'island', 'a wrong list');
  _expect(!odd.bar.containsKey('stray'), 'unknown layout keys are dropped');
  _expect(odd.dock['shape'] == 'floating', 'an unknown dock shape');
  _expect(odd.dock['align'] == 'center', 'a known dock name is kept');
  _expect(ShellPreset.fromJson('preset') == null, 'no map, no preset');

  // A preset file: out and back, with the look it carries.
  final mine = KitLook.stored('look-1', <String, Object?>{
    'label': 'Mine',
    'base': 'soft',
    'set': <String, Object?>{
      'accent': '#ff6b35',
      'corners': <String, Object?>{'scale': 1.4},
    },
  });
  final saved = ShellPreset.compact.renamed(
    id: 'preset-1',
    label: 'Work',
    look: mine.id,
  );
  final text = ShellPresetFile(saved, look: mine.toJson()).encode();
  final read = ShellPresetFile.decode(text);
  _expect(read.preset.label == 'Work', 'the name comes back');
  _expect(
    read.preset.matches(
      look: 'look-1',
      bar: saved.bar,
      dock: saved.dock,
      barMode: saved.barMode,
    ),
    'the arrangement comes back',
  );
  _expect(
    KitLook.fromJson(read.look!, base: KitLook.soft) == mine,
    'the look comes back',
  );
  _expect(
    ShellPresetFile(read.preset, look: read.look).encode() == text,
    'and writes the same text again',
  );
  _expect(
    ShellPresetFile.decode(ShellPresetFile(ShellPreset.mac).encode()).look ==
        null,
    'a look that ships is not carried',
  );

  // Files that are no preset say why.
  _expect(_fault('{ not json') == ShellPresetFault.notJson, 'broken text');
  _expect(_fault('[1, 2]') == ShellPresetFault.notPreset, 'a list');
  _expect(_fault('{"format": "other"}') == ShellPresetFault.notPreset, 'kind');
  _expect(
    _fault('{"format": "denial-shell-preset", "version": 99, "preset": {}}') ==
        ShellPresetFault.newer,
    'a newer file',
  );
  _expect(
    _fault('{"format": "denial-shell-preset", "version": 1, "preset": 4}') ==
        ShellPresetFault.notPreset,
    'no preset inside',
  );
  _expect(
    _fault('{"format": "denial-shell-preset", "version": "1"}') ==
        ShellPresetFault.notPreset,
    'a version that is no number',
  );
  _expect(
    _fault(' ' * (ShellPresetFile.longest + 1)) == ShellPresetFault.notPreset,
    'too long to be one',
  );
  _expect(ShellPresetFile.fileName('My  Bar!') == 'my-bar.json', 'file name');
  _expect(ShellPresetFile.fileName('///') == 'preset.json', 'no name left');

  // The user's presets as stored: ones that clash with a shipped id, or
  // with one another, are left out.
  final stored = ShellPreset.stored(<Object?>[
    saved.toJson(),
    saved.toJson(),
    ShellPreset.mac.toJson(),
    'junk',
  ]);
  _expect(stored.length == 1 && stored.single.id == 'preset-1', 'stored');

  // A look stops setting a dock value when the key is written as null, and
  // the store keeps that.
  final plasma = KitLook.builtin('plasma')!;
  _expect(plasma.dock['iconSize'] == 40, 'the reference sets an icon size');
  final freed = plasma.change(<String, Object?>{
    'id': 'look-2',
    'base': 'plasma',
    'dock': <String, Object?>{'iconSize': null, 'radius': 'round'},
  });
  _expect(!freed.dock.containsKey('iconSize'), 'null drops the key');
  _expect(freed.dock['radius'] == 8, 'a wrong kind keeps the base value');
  final kept = jsonDecode(jsonEncode(freed.toStored()));
  _expect(KitLook.stored('look-2', kept) == freed, 'and the store keeps it');

  // The store: a file from before looks and presets is read as it is and
  // gains them at the next write; a file from a newer build is not written.
  final directory = Directory(
    '${_scratchRoot().path}/kit-data-${DateTime.now().microsecondsSinceEpoch}',
  )..createSync(recursive: true);
  try {
    final file = File('${directory.path}/denial_shell_kit.json');
    Map<String, dynamic> onDisk() =>
        jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;

    file.writeAsStringSync(
      '{"version": 2, "style": "mac", "preset": "unified", "later": [1]}',
    );
    final old = KitStore(file);
    _expect(old.mayWrite, 'an older file may be written');
    _expect(old.read()['looks'] == null, 'it holds no looks yet');
    _expect(ShellPreset.stored(old.read()['userPresets']).isEmpty, 'no presets');
    old.put('looks', <String, Object?>{'look-1': mine.toStored()});
    old.put('userPresets', <Object?>[saved.toJson()]);
    final after = onDisk();
    _expect(after['version'] == KitStore.version, 'the version moves up');
    _expect(after['style'] == 'mac' && after['preset'] == 'unified', 'kept');
    _expect((after['later'] as List).single == 1, 'unknown keys are kept');
    _expect(
      KitLook.stored('look-1', (after['looks'] as Map)['look-1']) == mine,
      'the look reads back from the file',
    );
    _expect(
      ShellPreset.stored(after['userPresets']).single.label == 'Work',
      'the preset reads back from the file',
    );
    _expect(
      old.presetsDirectory!.path == '${directory.path}/presets',
      'preset files go beside the store',
    );

    const newer = '{"version": 99, "style": "soft", "looks": {"x": 1}}';
    file.writeAsStringSync(newer);
    final ahead = KitStore(file);
    _expect(!ahead.mayWrite, 'a newer file is not written');
    ahead.put('looks', <String, Object?>{});
    _expect(file.readAsStringSync() == newer, 'and stays as it was');
    _expect(ahead.read()['style'] == 'soft', 'but is still read');
    _expect(
      KitLook.stored('x', ahead.read()['looks']['x']).id == 'x',
      'and a look it holds in a form unknown here still gives a look',
    );
  } finally {
    directory.deleteSync(recursive: true);
  }

  stdout.writeln('kit_data_test: ok');
}
