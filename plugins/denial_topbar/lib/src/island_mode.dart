/// What the island is currently showing.
///
/// Kept free of Flutter imports so the priority rule can be tested on the plain
/// Dart VM.
enum IslandMode {
  /// Nothing happening: the clock, or a small dot when the clock lives
  /// elsewhere in the bar.
  quiet,
  media,
  notice,

  /// The charger went in or out. macOS shows this every time with no switch to
  /// turn it off [S28], so it outranks playback for the few seconds it lasts.
  charging;

  bool get isQuiet => this == IslandMode.quiet;
}

/// Ports revo-shell `DynamicIsland.qml`'s priority: a fresh notification wins
/// over everything, then the charge flash, then playback, then nothing.
IslandMode resolveIslandMode({
  required bool mediaEnabled,
  required bool mediaPlaying,
  required bool notificationsEnabled,
  required bool hasNotice,
  bool charging = false,
}) {
  if (notificationsEnabled && hasNotice) return IslandMode.notice;
  if (charging) return IslandMode.charging;
  if (mediaEnabled && mediaPlaying) return IslandMode.media;
  return IslandMode.quiet;
}
