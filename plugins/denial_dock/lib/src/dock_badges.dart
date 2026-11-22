import 'dock_settings.dart' show normalizeAppId;

/// One unread notification, reduced to the fields a badge needs.
typedef DockBadgeNotification = ({
  String desktopEntry,
  String appName,
  bool unread,
});

/// One dock entry's identities. [key] is the map key the caller looks up.
typedef DockBadgeEntry = ({
  String key,
  String appId,
  String? launchId,
  String name,
});

/// Counts unread notifications per dock entry. A notification names its
/// application through `desktop-entry`; senders that omit it fall back to the
/// application name, the same way the reference dock groups notifications.
abstract final class DockBadges {
  static Map<String, int> counts(
    Iterable<DockBadgeNotification> notifications,
    Iterable<DockBadgeEntry> entries,
  ) {
    final counts = <String, int>{};
    for (final notification in notifications) {
      if (!notification.unread) continue;
      final entry = _match(notification, entries);
      if (entry == null) continue;
      counts[entry.key] = (counts[entry.key] ?? 0) + 1;
    }
    return counts;
  }

  static DockBadgeEntry? _match(
    DockBadgeNotification notification,
    Iterable<DockBadgeEntry> entries,
  ) {
    final desktopEntry = normalizeAppId(notification.desktopEntry);
    final appName = normalizeAppId(notification.appName);
    for (final entry in entries) {
      final identities = <String>{
        normalizeAppId(entry.appId),
        if (entry.launchId case final launchId?) normalizeAppId(launchId),
        normalizeAppId(entry.name),
      };
      if (desktopEntry.isNotEmpty && identities.contains(desktopEntry)) {
        return entry;
      }
      if (desktopEntry.isEmpty && identities.contains(appName)) return entry;
    }
    return null;
  }
}
