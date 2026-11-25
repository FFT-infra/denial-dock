import 'package:denial_shell_kit/kit_motion_pace.dart';
import 'package:denial_topbar/src/panels/nc_motion.dart';

void _expect(bool ok, String what) {
  if (!ok) throw StateError(what);
}

bool _near(double a, double b, [double by = 1e-6]) => (a - b).abs() <= by;

SpringMotion _spring(double from, NcTuning tuning, {required double target}) =>
    SpringMotion(
      from,
      stiffness: tuning.stiffness,
      dampingRatio: tuning.dampingRatio,
      target: target,
    );

void main() {
  // ── The column's slide ──
  // From rest toward open: never past the target, and the first frame covers
  // almost nothing, so a slow first frame costs the slowest part of the way.
  var slide = _spring(0, NcMotion.slide, target: 1);
  slide.step(1 / 120);
  _expect(slide.value < 0.02, 'the slide starts from rest');
  var highest = slide.value;
  for (var i = 0; i < 240; i++) {
    slide.step(1 / 120);
    if (slide.value > highest) highest = slide.value;
  }
  _expect(highest <= 1.0001, 'the slide does not pass its place');
  _expect(_near(slide.value, 1, 0.002), 'the slide arrives within two seconds');

  // Turned round half way: the next frame continues from the same place at
  // the same speed instead of jumping.
  slide = _spring(0, NcMotion.slide, target: 1);
  for (var i = 0; i < 10; i++) {
    slide.step(1 / 120);
  }
  final at = slide.value, speed = slide.velocity;
  _expect(at > 0.2 && at < 0.8 && speed > 0, 'mid-flight');
  slide.target = 0;
  slide.step(1 / 120);
  // One frame later it is no further on than its speed carries it: the
  // old pair of curves put it most of the way back in that frame.
  _expect(
    slide.value >= at && slide.value - at <= speed / 120,
    'a reversal keeps the position',
  );
  _expect(slide.velocity < speed, 'and starts slowing from the same speed');
  var lowest = slide.value;
  for (var i = 0; i < 240; i++) {
    slide.step(1 / 120);
    if (slide.value < lowest) lowest = slide.value;
  }
  _expect(lowest >= -0.02, 'the way back barely passes closed');

  // ── Rebound ──
  final back = _spring(120, NcMotion.rebound, target: 0);
  var least = back.value;
  for (var i = 0; i < 360; i++) {
    back.step(1 / 120);
    if (back.value < least) least = back.value;
  }
  _expect(least >= -0.001, 'a released card does not pass home');
  _expect(back.value.abs() < 0.1, 'and gets there');

  // ── Following the drag ──
  _expect(NcMotion.swipeFollow(0) == 0, 'no drag, no move');
  _expect(NcMotion.swipeFollow(4.9) == 0, 'inside the slop the card stays');
  _expect(NcMotion.swipeFollow(-4.9) == 0, 'either way');
  _expect(
    NcMotion.swipeFollow(5.5) < 1,
    'the card starts from zero past the slop',
  );
  _expect(
    _near(NcMotion.swipeFollow(105) - NcMotion.swipeFollow(55), 50),
    'toward the edge it follows one to one',
  );
  var last = 0.0;
  for (var raw = -5.0; raw > -600; raw -= 7) {
    final now = NcMotion.swipeFollow(raw);
    _expect(now <= last, 'away from the edge it only gives more');
    _expect(now > -NcMotion.swipeInward, 'and never past its limit');
    last = now;
  }
  _expect(
    NcMotion.swipeFollow(-600) < -NcMotion.swipeInward * 0.95,
    'a long pull nearly reaches the limit',
  );

  // Catching a card on its way home starts the drag where the card is.
  for (final offset in <double>[120, 0, -3, -9, -15]) {
    _expect(
      _near(
        NcMotion.swipeFollow(NcMotion.swipeRaw(offset), slop: 0),
        offset,
        1e-6,
      ),
      'the drag for $offset puts the card there',
    );
  }

  // ── Letting go ──
  const width = 340.0;
  bool clears(double offset, double velocity) =>
      NcMotion.swipeClears(offset: offset, velocity: velocity, width: width);
  _expect(!clears(0, 2000), 'a card that has not moved stays');
  _expect(!clears(-10, 0), 'a card pulled the other way stays');
  _expect(!clears(40, 0), 'a short drag at rest stays');
  _expect(clears(150, 0), 'a long drag at rest clears');
  _expect(clears(20, 900), 'a flick clears from anywhere past the slop');
  _expect(clears(90, 400), 'a moving card clears where it would coast to');
  _expect(!clears(250, -400), 'a card thrown back stays however far it was');

  // ── Leaving ──
  // At a speed the limits allow, the card simply carries on at that speed.
  var exit = NcMotion.swipeExit(remaining: 300, velocity: 2000);
  _expect(_near(exit.ms, 150) && _near(exit.lead, 1), 'a brisk release');
  // Slow: capped time, starting at the finger's speed and gathering pace.
  exit = NcMotion.swipeExit(remaining: 300, velocity: 300);
  _expect(_near(exit.ms, 240), 'a slow release takes the longest');
  _expect(
    _near(exit.lead * 300 / (exit.ms / 1000), 300),
    'and starts at the release speed',
  );
  exit = NcMotion.swipeExit(remaining: 300, velocity: 0);
  _expect(_near(exit.ms, 240) && exit.lead == 0, 'a release at rest');
  // Very fast: the shortest time, still starting at the finger's speed.
  exit = NcMotion.swipeExit(remaining: 300, velocity: 4000);
  _expect(_near(exit.ms, 90), 'a throw takes the shortest');
  _expect(
    _near(exit.lead * 300 / (exit.ms / 1000), 4000),
    'and is not slowed at the start',
  );
  exit = NcMotion.swipeExit(remaining: 300, velocity: 40000);
  _expect(exit.lead <= 1.5, 'the lead is bounded');
  // Less left to cover means less time, at the same speed.
  _expect(
    NcMotion.swipeExit(remaining: 100, velocity: 800).ms <
        NcMotion.swipeExit(remaining: 180, velocity: 800).ms,
    'time follows the distance left',
  );
  _expect(NcMotion.swipeExit(remaining: 0, velocity: 10).ms == 0, 'none left');
  for (final lead in <double>[0, 0.4, 1, 1.5]) {
    _expect(NcMotion.exitCurve(lead, 0) == 0, 'the exit starts at zero');
    _expect(_near(NcMotion.exitCurve(lead, 1), 1), 'and ends at one');
    var before = 0.0;
    for (var i = 1; i <= 20; i++) {
      final now = NcMotion.exitCurve(lead, i / 20);
      _expect(now >= before, 'without turning back');
      before = now;
    }
  }

  // ── A stack ──
  _expect(NcMotion.peeks(1) == 0, 'one card has nothing behind');
  _expect(NcMotion.peeks(2) == 1 && NcMotion.peeks(9) == 2, 'two at most');
  _expect(NcMotion.peekRoom(3, 0) == 16, 'folded, both strips need room');
  _expect(NcMotion.peekRoom(3, 1) == 0, 'open, none');

  var plate = NcMotion.plate(index: 0, t: 0, width: 340, height: 70);
  _expect(
    plate.left == 0 && plate.top == 0 && plate.height == 70,
    'the front card is always its own size',
  );
  // Folded: a strip that starts at the front card's lower edge, which is
  // `lift` above the card's own origin, and shows one peek per step.
  plate = NcMotion.plate(index: 1, t: 0, width: 340, height: 70, lift: 8);
  _expect(plate.left == 12 && plate.width == 316, 'one step narrower');
  _expect(plate.top == -8 && plate.height == 8, 'showing 8 under the front');
  _expect(_near(plate.strength, 0.75), 'and fainter');
  plate = NcMotion.plate(index: 2, t: 0, width: 340, height: 70, lift: 8);
  _expect(plate.left == 24 && plate.top + plate.height == 8, 'two steps');
  _expect(_near(plate.strength, 0.5), 'fainter again');
  plate = NcMotion.plate(index: 5, t: 0, width: 340, height: 70, lift: 8);
  _expect(plate.left == 24 && plate.strength == 0, 'deeper cards are hidden');
  // Open: every card is its own plate.
  for (final index in <int>[1, 2, 5]) {
    plate = NcMotion.plate(index: index, t: 1, width: 340, height: 70, lift: 8);
    _expect(
      plate.left == 0 &&
          _near(plate.top, 0) &&
          plate.width == 340 &&
          _near(plate.height, 70) &&
          _near(plate.strength, 1),
      'open, card $index is whole',
    );
  }
  // Between: everything moves the same way the whole time.
  var previous = NcMotion.plate(index: 2, t: 0, width: 340, height: 70);
  for (var i = 1; i <= 10; i++) {
    final now = NcMotion.plate(index: 2, t: i / 10, width: 340, height: 70);
    _expect(
      now.left <= previous.left &&
          now.width >= previous.width &&
          now.height >= previous.height &&
          now.strength >= previous.strength,
      'a plate grows steadily',
    );
    previous = now;
  }
  // A spring that passes its target must not turn the plate inside out.
  plate = NcMotion.plate(index: 1, t: 1.08, width: 340, height: 70);
  _expect(plate.left == 0 && plate.width == 340, 'overshoot is held');

  _expect(NcMotion.reveal(0.5) == 0, 'no text in the first half');
  _expect(_near(NcMotion.reveal(0.75), 0.5), 'half way through the second');
  _expect(NcMotion.reveal(1.2) == 1 && NcMotion.reveal(-1) == 0, 'bounded');

  // ── Clear All ──
  _expect(NcMotion.clearDelay(0) == 0, 'the first row goes at once');
  _expect(NcMotion.clearDelay(3) == 135, 'the rest follow in turn');
  _expect(
    NcMotion.clearDelay(40) == NcMotion.clearDelay(12),
    'a long list does not take longer',
  );

  // ── Actions ──
  _expect(
    NcMotion.actionsThatFit(const <double>[], 200) == 0,
    'no actions, none shown',
  );
  _expect(
    NcMotion.actionsThatFit(const <double>[60, 60, 60], 200) == 3,
    'three that fit all show',
  );
  // 60+6+60+6+60 = 192 fits; a fourth does not, and the button for the rest
  // takes room of its own: 28 + 6+60 + 6+60 = 160, and a third would be 226.
  _expect(
    NcMotion.actionsThatFit(const <double>[60, 60, 60, 60], 200) == 2,
    'room is kept for the rest',
  );
  _expect(
    NcMotion.actionsThatFit(const <double>[190, 60], 200) == 0,
    'one too wide leaves only the button',
  );
  _expect(
    NcMotion.actionsThatFit(const <double>[200], 200) == 1,
    'a single action that just fits needs no button',
  );
}
