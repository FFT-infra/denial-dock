import 'dart:io';

import 'package:denial_topbar/src/bar_segments.dart';

void _expect(bool cond, String msg) {
  if (!cond) {
    stderr.writeln('FAIL: $msg');
    exitCode = 1;
  }
}

void main() {
  final depth = barArrowDepth(32);
  // Horizontal segment outline
  final h = barSegmentOutline(
    width: 100,
    height: 32,
    depth: depth,
    left: BarEdge.flat,
    right: BarEdge.point,
  );
  _expect(h.length == 6, 'horizontal outline has 6 vertices');
  _expect(h[2].x == 100 && h[2].y == 16, 'horizontal point tip at right middle');

  // Vertical segment outline (left=top, right=bottom)
  final v = barSegmentOutline(
    width: 32,
    height: 100,
    depth: depth,
    left: BarEdge.flat,
    right: BarEdge.point,
    horizontal: false,
  );
  _expect(v.length == 6, 'vertical outline has 6 vertices');
  _expect(v[4].x == 16 && v[4].y == 100, 'vertical point tip at bottom middle');
  _expect(v[3].y < 100 && v[5].y < 100, 'vertical point corners inset upward');

  // Multi-segment end zone edges face toward center (leftward / upward)
  final endEdges = barZoneEdges(2, 4);
  _expect(endEdges.length == 4, '4 end segments');
  _expect(endEdges.first.left == BarEdge.point, 'first end segment points inward');
  _expect(endEdges.last.right == BarEdge.flat, 'last end segment flush to edge');

  if (exitCode == 0) {
    stdout.writeln('All bar segments horizontal & vertical tests passed.');
  }
}
