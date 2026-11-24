import 'dart:async';

import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart';

import 'tray_address.dart';

class TrayIdentity {
  const TrayIdentity(this.key, this.title);

  /// Survives a restart of the application, unlike its bus name.
  final String key;
  final String title;
}

/// Resolves tray ids to the `Id` and `Title` each StatusNotifierItem
/// publishes, so a hidden item stays hidden after its bus name changes.
class TrayNames extends ValueNotifier<Map<String, TrayIdentity>> {
  TrayNames() : super(const <String, TrayIdentity>{});

  DBusClient? _client;
  final Set<String> _asked = <String>{};

  TrayIdentity of(String id) =>
      value[id] ?? TrayIdentity(id, trayFallbackName(id));

  void resolve(Iterable<String> ids) {
    for (final id in ids) {
      if (_asked.add(id)) unawaited(_ask(id));
    }
  }

  Future<void> _ask(String id) async {
    final address = trayAddress(id);
    if (address == null) return;
    try {
      final client = _client ??= DBusClient.session();
      final object = DBusRemoteObject(
        client,
        name: address.service,
        path: DBusObjectPath(address.path),
      );
      final all = await object
          .getAllProperties('org.kde.StatusNotifierItem')
          .timeout(const Duration(seconds: 3));
      String text(String name) {
        final found = all[name];
        return found is DBusString ? found.value : '';
      }

      final key = text('Id');
      final title = text('Title');
      if (key.isEmpty && title.isEmpty) return;
      value = <String, TrayIdentity>{
        ...value,
        id: TrayIdentity(
          key.isEmpty ? title : key,
          title.isEmpty ? key : title,
        ),
      };
    } on Object {
      _asked.remove(id);
    }
  }
}

final TrayNames trayNames = TrayNames();
