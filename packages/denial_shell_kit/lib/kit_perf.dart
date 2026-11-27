import 'dart:convert';
import 'dart:io';

import 'package:flutter/scheduler.dart';

import 'kit_perf_math.dart';

export 'kit_perf_math.dart' show KitPerfSample, kitPerfSummarize;

/// On-demand frame timing probe driven strictly by debug commands (`perf start`
/// / `perf stop`). Adds zero overhead while inactive.
abstract final class KitPerfProbe {
  static bool _active = false;
  static DateTime? _startedAt;
  static final List<KitPerfSample> _samples = <KitPerfSample>[];

  static bool get active => _active;

  static void start() {
    _samples.clear();
    _startedAt = DateTime.now();
    if (!_active) {
      _active = true;
      SchedulerBinding.instance.addTimingsCallback(_onTimings);
    }
  }

  static Map<String, Object?> stop() {
    if (_active) {
      _active = false;
      SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    }
    final durationMs = _startedAt == null
        ? 0
        : DateTime.now().difference(_startedAt!).inMilliseconds;
    final report = kitPerfSummarize(_samples, durationMs: durationMs);
    _samples.clear();
    _startedAt = null;
    _writeReport(report);
    return report;
  }

  static void _onTimings(List<FrameTiming> timings) {
    if (!_active) return;
    for (final timing in timings) {
      _samples.add((
        buildMs: timing.buildDuration.inMicroseconds / 1000.0,
        rasterMs: timing.rasterDuration.inMicroseconds / 1000.0,
        totalMs: timing.totalSpan.inMicroseconds / 1000.0,
      ));
    }
  }

  static File? outputFile() {
    final env = Platform.environment;
    final cache = env['XDG_CACHE_HOME'];
    final home = env['HOME'];
    final root = cache != null && cache.startsWith('/')
        ? cache
        : home != null && home.startsWith('/')
        ? '$home/.cache'
        : null;
    return root == null ? null : File('$root/denial_shell_kit/perf.json');
  }

  static void _writeReport(Map<String, Object?> report) {
    final file = outputFile();
    if (file == null) return;
    try {
      file.parent.createSync(recursive: true);
      final temp = File('${file.path}.$pid.tmp')
        ..writeAsStringSync(
          '${const JsonEncoder.withIndent('  ').convert(report)}\n',
        );
      temp.renameSync(file.path);
    } on FileSystemException {
      return;
    }
  }
}
