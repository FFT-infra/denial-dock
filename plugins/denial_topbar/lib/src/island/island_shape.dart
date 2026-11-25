/// The arithmetic behind the island's outline. No Flutter import, so it runs
/// as an ordinary Dart test.
library;

import 'package:denial_shell_kit/kit_control_math.dart';

/// How thick the neck between the pill and its bubble still is at [split],
/// as a share of the bubble's radius. Up to nearly half way the two are one
/// body; from there the neck thins, and it lets go exactly as the bubble
/// reaches its place, so a bubble that overshoots is already a free drop.
double islandNeck(double split) {
  if (split <= 0) return 1;
  final t = kitPhase(split, 0.45, 1);
  return 1 - t * t * (3 - 2 * t);
}

/// Where the bubble's left edge is, measured from the pill's right edge. At
/// 0 the bubble sits inside the pill's end; at 1 it stands [gap] clear.
double islandBubbleOffset(double split, double size, double gap) =>
    split * (size + gap) - size;

/// How far the outline has grown from the pill to its card, 0..1, from the
/// height it has now. Content that travels with the outline follows this.
double islandOpenShare(double height, double rest, double card) {
  if (card <= rest) return 0;
  return ((height - rest) / (card - rest)).clamp(0.0, 1.0).toDouble();
}

/// A dragged share past either end: it gives a little and resists.
double islandRubber(double share) {
  if (share > 1) return 1 + (share - 1) / (1 + (share - 1) * 6) * 0.5;
  if (share < 0) return share / (1 - share * 6) * 0.5;
  return share;
}

/// Whether a released horizontal drag turns the page, and which way: -1 for
/// the previous, 1 for the next, 0 for neither. A drag counts by its travel
/// or by its speed, so a slow deliberate swipe works as well as a flick.
int islandSwipeStep(double travel, double velocity) {
  if (velocity.abs() >= 120) return velocity < 0 ? 1 : -1;
  if (travel.abs() >= 36) return travel < 0 ? 1 : -1;
  return 0;
}
