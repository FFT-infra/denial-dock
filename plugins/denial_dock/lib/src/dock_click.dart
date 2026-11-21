import 'dock_settings.dart';

/// What a click on a running application should do, decided from the windows
/// the dock already knows about. Kept free of Flutter so the rule can be tested
/// directly.
abstract final class DockClick {
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
  }) {
    if (count <= 0) return null;
    if (count == 1) {
      // A single window only minimizes when it is already in front; otherwise
      // the click raises it.
      return activeIndex == 0 && action == DockClickAction.minimize ? null : 0;
    }
    if (activeIndex < 0 || activeIndex >= count) {
      // The application is not in front: bring its front-most window up.
      return 0;
    }
    if (action == DockClickAction.minimize) return null;
    return (activeIndex + 1) % count;
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
}
