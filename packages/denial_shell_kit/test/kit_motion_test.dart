import 'dart:math' as math;

import 'package:denial_shell_kit/kit_motion_pace.dart';

void _expect(bool ok, String what) {
  if (!ok) throw StateError(what);
}

void main() {
  // At normal speed every nominal value comes out exactly as written, so a
  // bar that has not touched the setting draws what it drew before.
  const nominal = Duration(milliseconds: 140);
  const normal = KitMotionPace(speed: 1, reduced: false);
  _expect(normal.duration(nominal) == nominal, 'speed 1 keeps a duration');
  _expect(normal.scaled(nominal) == nominal, 'speed 1 keeps a loop');
  _expect(normal.springStep(1 / 120) == 1 / 120, 'speed 1 keeps a frame');

  // The speed divides the time axis: 2 is twice as fast, 0.5 twice as slow.
  _expect(
    const KitMotionPace(speed: 2, reduced: false).duration(nominal) ==
        const Duration(milliseconds: 70),
    'speed 2 halves a duration',
  );
  _expect(
    const KitMotionPace(speed: 0.5, reduced: false).duration(nominal) ==
        const Duration(milliseconds: 280),
    'speed 0.5 doubles a duration',
  );
  // The setting's steps are not all whole numbers of milliseconds.
  _expect(
    const KitMotionPace(speed: 0.75, reduced: false).duration(nominal) ==
        const Duration(microseconds: 186667),
    'speed 0.75 rounds to the microsecond',
  );

  // Reduced motion zeroes a transition. A loop and a spring keep moving:
  // their reduced form is a still frame or a snap taken by the caller, and a
  // zero-length repeat would spin.
  const reduced = KitMotionPace(speed: 1.5, reduced: true);
  _expect(reduced.duration(nominal) == Duration.zero, 'reduced zeroes');
  _expect(
    reduced.scaled(const Duration(milliseconds: 300)) ==
        const Duration(milliseconds: 200),
    'reduced still scales a loop',
  );

  // A speed read from a file: missing, malformed and out-of-range values are
  // safe, and everything lands on a step the setting can show.
  _expect(KitMotionPace.clampSpeed(null) == 1, 'a missing speed is normal');
  _expect(KitMotionPace.clampSpeed('fast') == 1, 'a string is normal speed');
  _expect(KitMotionPace.clampSpeed(double.nan) == 1, 'NaN is normal speed');
  _expect(KitMotionPace.clampSpeed(99) == 2, 'a high speed is capped');
  _expect(KitMotionPace.clampSpeed(0.01) == 0.5, 'a low speed is floored');
  _expect(KitMotionPace.clampSpeed(1.1) == 1, 'a near value snaps down');
  _expect(KitMotionPace.clampSpeed(1.3) == 1.5, 'a near value snaps up');
  _expect(KitMotionPace.clampSpeed(0.65) == 0.75, 'the nearest step wins');

  // A spring at speed s is the same spring on a clock s times faster: every
  // state at speed 2 after one step equals the state at speed 1 after two
  // steps, so the damping ratio and the overshoot are untouched.
  final slow = SpringMotion(0, stiffness: 300, dampingRatio: 0.7, target: 1);
  final fast = SpringMotion(0, stiffness: 300, dampingRatio: 0.7, target: 1);
  const frame = 1 / 480;
  final fastFrame = const KitMotionPace(
    speed: 2,
    reduced: false,
  ).springStep(frame);
  var peak = 0.0;
  for (var i = 0; i < 300; i++) {
    fast.step(fastFrame);
    slow.step(frame);
    slow.step(frame);
    peak = math.max(peak, slow.value);
    _expect(
      (fast.value - slow.value).abs() < 1e-12 &&
          (fast.velocity - slow.velocity).abs() < 1e-9,
      'step $i: speed 2 is the same spring, twice as fast',
    );
  }
  _expect(peak > 1, 'the spring is free to overshoot');

  // The same property written as stiffness: k · speed² moves the natural
  // frequency by the speed and leaves the damping ratio alone.
  const stiffness = 300.0;
  const ratio = 0.7;
  final faster = const KitMotionPace(
    speed: 2,
    reduced: false,
  ).springStiffness(stiffness);
  _expect(faster == stiffness * 4, 'stiffness follows the speed squared');
  final damping = 2 * ratio * math.sqrt(faster);
  final fasterRatio = damping / (2 * math.sqrt(faster));
  _expect((fasterRatio - ratio).abs() < 1e-12, 'the damping ratio is kept');
}
