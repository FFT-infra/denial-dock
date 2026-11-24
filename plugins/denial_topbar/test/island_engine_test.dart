import 'dart:io';

import 'package:denial_topbar/src/island/island_engine.dart';

void main() {
  final t0 = DateTime(2026);
  DateTime at(int ms) => t0.add(Duration(milliseconds: ms));
  const two = Duration(seconds: 2);
  const five = Duration(seconds: 5);

  var engine = IslandEngine();
  _expect(engine.kind == null, 'rests with nothing to show');
  engine.setMedia(true);
  _expect(engine.kind == IslandKind.media, 'playback is the live activity');

  engine.show(IslandKind.hud, 'volume', two, at(0));
  _expect(engine.kind == IslandKind.hud, 'a level change takes the island');
  engine.show(IslandKind.hud, 'volume', two, at(1500));
  engine.tick(at(2500));
  _expect(engine.kind == IslandKind.hud, 'another change restarts the hold');
  engine.tick(at(3500));
  _expect(engine.kind == IslandKind.media, 'playback comes back afterwards');

  engine.show(IslandKind.notice, 'n1', five, at(4000));
  engine.show(IslandKind.hud, 'volume', two, at(5000));
  _expect(engine.kind == IslandKind.hud, 'the hud interrupts a notice');
  engine.tick(at(7000));
  _expect(engine.kind == IslandKind.notice, 'the notice returns');
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
  engine.end(IslandKind.notice, at(13000));
  _expect(
    engine.kind == IslandKind.charging,
    'and shows once the way is clear',
  );
  engine.tick(at(15000));
  _expect(engine.kind == IslandKind.media, 'for its own full hold');

  engine.expand();
  _expect(engine.expanded, 'playback opens into a card');
  engine.show(IslandKind.hud, 'volume', two, at(16000));
  _expect(!engine.expanded, 'a new item closes the card');
  engine.expand();
  _expect(!engine.expanded, 'the hud has no card');
  engine.tick(at(18000));

  engine.show(IslandKind.notice, 'n3', five, at(20000));
  engine.expand();
  engine.tick(at(26000));
  _expect(engine.kind == IslandKind.notice, 'an open card outlives its hold');
  engine.collapse(at(26000));
  _expect(engine.kind == IslandKind.media, 'and leaves when it is closed');

  engine.setMedia(false);
  _expect(
    engine.kind == null && !engine.expanded,
    'stopping playback rests it',
  );

  engine = IslandEngine();
  engine.expand();
  _expect(!engine.expanded, 'the resting pill never opens');

  engine = IslandEngine();
  engine.setLive(IslandKind.home, true);
  _expect(engine.kind == IslandKind.home, 'home is the weakest live activity');
  engine.setMedia(true);
  _expect(engine.kind == IslandKind.media, 'playback sits above home');
  _expect(engine.secondary == null, 'home never rides beside the pill');
  engine.setLive(IslandKind.timer, true);
  _expect(engine.kind == IslandKind.timer, 'a timer outranks playback');
  _expect(engine.secondary == IslandKind.media, 'playback rides beside it');
  engine.setLive(IslandKind.recording, true);
  _expect(engine.kind == IslandKind.recording, 'recording outranks a timer');
  engine.cycle(1);
  _expect(engine.kind == IslandKind.timer, 'a swipe moves to the next one');
  engine.cycle(1);
  _expect(engine.kind == IslandKind.media, 'and on to the one after');
  _expect(engine.secondary == IslandKind.recording, 'the strongest rides');
  engine.cycle(1);
  _expect(engine.kind == IslandKind.recording, 'and wraps around');
  engine.cycle(-1);
  _expect(engine.kind == IslandKind.media, 'a swipe back wraps too');
  engine.show(IslandKind.status, 'bt', two, at(30000));
  _expect(engine.kind == IslandKind.status, 'a status line takes the island');
  _expect(engine.secondary == null, 'with no bubble beside it');
  engine.expand();
  _expect(!engine.expanded, 'a status line has no card');
  engine.tick(at(32000));
  _expect(engine.kind == IslandKind.media, 'the picked activity returns');
  engine.setMedia(false);
  _expect(engine.kind == IslandKind.recording, 'ending it falls back');
  engine.pick(IslandKind.timer);
  engine.expand();
  _expect(engine.expanded && engine.kind == IslandKind.timer, 'pick and open');
  engine.setLive(IslandKind.timer, false);
  _expect(!engine.expanded, 'a card closes when its activity ends');

  stdout.writeln('All island engine tests passed.');
}

void _expect(bool condition, String message) {
  if (!condition) {
    stderr.writeln('FAILED: $message');
    exit(1);
  }
}
