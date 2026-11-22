/// What letting go of a dragged icon outside the dock does.
enum DockRemoval {
  /// A running application stays where it is; the dock is the only way back to
  /// its windows, so dragging it out is a no-op.
  none,

  /// A pinned application loses its pin.
  unpin,

  /// A suggestion for an application that is not running leaves the dock.
  dismissRecent,
}

/// Pure helpers for pinned-icon drag reorder, mirroring NextKDE's remove-then-
/// insert model and the nearest-slot rule used by the dock preview.
abstract final class DockDrag {
  static List<T> moved<T>(List<T> list, int from, int to) {
    final copy = [...list];
    if (from < 0 || from >= copy.length) return copy;
    final item = copy.removeAt(from);
    copy.insert(to.clamp(0, copy.length), item);
    return copy;
  }

  /// Inserts a running application into the pinned order for the drag preview.
  static List<T> inserted<T>(List<T> list, T item, int index) {
    final copy = [...list];
    copy.insert(index.clamp(0, copy.length), item);
    return copy;
  }

  /// Index of the centre closest to [pointerX], never outside the list.
  static int insertionIndex({
    required List<double> centers,
    required double pointerX,
    required int fallback,
  }) {
    if (centers.isEmpty) return fallback;
    var best = fallback.clamp(0, centers.length - 1);
    var bestDistance = double.infinity;
    for (var i = 0; i < centers.length; i++) {
      final distance = (pointerX - centers[i]).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        best = i;
      }
    }
    return best;
  }

  /// Releasing a dragged icon outside the dock.
  ///
  /// A pin is the user's own choice, so dragging it out drops the pin even
  /// while the application runs. A suggestion is only a shortcut for an
  /// application the launcher remembers, so it leaves while that application
  /// is closed; once it is open the row is the running entry, and removing it
  /// would hide a live window. A running entry that is neither keeps its
  /// place, because the dock is the only way back to its windows.
  static DockRemoval removalFor({
    required bool pinned,
    required bool suggestion,
    required bool running,
    required bool outside,
  }) {
    if (!outside) return DockRemoval.none;
    if (pinned) return DockRemoval.unpin;
    if (suggestion && !running) return DockRemoval.dismissRecent;
    return DockRemoval.none;
  }
}
