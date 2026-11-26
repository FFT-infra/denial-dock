/// The arithmetic behind the island's outline. No Flutter import, so it runs
/// as an ordinary Dart test.
library;

import 'dart:math' as math;

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

/// A share eased at both ends, so something that follows a spring's travel
/// neither starts nor stops abruptly.
double islandEase(double share) {
  final t = share.clamp(0.0, 1.0).toDouble();
  return t * t * (3 - 2 * t);
}

/// How much of the pill's face shows while the cross-over is at [content]
/// (0 the pill, 1 the card) and the outline is [open]. The face is gone
/// before the card arrives, and comes back only into an outline that has
/// nearly closed around it.
double islandFaceShare(double content, double open) =>
    (1 - kitPhase(content, 0, 0.45)) * (1 - islandEase(kitPhase(open, 0.1, 0.5)));

/// How much of the card shows. It needs the cross-over to be past the face
/// and the outline to be [open] far enough to hold it: a card laid out at
/// its full size must not show through an outline that is still a pill.
double islandCardShare(double content, double open) =>
    kitPhase(content, 0.4, 1) * islandEase(kitPhase(open, 0.2, 0.65));

/// Whether a closing outline still waits for its card to leave. The card
/// goes first; the outline follows once most of it is gone.
bool islandHoldsOutline(double content) => content > 0.55;

/// The stiffness of a critically damped spring that covers its travel in
/// about [seconds] on a clock running at [speed]: the preparation under a
/// held press arrives as the press is long enough.
double islandChargeStiffness(double seconds, double speed) {
  final time = seconds <= 0.05 ? 0.05 : seconds;
  final pace = speed <= 0 ? 1.0 : speed;
  final omega = 6 / (time * pace);
  return omega * omega;
}

/// A spring's answer to a step, as a curve over 0..1: it leaves 0 at rest
/// and is home at 1. Below a [damping] of 1 it passes its target on the way
/// and comes back; from 1 up it only approaches. A timed transition shaped
/// by this moves like the springs beside it.
double islandSpringCurve(double t, double damping) {
  if (t <= 0) return 0;
  if (t >= 1) return 1;
  double at(double time) {
    if (damping >= 1) {
      const omega = 9.0;
      return 1 - (1 + omega * time) * math.exp(-omega * time);
    }
    final zeta = damping < 0.2 ? 0.2 : damping;
    final omega = 7.5 / zeta;
    final ringing = omega * math.sqrt(1 - zeta * zeta);
    return 1 -
        math.exp(-zeta * omega * time) *
            (math.cos(ringing * time) +
                zeta * omega / ringing * math.sin(ringing * time));
  }

  // What is left of the travel at the end is spread over the whole of it,
  // so the curve lands exactly.
  return at(t) + (1 - at(1)) * t;
}

/// How much brisker than an ordinary panel the island moves in a look
/// whose panels open on a spring of [panelStiffness]. 620 is a panel that
/// settles at an ordinary pace.
double islandPace(double panelStiffness) =>
    (panelStiffness / 620).clamp(0.6, 2.4).toDouble();

/// The damping ratio the island may use where a design asks for [ratio]:
/// only a [liquid] look may pass a target, every other settles dead-beat.
double islandDamping(double ratio, {required bool liquid}) =>
    liquid || ratio >= 1 ? ratio : 1;
