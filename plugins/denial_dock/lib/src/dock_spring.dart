import 'dart:math' as math;

/// A damped spring's answer to a step from zero to one, in closed form.
///
/// The stack's rows are staggered on one clock, so each row needs the spring's
/// value at its own time rather than a simulation of its own. Tuned the way
/// the kit writes a spring: stiffness and damping ratio, unit mass.
///
/// No Flutter import, so it runs as an ordinary Dart test.
class DockSpring {
  DockSpring({
    required this.stiffness,
    required this.dampingRatio,
    this.tolerance = 0.002,
  }) : seconds = _settle(stiffness, dampingRatio, tolerance);

  final double stiffness;
  final double dampingRatio;

  /// How close to one counts as arrived.
  final double tolerance;

  /// The time after which the spring stays within [tolerance] of one.
  final double seconds;

  /// The spring's value [t] seconds after the step: zero before it starts,
  /// exactly one once it has settled, and free to pass one in between.
  double at(double t) {
    if (!(t > 0)) return 0;
    if (t >= seconds) return 1;
    return _response(t, stiffness, dampingRatio);
  }

  static double _response(double t, double stiffness, double ratio) {
    final omega = math.sqrt(stiffness);
    if (ratio < 1) {
      final damped = omega * math.sqrt(1 - ratio * ratio);
      return 1 -
          math.exp(-ratio * omega * t) *
              (math.cos(damped * t) +
                  ratio * omega / damped * math.sin(damped * t));
    }
    if (ratio == 1) return 1 - math.exp(-omega * t) * (1 + omega * t);
    final root = math.sqrt(ratio * ratio - 1);
    final slow = -omega * (ratio - root);
    final fast = -omega * (ratio + root);
    return 1 -
        (fast * math.exp(slow * t) - slow * math.exp(fast * t)) / (fast - slow);
  }

  /// An underdamped spring is bounded by its envelope, which has a closed
  /// form; the others approach from below and are walked until they arrive.
  static double _settle(double stiffness, double ratio, double tolerance) {
    final omega = math.sqrt(stiffness);
    if (ratio < 1) {
      return math.log(1 / (tolerance * math.sqrt(1 - ratio * ratio))) /
          (ratio * omega);
    }
    const step = 1 / 240;
    var t = step;
    while (t < 3 && 1 - _response(t, stiffness, ratio) > tolerance) {
      t += step;
    }
    return t;
  }
}
