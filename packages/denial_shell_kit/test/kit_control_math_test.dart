import 'package:denial_shell_kit/kit_control_math.dart';
import 'package:denial_shell_kit/kit_motion_pace.dart';

void _expect(bool ok, String what) {
  if (!ok) throw StateError(what);
}

bool _near(double a, double b, [double eps = 1e-9]) => (a - b).abs() < eps;

void main() {
  // A slider's value is its knob's centre, so a press on the first half knob
  // is already zero and the track never asks for a value outside 0..1.
  _expect(sliderValueAt(0, 200, 20) == 0, 'the leading end is zero');
  _expect(sliderValueAt(10, 200, 20) == 0, 'half a knob in is still zero');
  _expect(_near(sliderValueAt(100, 200, 20), 0.5), 'the middle is a half');
  _expect(sliderValueAt(190, 200, 20) == 1, 'half a knob from the end is one');
  _expect(sliderValueAt(900, 200, 20) == 1, 'past the end is one, no band');
  _expect(sliderValueAt(-50, 200, 20) == 0, 'before the start is zero');
  _expect(sliderValueAt(5, 20, 20) == 0, 'a track with no run does not divide');
  for (final v in <double>[0, 0.25, 0.5, 1]) {
    _expect(
      _near(sliderValueAt(sliderCentreFor(v, 200, 20), 200, 20), v),
      'centre and value are inverses at $v',
    );
  }

  // Wheel and keys step and stop dead at the ends.
  _expect(_near(sliderNudge(0.5, sliderWheelStep), 0.55), 'a notch adds');
  _expect(sliderNudge(0.98, sliderWheelStep) == 1, 'a notch stops at one');
  _expect(sliderNudge(0.02, -sliderKeyStep) == 0, 'a key stops at zero');
  _expect(_near(sliderKeyStep * 16, 1), 'sixteen keys cross the track');

  // The wheel: up raises, down lowers, a full notch is one step and a
  // touchpad's trickle is a fraction of it.
  _expect(_near(sliderWheelDelta(0, -120), sliderWheelStep), 'wheel up raises');
  _expect(
    _near(sliderWheelDelta(0, 53), -sliderWheelStep),
    'wheel down lowers',
  );
  _expect(_near(sliderWheelDelta(60, 4), sliderWheelStep), 'right raises');
  _expect(sliderWheelDelta(0, 0) == 0, 'no scroll, no change');
  _expect(
    _near(sliderWheelDelta(0, -2), sliderWheelStep * 0.1),
    'a touchpad trickle is a tenth of a notch',
  );

  // A switch knob follows the finger across its travel and no further.
  _expect(_near(switchDragTo(-1, 10, 20), 0), 'half the travel is the middle');
  _expect(switchDragTo(-1, 50, 20) == 1, 'the knob stops at the end');
  _expect(switchDragTo(1, -50, 20) == -1, 'and at the start');
  _expect(switchDragTo(0.3, 5, 0) == 0.3, 'no travel, no move');

  // Let go slowly and the knob falls to its own half; a flick wins over
  // where it was.
  _expect(switchRelease(at: 0.2, velocity: 0), 'right half falls on');
  _expect(!switchRelease(at: -0.2, velocity: 50), 'left half falls off');
  _expect(switchRelease(at: -0.8, velocity: 600), 'a flick right turns on');
  _expect(!switchRelease(at: 0.8, velocity: -600), 'a flick left turns off');

  // Phases cut one progress into overlapping stretches and hold their ends,
  // so a spring that overshoots never drives an opacity out of range.
  _expect(kitPhase(0, 0, 0.4) == 0, 'a phase starts at zero');
  _expect(_near(kitPhase(0.2, 0, 0.4), 0.5), 'half way through its stretch');
  _expect(kitPhase(0.4, 0, 0.4) == 1, 'done at its end');
  _expect(kitPhase(1.07, 0.5, 1) == 1, 'an overshoot is held');
  _expect(kitPhase(-0.05, 0, 0.4) == 0, 'an undershoot is held');
  _expect(kitPhase(0.3, 0.5, 1) == 0, 'not started before its stretch');
  _expect(kitPhase(0.6, 0.5, 0.5) == 1, 'an empty stretch is a step');

  // Going back takes one level at a time: the page, then the edit, then
  // the panel itself.
  _expect(
    panelBackStep(detail: true, editing: true) == PanelBackStep.leaveDetail,
    'a detail page goes back first',
  );
  _expect(
    panelBackStep(detail: false, editing: true) == PanelBackStep.endEditing,
    'then an edit ends',
  );
  _expect(
    panelBackStep(detail: false, editing: false) == PanelBackStep.close,
    'and a panel at rest closes',
  );

  // A track's progress stays in range whatever the player reports.
  _expect(mediaProgress(30, 120) == 0.25, 'a quarter played');
  _expect(mediaProgress(500, 120) == 1, 'a position past the end is the end');
  _expect(mediaProgress(-5, 120) == 0, 'a negative position is the start');
  _expect(mediaProgress(30, 0) == 0, 'an unknown length shows nothing');

  // The entrance: the first tile goes at once, later ones wait, none long.
  _expect(staggerDelay(0, 0) == 0, 'the first tile does not wait');
  _expect(staggerDelay(1, 0) > staggerDelay(0, 3), 'a row outweighs columns');
  _expect(staggerDelay(40, 3) == 0.36, 'the wait is capped');

  // The spring a detail page grows on is critically damped: it must reach
  // its end without passing it, and turning round half way must not jump.
  final grow = SpringMotion(0, stiffness: 322, dampingRatio: 1, target: 1);
  var peak = 0.0;
  for (var i = 0; i < 240; i++) {
    grow.step(1 / 120);
    if (grow.value > peak) peak = grow.value;
  }
  _expect(peak <= 1.0005, 'a critically damped page does not overshoot');
  _expect((grow.value - 1).abs() < 0.001, 'and has arrived within two seconds');

  final turn = SpringMotion(0, stiffness: 322, dampingRatio: 1, target: 1);
  for (var i = 0; i < 12; i++) {
    turn.step(1 / 120);
  }
  final before = turn.value;
  final speed = turn.velocity;
  turn.target = 0;
  turn.step(1 / 120);
  _expect(speed > 0 && turn.velocity < speed, 'turning round starts braking');
  _expect(
    (turn.value - before).abs() < 0.05,
    'and the value carries on from where it was',
  );

  // Denial's page spring passes its end by a hair and no more.
  final liquid = SpringMotion(0, stiffness: 300, dampingRatio: 0.8, target: 1);
  peak = 0;
  for (var i = 0; i < 360; i++) {
    liquid.step(1 / 120);
    if (liquid.value > peak) peak = liquid.value;
  }
  _expect(peak > 1 && peak < 1.03, 'the liquid page overshoots under 3%');
}
