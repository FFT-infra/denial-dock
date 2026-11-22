/// Maps a Wi-Fi strength percentage onto the three arcs of the bar glyph.
///
/// shell27 `MacBar.qml` uses `> 90 → 100`, `> 66 → 66`, `> 33 → 33`, else `0`.
/// The vendored icon font has no strength variants, so this returns an arc
/// count instead. Flutter-free so the thresholds can be tested on the plain
/// Dart VM.
int wifiSignalArcs(int strength) {
  if (strength > 66) return 3;
  if (strength > 33) return 2;
  return 1;
}
