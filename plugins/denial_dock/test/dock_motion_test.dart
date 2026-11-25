import 'package:denial_dock/src/dock_launch.dart';
import 'package:denial_dock/src/dock_math.dart';
import 'package:denial_dock/src/dock_motion.dart';
import 'package:denial_dock/src/dock_settings.dart';

void main() {
  const full = DockMotion(reduced: false);
  const reduced = DockMotion(reduced: true);
  const frame = 1 / 60;

  // With full motion a chased value is exactly what the dock always computed.
  _expect(
    full.advance(0, 1, frame, responseSeconds: 0.055) ==
        DockMath.advance(0, 1, frame, responseSeconds: 0.055),
    'full motion keeps the response',
  );
  final step = full.advance(0, 1, frame, responseSeconds: 0.055);
  _expect(step > 0 && step < 1, 'full motion travels: $step');

  // With reduced motion it is at its target at once, whatever the frame time.
  _expect(
    reduced.advance(0, 1, frame, responseSeconds: 0.055) == 1,
    'reduced motion arrives in one step',
  );
  _expect(
    reduced.advance(1, 0, frame, responseSeconds: 0.10) == 0,
    'reduced motion arrives on the way back too',
  );
  _expect(
    reduced.advance(0, 1, 0, responseSeconds: 0.026) == 1,
    'reduced motion does not wait for a frame time',
  );
  _expect(
    reduced.advance(-10000, 320, double.nan, responseSeconds: 0.026) == 320,
    'reduced motion survives a broken frame time',
  );

  // A timed glide adds up to its length, or is over at once.
  var progress = 0.0;
  for (var i = 0; i < 6; i++) {
    progress = full.glide(progress, 0.03, 0.18);
  }
  _expect((progress - 1).abs() < 1e-9, 'six 30 ms frames cover 180 ms');
  _expect(full.glide(0, 0.03, 0.18) < 1, 'a glide takes its time');
  _expect(reduced.glide(0, 0.03, 0.18) == 1, 'reduced motion skips the glide');
  _expect(reduced.glide(0, 0, 0.18) == 1, 'even on a frame of no length');

  // Implicit position and size animations keep their length or lose it.
  const shuffle = Duration(milliseconds: 180);
  _expect(full.duration(shuffle) == shuffle, 'full motion keeps durations');
  _expect(
    reduced.duration(shuffle) == Duration.zero,
    'reduced motion has no durations',
  );
  _expect(
    full.duration(Duration.zero) == Duration.zero,
    'nothing stays nothing',
  );

  // The hop becomes the pulse; the other choices are left alone.
  for (final chosen in DockLaunchFeedback.values) {
    _expect(full.launchFeedback(chosen) == chosen, 'full motion: $chosen');
  }
  _expect(
    reduced.launchFeedback(DockLaunchFeedback.hop) == DockLaunchFeedback.pulse,
    'reduced motion pulses instead of hopping',
  );
  _expect(
    reduced.launchFeedback(DockLaunchFeedback.pulse) ==
        DockLaunchFeedback.pulse,
    'a pulse stays a pulse',
  );
  _expect(
    reduced.launchFeedback(DockLaunchFeedback.none) == DockLaunchFeedback.none,
    'no feedback stays none',
  );

  // Attention hops once at the start of each period and then rests.
  _expect(DockMotion.attentionWave(0) == 0, 'the hop starts on the row');
  _expect(
    (DockMotion.attentionWave(0.2) - 1).abs() < 1e-9,
    'the hop peaks half way through its share',
  );
  _expect(DockMotion.attentionWave(0.4) == 0, 'the hop has landed');
  _expect(DockMotion.attentionWave(0.9) == 0, 'the rest is still');
  _expect(
    (full.attentionLift(0.2, 48) - 48 * 0.22).abs() < 1e-9,
    'the hop is 0.22 of an icon high',
  );
  _expect(full.attentionOpacity(0.2) == 1, 'a hopping icon keeps its opacity');

  // With reduced motion the icon never leaves the row; it dims in the hop's
  // place and is back to full for the rest of the period.
  for (final phase in [0.0, 0.1, 0.2, 0.3, 0.4, 0.7, 1.0]) {
    _expect(reduced.attentionLift(phase, 48) == 0, 'no lift at $phase');
  }
  _expect(
    (reduced.attentionOpacity(0.2) - DockLaunch.pulseFloor).abs() < 1e-9,
    'the dim reaches the pulse floor',
  );
  _expect(reduced.attentionOpacity(0) == 1, 'the dim starts from full');
  _expect(reduced.attentionOpacity(0.4) == 1, 'the dim is over with the hop');
  _expect(reduced.attentionOpacity(0.9) == 1, 'the rest is at full opacity');
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
