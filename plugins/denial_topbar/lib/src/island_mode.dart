/// What the island is currently showing.
///
/// Kept free of Flutter imports so the priority rule can be tested on the plain
/// Dart VM.
enum IslandMode {
  /// Nothing happening: the clock, or a small dot when the clock lives
  /// elsewhere in the bar.
  quiet,
  media,
  notice;

  bool get isQuiet => this == IslandMode.quiet;
}

/// Ports revo-shell `DynamicIsland.qml`'s priority: a fresh notification wins
/// over playback, playback wins over nothing.
IslandMode resolveIslandMode({
  required bool mediaEnabled,
  required bool mediaPlaying,
  required bool notificationsEnabled,
  required bool hasNotice,
}) {
  if (notificationsEnabled && hasNotice) return IslandMode.notice;
  if (mediaEnabled && mediaPlaying) return IslandMode.media;
  return IslandMode.quiet;
}
