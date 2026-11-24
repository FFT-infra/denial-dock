import 'dart:math' as math;

/// How the shell's motion is paced: the user's speed multiplier and the
/// system's reduced-motion flag, in the one place that turns a nominal
/// duration or spring into the time actually drawn.
///
/// No Flutter import, so the arithmetic runs as an ordinary Dart test.
class KitMotionPace {
  const KitMotionPace({required this.speed, required this.reduced});

  /// The speeds the setting offers, slowest first. They are the five steps of
  /// the reference shell's duration scale, without its off step: turning
  /// motion off is what the system's reduced-motion flag already does.
  static const List<double> speeds = <double>[0.5, 0.75, 1, 1.5, 2];

  static const double minSpeed = 0.5;
  static const double maxSpeed = 2;

  /// A speed from a file or a control. A missing or malformed value is
  /// normal speed; anything else lands on the nearest offered step, so the
  /// setting always shows a selection.
  static double clampSpeed(Object? value) {
    final raw = value is num && value.isFinite ? value.toDouble() : 1.0;
    final bounded = raw.clamp(minSpeed, maxSpeed).toDouble();
    var nearest = speeds.first;
    for (final step in speeds) {
      if ((step - bounded).abs() < (nearest - bounded).abs()) nearest = step;
    }
    return nearest;
  }

  /// 2 runs everything twice as fast, 0.5 twice as slow.
  final double speed;

  /// The system asks for no travel.
  final bool reduced;

  /// A transition's duration at this pace: the time axis is divided by the
  /// speed, and reduced motion removes the travel entirely, as the bar's
  /// popups already did.
  Duration duration(Duration nominal) =>
      reduced ? Duration.zero : scaled(nominal);

  /// A duration with only the speed applied. For loops, whose reduced-motion
  /// form is a still frame rather than a zero-length repeat, and for springs,
  /// whose reduced-motion form is a snap taken by their caller.
  Duration scaled(Duration nominal) {
    if (speed == 1) return nominal;
    return Duration(microseconds: (nominal.inMicroseconds / speed).round());
  }

  /// The simulated time one frame advances a spring: the frame time times the
  /// speed. A spring's trajectory is a function of its own clock, so feeding
  /// it the scaled clock makes every part of the motion take 1/speed the
  /// time. In stiffness terms that is k · speed² while the damping ratio is
  /// unchanged, which is why the shape — the overshoot above all — stays the
  /// same at every speed.
  double springStep(double dt) => dt * speed;

  /// The stiffness a spring needs to complete in 1/speed the time at the same
  /// damping ratio: the damping term follows from the ratio, so scaling
  /// stiffness alone scales the clock and not the shape.
  double springStiffness(double stiffness) => stiffness * speed * speed;
}

/// The damped-spring integrator behind the kit's springs, without Flutter, so
/// its behaviour at different speeds can be tested as plain Dart.
///
/// After the recipe in Denial's `docs/LIQUID_MOTION.md`: a new target keeps
/// the velocity, so quick changes blend into one motion. Values are free to
/// overshoot.
class SpringMotion {
  SpringMotion(
    this.value, {
    required this.stiffness,
    required this.dampingRatio,
    double? target,
  }) : target = target ?? value;

  double value;
  double target;
  double velocity = 0;
  double stiffness;
  double dampingRatio;

  /// Sub-steps of at most 1/480 s keep a stiff spring stable at any refresh
  /// rate.
  void step(double dt) {
    final damping = 2 * dampingRatio * math.sqrt(stiffness);
    var left = dt;
    while (left > 0) {
      final h = math.min(left, 1 / 480);
      velocity += (-stiffness * (value - target) - damping * velocity) * h;
      value += velocity * h;
      left -= h;
    }
  }
}
