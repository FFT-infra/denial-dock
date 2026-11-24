import 'dart:async';

import 'package:dbus/dbus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'launcher_entry.dart';

/// What applications publish through the Unity launcher API, keyed by
/// application id as [LauncherEntries.applicationId] spells it. Only entries
/// with something to show are in the map.
final launcherEntriesProvider =
    NotifierProvider<LauncherEntryBus, Map<String, LauncherEntry>>(
      LauncherEntryBus.new,
    );

/// Listens on the session bus and folds the signals through
/// [LauncherEntries]. A session without a bus leaves the map empty.
class LauncherEntryBus extends Notifier<Map<String, LauncherEntry>> {
  static const String _interface = 'com.canonical.Unity.LauncherEntry';

  final LauncherEntries _entries = LauncherEntries();
  final List<StreamSubscription<Object?>> _subscriptions = [];
  DBusClient? _client;
  bool _disposed = false;

  @override
  Map<String, LauncherEntry> build() {
    _disposed = false;
    ref.onDispose(_close);
    unawaited(_listen());
    return const {};
  }

  Future<void> _listen() async {
    try {
      final client = DBusClient.session();
      _client = client;
      _subscriptions.add(
        DBusSignalStream(
          client,
          interface: _interface,
          name: 'Update',
        ).listen(_onUpdate, onError: (Object _) {}),
      );
      _subscriptions.add(
        client.nameOwnerChanged.listen(_onOwnerChanged, onError: (Object _) {}),
      );
      // Some senders only publish while this name has an owner. Another shell
      // component may hold it already, which serves them just as well.
      await client.requestName(
        'com.canonical.Unity',
        flags: {DBusRequestNameFlag.doNotQueue},
      );
    } on Object {
      // No session bus, or it refused the name: the signals that do arrive
      // are still handled.
    }
    if (_disposed) _close();
  }

  /// The desktop id for [id] as its sender spelled it.
  String desktopId(String id) => _entries.spelling(id);

  void _onUpdate(DBusSignal signal) {
    final sender = signal.sender;
    final values = signal.values;
    if (sender == null || values.length != 2) return;
    final uri = values[0];
    final properties = values[1];
    if (uri is! DBusString || properties is! DBusDict) return;
    final plain = <String, Object?>{};
    for (final entry in properties.children.entries) {
      final key = entry.key;
      if (key is! DBusString) continue;
      var value = entry.value;
      if (value is DBusVariant) value = value.value;
      plain[key.value] = switch (value) {
        DBusBoolean(:final value) => value,
        DBusDouble(:final value) => value,
        DBusInt32(:final value) => value,
        DBusInt64(:final value) => value,
        DBusUint32(:final value) => value,
        _ => null,
      };
    }
    if (_entries.update(sender, uri.value, plain) != null) _publish();
  }

  void _onOwnerChanged(DBusNameOwnerChangedEvent event) {
    if (event.newOwner != null || !event.name.startsWith(':')) return;
    if (_entries.removeSender(event.name).isNotEmpty) _publish();
  }

  void _publish() {
    if (_disposed) return;
    state = Map.unmodifiable(_entries.active);
  }

  void _close() {
    _disposed = true;
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    final client = _client;
    _client = null;
    if (client != null) unawaited(client.close().catchError((Object _) {}));
  }
}
