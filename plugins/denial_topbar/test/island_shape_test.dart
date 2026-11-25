import 'dart:io';
import 'dart:math' as math;

import 'package:denial_topbar/src/island/island_shape.dart';

void main() {
  _expect(islandNeck(0) == 1, 'merged, the neck is the whole bubble');
  _expect(islandNeck(0.45) == 1, 'it holds until nearly half way');
  _expect(islandNeck(1) == 0, 'and lets go as the bubble arrives');
  _expect(islandNeck(1.2) == 0, 'an overshooting bubble is free');
  var last = 1.0;
  for (var i = 0; i <= 20; i++) {
    final neck = islandNeck(i / 20);
    _expect(neck <= last && neck >= 0, 'the neck only thins');
    last = neck;
  }

  _expect(islandBubbleOffset(0, 28, 6) == -28, 'the bubble starts inside');
  _expect(islandBubbleOffset(1, 28, 6) == 6, 'and ends a gap away');

  _expect(islandOpenShare(28, 28, 172) == 0, 'the pill is not open');
  _expect(islandOpenShare(100, 28, 172) == 0.5, 'half way is half');
  _expect(islandOpenShare(172, 28, 172) == 1, 'the card is open');
  _expect(islandOpenShare(200, 28, 172) == 1, 'an overshoot is still open');
  _expect(islandOpenShare(20, 28, 172) == 0, 'an undershoot is still shut');
  _expect(islandOpenShare(50, 28, 28) == 0, 'a card no taller never opens');

  _expect(islandRubber(0.5) == 0.5, 'inside its travel a drag is exact');
  final over = islandRubber(1.5);
  _expect(over > 1 && over < 1.25, 'past the end it gives a little');
  final under = islandRubber(-0.5);
  _expect(under < 0 && under > -0.25, 'and before the start');

  _expect(islandSwipeStep(-40, 0) == 1, 'a slow drag left turns forward');
  _expect(islandSwipeStep(40, 0) == -1, 'a slow drag right turns back');
  _expect(islandSwipeStep(10, 0) == 0, 'a short one does nothing');
  _expect(islandSwipeStep(-5, -300) == 1, 'a flick counts by its speed');
  _expect(islandSwipeStep(5, 300) == -1, 'either way');


  _expect(islandFaceShare(0, 0) == 1, 'the pill shows its face');
  _expect(islandFaceShare(0.45, 0) == 0, 'which leaves first');
  _expect(islandFaceShare(0, 0.6) == 0, 'and waits for a closing outline');
  _expect(islandCardShare(1, 1) == 1, 'an open card shows in full');
  _expect(islandCardShare(1, 0.1) == 0, 'not through a closed outline');
  _expect(islandCardShare(0.3, 1) == 0, 'nor before the face has gone');
  for (var i = 0; i <= 20; i++) {
    final share = i / 20;
    _expect(
      islandFaceShare(share, 0) == 0 || islandCardShare(share, 1) < 0.2,
      'the face and the card never show together',
    );
  }
  _expect(islandHoldsOutline(1) && !islandHoldsOutline(0.5), 'card leaves first');
  _expect(islandEase(0) == 0 && islandEase(1) == 1, 'eased ends');
  _expect(islandEase(0.5) == 0.5, 'and an even middle');
  final slow = islandChargeStiffness(0.28, 1);
  _expect(slow > 400 && slow < 520, 'a held press charges in its own time');
  _expect(islandChargeStiffness(0.28, 2) < slow, 'whatever the clock runs at');


  for (final damping in <double>[0.45, 0.62, 1, 1.4]) {
    _expect(islandSpringCurve(0, damping) == 0, 'the curve starts at rest');
    _expect(islandSpringCurve(1, damping) == 1, 'and lands exactly');
    var peak = 0.0;
    for (var i = 0; i <= 100; i++) {
      peak = math.max(peak, islandSpringCurve(i / 100, damping));
    }
    _expect(
      damping >= 1 ? peak <= 1.0005 : peak > 1.02 && peak < 1.3,
      'only a loose spring passes its target ($damping: $peak)',
    );
  }

  stdout.writeln('All island shape tests passed.');
}

void _expect(bool condition, String message) {
  if (!condition) {
    stderr.writeln('FAILED: $message');
    exit(1);
  }
}
