import 'dock_settings.dart';

enum DockClickKind { activate, minimize, previews, nothing }

/// What a click on a running application should do, decided from the windows
/// the dock already knows about. Kept free of Flutter so the rule can be tested
/// directly.
abstract final class DockClick {
  /// Window indices in the order a click should visit them: restored windows
  /// before minimized ones, each group in stable list order.
  ///
  /// The shell exposes no workspace per window, so Omarchy's third tier
  /// (windows on other workspaces last) cannot be expressed here.
  static List<int> visitOrder(int count, Iterable<bool> minimized) {
    final flags = minimized.toList();
    final restored = <int>[];
    final hidden = <int>[];
    for (var index = 0; index < count; index++) {
      final isMinimized = index < flags.length && flags[index];
      (isMinimized ? hidden : restored).add(index);
    }
    return [...restored, ...hidden];
  }

  /// What a click on a running application does. `index` is the window to
  /// bring forward or to minimize, and -1 where the outcome names no window.
  static ({DockClickKind kind, int index}) resolve({
    required DockClickAction action,
    required int count,
    required int activeIndex,
    Iterable<bool> minimized = const [],
  }) {
    if (count <= 0) return (kind: DockClickKind.nothing, index: -1);
    if (action == DockClickAction.previews && count > 1) {
      return (kind: DockClickKind.previews, index: -1);
    }
    final next = nextIndex(
      action: action == DockClickAction.cycle
          ? DockClickAction.cycle
          : DockClickAction.minimize,
      count: count,
      activeIndex: activeIndex,
      minimized: minimized,
    );
    if (next != null) return (kind: DockClickKind.activate, index: next);
    if (action == DockClickAction.raise ||
        activeIndex < 0 ||
        activeIndex >= count) {
      return (kind: DockClickKind.nothing, index: -1);
    }
    return (kind: DockClickKind.minimize, index: activeIndex);
  }

  /// Index of the window to bring forward, or null when the click should
  /// minimize instead.
  ///
  /// [activeIndex] is the position of the app's currently front-most window in
  /// [windowIds], or -1 when the application is not in front. Cycling advances
  /// in stable list order: sorting by recency here would oscillate between the
  /// top two windows, because every activation swaps their ranks.
  static int? nextIndex({
    required DockClickAction action,
    required int count,
    required int activeIndex,
    Iterable<bool> minimized = const [],
  }) {
    if (count <= 0) return null;
    final order = visitOrder(count, minimized);
    final rank = order.indexOf(activeIndex);
    if (count == 1) {
      // A single window only minimizes when it is already in front; otherwise
      // the click raises it.
      return rank == 0 && action == DockClickAction.minimize ? null : 0;
    }
    if (rank < 0) {
      // The application is not in front: bring its first restored window up.
      return order.first;
    }
    if (action == DockClickAction.minimize) return null;
    return order[(rank + 1) % order.length];
  }

  /// Convenience wrapper over window records that expose `active`.
  static int activeIndex(Iterable<bool> activeFlags) {
    var index = 0;
    for (final active in activeFlags) {
      if (active) return index;
      index++;
    }
    return -1;
  }

  /// The window a wheel turn over an application should raise.
  ///
  /// Up walks backwards through the stable window list and down walks forwards,
  /// so a full turn of the wheel visits every window once. An application that
  /// is not in front has no meaningful direction: either way brings its
  /// front-most window up.
  static int? scrollIndex({
    required int count,
    required int activeIndex,
    required bool down,
  }) {
    if (count <= 0) return null;
    if (activeIndex < 0 || activeIndex >= count) return 0;
    if (count == 1) return 0;
    return down ? (activeIndex + 1) % count : (activeIndex - 1 + count) % count;
  }
}
