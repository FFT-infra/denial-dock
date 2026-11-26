import 'package:denial_shell_kit/kit_style.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dock_look.dart';
import 'dock_metrics.dart';
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

  Future<void> setMagnificationAmount(double amount) =>
      _update((current) => current.copyWith(magnificationAmount: amount));

  Future<void> setPosition(DockPosition position) =>
      _update((current) => current.copyWith(position: position));

  Future<void> setIconMode(DockIconMode mode) =>
      _update((current) => current.copyWith(iconMode: mode));

  Future<void> setAppearance(DockAppearance appearance) =>
      _update((current) => current.copyWith(appearance: appearance));

  Future<void> setIconOpacity(double opacity) =>
      _update((current) => current.copyWith(iconOpacity: opacity));

  Future<void> setTintColor(String? color) => _update(
    (current) => color == null
        ? current.copyWith(clearTint: true)
        : current.copyWith(tintColor: normalizeTintColor(color)),
  );

  Future<void> setRevealIndicator({required bool show}) =>
      _update((current) => current.copyWith(revealIndicator: show));

  Future<void> setLaunchFeedback(DockLaunchFeedback feedback) =>
      _update((current) => current.copyWith(launchFeedback: feedback));

  Future<void> setIndicatorStyle(DockIndicatorStyle style) =>
      _update((current) => current.copyWith(indicatorStyle: style));

  /// Puts values a look brings back on the look's own; [keys] are the
  /// names [DockMetrics] knows them under.
  Future<void> followLook(List<String> keys) => _update((current) {
    var next = current;
    var look = current.look;
    for (final key in keys) {
      next = next.following(key);
      look = DockLook.withOverride(look, key, null);
    }
    return next.copyWith(look: look);
  });

  /// What the pointer does to an icon: grow it, light it up, or neither.
  Future<void> setHoverFeedback({
    required bool magnify,
    required bool highlight,
  }) => _update(
    (current) => current.copyWith(
      magnification: magnify,
      look: DockLook.withOverride(
        current.look,
        DockMetrics.highlightKey,
        highlight,
      ),
    ),
  );

  Future<void> setPreviewStyle(DockPreviewStyle style) =>
      _update((current) => current.copyWith(previewStyle: style));

  Future<void> setDimInactivePinned({required bool dim}) =>
      _update((current) => current.copyWith(dimInactivePinned: dim));

  /// Sets one value of the capsule's look, or puts it back on the preset
  /// when [value] is null. Structural bar keys (`shape`, `taskTitles`) apply
  /// across looks; cosmetic look overrides stay scoped to the active style.
  Future<void> setLook(String key, Object? value) => _update((current) {
    if (key == DockLook.shapeKey || key == DockMetrics.taskTitlesKey) {
      return current.copyWith(
        look: DockLook.withOverride(current.look, key, value),
      );
    }
    final styleId = kitStyle.value.id;
    final scoped = DockLook.withOverride(
      current.lookByStyle[styleId] ?? const <String, Object?>{},
      key,
      value,
    );
    final nextMap = <String, Map<String, Object?>>{...current.lookByStyle};
    if (scoped.isEmpty) {
      nextMap.remove(styleId);
    } else {
      nextMap[styleId] = scoped;
    }
    return current.copyWith(
      // Clearing a value also clears one an older version kept for every look.
      look: value == null
          ? DockLook.withOverride(current.look, key, null)
          : current.look,
      lookByStyle: Map.unmodifiable(nextMap),
    );
  });

  /// Puts the whole look back on the preset of the shell look in force.
  Future<void> resetLook() => _update((current) {
    final styleId = kitStyle.value.id;
    final nextMap = <String, Map<String, Object?>>{...current.lookByStyle}
      ..remove(styleId);
    return current.copyWith(
      look: const {},
      lookByStyle: Map.unmodifiable(nextMap),
      chosen: const {},
    );
  });

  Future<void> setPreviewDelayMs(int delay) =>
      _update((current) => current.copyWith(previewDelayMs: delay));

  Future<void> setPreviewHover(DockPreviewHover hover) =>
      _update((current) => current.copyWith(previewHover: hover));

  Future<void> setScrollReversed({required bool reversed}) =>
      _update((current) => current.copyWith(scrollReversed: reversed));

  Future<void> setScrollWraps({required bool wraps}) =>
      _update((current) => current.copyWith(scrollWraps: wraps));

  Future<void> setShowBadges({required bool show}) =>
      _update((current) => current.copyWith(showBadges: show));

  Future<void> setShowSuggestions({required bool show}) =>
      _update((current) => current.copyWith(showSuggestions: show));

  Future<void> setRecentCount(int count) =>
      _update((current) => current.copyWith(recentCount: count));

  /// Saves the unpinned section and the ids parked outside it. Skipped when
  /// nothing moved, so the dock can call it from a build without writing on
  /// every frame.
  Future<void> setRecentsOrder(List<String> order, List<String> parked) =>
      _update((current) {
        if (_sameOrder(current.recentsOrder, order) &&
            _sameOrder(current.parkedRecents, parked)) {
          return current;
        }
        return current.copyWith(
          recentsOrder: List.unmodifiable(order),
          parkedRecents: List.unmodifiable(parked),
        );
      });

  static bool _sameOrder(List<String> first, List<String> second) {
    if (first.length != second.length) return false;
    for (var i = 0; i < first.length; i++) {
      if (first[i] != second[i]) return false;
    }
    return true;
  }

  Future<void> setScrollAction(DockScrollAction action) =>
      _update((current) => current.copyWith(scrollAction: action));

  Future<void> setMiddleClickAction(DockMiddleClickAction action) =>
      _update((current) => current.copyWith(middleClickAction: action));

  Future<void> setHideScope(DockHideScope scope) =>
      _update((current) => current.copyWith(hideScope: scope));

  Future<void> setRevealDelayMs(int delay) =>
      _update((current) => current.copyWith(revealDelayMs: delay));

  Future<void> setHideDelayMs(int delay) =>
      _update((current) => current.copyWith(hideDelayMs: delay));

  Future<void> setShowProgress({required bool show}) =>
      _update((current) => current.copyWith(showProgress: show));

  Future<void> setShowAttention({required bool show}) =>
      _update((current) => current.copyWith(showAttention: show));

  Future<void> setShowDesktopActions({required bool show}) =>
      _update((current) => current.copyWith(showDesktopActions: show));

  Future<void> setShowAudioIndicator({required bool show}) =>
      _update((current) => current.copyWith(showAudioIndicator: show));

  Future<void> setLockItems({required bool locked}) =>
      _update((current) => current.copyWith(lockItems: locked));

  Future<void> setCurrentWorkspaceOnly({required bool only}) =>
      _update((current) => current.copyWith(currentWorkspaceOnly: only));

  Future<void> setPreviewMiddleClose({required bool close}) =>
      _update((current) => current.copyWith(previewMiddleClose: close));

  Future<void> setAvoidReservedEdge({required bool avoid}) =>
      _update((current) => current.copyWith(avoidReservedEdge: avoid));

  /// Lays a layout another plugin asked for, such as a shell preset, over
  /// the settings. See [DockSettings.withLayout].
  Future<void> applyLayout(Map<String, Object?> changes) =>
      _update((current) => current.withLayout(changes));

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

  Future<void> addFile(DockFile file) =>
      _update((current) => current.withFile(file));

  Future<void> removeFile(String path) =>
      _update((current) => current.withoutFile(path));

  Future<void> setFolderView(String path, DockStackMode view) =>
      _update((current) => current.withFolderStack(path, view: view));

  Future<void> setFolderStacked(String path, bool stacked) =>
      _update((current) => current.withFolderStack(path, stacked: stacked));

  Future<void> setFolderSort(String path, DockStackSortMode sort) =>
      _update((current) => current.withFolderStack(path, sort: sort));

  /// Saves a dragged order and switches the folder to it, since a custom order
  /// only means anything under the `manual` sort.
  Future<void> setFolderOrder(String path, List<String> order) => _update(
    (current) => current.withFolderStack(
      path,
      order: order,
      sort: DockStackSortMode.manual,
    ),
  );

  /// Drops an app from the unpinned section and keeps the launcher's recents
  /// from putting it back. It returns on its next launch, and quitting it
  /// afterwards leaves it in place.
  Future<void> removeRecent(String appId) {
    final key = appIdentity(appId);
    return _update(
      (current) => current.copyWith(
        recentsOrder: List.unmodifiable(
          current.recentsOrder.where((id) => appIdentity(id) != key),
        ),
        parkedRecents: List.unmodifiable(
          current.parkedRecents.where((id) => appIdentity(id) != key),
        ),
        dismissedSuggestions: current.dismissedSuggestions.contains(key)
            ? current.dismissedSuggestions
            : List.unmodifiable([...current.dismissedSuggestions, key]),
      ),
    );
  }

  Future<void> _updatePins(List<DockPin> Function(List<DockPin>) update) =>
      _update(
        (current) =>
            current.copyWith(pinned: List.unmodifiable(update(current.pinned))),
      );

  Future<void> _update(DockSettings Function(DockSettings) update) {
    final operation = _writes.then((_) async {
      if (!ref.mounted) return;
      // Until the file has been read there is nothing to update. Writing
      // defaults here would erase the stored settings.
      final current = state.value;
      if (current == null) return;
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
