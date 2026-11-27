import 'dart:io';

import 'package:denial_shell_kit/kit_perf_math.dart';

void _expect(bool ok, String what) {
  if (!ok) throw StateError(what);
}

void main() {
  final empty = kitPerfSummarize(const <KitPerfSample>[], durationMs: 30000);
  _expect(empty['frames'] == 0, 'empty has 0 frames');
  _expect(empty['buildP95Ms'] == 0.0, 'empty p95 is 0');
  _expect(empty['over8_3ms'] == 0 && empty['over16_7ms'] == 0, 'empty overruns 0');

  final samples = <KitPerfSample>[
    (buildMs: 1.0, rasterMs: 2.0, totalMs: 3.0),
    (buildMs: 2.0, rasterMs: 3.0, totalMs: 5.0),
    (buildMs: 3.0, rasterMs: 4.0, totalMs: 7.0),
    (buildMs: 5.0, rasterMs: 9.0, totalMs: 14.0),
    (buildMs: 10.0, rasterMs: 12.0, totalMs: 22.0),
  ];
  final report = kitPerfSummarize(samples, durationMs: 5000);
  _expect(report['frames'] == 5, 'frame count');
  _expect(report['buildP50Ms'] == 3.0, 'build p50');
  _expect(report['buildMaxMs'] == 10.0, 'build max');
  _expect(report['rasterP50Ms'] == 4.0, 'raster p50');
  _expect(report['rasterMaxMs'] == 12.0, 'raster max');
  _expect(report['over8_3ms'] == 2, '2 frames over 8.33ms');
  _expect(report['over16_7ms'] == 1, '1 frame over 16.67ms');
  stdout.writeln('All kit perf math tests passed.');
}
