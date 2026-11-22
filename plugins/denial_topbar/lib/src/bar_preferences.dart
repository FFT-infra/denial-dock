import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'bar_settings.dart';

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
