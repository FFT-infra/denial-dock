import 'package:denial_dock/src/dock_spring.dart';
import 'package:denial_shell_kit/kit_look_motion.dart';

void _expect(bool ok, String what) {
  if (!ok) throw StateError(what);
}

double _peak(DockSpring spring) {
  var peak = 0.0;
  for (var t = 0.0; t <= spring.seconds + 0.1; t += 1 / 240) {
    final v = spring.at(t);
    if (v > peak) peak = v;
  }
  return peak;
}

DockSpring _spring(KitSpringTuning tuning) =>
    DockSpring(stiffness: tuning.stiffness, dampingRatio: tuning.dampingRatio);

void main() {
  // The stack's rows leave the pile on a spring written with an overshoot.
  // Through a look that is not liquid no row passes its place, and every
  // look brings them home on its shrink spring, which never does.
  const out = KitSpringTuning(420, 0.62);
  for (final look in KitLookMotion.presets) {
    final run = _spring(look.settled(out));
    if (look.liquid) {
      _expect(_peak(run) > 1.01, 'a liquid row runs past its place');
    } else {
      _expect(_peak(run) <= 1.0, 'a row lands without passing its place');
    }
    _expect(_peak(_spring(look.panelShrink)) <= 1.0, 'a row folds dead-beat');
    // The cascade stays short enough to feel like one gesture.
    _expect(run.seconds > 0 && run.seconds < 1, 'a row settles within 1 s');
  }
}
