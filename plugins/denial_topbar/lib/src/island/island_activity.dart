/// What the island is showing when nothing is being opened.
enum IslandActivity {
  quiet,
  media,
  charging,
  notification;

  bool get isQuiet => this == IslandActivity.quiet;
}

/// One activity wins at a time: a fresh notification, then playback, then the
/// charger. Workspace and volume feedback are transient and handled by the
/// widget's own flash timer.
IslandActivity resolveIslandActivity({
  required bool mediaEnabled,
  required bool mediaAvailable,
  required bool chargingEnabled,
  required bool charging,
  required bool notificationsEnabled,
  required bool notification,
}) {
  if (notificationsEnabled && notification) return IslandActivity.notification;
  if (mediaEnabled && mediaAvailable) return IslandActivity.media;
  if (chargingEnabled && charging) return IslandActivity.charging;
  return IslandActivity.quiet;
}
