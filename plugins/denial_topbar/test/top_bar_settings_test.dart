import 'package:denial_topbar/src/top_bar_settings.dart';

void main() {
  const defaults = TopBarSettings.defaults;
  _expect(defaults.appearance == TopBarAppearance.attached, 'edge by default');
  _expect(defaults.islandEnabled, 'island on by default');
  _expect(defaults.clockPlacement == TopBarSlot.island, 'clock in island');
  _expect(defaults.mediaPlacement == TopBarSlot.island, 'media in island');
  _expect(
    defaults.notificationPlacement == TopBarSlot.trailing,
    'notifications stay in the bar',
  );
  _expect(!defaults.activityNotifications, 'host banners stay in charge');

  final json = <String, dynamic>{
    'appearance': 'segmented',
    'islandEnabled': false,
    'islandStyle': 'theme',
    'islandAutoCollapseSeconds': 99,
    'clockPlacement': 'leading',
    'mediaPlacement': 'trailing',
    'showBatteryPercent': true,
    'futureKey': 7,
  };
  final parsed = TopBarSettings.fromJson(json);
  _expect(parsed.appearance == TopBarAppearance.segmented, 'appearance parses');
  _expect(!parsed.islandEnabled, 'switch parses');
  _expect(parsed.islandStyle == TopBarIslandStyle.theme, 'style parses');
  _expect(parsed.islandAutoCollapseSeconds == 10, 'auto collapse clamps');
  _expect(parsed.clockPlacement == TopBarSlot.leading, 'slot parses');
  _expect(parsed.mediaPlacement == TopBarSlot.trailing, 'media slot parses');
  _expect(parsed.showBatteryPercent, 'new switch parses');

  parsed.writeJson(json);
  _expect(json['futureKey'] == 7, 'unknown keys survive');
  _expect(json['appearance'] == 'segmented', 'keys rewrite');
  _expect(json['clockPlacement'] == 'leading', 'slots rewrite');

  final broken = TopBarSettings.fromJson(<String, dynamic>{
    'appearance': 'nonsense',
    'clockPlacement': 'nonsense',
    'islandAutoCollapseSeconds': 'fast',
    'showTray': 'yes',
  });
  _expect(
    broken.appearance == TopBarAppearance.attached,
    'bad appearance falls back',
  );
  _expect(broken.clockPlacement == TopBarSlot.island, 'bad slot falls back');
  _expect(
    broken.islandAutoCollapseSeconds == topBarDefaultAutoCollapse,
    'bad collapse falls back',
  );
  _expect(broken.showTray, 'bad switch falls back');

  _expect(
    defaults.resolveSlot(TopBarSlot.island, islandAvailable: false) ==
        TopBarSlot.trailing,
    'island falls back to the bar',
  );
  _expect(
    defaults.resolveSlot(TopBarSlot.leading, islandAvailable: false) ==
        TopBarSlot.leading,
    'other slots stay',
  );
}

void _expect(bool condition, String label) {
  if (!condition) throw StateError('failed: $label');
}
