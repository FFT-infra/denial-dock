/// The non-pinned section of the dock: applications that are running, plus a
/// few closed ones the launcher still remembers.
///
/// The order is the section itself, oldest first. An app joins when it starts
/// running and keeps its slot after it quits, so closing never moves an icon
/// and never pulls an older one back in; only a launch over the cap pushes the
/// oldest closed slot out. macOS reads the same way: quitting leaves the icon
/// in place and only the running dot goes away.
abstract final class DockRecents {
  /// Stored members for the next build: [order], then every running app, then
  /// whatever [recent] ids still fit, capped at [count] from the oldest closed
  /// end. A running app is never dropped — the dock is the only handle on its
  /// windows — so the section can sit over [count] while that many apps are
  /// open.
  ///
  /// [removed] only keeps the launcher's recents from refilling a slot with an
  /// app the user dragged out; it never hides a member, so an app that is
  /// there stays there after it quits.
  static List<String> members({
    required List<String> order,
    required Set<String> running,
    required Iterable<String> recent,
    required int count,
    Set<String> removed = const {},
  }) {
    final next = [...order];
    final seen = next.toSet();
    for (final id in running) {
      if (seen.add(id)) next.add(id);
    }
    for (final id in recent) {
      if (next.length >= count) break;
      if (removed.contains(id)) continue;
      if (seen.add(id)) next.add(id);
    }
    if (next.length <= count) return next;
    final kept = <String>[];
    var excess = next.length - count;
    for (final id in next) {
      if (excess > 0 && !running.contains(id)) {
        excess--;
        continue;
      }
      kept.add(id);
    }
    return kept;
  }
}
