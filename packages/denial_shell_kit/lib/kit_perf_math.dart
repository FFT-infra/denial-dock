import 'dart:math' as math;

/// Sample of a single frame's build, raster, and total durations in ms.
typedef KitPerfSample = ({double buildMs, double rasterMs, double totalMs});

/// Summarizes [samples] into p50/p95/max percentiles and 120Hz/60Hz budget
/// overrun counts.
Map<String, Object?> kitPerfSummarize(
  List<KitPerfSample> samples, {
  required int durationMs,
}) {
  final builds = <double>[for (final s in samples) s.buildMs]..sort();
  final rasters = <double>[for (final s in samples) s.rasterMs]..sort();
  final totals = <double>[for (final s in samples) s.totalMs]..sort();
  var over83 = 0;
  var over167 = 0;
  for (final s in samples) {
    final frameMs = math.max(s.buildMs, s.rasterMs);
    if (frameMs > 8.333 || s.totalMs > 8.333) over83++;
    if (frameMs > 16.667 || s.totalMs > 16.667) over167++;
  }
  return <String, Object?>{
    'durationMs': durationMs,
    'frames': samples.length,
    'buildP50Ms': _percentile(builds, 0.50),
    'buildP95Ms': _percentile(builds, 0.95),
    'buildMaxMs': builds.isEmpty ? 0.0 : _round2(builds.last),
    'rasterP50Ms': _percentile(rasters, 0.50),
    'rasterP95Ms': _percentile(rasters, 0.95),
    'rasterMaxMs': rasters.isEmpty ? 0.0 : _round2(rasters.last),
    'totalP50Ms': _percentile(totals, 0.50),
    'totalP95Ms': _percentile(totals, 0.95),
    'totalMaxMs': totals.isEmpty ? 0.0 : _round2(totals.last),
    'over8_3ms': over83,
    'over16_7ms': over167,
  };
}

double _percentile(List<double> sorted, double q) {
  if (sorted.isEmpty) return 0.0;
  final idx = ((sorted.length - 1) * q).round().clamp(0, sorted.length - 1);
  return _round2(sorted[idx]);
}

double _round2(double v) => (v * 100).round() / 100.0;
