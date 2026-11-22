import 'package:denial_topbar/src/island/island_activity.dart';

void main() {
  IslandActivity resolve({
    bool mediaEnabled = true,
    bool mediaAvailable = true,
    bool chargingEnabled = true,
    bool charging = true,
    bool notificationsEnabled = true,
    bool notification = true,
  }) {
    return resolveIslandActivity(
      mediaEnabled: mediaEnabled,
      mediaAvailable: mediaAvailable,
      chargingEnabled: chargingEnabled,
      charging: charging,
      notificationsEnabled: notificationsEnabled,
      notification: notification,
    );
  }

  _expect(
    resolve() == IslandActivity.notification,
    'a fresh notification wins',
  );
  _expect(
    resolve(notification: false) == IslandActivity.media,
    'playback beats the charger',
  );
  _expect(
    resolve(notification: false, mediaAvailable: false) ==
        IslandActivity.charging,
    'the charger fills the gap',
  );
  _expect(
    resolve(notification: false, mediaAvailable: false, charging: false) ==
        IslandActivity.quiet,
    'nothing active',
  );
  _expect(
    resolve(notificationsEnabled: false) == IslandActivity.media,
    'disabled notifications hand over',
  );
  _expect(
    resolve(mediaEnabled: false, notification: false) ==
        IslandActivity.charging,
    'disabled media hands over',
  );
  _expect(
    resolve(mediaEnabled: false, chargingEnabled: false, notification: false) ==
        IslandActivity.quiet,
    'everything disabled',
  );
}

void _expect(bool condition, String label) {
  if (!condition) throw StateError('failed: $label');
}
