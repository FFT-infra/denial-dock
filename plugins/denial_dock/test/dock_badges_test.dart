import 'package:denial_dock/src/dock_badges.dart';

void main() {
  const entries = <DockBadgeEntry>[
    (
      key: 'google-chrome',
      appId: 'google-chrome.desktop',
      launchId: 'google-chrome.desktop',
      name: 'Chrome',
    ),
    (
      key: 'md.obsidian.obsidian',
      appId: 'md.obsidian.Obsidian.desktop',
      launchId: 'desktop:md.obsidian.Obsidian.desktop',
      name: 'Obsidian',
    ),
    (
      key: 'com.mitchellh.ghostty',
      appId: 'com.mitchellh.ghostty.desktop',
      launchId: 'com.mitchellh.ghostty.desktop',
      name: 'Ghostty',
    ),
  ];

  Map<String, int> counts(List<DockBadgeNotification> notifications) =>
      DockBadges.counts(notifications, entries);

  // The desktop-entry hint is matched against every identity an entry has, so
  // a notification may name the desktop file, the launch id or the app name.
  final byDesktopEntry = counts([
    (desktopEntry: 'google-chrome.desktop', appName: 'Chrome', unread: true),
    (desktopEntry: 'google-chrome', appName: 'Chrome', unread: true),
  ]);
  _expect(byDesktopEntry['google-chrome'] == 2, 'desktop entry match');

  final byLaunchId = counts([
    (
      desktopEntry: 'desktop:md.obsidian.Obsidian.desktop',
      appName: '',
      unread: true,
    ),
  ]);
  _expect(byLaunchId['md.obsidian.obsidian'] == 1, 'launch id match');

  // Senders that omit the hint fall back to the application name.
  final byName = counts([
    (desktopEntry: '', appName: 'Ghostty', unread: true),
    (desktopEntry: '', appName: 'ghostty', unread: true),
  ]);
  _expect(byName['com.mitchellh.ghostty'] == 2, 'name fallback');

  // A hint that matches nothing does not fall back to the name.
  final noFallback = counts([
    (desktopEntry: 'some-other.desktop', appName: 'Ghostty', unread: true),
    (desktopEntry: '', appName: 'Chrome', unread: true),
  ]);
  _expect(noFallback['com.mitchellh.ghostty'] == null, 'hint wins over name');
  _expect(noFallback['google-chrome'] == 1, 'name only matches name');

  // Read notifications and unknown applications are not counted.
  final filtered = counts([
    (desktopEntry: 'google-chrome.desktop', appName: 'Chrome', unread: false),
    (desktopEntry: 'unknown.desktop', appName: 'Unknown', unread: true),
  ]);
  _expect(filtered.isEmpty, 'unread and known only');

  print('All dock badge tests passed.');
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
