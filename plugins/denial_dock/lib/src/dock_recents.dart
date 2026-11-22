/// The non-pinned section of the dock: applications that are running, plus a
/// few closed ones the launcher still remembers.
///
/// The order is the section itself, oldest first. An app joins when it starts
/// running and keeps its slot after it quits, so closing never moves an icon
/// and never pulls an older one back in; only a launch over the cap pushes the
/// oldest closed slot out. macOS reads the same way: quitting leaves the icon
/// in place and only the running dot goes away.
abstract final class DockRecents {
  /// Evicted ids kept outside the section, so a smaller count or a hidden
  /// section can be undone instead of throwing the history away.
  static const int parkedLimit = 24;

  /// The section, the ids parked outside it, and the ids to paint.
  ///
  /// [order] and [parked] are both oldest first. A count of zero means the
  /// section is off: the members stay stored and only the running apps are
  /// painted, so turning it back on restores the row instead of starting it
  /// from whatever happens to be open.
  ///
  /// A running app is never evicted — the dock is the only handle on its
  /// windows — so the section can sit over [count] while that many apps are
  /// open. [removed] only keeps a dragged-out app from being refilled; it never
  /// hides a member, so an app that is there stays there after it quits.
  static ({List<String> members, List<String> parked, List<String> shown})
  resolve({
    required List<String> order,
    required List<String> parked,
    required Set<String> running,
    required Iterable<String> recent,
    required int count,
    Set<String> removed = const {},
  }) {
    final members = [...order];
    final seen = members.toSet();
    for (final id in running) {
      if (seen.add(id)) members.add(id);
    }
    // Evicted ids are older than every member, so the newest ones come back at
    // the front.
    final spare = count - members.length;
    if (spare > 0) {
      final restored = <String>[];
      for (final id in parked.reversed) {
        if (restored.length == spare) break;
        if (removed.contains(id) || !seen.add(id)) continue;
        restored.add(id);
      }
      members.insertAll(0, restored.reversed);
    }
    // The launcher's own recents are newer than the section, so they join at
    // the end.
    final fresh = <String>[];
    for (final id in recent.toList().reversed) {
      if (members.length + fresh.length >= count) break;
      if (removed.contains(id) || !seen.add(id)) continue;
      fresh.add(id);
    }
    members.addAll(fresh.reversed);

    final limit = count > 0 ? count : parkedLimit;
    var excess = members.length - limit;
    final kept = <String>[];
    final evicted = <String>[];
    for (final id in members) {
      if (excess > 0 && !running.contains(id)) {
        excess--;
        evicted.add(id);
        continue;
      }
      kept.add(id);
    }
    final inside = kept.toSet();
    final next = <String>[];
    final nextSeen = <String>{};
    for (final id in [...parked, ...evicted].reversed) {
      if (inside.contains(id) || !nextSeen.add(id)) continue;
      next.add(id);
      if (next.length == parkedLimit) break;
    }
    return (
      members: kept,
      parked: next.reversed.toList(),
      shown: count > 0
          ? kept
          : [
              for (final id in kept)
                if (running.contains(id)) id,
            ],
    );
  }
}
