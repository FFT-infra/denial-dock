import 'package:denial_shell_kit/kit_look_motion.dart';
import 'package:denial_topbar/src/panels/nc_motion.dart';

void _expect(bool ok, String what) {
  if (!ok) throw StateError(what);
}

void main() {
  // The notification centre keeps a plain and a liquid tuning for each of
  // its moves. The plain ones serve every look that is not liquid, so they
  // must be dead-beat; the liquid ones are the only ones allowed life.
  const plain = <String, NcTuning>{
    'slide': NcMotion.slide,
    'gap': NcMotion.gap,
    'unfold': NcMotion.unfold,
    'rebound': NcMotion.rebound,
  };
  for (final entry in plain.entries) {
    _expect(
      entry.value.dampingRatio >= 1,
      '${entry.key} settles without overshoot',
    );
  }
  _expect(NcMotion.gapLiquid.dampingRatio < 1, 'the liquid gap has life');
  _expect(NcMotion.unfoldLiquid.dampingRatio < 1, 'the liquid fan has life');

  // Run through a look, even a liquid tuning lands dead-beat outside
  // Denial.
  for (final look in KitLookMotion.presets) {
    for (final tuning in <NcTuning>[
      NcMotion.gapLiquid,
      NcMotion.unfoldLiquid,
    ]) {
      final run = look.settled(
        KitSpringTuning(tuning.stiffness, tuning.dampingRatio),
      );
      _expect(
        look.liquid ? run.dampingRatio < 1 : run.dampingRatio >= 1,
        'a look decides whether a spring may overshoot',
      );
    }
  }
}
