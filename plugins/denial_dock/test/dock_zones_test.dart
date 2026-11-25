import 'dart:convert';
import 'dart:io';

import 'package:denial_dock/src/dock_layout.dart';
import 'package:denial_dock/src/dock_look.dart';
import 'package:denial_dock/src/dock_sections.dart';
import 'package:denial_dock/src/dock_settings.dart';

Future<void> main() async {
  // Settings that never had zones draw what the side settings always drew.
  const defaults = DockSettings.defaults;
  _expect(defaults.explicitZones == null, 'no zones stored by default');
  _expect(
    defaults.zones ==
        const DockZones(
          leading: [DockPart.launcher],
          trailing: [DockPart.stacks, DockPart.trash],
        ),
    'default zones ${defaults.zones}',
  );
  _expect(
    const DockSettings(
          launcherSide: DockSide.right,
          extrasSide: DockSide.left,
          showTrash: false,
        ).zones ==
        const DockZones(
          leading: [DockPart.stacks],
          trailing: [DockPart.launcher],
        ),
    'sides swapped, no trash',
  );
  _expect(
    const DockSettings(
          launcherSide: DockSide.left,
          extrasSide: DockSide.left,
        ).zones ==
        const DockZones(
          leading: [DockPart.launcher, DockPart.stacks, DockPart.trash],
        ),
    'the launcher leads its side',
  );
  _expect(
    const DockSettings(
          launcherSide: DockSide.right,
          extrasSide: DockSide.right,
        ).zones ==
        const DockZones(
          trailing: [DockPart.stacks, DockPart.trash, DockPart.launcher],
        ),
    'the launcher ends its side',
  );
  _expect(
    const DockSettings(
      launcherSide: DockSide.hidden,
      extrasSide: DockSide.hidden,
    ).zones.parts.isEmpty,
    'both hidden',
  );

  // Cleaning: unknown ids of the dock go, another plugin's stay, a part
  // that may appear once appears once, a divider as often as it likes.
  final cleaned = DockZones.stored(
    ['dock.launcher', 'dock.nope', 'clock', 3, '', 'dock.divider', 'clock'],
    ['dock.launcher', 'dock.divider', 'status', 'dock.trash'],
    fallback: const DockZones(),
  );
  _expect(
    cleaned ==
        const DockZones(
          leading: ['dock.launcher', 'clock', 'dock.divider'],
          trailing: ['dock.divider', 'status', 'dock.trash'],
        ),
    'cleaned $cleaned',
  );
  _expect(
    DockZones.stored(null, ['clock'], fallback: defaults.zones) ==
        const DockZones(leading: [DockPart.launcher], trailing: ['clock']),
    'a missing zone keeps the fallback',
  );

  // The layout a preset names lays over the settings and reads back.
  const taskbar = <String, Object?>{
    'leading': ['dock.launcher', 'workspaces'],
    'trailing': ['status.tray', 'status', 'clock'],
    'shape': 'bar',
    'align': 'start',
    'magnification': false,
    'visibility': 'always',
  };
  final applied = defaults
      .copyWith(iconSize: 40, look: const {'blur': 0.5})
      .withLayout(taskbar);
  _expect(_sameMap(applied.layoutJson('soft'), taskbar), 'taskbar reads back');
  _expect(applied.iconSize == 40, 'other settings stay');
  _expect(applied.look['blur'] == 0.5, 'other look overrides stay');
  _expect(applied.look[DockLook.shapeKey] == 'bar', 'the shape is an override');
  _expect(applied.launcherSide == DockSide.left, 'launcher side follows');
  _expect(applied.extrasSide == DockSide.hidden, 'no stacks, no extras side');
  _expect(applied.align == DockAlign.start, 'aligned to the start');

  // Going back to floating drops the override rather than pinning it.
  final floating = applied.withLayout(const {
    'shape': 'floating',
    'align': 'packed',
  });
  _expect(!floating.look.containsKey(DockLook.shapeKey), 'no shape override');
  _expect(floating.zones == applied.zones, 'zones untouched by other keys');
  _expect(floating.align == DockAlign.packed, 'packed again');

  // Values of the wrong kind change nothing.
  final odd = applied.withLayout(const {
    'leading': 'clock',
    'shape': 7,
    'magnification': 'yes',
    'visibility': 3,
  });
  _expect(_sameMap(odd.layoutJson('soft'), taskbar), 'odd values ignored');

  // Applying the usual dock's layout to defaults keeps what is drawn.
  const usual = <String, Object?>{
    'leading': ['dock.launcher'],
    'trailing': ['dock.stacks', 'dock.trash'],
    'shape': 'floating',
    'align': 'packed',
    'magnification': true,
    'visibility': 'smart',
  };
  final same = defaults.withLayout(usual);
  _expect(same.zones == defaults.zones, 'the usual layout is the default');
  _expect(
    same.launcherSide == DockSide.left &&
        same.extrasSide == DockSide.right &&
        same.showTrash,
    'side settings agree with it',
  );
  _expect(_sameMap(defaults.layoutJson('denial'), usual), 'defaults read so');

  // With zones stored, the older side settings move their own part only.
  final moved = applied.copyWith(launcherSide: DockSide.right);
  _expect(
    moved.zones ==
        const DockZones(
          leading: ['workspaces'],
          trailing: ['status.tray', 'status', 'clock', 'dock.launcher'],
        ),
    'launcher moved: ${moved.zones}',
  );
  final withTrash = applied.copyWith(extrasSide: DockSide.right);
  _expect(
    withTrash.zones.trailing.join(',') ==
        'dock.stacks,dock.trash,status.tray,status,clock',
    'extras join the inner end: ${withTrash.zones}',
  );
  _expect(
    withTrash.copyWith(showTrash: false).zones.trailing.join(',') ==
        'dock.stacks,status.tray,status,clock',
    'the trash goes alone',
  );
  _expect(
    applied.copyWith(iconSize: 52).zones == applied.zones,
    'other changes leave zones alone',
  );

  // The row: parts become slots of their own, dividers keep their place
  // inside a zone and vanish at its ends.
  List<String> row(DockSettings settings, int entries) => [
    for (final slot in DockSections.build(
      entryCount: entries,
      isPinned: (_) => true,
      settings: settings,
    ))
      switch (slot.kind) {
        DockSlotKind.app => 'app',
        DockSlotKind.launcher => 'launcher',
        DockSlotKind.folder => 'folder',
        DockSlotKind.file => 'file',
        DockSlotKind.trash => 'trash',
        DockSlotKind.divider => '|${slot.dividerKey}',
        DockSlotKind.part => slot.partId!,
      },
  ];
  final unified = defaults.withLayout(const {
    'leading': ['dock.divider', 'clock', 'dock.divider', 'dock.launcher'],
    'trailing': ['dock.stacks', 'dock.trash', 'dock.divider', 'status'],
  });
  _expect(
    row(unified, 2).join(' ') ==
        'clock |leading.1 launcher |leading app app |trailing trash '
            '|trailing.0 status',
    'unified row: ${row(unified, 2)}',
  );
  _expect(
    row(applied, 1).join(' ') ==
        'launcher workspaces |leading app |trailing status.tray status clock',
    'taskbar row: ${row(applied, 1)}',
  );
  final ends = DockSections.ends(entryCount: 1, settings: applied);
  _expect(ends.leading == 3 && ends.trailing == 4, 'ends $ends');
  final bare = DockSections.ends(entryCount: 0, settings: applied);
  _expect(bare.leading == 2 && bare.trailing == 3, 'ends with no apps $bare');

  // Saved and read back, zones and alignment survive; a dock that never
  // had them keeps a file without them.
  final dir = await Directory.systemTemp.createTemp('dock_zones_test');
  try {
    final store = DockPreferencesStore(File('${dir.path}/dock.json'));
    await store.write(defaults);
    final plain = jsonDecode(await store.file.readAsString()) as Map;
    _expect(
      !plain.containsKey('leading') &&
          !plain.containsKey('trailing') &&
          !plain.containsKey('align'),
      'no zone keys for an old dock',
    );
    _expect((await store.read()).explicitZones == null, 'still following');

    await store.write(applied);
    final back = await store.read();
    _expect(back.explicitZones == applied.zones, 'zones round-trip');
    _expect(back.align == DockAlign.start, 'alignment round-trips');
    _expect(_sameMap(back.layoutJson('soft'), taskbar), 'layout round-trips');

    await store.write(back.copyWith(align: DockAlign.packed));
    final again = jsonDecode(await store.file.readAsString()) as Map;
    _expect(!again.containsKey('align'), 'packed is not stored');
  } finally {
    await dir.delete(recursive: true);
  }

  // A bar that shares its edge out: ends at the ends, the rest between.
  final slots = [
    const DockSlot(half: 24),
    const DockSlot(half: 30, growable: false),
    const DockSlot(half: 0.5, growable: false),
    const DockSlot(half: 24),
    const DockSlot(half: 24),
    const DockSlot(half: 0.5, growable: false),
    const DockSlot(half: 50, growable: false),
  ];
  DockLayoutFrame lay(DockSpread? spread, {double hover = 0, double at = 0}) =>
      DockLayout.compute(
        surfaceExtent: 1000,
        slots: slots,
        padding: 10,
        gap: 8,
        pointer: at,
        hover: hover,
        maxScale: 1.6,
        radius: 140,
        spread: spread,
      );
  const start = DockSpread(leading: 3, trailing: 2, centered: false);
  const centre = DockSpread(leading: 3, trailing: 2, centered: true);
  final started = lay(start);
  _expect(
    started.capsuleStart == 0 && started.extent == 1000 && started.total == 0,
    'the bar is the edge',
  );
  _expect(started.slots[0].center == 34, 'first slot at the edge');
  _expect(started.slots[6].center == 940, 'last slot at the far edge');
  _expect(
    started.slots[3].center == started.slots[2].center + 0.5 + 8 + 24,
    'applications follow the leading end',
  );
  final centred = lay(centre);
  _expect(
    ((centred.slots[3].center + centred.slots[4].center) / 2 - 500).abs() <
        0.001,
    'applications in the middle',
  );
  _expect(
    centred.slots[0].center == started.slots[0].center &&
        centred.slots[6].center == started.slots[6].center,
    'the ends do not move with the alignment',
  );
  // Magnifying pushes only the applications; the ends and the bar stay.
  final grown = lay(centre, hover: 1, at: centred.slots[3].center);
  _expect(grown.slots[3].scale > 1.3, 'the hovered icon grows');
  _expect(
    grown.slots[1].scale == 1 && grown.slots[6].scale == 1,
    'parts do not grow',
  );
  _expect(
    grown.slots[0].center == centred.slots[0].center &&
        grown.slots[6].center == centred.slots[6].center &&
        grown.extent == 1000,
    'the ends hold while icons grow',
  );
  // No spread is the row as it always was.
  final packed = lay(null);
  _expect(packed.capsuleStart > 0 && packed.extent < 1000, 'packed is centred');
  // A row too long for its edge falls back to the packed one.
  final narrow = DockLayout.compute(
    surfaceExtent: 200,
    slots: slots,
    padding: 10,
    gap: 8,
    pointer: 0,
    hover: 0,
    maxScale: 1.6,
    radius: 140,
    spread: start,
  );
  _expect(narrow.extent > 200, 'too long: one packed group');
}

bool _sameMap(Map<String, Object?> a, Map<String, Object?> b) =>
    jsonEncode(a) == jsonEncode(b);

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
