/// What the island is currently showing.
///
/// Follows Apple's ActivityKit & Dynamic Island specification (as modeled in
/// `jackson-storm/DynamicNotch` and `Dtem4ik/meniscus`).
enum IslandMode {
  /// Nothing happening: the clock, or a minimal dot.
  quiet,

  /// Active playback: compact cover on the left, waveform on the right.
  media,

  /// Active notification banner with summary and close chip.
  notice,

  /// Transient charging event (2-3 seconds).
  charging,

  /// Transient HUD event (Volume / Brightness change).
  hud;

  bool get isQuiet => this == IslandMode.quiet;
}

/// Dynamic Island event priority dispatcher.
///
/// Priority hierarchy:
/// 1. Fresh notification (`notice`) wins over everything.
/// 2. Transient hardware event: `charging` flash.
/// 3. Transient user adjustment: `hud` (volume/brightness).
/// 4. Persistent Live Activity: `media` playback.
/// 5. Resting state: `quiet`.
IslandMode resolveIslandMode({
  required bool mediaEnabled,
  required bool mediaPlaying,
  required bool notificationsEnabled,
  required bool hasNotice,
  bool charging = false,
  bool hud = false,
}) {
  if (notificationsEnabled && hasNotice) return IslandMode.notice;
  if (charging) return IslandMode.charging;
  if (hud) return IslandMode.hud;
  if (mediaEnabled && mediaPlaying) return IslandMode.media;
  return IslandMode.quiet;
}
