import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dock_settings.dart';

export 'dock_settings.dart';

/// Height of the plugin's surface. It covers the capsule, the magnification
/// headroom, the launch bounce and the name label, and stays clear of the top
/// bar even at the largest icon size.
const double dockSurfaceHeight = 180.0;

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
      _updatePins((pins) {
        final key = normalizeAppId(pin.appId);
        final without = pins
            .where((existing) => normalizeAppId(existing.appId) != key)
            .toList();
        return pinned ? [...without, pin] : without;
      });

  /// Moves a pinned entry to [to] using remove-then-insert order, matching the
  /// dock's drag preview.
  Future<void> movePin(int from, int to) => _updatePins((pins) {
    if (from < 0 || from >= pins.length) return pins;
    final copy = [...pins];
    final item = copy.removeAt(from);
    copy.insert(to.clamp(0, copy.length), item);
    return copy;
  });

  /// Pins a running application at [to], so dropping it among the pins keeps
  /// the drop position instead of appending it.
  Future<void> insertPin(DockPin pin, int to) => _updatePins((pins) {
    final key = normalizeAppId(pin.appId);
    final copy = pins
        .where((existing) => normalizeAppId(existing.appId) != key)
        .toList();
    copy.insert(to.clamp(0, copy.length), pin);
    return copy;
  });

  Future<void> setVisibility(DockVisibilityMode visibility) =>
      _update((current) => current.copyWith(visibility: visibility));

  Future<void> setClickAction(DockClickAction action) =>
      _update((current) => current.copyWith(clickAction: action));

  Future<void> setIconSize(double size) =>
      _update((current) => current.copyWith(iconSize: size));

  Future<void> setMagnification({required bool magnification}) =>
      _update((current) => current.copyWith(magnification: magnification));

  Future<void> setLauncherSide(DockSide side) =>
      _update((current) => current.copyWith(launcherSide: side));

  Future<void> setExtrasSide(DockSide side) =>
      _update((current) => current.copyWith(extrasSide: side));

  Future<void> setShowTrash({required bool show}) =>
      _update((current) => current.copyWith(showTrash: show));

  Future<void> addFolder(DockFolder folder) =>
      _update((current) => current.withFolder(folder));

  Future<void> removeFolder(String path) =>
      _update((current) => current.withoutFolder(path));

  Future<void> _updatePins(List<DockPin> Function(List<DockPin>) update) =>
      _update(
        (current) =>
            current.copyWith(pinned: List.unmodifiable(update(current.pinned))),
      );

  Future<void> _update(DockSettings Function(DockSettings) update) {
    final operation = _writes.then((_) async {
      if (!ref.mounted) return;
      final current = state.value ?? DockSettings.defaults;
      final next = update(current);
      await _store.write(next);
      if (!ref.mounted) return;
      state = AsyncData(next);
    });
    // A failed write is reported to the caller but must not poison later saves.
    _writes = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }
}
