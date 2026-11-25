/// The pointer families the pick-up rule tells apart.
enum DockPointerKind {
  /// A mouse or a trackpad: a cursor steered onto the icon, so travelling with
  /// the button down is already a choice.
  precise,

  /// A finger or a pen. It crosses the dock on its way elsewhere, so travel
  /// alone says nothing and the icon has to be held first.
  touch,
}

/// How a press on an icon has gone so far.
enum DockPress {
  /// Down, and nothing decided yet.
  down,

  /// A finger or pen that travelled before it had rested: a swipe across the
  /// dock. It never picks the icon up, however long it stays afterwards.
  swipe,

  /// A finger or pen that rested for the long-press time. The icon has lifted
  /// off the row and waits: moving drags it, letting go opens its menu.
  lifted,

  /// The icon follows the pointer.
  dragging,
}

/// What letting go of a press does on top of what a tap already does.
enum DockPressEnd {
  /// Nothing: a click, or a swipe that never held the icon.
  none,

  /// The hold was a long press: the icon goes back and its menu opens.
  menu,

  /// The icon is dropped where the pointer left it.
  drop,
}

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
  /// How far a finger or pen may wander and still count as resting on the
  /// icon. It is the distance a drag covers along the dock before it changes
  /// the order, so a wobble neither breaks a hold nor moves a slot.
  static const double restSlop = 6.0;

  /// Whether a pointer [distance] from where it went down has left its
  /// resting spot.
  static bool leftRest(double distance) =>
      distance.isFinite && distance >= restSlop;

  /// The press after its pointer travelled.
  ///
  /// A mouse picks the icon up by travelling, as it always has. A finger or
  /// pen that travels before it has rested is swiping across the dock and
  /// stays a swipe; once the icon has lifted, the same travel drags it.
  static DockPress pressTravelled(DockPress press, DockPointerKind kind) =>
      switch (press) {
        DockPress.down =>
          kind == DockPointerKind.precise
              ? DockPress.dragging
              : DockPress.swipe,
        DockPress.lifted => DockPress.dragging,
        DockPress.swipe || DockPress.dragging => press,
      };

  /// The press after its pointer stayed down for the long-press time.
  ///
  /// Only a finger or pen that has not moved lifts the icon. A mouse has its
  /// secondary button for the menu and travel for the drag, so resting on the
  /// icon changes nothing for it.
  static DockPress pressRested(DockPress press, DockPointerKind kind) =>
      press == DockPress.down && kind == DockPointerKind.touch
      ? DockPress.lifted
      : press;

  /// What letting go does. A lifted icon that never moved was a long press;
  /// one that moved is dropped where it is.
  static DockPressEnd pressReleased(DockPress press) => switch (press) {
    DockPress.lifted => DockPressEnd.menu,
    DockPress.dragging => DockPressEnd.drop,
    DockPress.down || DockPress.swipe => DockPressEnd.none,
  };

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
