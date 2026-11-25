import 'dart:math' as math;

/// A spring as the kit tunes one: stiffness and damping ratio. A ratio of 1
/// is critically damped, so the value reaches its target without passing it.
typedef NcTuning = ({double stiffness, double dampingRatio});

/// The numbers behind the notification centre's motion and gestures, kept
/// free of Flutter so they run as an ordinary Dart test.
abstract final class NcMotion {
  // ── Springs ──────────────────────────────────────────────────────────────
  /// The column sliding in and out. One spring for both directions, so a
  /// close during the opening turns round from where the column is.
  static const NcTuning slide = (stiffness: 441, dampingRatio: 1);

  /// The cards below a cleared one rising into its place.
  static const NcTuning gap = (stiffness: 473, dampingRatio: 1);

  /// The same where the look is liquid: a little past, then home.
  static const NcTuning gapLiquid = (stiffness: 420, dampingRatio: 0.82);

  /// A stack fanning open and folding back.
  static const NcTuning unfold = (stiffness: 330, dampingRatio: 1);
  static const NcTuning unfoldLiquid = (stiffness: 300, dampingRatio: 0.8);

  /// A card let go short of clearing. Critically damped and started at rest,
  /// so it comes home without passing it.
  static const NcTuning rebound = (stiffness: 320, dampingRatio: 1);

  // ── Sideways drag ────────────────────────────────────────────────────────
  // Distances are positive toward the screen edge the column sits at, which
  // is the way a card leaves.

  /// How far a press may wander before the card starts to move.
  static const double swipeSlop = 5;

  /// The most a card gives when pulled away from the edge.
  static const double swipeInward = 16;

  /// Where the card sits for a drag of [raw] from the press. Past the slop
  /// it follows the finger one to one toward the edge, starting from zero so
  /// there is no jump; the other way it gives a little and stops.
  static double swipeFollow(double raw, {double slop = swipeSlop}) {
    if (raw > slop) return raw - slop;
    if (raw < -slop) {
      final pull = -raw - slop;
      return -swipeInward * (1 - math.exp(-pull / (swipeInward * 2.5)));
    }
    return 0;
  }

  /// The drag that puts the card at [offset]: the inverse of [swipeFollow]
  /// without a slop, for a finger that catches a card on its way home.
  static double swipeRaw(double offset) {
    if (offset >= 0) return offset;
    final share = (-offset / swipeInward).clamp(0.0, 0.999);
    return swipeInward * 2.5 * math.log(1 - share);
  }

  /// Whether letting go at [offset] with [velocity] clears the card: a flick
  /// toward the edge does, a card heading back does not, and otherwise it is
  /// where the card would coast to.
  static bool swipeClears({
    required double offset,
    required double velocity,
    required double width,
  }) {
    if (offset <= 0 || width <= 0) return false;
    if (velocity < -120) return false;
    if (velocity > 600) return true;
    return offset + velocity * 0.12 > width * 0.38;
  }

  /// How a released card leaves over the [remaining] distance: the time it
  /// takes, and the share of its average speed it starts at ([lead]). At the
  /// release velocity the card would take `remaining / velocity`; that is
  /// kept between [shortest] and [longest], and the lead makes up the
  /// difference so the first frame still moves at the finger's speed.
  static ({double ms, double lead}) swipeExit({
    required double remaining,
    required double velocity,
    double shortest = 90,
    double longest = 240,
  }) {
    if (remaining <= 0) return (ms: 0, lead: 1);
    final speed = math.max(velocity, 0.0);
    final natural = speed <= 0 ? longest : remaining / speed * 1000;
    final ms = natural.clamp(shortest, longest).toDouble();
    final lead = (speed * ms / 1000 / remaining).clamp(0.0, 1.5).toDouble();
    return (ms: ms, lead: lead);
  }

  /// Progress of an exit at [t] of its time. The slope at zero is [lead],
  /// and it never turns back for a lead up to 2.
  static double exitCurve(double lead, double t) =>
      lead * t + (1 - lead) * t * t;

  // ── A stack of one application's cards ───────────────────────────────────
  /// How many cards show behind the front one.
  static const int stackDepth = 2;

  /// What each card behind is narrower by on either side, and how far it
  /// shows below the one in front.
  static const double stackInset = 12;
  static const double stackPeek = 8;

  static int peeks(int members) =>
      math.max(0, math.min(stackDepth, members - 1));

  /// The room the folded stack needs under its front card at [t].
  static double peekRoom(int members, double t) =>
      peeks(members) * stackPeek * (1 - t.clamp(0.0, 1.0));

  /// The plate of the card at [index] of a stack, in that card's own
  /// coordinates, at expansion [t]: folded (0) it is the strip showing under
  /// the front card, open (1) it is the card's own [width] by [height]. A
  /// folded card's origin sits [lift] below the front card's lower edge,
  /// which is where its strip starts. [strength] scales the plate's fill, and
  /// cards deeper than the stack shows start from nothing.
  static ({
    double left,
    double top,
    double width,
    double height,
    double strength,
  })
  plate({
    required int index,
    required double t,
    required double width,
    required double height,
    double lift = 0,
  }) {
    if (index <= 0) {
      return (left: 0, top: 0, width: width, height: height, strength: 1);
    }
    final depth = math.min(index, stackDepth);
    final p = t.clamp(0.0, 1.0);
    final left = stackInset * depth * (1 - p);
    final folded = stackPeek * depth;
    final foldedStrength = index > stackDepth ? 0.0 : 1 - 0.25 * depth;
    return (
      left: left,
      top: -lift * (1 - p),
      width: math.max(0, width - 2 * left),
      height: folded + (height - folded) * p,
      strength: foldedStrength + (1 - foldedStrength) * p,
    );
  }

  /// A card behind keeps its text back until the stack is half open, so the
  /// plates separate before there is anything to read.
  static double reveal(double t) => ((t - 0.5) * 2).clamp(0.0, 1.0).toDouble();

  // ── Clear All ────────────────────────────────────────────────────────────
  /// When the row at [index] starts to go, in milliseconds after the first.
  /// Past [cap] rows the rest leave together, so a long list still clears
  /// in bounded time.
  static double clearDelay(int index, {double step = 45, int cap = 12}) =>
      math.max(0, math.min(index, cap)) * step;

  // ── Actions ──────────────────────────────────────────────────────────────
  /// How many of a card's actions fit side by side in [available], given
  /// each pill's width. When not all fit, room is kept for the button that
  /// opens the rest.
  static int actionsThatFit(
    List<double> widths,
    double available, {
    double gap = 6,
    double more = 28,
  }) {
    var all = 0.0;
    for (var i = 0; i < widths.length; i++) {
      all += widths[i] + (i == 0 ? 0 : gap);
    }
    if (all <= available) return widths.length;
    var used = more;
    var count = 0;
    for (final width in widths) {
      if (used + gap + width > available) break;
      used += gap + width;
      count++;
    }
    return count;
  }
}
