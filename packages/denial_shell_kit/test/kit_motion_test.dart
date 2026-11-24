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

  // A spring at speed s is the same spring on a clock s times faster. Run it
  // at every offered speed on a 120 Hz frame clock and compare it with the
  // unpaced spring read at s times the elapsed time: the whole trajectory
  // matches, so the overshoot is the same and only the time to reach it
  // changes, by 1/speed.
  const frame = 1 / 120;
  const substep = 1 / 480;
  SpringMotion spring() =>
      SpringMotion(0, stiffness: 300, dampingRatio: 0.7, target: 1);
  int framesToTarget(double speed) {
    final pace = KitMotionPace(speed: speed, reduced: false);
    final paced = spring();
    var frames = 0;
    while (paced.value < 1) {
      paced.step(pace.springStep(frame));
      frames++;
    }
    return frames;
  }

  final normalFrames = framesToTarget(1);
  for (final speed in KitMotionPace.speeds) {
    final pace = KitMotionPace(speed: speed, reduced: false);
    final paced = spring();
    final plain = spring();
    // Each paced frame covers this many of the plain spring's sub-steps.
    final perFrame = (speed * frame / substep).round();
    var pacedPeak = 0.0;
    var plainPeak = 0.0;
    for (var i = 0; i < 480; i++) {
      paced.step(pace.springStep(frame));
      for (var k = 0; k < perFrame; k++) {
        plain.step(substep);
        plainPeak = math.max(plainPeak, plain.value);
      }
      pacedPeak = math.max(pacedPeak, paced.value);
      _expect(
        (paced.value - plain.value).abs() < 1e-9 &&
            (paced.velocity - plain.velocity).abs() < 1e-6,
        'speed $speed, frame $i: the same spring on a faster clock',
      );
    }
    _expect(plainPeak > 1.01, 'the spring overshoots');
    // The paced spring is only seen once a frame, so its highest frame sits a
    // little under the true peak.
    _expect(
      pacedPeak <= plainPeak && plainPeak - pacedPeak < 1e-3,
      'speed $speed keeps the overshoot',
    );
    _expect(
      (framesToTarget(speed) - normalFrames / speed).abs() <= 1,
      'speed $speed reaches the target in 1/speed the time',
    );
  }
}
