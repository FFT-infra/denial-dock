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
}
