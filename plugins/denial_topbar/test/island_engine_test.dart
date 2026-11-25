import 'dart:io';

import 'package:denial_topbar/src/island/island_engine.dart';

void main() {
  final t0 = DateTime(2026);
  DateTime at(int ms) => t0.add(Duration(milliseconds: ms));
  const two = Duration(seconds: 2);
  const five = Duration(seconds: 5);

  // ── Layers and pre-emption ────────────────────────────────────────────
  var engine = IslandEngine();
  _expect(engine.kind == IslandKind.home, 'rests on home');
  engine.setMedia(true);
  _expect(engine.kind == IslandKind.media, 'playback is the live activity');

  engine.show(IslandKind.hud, 'volume', two, at(0));
  _expect(engine.kind == IslandKind.hud, 'a level change takes the island');
  _expect(engine.arrivals == 1, 'and counts as an arrival');
  engine.show(IslandKind.hud, 'volume', two, at(1500));
  _expect(engine.arrivals == 1, 'more of the same item is not another one');
  engine.tick(at(2500));
  _expect(engine.kind == IslandKind.hud, 'another change restarts the hold');
  engine.tick(at(3500));
  _expect(engine.kind == IslandKind.media, 'playback comes back afterwards');

  engine.show(IslandKind.notice, 'n1', five, at(4000));
  engine.show(IslandKind.hud, 'volume', two, at(5000));
  _expect(engine.kind == IslandKind.hud, 'the hud interrupts a notice');
  _expect(engine.waiting == 1, 'which waits');
  final before = engine.arrivals;
  engine.tick(at(7000));
  _expect(engine.kind == IslandKind.notice, 'the notice returns');
  _expect(engine.arrivals == before, 'coming back is not an arrival');
  engine.tick(at(10900));
  _expect(
    engine.kind == IslandKind.notice,
    'with the four seconds it had left',
  );
  engine.tick(at(11000));
  _expect(engine.kind == IslandKind.media, 'and then ends');

  engine.show(IslandKind.notice, 'n2', five, at(12000));
  engine.show(IslandKind.charging, 'plug', two, at(12500));
  _expect(engine.kind == IslandKind.notice, 'a weaker item waits');
  final queued = engine.arrivals;
  engine.end(IslandKind.notice, at(13000));
  _expect(
    engine.kind == IslandKind.charging,
    'and shows once the way is clear',
  );
  _expect(engine.arrivals == queued + 1, 'as an arrival: it was never seen');
  engine.tick(at(14900));
  _expect(engine.kind == IslandKind.charging, 'for its own full hold');
  engine.tick(at(15000));
  _expect(engine.kind == IslandKind.media, 'and no longer');

  engine.show(IslandKind.notice, 'n3', five, at(20000));
  engine.show(IslandKind.hud, 'volume', two, at(24600));
  _expect(engine.waiting == 0, 'an item with a moment left does not wait');
  engine.tick(at(26600));
  _expect(engine.kind == IslandKind.media, 'and does not flash back');

  engine.show(IslandKind.hud, 'volume', const Duration(seconds: 20), at(30000));
  engine.show(IslandKind.charging, 'plug', two, at(30000));
  engine.tick(at(50000));
  _expect(engine.kind == IslandKind.media, 'an item that waited too long goes');

  engine.show(IslandKind.notice, 'a', five, at(60000));
  engine.show(IslandKind.hud, 'volume', two, at(60500));
  engine.show(IslandKind.notice, 'b', five, at(61000));
  _expect(engine.waiting == 1, 'one item of a kind waits');
  engine.tick(at(62500));
  _expect(engine.transient?.id == 'b', 'the newer one');
  engine.tick(at(67400));
  _expect(engine.kind == IslandKind.notice, 'with its full hold');
  engine.tick(at(67500));
  _expect(engine.kind == IslandKind.media, 'then playback again');

  // ── Hold ──────────────────────────────────────────────────────────────
  engine.show(IslandKind.notice, 'h', five, at(70000));
  engine.hold(at(71000));
  _expect(engine.nextDeadline == null, 'a held item has no deadline');
  engine.tick(at(79000));
  _expect(engine.kind == IslandKind.notice, 'and does not run out');
  engine.release(at(79000));
  engine.tick(at(82999));
  _expect(engine.kind == IslandKind.notice, 'released, it has what was left');
  engine.tick(at(83000));
  _expect(engine.kind == IslandKind.media, 'and then ends');

  engine.show(IslandKind.hud, 'volume', two, at(90000));
  engine.hold(at(91900));
  engine.release(at(95000));
  engine.tick(at(96100));
  _expect(engine.kind == IslandKind.hud, 'a release always leaves a moment');
  engine.tick(at(96200));
  _expect(engine.kind == IslandKind.media, 'of a little over a second');

  engine.hold(at(100000));
  engine.show(IslandKind.hud, 'volume', two, at(100000));
  engine.release(at(109000));
  engine.tick(at(110900));
  _expect(engine.kind == IslandKind.hud, 'an item arriving under a hold');
  engine.tick(at(111000));
  _expect(engine.kind == IslandKind.media, 'keeps its whole time for later');

  // ── Tap ───────────────────────────────────────────────────────────────
  _expect(engine.tap == IslandTap.open, 'a tap opens the panel');
  engine.show(IslandKind.hud, 'volume', two, at(120000));
  _expect(engine.tap == IslandTap.dismiss, 'or dismisses an item with no card');
  engine.dismiss(at(120100));
  _expect(engine.kind == IslandKind.media, 'at once');
  engine.show(IslandKind.status, 'bt', two, at(121000));
  _expect(engine.opens == IslandKind.media, 'a status line has no card');
  engine.expand();
  _expect(
    engine.card == IslandKind.media && engine.transient == null,
    'opening over it opens what is underneath',
  );
  engine.collapse(at(122000));

  // ── Panel ─────────────────────────────────────────────────────────────
  engine.expand();
  _expect(engine.pinned && engine.card == IslandKind.media, 'a pinned panel');
  _expect(
    !engine.show(IslandKind.hud, 'volume', two, at(130000)),
    'turns a passing item away',
  );
  _expect(engine.card == IslandKind.media, 'and stays');
  _expect(
    engine.show(IslandKind.notice, 'p', five, at(130500)),
    'keeps a notice for later',
  );
  _expect(engine.card == IslandKind.media, 'still open');
  engine.collapse(at(131500));
  _expect(engine.kind == IslandKind.notice, 'and shows it once closed');
  engine.tick(at(136500));
  _expect(engine.kind == IslandKind.media, 'for its hold');

  engine.expand(pinned: false);
  _expect(engine.expanded && !engine.pinned, 'a preview is not pinned');
  engine.show(IslandKind.hud, 'volume', two, at(140000));
  _expect(!engine.expanded, 'and gives way to a new item');
  _expect(engine.kind == IslandKind.hud, 'which takes the pill');
  engine.tick(at(142000));

  engine.expand(pinned: false);
  engine.pin();
  _expect(engine.pinned, 'a preview can be pinned');
  engine.collapse(at(143000));

  engine.show(IslandKind.notice, 'n4', five, at(150000));
  engine.expand();
  _expect(engine.card == IslandKind.notice, 'a notice opens into its card');
  _expect(engine.pages.length == 1, 'which stands alone');
  engine.tick(at(156000));
  _expect(engine.kind == IslandKind.notice, 'an open card outlives its hold');
  engine.show(IslandKind.notice, 'n5', five, at(156500));
  _expect(
    engine.card == IslandKind.notice && engine.transient?.id == 'n5',
    'and takes the next of its kind',
  );
  engine.collapse(at(170000));
  _expect(engine.kind == IslandKind.media, 'and leaves when it is closed');

  engine.show(IslandKind.notice, 'n6', five, at(180000));
  engine.expand();
  engine.end(IslandKind.notice, at(181000));
  _expect(!engine.expanded, 'a card closes when its item is withdrawn');

  engine.setLive(IslandKind.timer, true);
  engine.expand();
  _expect(engine.card == IslandKind.timer, 'a timer outranks playback');
  engine.setLive(IslandKind.timer, false);
  _expect(
    engine.card == IslandKind.media,
    'a pinned panel moves on when its activity ends',
  );
  engine.setMedia(false);
  _expect(engine.card == IslandKind.home, 'down to the home page');
  engine.collapse(at(190000));
  _expect(engine.kind == IslandKind.home && !engine.expanded, 'and rests');

  engine.setMedia(true);
  engine.expand(pinned: false);
  engine.setMedia(false);
  _expect(!engine.expanded, 'a preview closes when its activity ends');

  engine = IslandEngine()..homeCard = false;
  _expect(!engine.canExpand, 'with no home card the resting pill is inert');
  engine.expand();
  _expect(!engine.expanded, 'and never opens');
  engine.setMedia(true);
  engine.expand();
  _expect(engine.pages.length == 1, 'home is not a page then');
  engine.setMedia(false);
  _expect(!engine.expanded, 'and there is nothing to fall back to');

  // ── Several live activities ───────────────────────────────────────────
  engine = IslandEngine();
  engine.setMedia(true);
  _expect(engine.secondary == null, 'one activity rides alone');
  engine.setLive(IslandKind.timer, true);
  _expect(engine.kind == IslandKind.timer, 'a timer outranks playback');
  _expect(engine.secondary == IslandKind.media, 'playback rides beside it');
  engine.setLive(IslandKind.recording, true);
  _expect(engine.kind == IslandKind.recording, 'recording outranks a timer');
  _expect(engine.cycle(1), 'a swipe moves');
  _expect(engine.kind == IslandKind.timer, 'to the next one');
  engine.cycle(1);
  _expect(engine.kind == IslandKind.media, 'and on to the one after');
  _expect(engine.secondary == IslandKind.recording, 'the strongest rides');
  engine.cycle(1);
  _expect(engine.kind == IslandKind.recording, 'and wraps around');
  engine.cycle(-1);
  _expect(engine.kind == IslandKind.media, 'a swipe back wraps too');
  engine.show(IslandKind.status, 'bt', two, at(200000));
  _expect(engine.kind == IslandKind.status, 'a status line takes the island');
  _expect(engine.secondary == null, 'with no bubble beside it');
  _expect(!engine.cycle(1), 'and no swiping under it');
  engine.tick(at(202000));
  _expect(engine.kind == IslandKind.media, 'the picked activity returns');
  engine.setMedia(false);
  _expect(engine.kind == IslandKind.recording, 'ending it falls back');
  engine.setMedia(true);
  engine.pick(IslandKind.timer);
  engine.expand();
  _expect(engine.card == IslandKind.timer, 'pick and open');
  _expect(engine.secondary == null, 'an open panel has no bubble');
  _expect(
    engine.pages.join() ==
        <IslandKind>[
          IslandKind.recording,
          IslandKind.timer,
          IslandKind.media,
          IslandKind.home,
        ].join(),
    'pages keep a steady order, home last',
  );
  engine.cycle(1);
  _expect(engine.card == IslandKind.media, 'a swipe turns the page');
  engine.cycle(1);
  _expect(engine.card == IslandKind.home, 'on to home');
  engine.cycle(1);
  _expect(engine.card == IslandKind.recording, 'and around');
  engine.showPage(IslandKind.media);
  _expect(engine.card == IslandKind.media, 'a dot turns to its page');
  engine.collapse(at(210000));
  _expect(engine.kind == IslandKind.media, 'the page last read keeps the pill');

  // ── Levels ────────────────────────────────────────────────────────────
  var gate = IslandLevelGate(born: at(0));
  _expect(!gate.feed(0.5, at(100)), 'the first level is not a change');
  _expect(!gate.feed(0.6, at(1000), from: 0.5), 'nor is one while starting');
  _expect(gate.feed(0.7, at(5000), from: 0.6), 'a change after that is');
  _expect(!gate.feed(0.7005, at(6000)), 'a hair of a difference is not');
  // A workspace switch: the source starts over at a placeholder, reads the
  // backlight again, and the level is echoed once more, rounded.
  _expect(!gate.feed(0.72, at(10000), loading: true), 'a reload is quiet');
  _expect(!gate.feed(0.7, at(10200)), 'and so is the level it reads back');
  _expect(!gate.feed(0.695, at(10400)), 'and its rounded echo');
  _expect(!gate.feed(0.7, at(13000)), 'the old level is still the level');
  _expect(gate.feed(0.8, at(14000)), 'a real change afterwards shows');
  _expect(!gate.feed(null, at(20000)), 'a lost output is quiet');
  _expect(!gate.feed(0.3, at(30000)), 'and so is its first level back');
  _expect(gate.feed(0.4, at(31000)), 'the next change shows');

  gate = IslandLevelGate(born: at(0));
  _expect(!gate.feed(0.72, at(200), loading: true), 'a placeholder is quiet');
  _expect(!gate.feed(0.4, at(900)), 'the first real level replaces it');
  _expect(!gate.feed(0.4, at(9000)), 'unchanged, it stays quiet');
  _expect(gate.feed(0.45, at(9500)), 'until the user moves it');

  gate = IslandLevelGate(born: at(0));
  _expect(
    gate.feed(0.5, at(10000), from: 0.3),
    'a first change long after the start counts from what was there',
  );

  // ── Stepping out of the way ───────────────────────────────────────────
  bool yields({
    bool fade = true,
    bool dwelt = true,
    bool expanded = false,
    bool arriving = false,
    bool pressed = false,
  }) => islandYields(
    fade: fade,
    dwelt: dwelt,
    expanded: expanded,
    arriving: arriving,
    pressed: pressed,
  );
  _expect(yields(), 'a resting pointer fades the compact island');
  _expect(!yields(fade: false), 'only where the user asked');
  _expect(!yields(dwelt: false), 'only once it has rested');
  _expect(!yields(expanded: true), 'never an open panel');
  _expect(!yields(arriving: true), 'never an item that just arrived');
  _expect(!yields(pressed: true), 'never under a press');

  stdout.writeln('All island engine tests passed.');
}

void _expect(bool condition, String message) {
  if (!condition) {
    stderr.writeln('FAILED: $message');
    exit(1);
  }
}
