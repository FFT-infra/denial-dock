import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Height of the plugin's surface. It covers the capsule, the magnification
/// headroom and the name label, and stays clear of the top bar.
const double dockSurfaceHeight = 180.0;

/// Icons and their identity are matched without the `.desktop` suffix and case.
String normalizeAppId(String id) =>
    id.trim().toLowerCase().replaceFirst(RegExp(r'\.desktop$'), '');

enum DockVisibilityMode {
  /// Always in reach, even under a window.
  always,

  /// Retract while a window covers the dock's strip; return on edge hover.
  smart,
}

@immutable
class DockPin {
  const DockPin({required this.id, required this.appId, required this.name});

  /// Opaque launch identity. [appId] is only the icon identity.
  final String id;
  final String appId;
  final String name;

  Map<String, String> toJson() => {'id': id, 'appId': appId, 'name': name};
}

@immutable
class DockSettings {
  const DockSettings({
    this.pinned = defaultPins,
    this.visibility = DockVisibilityMode.smart,
  });

  /// Base icon edge before magnification.
  static const double iconSize = 48.0;
  static const double gap = 8.0;
  static const double padding = 8.0;
  static const double maxScale = 1.6;
  static const double magnificationRadius = 140.0;
  static const double liftRatio = 0.25;

  /// Release glide for a dragged icon; same 180ms ease as the reference dock's
  /// neighbour reorder.
  static const double dragSettleSeconds = 0.18;

  /// Capsule height with no magnification.
  static const double capsuleHeight = iconSize + padding * 2;

  static const List<DockPin> defaultPins = [
    DockPin(
      id: 'org.gnome.Nautilus.desktop',
      appId: 'org.gnome.Nautilus.desktop',
      name: '文件',
    ),
    DockPin(
      id: 'google-chrome.desktop',
      appId: 'google-chrome.desktop',
      name: 'Chrome',
    ),
    DockPin(id: 'code.desktop', appId: 'code.desktop', name: 'VS Code'),
    DockPin(
      id: 'com.mitchellh.ghostty.desktop',
      appId: 'com.mitchellh.ghostty.desktop',
      name: 'Ghostty',
    ),
    DockPin(
      id: 'md.obsidian.Obsidian.desktop',
      appId: 'md.obsidian.Obsidian.desktop',
      name: 'Obsidian',
    ),
    DockPin(
      id: 'antigravity.desktop',
      appId: 'antigravity.desktop',
      name: 'Antigravity',
    ),
  ];

  static const DockSettings defaults = DockSettings();

  final List<DockPin> pinned;
  final DockVisibilityMode visibility;

  factory DockSettings.fromJson(Map<String, dynamic> json) {
    final stored = json['pinnedApplications'];
    final seen = <String>{};
    final pins = <DockPin>[];
    if (stored is List) {
      for (final entry in stored) {
        if (entry is! Map) continue;
        final id = entry['id'];
        final appId = entry['appId'];
        final name = entry['name'];
        if (id is! String ||
            id.isEmpty ||
            appId is! String ||
            appId.isEmpty ||
            name is! String ||
            !seen.add(normalizeAppId(appId))) {
          continue;
        }
        pins.add(DockPin(id: id, appId: appId, name: name));
      }
    }
    return DockSettings(
      // An explicit empty list means the user removed every pin.
      pinned: stored is List ? List.unmodifiable(pins) : defaultPins,
      visibility: json['visibility'] == 'always'
          ? DockVisibilityMode.always
          : DockVisibilityMode.smart,
    );
  }
}

/// Atomic, plugin-owned preferences. Unknown keys survive a pin update and a
/// malformed file is surfaced instead of being silently replaced.
class DockPreferencesStore {
  DockPreferencesStore(this.file);

  final File file;
  int _sequence = 0;

  static File defaultFile() {
    final env = Platform.environment;
    final configured = env['XDG_CONFIG_HOME'];
    final home = env['HOME'];
    final root = configured != null && configured.startsWith('/')
        ? configured
        : home != null && home.startsWith('/')
        ? '$home/.config'
        : null;
    if (root == null) {
      throw const FileSystemException('No configuration directory');
    }
    return File('$root/denial/plugins/denial_dock.json');
  }

  Future<Map<String, dynamic>> _readJson() async {
    try {
      final value = jsonDecode(await file.readAsString());
      if (value is! Map<String, dynamic>) {
        throw const FormatException('Expected a JSON object');
      }
      return value;
    } on FileSystemException catch (error) {
      if (error.osError?.errorCode == 2) return {};
      rethrow;
    }
  }

  Future<DockSettings> read() async => DockSettings.fromJson(await _readJson());

  Future<void> writePins(List<DockPin> pins) async {
    final json = await _readJson();
    json['pinnedApplications'] = pins.map((pin) => pin.toJson()).toList();
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.$pid.${_sequence++}.tmp');
    try {
      await temp.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(json)}\n',
        flush: true,
      );
      await temp.rename(file.path);
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  }
}

final dockSettingsProvider =
    AsyncNotifierProvider<DockSettingsController, DockSettings>(
      DockSettingsController.new,
    );

class DockSettingsController extends AsyncNotifier<DockSettings> {
  late DockPreferencesStore _store;
  Future<void> _writes = Future.value();

  @override
  Future<DockSettings> build() {
    _store = DockPreferencesStore(DockPreferencesStore.defaultFile());
    return _store.read();
  }

  Future<void> togglePin(DockPin pin, {required bool pinned}) =>
      _update((pins) {
        final key = normalizeAppId(pin.appId);
        final without = pins
            .where((existing) => normalizeAppId(existing.appId) != key)
            .toList();
        return pinned ? [...without, pin] : without;
      });

  /// Moves a pinned entry to [to] using remove-then-insert order, matching the
  /// dock's drag preview.
  Future<void> movePin(int from, int to) => _update((pins) {
    if (from < 0 || from >= pins.length) return pins;
    final copy = [...pins];
    final item = copy.removeAt(from);
    copy.insert(to.clamp(0, copy.length), item);
    return copy;
  });

  Future<void> _update(List<DockPin> Function(List<DockPin>) update) {
    final operation = _writes.then((_) async {
      if (!ref.mounted) return;
      final current = state.value ?? DockSettings.defaults;
      final snapshot = List<DockPin>.unmodifiable(update(current.pinned));
      await _store.writePins(snapshot);
      if (!ref.mounted) return;
      state = AsyncData(
        DockSettings(pinned: snapshot, visibility: current.visibility),
      );
    });
    // A failed write is reported to the caller but must not poison later saves.
    _writes = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }
}
