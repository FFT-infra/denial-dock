import 'package:denial_shell_kit/kit_panel_style.dart';
import 'package:denial_shell_kit/kit_widgets.dart';

void _expect(bool condition, String label) {
  if (!condition) throw StateError('FAIL: $label');
}

void main() {
  // Panel & widget style parsing.
  for (final style in KitPanelStyle.values) {
    _expect(
      KitPanelStyle.tryParse(style.name) == style,
      'KitPanelStyle round-trip ${style.name}',
    );
  }
  _expect(KitPanelStyle.tryParse('bogus') == null, 'invalid panel style');
  _expect(
    KitWidgetStyle.tryParse('glass') == KitWidgetStyle.glass &&
        KitWidgetStyle.tryParse('color') == KitWidgetStyle.color,
    'KitWidgetStyle round-trip',
  );

  // Registry builtins cover core macOS + NextKDE widgets.
  final reg = KitWidgetRegistry();
  for (final id in <String>[
    'calendar',
    'clock',
    'worldclock',
    'battery',
    'cpu',
    'media',
    'timer',
    'reminders',
    'quickactions',
  ]) {
    _expect(reg.byId(id) != null, 'builtin widget $id registered');
  }

  // Size clamping & cycling.
  final cal = reg.byId('calendar')!;
  _expect(cal.supportedSizes.length == 3, 'calendar supports S/M/L');
  _expect(
    cal.nextSize(KitWidgetSize.small) == KitWidgetSize.medium,
    'S -> M cycle',
  );
  _expect(
    cal.nextSize(KitWidgetSize.medium) == KitWidgetSize.large,
    'M -> L cycle',
  );
  _expect(
    cal.nextSize(KitWidgetSize.large) == KitWidgetSize.small,
    'L -> S cycle',
  );

  // Magnetic corner resize snapping (NextKDE style).
  final snapMedium = snapWidgetResize(
    current: KitWidgetSize.small,
    supported: cal.supportedSizes,
    dx: 100,
    dy: 10,
    cell: 164,
    gap: 12,
  );
  _expect(snapMedium == KitWidgetSize.medium, 'drag right snaps S -> M');

  final snapLarge = snapWidgetResize(
    current: KitWidgetSize.small,
    supported: cal.supportedSizes,
    dx: 110,
    dy: 110,
    cell: 164,
    gap: 12,
  );
  _expect(snapLarge == KitWidgetSize.large, 'drag down-right snaps S -> L');

  final snapBackSmall = snapWidgetResize(
    current: KitWidgetSize.large,
    supported: cal.supportedSizes,
    dx: -140,
    dy: -140,
    cell: 164,
    gap: 12,
  );
  _expect(snapBackSmall == KitWidgetSize.small, 'drag up-left snaps L -> S');

  // Custom widget registration & JSON round-trip.
  final id = reg.freshCustomId('Disk Usage');
  _expect(id == 'custom.disk_usage', 'freshCustomId slug');
  final def = KitCustomWidgetDef(
    id: id,
    title: 'Disk Usage',
    kind: KitCustomWidgetKind.command,
    command: 'df -h / | tail -1',
    refreshSeconds: 60,
  );
  reg.registerCustom(def);
  _expect(reg.byId(id)?.isCustom == true, 'custom widget registered');
  final exported = reg.exportCustomJson();
  final reg2 = KitWidgetRegistry()..loadCustomJson(exported);
  final restored = reg2.byId(id);
  _expect(
    restored != null &&
        restored.custom!.command == 'df -h / | tail -1' &&
        restored.custom!.refreshSeconds == 60,
    'custom widget JSON round-trip',
  );
  reg2.removeCustom(id);
  _expect(reg2.byId(id) == null, 'custom widget removed');
}
