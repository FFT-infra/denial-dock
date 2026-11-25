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

  // Folded, the two cards behind show their lower edge under the front one.
  var peek = NcMotion.peek(depth: 1, width: 372, height: 80, tuck: 24);
  _expect(peek.left == 12 && peek.width == 348, 'the first is 12 in a side');
  _expect(peek.top == 56, 'it starts under the front card');
  _expect(peek.top + peek.height == 88, 'and ends 8 below it');
  _expect(_near(peek.strength, 0.75), 'a little fainter');
  peek = NcMotion.peek(depth: 2, width: 372, height: 80, tuck: 24);
  _expect(peek.left == 24 && peek.width == 324, 'the second is 24 in');
  _expect(peek.top + peek.height == 96, 'and ends 16 below');
  _expect(_near(peek.strength, 0.5), 'fainter again');
  // What shows below the front card is what the stack keeps room for, and
  // what a card behind starts from when the stack opens.
  for (final depth in <int>[1, 2]) {
    final under = NcMotion.peek(depth: depth, width: 372, height: 80);
    final start = NcMotion.plate(index: depth, t: 0, width: 372, height: 80);
    _expect(
      under.top + under.height - 80 == start.height &&
          under.left == start.left &&
          under.width == start.width &&
          under.strength == start.strength,
      'peek $depth is the strip card $depth opens from',
    );
    _expect(
      under.top + under.height - 80 <= NcMotion.peekRoom(depth + 1, 0),
      'peek $depth is inside the room kept for it',
    );
  }
  // Each one shows whole below the one in front of it.
  final first = NcMotion.peek(depth: 1, width: 372, height: 80);
  final second = NcMotion.peek(depth: 2, width: 372, height: 80);
  _expect(
    second.left > first.left &&
        second.left + second.width < first.left + first.width &&
        second.top + second.height > first.top + first.height,
    'the second is narrower and lower than the first',
  );
  // A front card shorter than the tuck: the card behind starts at its top
  // and never above it.
  peek = NcMotion.peek(depth: 1, width: 372, height: 16, tuck: 24);
  _expect(peek.top == 0 && peek.height == 24, 'a short card hides no more');
  // Deeper than the stack shows is drawn as the last one; too narrow a
  // column gives no width and never a negative one.
  peek = NcMotion.peek(depth: 7, width: 372, height: 80);
  _expect(peek.left == 24, 'depth is held at the stack\'s');
  peek = NcMotion.peek(depth: 2, width: 40, height: 80);
  _expect(peek.width == 0, 'no negative width');

  // ── Older notifications ──
  _expect(NcMotion.groupsListed(3, all: false) == 3, 'a short list is whole');
  _expect(NcMotion.groupsListed(6, all: false) == 6, 'one over is shown too');
  _expect(NcMotion.groupsListed(9, all: false) == 5, 'more are folded away');
  _expect(NcMotion.groupsListed(9, all: true) == 9, 'until asked for');
  _expect(NcMotion.groupsListed(0, all: false) == 0, 'none is none');

  // ── The widget grid ──
  // 372 across with a gap of 12: two square cells of 180.
  _expect(NcMotion.widgetCell(372) == 180, 'a cell is half less the gap');
  var cell = NcMotion.widgetRect(col: 0, row: 0, w: 1, h: 1, width: 372);
  _expect(
    cell.left == 0 && cell.top == 0 && cell.width == 180 && cell.height == 180,
    'a small widget is one square cell',
  );
  cell = NcMotion.widgetRect(col: 1, row: 0, w: 1, h: 1, width: 372);
  _expect(cell.left == 192 && cell.left + cell.width == 372, 'the second');
  cell = NcMotion.widgetRect(col: 0, row: 1, w: 2, h: 1, width: 372);
  _expect(
    cell.left == 0 &&
        cell.top == 192 &&
        cell.width == 372 &&
        cell.height == 180,
    'a medium widget is a row of two',
  );
  cell = NcMotion.widgetRect(col: 0, row: 2, w: 2, h: 2, width: 372);
  _expect(
    cell.top == 384 && cell.width == 372 && cell.height == 372,
    'a large widget is two rows as well',
  );
  cell = NcMotion.widgetRect(col: 0, row: 0, w: 5, h: 0, width: 372);
  _expect(
    cell.width == 372 && cell.height == 180,
    'sizes are held to the grid',
  );
  _expect(NcMotion.widgetsHeight(0, 372) == 0, 'no rows, no height');
  _expect(NcMotion.widgetsHeight(1, 372) == 180, 'one row');
  _expect(NcMotion.widgetsHeight(3, 372) == 564, 'three rows and two gaps');
  // A grid's height is where its last row ends.
  cell = NcMotion.widgetRect(col: 0, row: 2, w: 1, h: 1, width: 372);
  _expect(
    cell.top + cell.height == NcMotion.widgetsHeight(3, 372),
    'the height is the last row\'s lower edge',
  );
  _expect(NcMotion.widgetCell(4) == 0, 'a column too narrow has no cell');

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

  // ── How the centre is shown ──
  _expect(
    NcMotion.hangs(square: true, anchored: true),
    'a look with square corners hangs the centre from its item',
  );
  _expect(
    !NcMotion.hangs(square: false, anchored: true),
    'a glass look keeps the column',
  );
  _expect(
    !NcMotion.hangs(square: true, anchored: false),
    'with nothing to hang from there is only the column',
  );
  _expect(_near(NcMotion.hangHeight(1000), 700), 'at most 70% of the screen');
  _expect(NcMotion.hangHeight(-5) == 0, 'never a negative height');
  final hung = NcMotion.hangWidth(plate: 372, reach: 6, sceneWidth: 2000);
  _expect(_near(hung, 372 + (6 + NcMotion.hangPad) * 2), 'frame around cards');
  _expect(
    _near(NcMotion.hangPlate(width: hung, reach: 6), 372),
    'the cards inside are as wide as the column\'s',
  );
  final tight = NcMotion.hangWidth(plate: 372, reach: 6, sceneWidth: 320);
  _expect(_near(tight, 304), 'a narrow screen keeps a margin either side');
  _expect(
    _near(NcMotion.hangPlate(width: tight, reach: 6), 304 - 24),
    'and the cards narrow with it',
  );
  _expect(
    NcMotion.hangWidth(plate: 372, reach: 6, sceneWidth: 0) == 0 &&
        NcMotion.hangPlate(width: 0, reach: 6) == 0,
    'no room is no width, not a negative one',
  );
}
