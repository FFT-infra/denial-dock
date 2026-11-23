/// Where the cards of a stacked folder icon sit, in fractions of the tile.
///
/// Plain records rather than Flutter geometry so the offsets stay testable as
/// an ordinary Dart program, and so the fan can open from exactly the same
/// places the icon drew its cards.
abstract final class DockPile {
  /// Cards in the icon, the newest in front.
  static const int count = 3;

  /// How far behind the front card each one sits. Together with the icon's
  /// inset this keeps a three-card pile inside the tile instead of spilling
  /// over the dock capsule's edge.
  static const double stepX = 0.070;
  static const double stepY = 0.060;
  static const double stepAngle = 0.10;
  static const double stepScale = 0.050;

  /// Inset of the front card from the tile's edge, as a fraction of its side.
  static const double inset = 0.140;

  /// Offset of card [index] (0 = front) from the tile centre.
  static ({double dx, double dy}) offset(int index) =>
      (dx: -stepX * index, dy: -stepY * index);

  /// Turn of card [index], in radians.
  static double angle(int index) => -stepAngle * index;

  /// Edge length of card [index] relative to the front card.
  static double scale(int index) => 1 - stepScale * index;

  /// Edge length of card [index] as a fraction of the tile, which is also the
  /// size the fan row of that file starts from.
  static double edge(int index) => (1 - 2 * inset) * scale(index);
}
