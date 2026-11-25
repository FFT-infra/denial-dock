import 'package:denial_dock/src/dock_spring.dart';

void main() {
  // A liquid spring runs past its target once and comes home; the value is
  // zero before it starts and exactly one once it has settled.
  final bouncy = DockSpring(stiffness: 420, dampingRatio: 0.62);
  _expect(bouncy.at(0) == 0 && bouncy.at(-1) == 0, 'nothing before the step');
  _expect(bouncy.at(bouncy.seconds) == 1, 'settled is exactly one');
  _expect(bouncy.at(10) == 1, 'and stays there');
  var peak = 0.0;
  var last = 0.0;
  for (var t = 0.0; t < bouncy.seconds; t += 1 / 240) {
    final value = bouncy.at(t);
    _expect(value.isFinite, 'finite at $t');
    if (value > peak) peak = value;
    last = value;
  }
  _expect(peak > 1.02 && peak < 1.15, 'one modest overshoot: $peak');
  _expect((last - 1).abs() <= bouncy.tolerance * 1.5, 'no jump at the end');
  _expect(
    bouncy.seconds > 0.3 && bouncy.seconds < 0.7,
    'settles in about half a second: ${bouncy.seconds}',
  );

  // A critically damped spring never passes its target, which is what lets a
  // card fold back onto its icon without dipping past it.
  for (final ratio in const [1.0, 1.4]) {
    final plain = DockSpring(stiffness: 420, dampingRatio: ratio);
    var before = 0.0;
    for (var t = 0.0; t <= plain.seconds; t += 1 / 240) {
      final value = plain.at(t);
      _expect(value <= 1 && value >= before - 1e-12, 'monotonic at $t');
      before = value;
    }
    _expect(plain.at(plain.seconds) == 1, 'ratio $ratio settles');
    _expect(plain.seconds < 3, 'ratio $ratio settles in time');
  }

  // A stiffer spring is a faster one.
  _expect(
    DockSpring(stiffness: 900, dampingRatio: 1).seconds <
        DockSpring(stiffness: 420, dampingRatio: 1).seconds,
    'stiffness shortens the settle',
  );
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
