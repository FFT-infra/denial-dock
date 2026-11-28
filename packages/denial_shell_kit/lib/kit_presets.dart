import 'dart:io';

import 'package:flutter/foundation.dart';

import 'kit_store.dart';
import 'kit_style.dart';
import 'shell_preset.dart';

/// The presets the user saved, kept under `userPresets` in
/// `denial_shell_kit.json`, and their way in and out of the shell as JSON:
/// a file under `presets` in the configuration directory, or text on the
/// clipboard.
final KitPresetsNotifier kitPresets = KitPresetsNotifier._();

class KitPresetsNotifier extends ValueNotifier<List<ShellPreset>> {
  KitPresetsNotifier._() : super(ShellPreset.stored(kitStore.read()['userPresets'])) {
    ShellPreset.user = value;
  }

  /// An id no preset has yet.
  String freshId() => _fresh('preset', <String>{
    for (final preset in ShellPreset.everything) preset.id,
  });

  void _write(List<ShellPreset> next) {
    value = List<ShellPreset>.unmodifiable(next);
    ShellPreset.user = value;
    kitStore.put('userPresets', <Object?>[
      for (final preset in next) preset.toJson(),
    ]);
  }

  /// Adds [preset], or puts it in place of the one with its id. Unless
  /// [keepMemory] is true, what the shell remembered of the replaced preset is
  /// dropped. A preset that ships cannot be replaced.
  void save(ShellPreset preset, {bool keepMemory = false}) {
    if (ShellPreset.all.any((one) => one.id == preset.id)) return;
    final replaced = value.any((one) => one.id == preset.id);
    _write(<ShellPreset>[
      for (final one in value)
        if (one.id == preset.id) preset else one,
      if (!replaced) preset,
    ]);
    if (replaced && !keepMemory) _forget(preset.id);
  }

  /// Drops the preset called [id] and what the shell remembered of it.
  void remove(String id) {
    if (!value.any((one) => one.id == id)) return;
    _write(<ShellPreset>[
      for (final one in value)
        if (one.id != id) one,
    ]);
    _forget(id);
  }

  void _forget(String id) {
    final memory = kitStore.read()['presets'];
    if (memory is! Map || !memory.containsKey(id)) return;
    kitStore.put('presets', <String, Object?>{
      for (final entry in memory.entries)
        if (entry.key is String && entry.key != id)
          entry.key as String: entry.value,
    });
  }

  /// [preset] as a document, with its look inside when the user made it.
  String export(ShellPreset preset) {
    final look = KitStyle.byId(preset.look);
    return ShellPresetFile(
      preset,
      look: look.custom && look.id == preset.look ? look.look.toJson() : null,
    ).encode();
  }

  /// Reads a preset from [text] and keeps it under a new id. A look that
  /// came with it is kept too, unless the user already has that very look;
  /// a preset naming a look this shell lacks takes Denial's. Throws a
  /// [ShellPresetException] when [text] is no preset.
  ShellPreset import(String text) {
    final file = ShellPresetFile.decode(text);
    var look = file.preset.look;
    final carried = file.look;
    if (carried != null && KitLook.builtin(look) == null) {
      final base = carried['base'];
      final under = KitLook.builtin(base is String ? base : null) ??
          KitLook.denial;
      final label = carried['label'];
      var read = KitLook.fromJson(<String, Object?>{
        ...carried,
        'base': under.id,
        'label': label is String && label.isNotEmpty ? label : file.preset.label,
      }, base: under);
      final same = kitLooks.value
          .where((one) => one.id == read.id && one.look == read)
          .firstOrNull;
      if (same == null) {
        read = read.change(<String, Object?>{'id': kitLooks.freshId()});
        look = kitLooks.save(read)?.id ?? KitLook.denial.id;
      } else {
        look = same.id;
      }
    } else if (KitStyle.byId(look).id != look) {
      look = KitLook.denial.id;
    }
    final preset = file.preset.renamed(id: freshId(), look: look);
    save(preset);
    return preset;
  }

  /// Writes [preset] into the presets directory and returns the file, or
  /// null when there is nowhere to write or the write failed. A file of the
  /// same name is replaced.
  File? exportFile(ShellPreset preset) {
    final directory = kitStore.presetsDirectory;
    if (directory == null) return null;
    try {
      directory.createSync(recursive: true);
      final file = File(
        '${directory.path}/${ShellPresetFile.fileName(preset.label)}',
      );
      final temp = File('${file.path}.$pid.tmp')
        ..writeAsStringSync('${export(preset)}\n');
      temp.renameSync(file.path);
      return file;
    } on FileSystemException {
      return null;
    }
  }

  /// The preset files in the presets directory, by name.
  List<File> files() {
    final directory = kitStore.presetsDirectory;
    if (directory == null || !directory.existsSync()) return const <File>[];
    try {
      return <File>[
        for (final entry in directory.listSync())
          if (entry is File && entry.path.endsWith('.json')) entry,
      ]..sort((a, b) => a.path.compareTo(b.path));
    } on FileSystemException {
      return const <File>[];
    }
  }

  /// Reads the preset in [file]; see [import]. A file that cannot be read
  /// counts as one that is no preset.
  ShellPreset importFile(File file) {
    final String text;
    try {
      if (file.lengthSync() > ShellPresetFile.longest) {
        throw const ShellPresetException(ShellPresetFault.notPreset);
      }
      text = file.readAsStringSync();
    } on FileSystemException {
      throw const ShellPresetException(ShellPresetFault.notPreset);
    } on FormatException {
      throw const ShellPresetException(ShellPresetFault.notJson);
    }
    return import(text);
  }
}

String _fresh(String prefix, Set<String> taken) {
  final stamp = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
  var id = '$prefix-$stamp';
  for (var n = 2; taken.contains(id); n++) {
    id = '$prefix-$stamp-$n';
  }
  return id;
}
