import 'dart:io';

import 'package:denial_topbar/src/island/island_shape.dart';

/// The rules the island's motion per look is built from. Only a liquid look
/// may pass a target; every other one settles dead-beat.
void main() {
  for (final ratio in <double>[0.42, 0.55, 0.72, 0.9]) {
    _expect(
      islandDamping(ratio, liquid: true) == ratio,
      'a liquid look keeps its overshoot',
    );
    _expect(
      islandDamping(ratio, liquid: false) == 1,
      'no other look passes a target',
    );
  }
  _expect(islandDamping(1.3, liquid: false) == 1.3, 'overdamped stays so');

  // The panel springs the four looks open on.
  _expect(islandPace(620) == 1, 'an ordinary panel, an ordinary island');
  _expect(islandPace(1100) > 1.5, 'a brisk look has a brisk island');
  _expect(islandPace(520) < 1, 'a calm one a calmer island');
  _expect(islandPace(50) == 0.6 && islandPace(9000) == 2.4, 'within bounds');

  stdout.writeln('All island look tests passed.');
}

void _expect(bool condition, String message) {
  if (!condition) {
    stderr.writeln('FAILED: $message');
    exit(1);
  }
}
