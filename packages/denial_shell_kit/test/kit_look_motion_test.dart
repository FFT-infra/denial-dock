import 'package:denial_shell_kit/kit_feedback.dart';
import 'package:denial_shell_kit/kit_look_motion.dart';
import 'package:denial_shell_kit/kit_motion_pace.dart';

void _expect(bool ok, String what) {
  if (!ok) throw StateError(what);
}

/// The furthest past its target a spring tuned as [tuning] gets on the way
/// from [from] to [to], as a share of the distance.
double _overshoot(KitSpringTuning tuning, {double from = 0, double to = 1}) {
  final spring = SpringMotion(
    from,
    stiffness: tuning.stiffness,
    dampingRatio: tuning.dampingRatio,
    target: to,
  );
  final way = to > from ? 1.0 : -1.0;
  var past = 0.0;
  for (var i = 0; i < 480; i++) {
    spring.step(1 / 120);
    final beyond = (spring.value - to) * way;
    if (beyond > past) past = beyond;
  }
  return past / (to - from).abs();
}

void main() {
  const names = <String>['denial', 'mac', 'soft', 'terminal'];
  const looks = KitLookMotion.presets;
  _expect(looks.length == names.length, 'every look has a name here');

  // Only a liquid look may pass its target. Everything another look moves
  // on is critically damped or heavier, and the simulation agrees.
  for (var i = 0; i < looks.length; i++) {
    final look = looks[i];
    final name = names[i];
    final springs = <String, KitSpringTuning>{
      'panelGrow': look.panelGrow,
      'panelShrink': look.panelShrink,
      'press': look.pressTuning,
      'toggle': look.toggle,
    };
    for (final entry in springs.entries) {
      _expect(entry.value.stiffness > 0, '$name ${entry.key} has stiffness');
      if (look.liquid) continue;
      _expect(
        entry.value.dampingRatio >= 1,
        '$name ${entry.key} is damped critically or more',
      );
      _expect(
        _overshoot(entry.value) < 1e-6,
        '$name ${entry.key} does not pass its target',
      );
    }
    // A press goes from full size to a little under and back.
    if (!look.liquid) {
      _expect(
        _overshoot(look.pressTuning, from: 0.96, to: 1) < 1e-6,
        '$name: a released control does not spring past its size',
      );
    }
    // A surface going away never bounces, in any look: it would dip past
    // the thing it lands on.
    _expect(look.panelShrink.dampingRatio >= 1, '$name leaves dead-beat');
    _expect(
      _overshoot(look.panelShrink, from: 1, to: 0) < 1e-6,
      '$name: a leaving panel does not pass zero',
    );
    // The way out is quicker than the way in.
    _expect(
      look.panelShrink.stiffness > look.panelGrow.stiffness,
      '$name leaves faster than it arrives',
    );
    _expect(look.pace >= 1, '$name is never slower than written');
  }

  // Denial is the liquid one, and it does overshoot.
  _expect(KitLookMotion.denial.liquid, 'Denial is liquid');
  _expect(looks.where((look) => look.liquid).length == 1, 'one look is liquid');
  _expect(
    _overshoot(KitLookMotion.denial.panelGrow) > 0.01,
    'a Denial popup stretches past its shape',
  );
  _expect(
    _overshoot(KitLookMotion.denial.pressTuning, from: 0.96, to: 1) > 0.01,
    'a Denial control springs back past its size',
  );

  // A spring written for Denial, run through a look. Liquid keeps it; the
  // others damp it critically, never loosen its stiffness, and a brisk look
  // is at least as stiff as its own popups.
  const written = <KitSpringTuning>[
    KitSpringTuning(200, 0.2),
    KitSpringTuning(420, 0.62),
    KitSpringTuning(460, 0.79),
    KitSpringTuning(520, 1),
    KitSpringTuning(300, 1.4),
    KitSpringTuning(2000, 0.5),
  ];
  for (var i = 0; i < looks.length; i++) {
    final look = looks[i];
    final name = names[i];
    for (final tuning in written) {
      final run = look.settled(tuning);
      if (look.liquid) {
        _expect(identical(run, tuning), '$name keeps a spring as written');
        continue;
      }
      _expect(run.dampingRatio >= 1, '$name damps a written spring');
      _expect(
        run.dampingRatio >= tuning.dampingRatio,
        '$name never loosens the damping',
      );
      _expect(run.stiffness >= tuning.stiffness, '$name keeps the stiffness');
      _expect(_overshoot(run) < 1e-6, '$name: a written spring settles');
      if (look.pace > 1) {
        _expect(
          run.stiffness >= look.panelGrow.stiffness,
          '$name is as brisk as its popups',
        );
      } else {
        _expect(
          run.stiffness == tuning.stiffness,
          '$name leaves the stiffness alone',
        );
      }
    }
  }

  // The user's speed times the look's pace has bounds, so every timed
  // transition stays between a quarter and twice its written length.
  const nominals = <Duration>[
    Duration(milliseconds: 60),
    Duration(milliseconds: 140),
    Duration(milliseconds: 320),
    Duration(milliseconds: 500),
  ];
  for (final speed in KitMotionPace.speeds) {
    for (final look in <double>[1, 1.6, 3, 100, 0.01]) {
      final timed = KitMotionPace.timedSpeed(speed, look);
      _expect(
        timed >= KitMotionPace.minSpeed && timed <= KitMotionPace.maxTimedSpeed,
        'speed $speed at pace $look stays in bounds',
      );
      final pace = KitMotionPace.timed(
        speed: speed,
        look: look,
        reduced: false,
      );
      for (final nominal in nominals) {
        final drawn = pace.duration(nominal);
        _expect(
          drawn.inMicroseconds * 4 >= nominal.inMicroseconds - 4 &&
              drawn.inMicroseconds <= nominal.inMicroseconds * 2,
          '$nominal at speed $speed, pace $look is $drawn',
        );
      }
    }
  }
  // Inside the bounds the two simply multiply, and a look with no pace of
  // its own leaves the user's speed alone.
  _expect(KitMotionPace.timedSpeed(1, 1.6) == 1.6, 'pace multiplies');
  _expect(KitMotionPace.timedSpeed(2, 1.6) == 3.2, 'speed and pace multiply');
  for (final speed in KitMotionPace.speeds) {
    _expect(KitMotionPace.timedSpeed(speed, 1) == speed, 'pace 1 is neutral');
  }
  // A malformed pace is no pace.
  _expect(KitMotionPace.timedSpeed(1.5, double.nan) == 1.5, 'NaN is 1');
  _expect(KitMotionPace.timedSpeed(1.5, 0) == 1.5, 'zero is 1');
  _expect(KitMotionPace.timedSpeed(1.5, -2) == 1.5, 'negative is 1');
  _expect(
    KitMotionPace.timedSpeed(1.5, double.infinity) == 1.5,
    'infinity is 1',
  );

  // Reduced motion: every timed transition is instant in every look at
  // every speed. What is left is a change of state, never travel.
  for (final speed in KitMotionPace.speeds) {
    for (final look in looks) {
      final pace = KitMotionPace.timed(
        speed: speed,
        look: look.pace,
        reduced: true,
      );
      for (final nominal in nominals) {
        _expect(
          pace.duration(nominal) == Duration.zero,
          'reduced motion zeroes $nominal',
        );
      }
      // A loop keeps a length: a zero-length repeat would spin.
      _expect(
        pace.scaled(nominals.last) > Duration.zero,
        'a loop keeps its length under reduced motion',
      );
    }
  }

  // Feedback: the states rank, so no two look alike.
  for (final flat in <bool>[false, true]) {
    double wash(bool h, bool p, {bool on = true}) =>
        KitFeedback.wash(hovered: h, pressed: p, enabled: on);
    double line(bool h, bool p, {bool on = true}) =>
        KitFeedback.line(hovered: h, pressed: p, flat: flat, enabled: on);
    _expect(wash(false, false) == 0, 'a resting control has no wash');
    _expect(wash(true, false) > 0, 'a hovered control has one');
    _expect(wash(true, true) > wash(true, false), 'pressed outranks hovered');
    _expect(wash(false, true) == wash(true, true), 'a finger press counts');
    _expect(line(false, false) == 0, 'a resting control has no line');
    if (flat) {
      _expect(line(true, false) > 0, 'a flat look lines a hovered control');
      _expect(line(true, true) > line(true, false), 'and more when pressed');
    } else {
      _expect(
        line(true, false) == 0 && line(true, true) == 0,
        'a look with gloss draws no line',
      );
    }
    // An unavailable control answers nothing.
    for (final h in <bool>[false, true]) {
      for (final p in <bool>[false, true]) {
        _expect(wash(h, p, on: false) == 0, 'disabled has no wash');
        _expect(line(h, p, on: false) == 0, 'disabled has no line');
        _expect(
          KitFeedback.scale(0.9, held: p, enabled: false) == 1,
          'disabled does not give',
        );
        _expect(
          KitFeedback.plate(0.1, hovered: h, pressed: p, enabled: false) == 0.1,
          'disabled keeps its resting plate',
        );
      }
    }
  }
  _expect(
    KitFeedback.plate(0.1, hovered: true, pressed: false) > 0.1 &&
        KitFeedback.plate(0.1, hovered: true, pressed: true) >
            KitFeedback.plate(0.1, hovered: true, pressed: false),
    'a plate lifts under the pointer and more when held',
  );
  _expect(
    KitFeedback.plate(0.97, hovered: true, pressed: true) == 1,
    'a plate is never past solid',
  );
  _expect(KitFeedback.scale(0.9, held: true) == 0.9, 'a held control gives');
  _expect(KitFeedback.scale(0.9, held: false) == 1, 'and comes back');
  _expect(
    KitFeedback.disabledOpacity > 0.25 && KitFeedback.disabledOpacity < 0.6,
    'a disabled control is dim but legible',
  );
  _expect(KitFeedback.ringWidth >= 2, 'the focus ring is easy to see');
}
