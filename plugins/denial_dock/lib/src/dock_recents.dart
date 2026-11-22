/// The non-pinned section of the dock: applications that are running, plus a
/// few closed ones the launcher still remembers.
///
/// macOS keeps this section's order fixed. An unpinned app joins at the end
/// when it is launched and keeps that slot after it quits, so opening or
/// closing one app never moves its neighbours — which is why the divider
/// section reads as a row rather than as a queue. The section is also what
/// makes a quit app reopenable from the dock without pinning it.
abstract final class DockRecents {
  /// How many ids the section remembers, so an app that falls out of view
  /// keeps its slot when it comes back instead of appending a second time.
  static const int remembered = 24;

  /// [order] extended with ids it does not already hold, in [incoming] order.
  /// Existing positions never change; [trimmed] keeps the result bounded.
  static List<String> extended(List<String> order, Iterable<String> incoming) {
    final next = [...order];
    final seen = next.toSet();
    for (final id in incoming) {
      if (!seen.add(id)) continue;
      next.add(id);
    }
    return next;
  }

  /// [order] cut back to [limit] slots by dropping the oldest ids the row does
  /// not paint.
  ///
  /// Dropping only unpainted ids is what keeps the cap invisible: the painted
  /// ones are a prefix (running apps anywhere, then the first [count] closed
  /// ones), so removing the idle tail never moves a visible slot. Without this
  /// an install that has launched [limit] applications once would stop
  /// recording new ones.
  static List<String> trimmed({
    required List<String> order,
    required Set<String> running,
    required int count,
    Set<String> dismissed = const {},
    int limit = remembered,
  }) {
    if (order.length <= limit) return order;
    final painted = visible(
      order: order,
      running: running,
      count: count,
      dismissed: dismissed,
    ).toSet();
    var excess = order.length - limit;
    final kept = <String>[];
    for (final id in order) {
      if (excess > 0 && !painted.contains(id)) {
        excess--;
        continue;
      }
      kept.add(id);
    }
    return kept;
  }

  /// The ids the section paints, in slot order: every running application
  /// wherever it sits, plus the first [count] closed ones.
  ///
  /// A dismissed id is skipped while it is closed; once the app runs again the
  /// row is the running entry and comes back, because the dock is the only way
  /// back to its windows.
  static List<String> visible({
    required List<String> order,
    required Set<String> running,
    required int count,
    Set<String> dismissed = const {},
  }) {
    final shown = <String>[];
    var closed = 0;
    for (final id in order) {
      if (running.contains(id)) {
        shown.add(id);
        continue;
      }
      if (dismissed.contains(id)) continue;
      if (closed >= count) continue;
      closed++;
      shown.add(id);
    }
    return shown;
  }
}
