import 'dart:async';

import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart';

import 'launcher_entry.dart';

/// Progress that applications publish for docks, over the session bus signal
/// `com.canonical.Unity.LauncherEntry.Update`: downloads, file copies, and so
/// on. The value maps desktop ids to a progress of 0..1.
class LauncherProgress extends ValueNotifier<Map<String, double>> {
  LauncherProgress() : super(const <String, double>{});

  static const Duration _stale = Duration(seconds: 90);

  DBusClient? _client;
  StreamSubscription<DBusSignal>? _signals;
  final LauncherEntries _entries = LauncherEntries();
  Timer? _sweep;

  void start() {
    if (_client != null) return;
    try {
      final client = _client = DBusClient.session();
      _signals = DBusSignalStream(
        client,
        interface: 'com.canonical.Unity.LauncherEntry',
        name: 'Update',
      ).listen(_onSignal, onError: (_) {});
    } on Object {
      _client = null;
    }
  }

  void _onSignal(DBusSignal signal) {
    if (signal.signature != DBusSignature('sa{sv}')) return;
    final props = <String, Object?>{
      for (final entry in signal.values[1].asStringVariantDict().entries)
        entry.key: entry.value.toNative(),
    };
    _entries.update(signal.values[0].asString(), props, DateTime.now());
    _publish();
  }

  void _publish() {
    final now = DateTime.now();
    _entries.dropOlderThan(now.subtract(_stale));
    final next = _entries.progress;
    if (!mapEquals(next, value)) value = next;
    _sweep?.cancel();
    if (next.isNotEmpty) _sweep = Timer(_stale, _publish);
  }

  @override
  void dispose() {
    _sweep?.cancel();
    _signals?.cancel();
    _client?.close();
    super.dispose();
  }
}

final LauncherProgress launcherProgress = LauncherProgress();
