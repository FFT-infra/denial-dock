import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'top_bar_settings.dart';

export 'top_bar_settings.dart';

final topBarSettingsProvider =
    AsyncNotifierProvider<TopBarSettingsController, TopBarSettings>(
      TopBarSettingsController.new,
    );

class TopBarSettingsController extends AsyncNotifier<TopBarSettings> {
  late TopBarPreferencesStore _store;
  Future<void> _writes = Future.value();

  @override
  Future<TopBarSettings> build() {
    _store = TopBarPreferencesStore(TopBarPreferencesStore.defaultFile());
    return _store.read();
  }

  Future<void> save(TopBarSettings Function(TopBarSettings) change) {
    final operation = _writes.then((_) async {
      if (!ref.mounted) return;
      final current = state.value;
      if (current == null) return;
      final next = change(current);
      await _store.write(next);
      if (!ref.mounted) return;
      state = AsyncData(next);
    });
    _writes = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }
}
