import 'dart:io';

import 'package:denial_topbar/src/signal.dart';

void main() {
  // shell27's thresholds: > 66 draws all three arcs, > 33 two, else one.
  _expect(wifiSignalArcs(100) == 3, 'full strength');
  _expect(wifiSignalArcs(67) == 3, 'just above the top threshold');
  _expect(wifiSignalArcs(66) == 2, 'at the top threshold');
  _expect(wifiSignalArcs(50) == 2, 'mid strength');
  _expect(wifiSignalArcs(34) == 2, 'just above the low threshold');
  _expect(wifiSignalArcs(33) == 1, 'at the low threshold');
  _expect(wifiSignalArcs(0) == 1, 'no signal still draws the base arc');
  stdout.writeln('All signal tests passed.');
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
