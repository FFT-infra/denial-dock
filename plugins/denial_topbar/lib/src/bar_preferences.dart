import 'package:denial_shell_kit/kit_dock_link.dart';
import 'package:denial_shell_kit/kit_host.dart';
import 'package:denial_shell_kit/kit_presets.dart';
import 'package:denial_shell_kit/kit_store.dart';
import 'package:denial_shell_kit/kit_style.dart';
import 'package:denial_shell_kit/shell_preset.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'bar_settings.dart';

// The layout page is a part of the settings panel, which imports this file;
// the preset tools reach it from here.
export 'package:denial_shell_kit/kit_presets.dart' show kitPresets;
export 'panels/preset_tools.dart' show PresetTools;

/// Persisted bar preferences. Reads once, writes are serialized so two quick
/// toggles cannot interleave their temp files.
final barSettingsProvider =
    AsyncNotifierProvider<BarSettingsController, BarSettings>(
      BarSettingsController.new,
    );

class BarSettingsController extends AsyncNotifier<BarSettings> {
  BarPreferencesStore? _store;
  Future<void> _writes = Future<void>.value();

  @override
  Future<BarSettings> build() async {
    final store = BarPreferencesStore(BarPreferencesStore.defaultFile());
    _store = store;
    return store.read();
  }

  /// Applies [change] to the current value and persists the result.
  Future<void> save(BarSettings Function(BarSettings current) change) async {
    final current = state.value ?? BarSettings.defaults;
    final next = change(current);
    state = AsyncData(next);
    final store = _store;
    if (store == null) return;
    _writes = _writes.then((_) => store.write(next)).catchError((_) {});
    await _writes;
  }
}

/// Applies [preset]: the look for the whole shell, the bar's layout, how
/// much of itself the bar draws, and the dock's layout. Every other setting
/// of the bar and the dock stays as it is. With no dock running the dock's
/// part waits in the kit until one starts.
///
/// Each preset remembers how the user left it: going to another keeps the
/// one in force under its name, and coming back brings it out again. With
/// [fresh] the preset is applied as it ships and its memory is dropped.
void applyShellPreset(WidgetRef ref, ShellPreset preset, {bool fresh = false}) {
  final settings = ref.read(barSettingsProvider).value;
  final stored = kitStore.read()['presets'];
  final memory = <String, Object?>{
    if (stored is Map)
      for (final entry in stored.entries)
        if (entry.key is String) entry.key as String: entry.value,
  };
  final leaving = ShellPreset.byId(kitPreset.value);
  if (settings != null && leaving.id != preset.id) {
    memory[leaving.id] = leaving.remember(
      look: kitStyle.chosen,
      barMode: kitBarMode.value.key,
      bar: settings.layoutJson(),
      dock: kitDock.layout,
      before: memory[leaving.id],
    );
  }
  if (fresh) memory.remove(preset.id);
  kitStore.put('presets', memory);
  final next = preset.recall(memory[preset.id]);
  kitStyle.choose(KitStyle.byId(next.look));
  kitPreset.value = preset.id;
  kitBarMode.value = KitBarMode.parse(next.barMode);
  kitDock.apply(next.dock);
  ref
      .read(barSettingsProvider.notifier)
      .save((settings) => settings.withLayout(next.bar));
}

/// Drops what every preset remembers.
void forgetShellPresets() => kitStore.put('presets', <String, Object?>{});

/// Whether the shell has been changed since [preset] was applied. The dock
/// counts while one runs.
bool shellPresetModified(ShellPreset preset, BarSettings settings) =>
    !preset.matches(
      look: kitStyle.chosen,
      bar: settings.layoutJson(),
      dock: kitDock.layout,
      barMode: kitBarMode.value.key,
    );

/// The shell as it stands as a preset of the user's: the look in force, how
/// much of itself the bar draws, the bar's layout and the dock's. With no
/// dock running the dock's part is the one of the preset in force.
ShellPreset snapshotShellPreset(
  BarSettings settings, {
  required String id,
  required String label,
}) => ShellPreset.fromJson(<String, Object?>{
  'label': label,
  'look': kitStyle.chosen,
  'barMode': kitBarMode.value.key,
  'bar': settings.layoutJson(),
  'dock': kitDock.layout ?? ShellPreset.byId(kitPreset.value).dock,
}, id: id)!;

/// Saves the shell as it stands as a new preset called [label] and makes it
/// the preset in force.
ShellPreset saveShellPresetAs(BarSettings settings, String label) {
  final preset = snapshotShellPreset(
    settings,
    id: kitPresets.freshId(),
    label: label,
  );
  kitPresets.save(preset);
  kitPreset.value = preset.id;
  return preset;
}

/// Reads a preset from [text] and keeps it; see [KitPresetsNotifier.import].
/// The bar's part is passed through the bar's own settings first, so every
/// value is one the bar can draw and the preset matches the shell once it
/// is applied.
ShellPreset importShellPreset(String text) {
  final read = kitPresets.import(text);
  final sound = ShellPreset.fromJson(<String, Object?>{
    ...read.toJson(),
    'bar': BarSettings.defaults.withLayout(read.bar).layoutJson(),
  }, id: read.id)!;
  kitPresets.save(sound);
  return sound;
}
