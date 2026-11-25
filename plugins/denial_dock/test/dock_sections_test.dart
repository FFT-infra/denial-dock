import 'package:denial_dock/src/dock_sections.dart';
import 'package:denial_dock/src/dock_settings.dart';

void main() {
  const folderA = DockFolder(path: '/home/me/Documents', label: 'Documents');
  const folderB = DockFolder(path: '/home/me/Projects', label: 'Projects');

  List<String> layout(
    DockSettings settings, {
    required int entries,
    required Set<int> pinned,
  }) => [
    for (final slot in DockSections.build(
      entryCount: entries,
      isPinned: pinned.contains,
      settings: settings,
    ))
      switch (slot.kind) {
        DockSlotKind.app =>
          pinned.contains(slot.index) ? 'p${slot.index}' : 'r${slot.index}',
        DockSlotKind.launcher => 'launcher',
        DockSlotKind.folder => 'folder:${slot.folder!.label}',
        DockSlotKind.file => 'file:${slot.file!.label}',
        DockSlotKind.trash => 'trash',
        DockSlotKind.divider => 'divider:${slot.dividerKey}',
        DockSlotKind.part => 'part:${slot.partId}',
      },
  ];

  // Pinned and running: two dividers, launcher leading, trash last.
  _expect(
    _same(layout(DockSettings.defaults, entries: 3, pinned: {0, 1}), [
      'launcher',
      'divider:leading',
      'p0',
      'p1',
      'divider:pinned',
      'r2',
      'divider:trailing',
      'trash',
    ]),
    'basic ${layout(DockSettings.defaults, entries: 3, pinned: {0, 1})}',
  );

  // Nothing running: the pinned divider is omitted, the accessory one stays.
  _expect(
    _same(layout(DockSettings.defaults, entries: 2, pinned: {0, 1}), [
      'launcher',
      'divider:leading',
      'p0',
      'p1',
      'divider:trailing',
      'trash',
    ]),
    'no running',
  );

  // Nothing pinned: same rule on the other side.
  _expect(
    _same(layout(DockSettings.defaults, entries: 2, pinned: {}), [
      'launcher',
      'divider:leading',
      'r0',
      'r1',
      'divider:trailing',
      'trash',
    ]),
    'no pinned',
  );

  // Folders come before the trash inside the accessory group.
  const withExtras = DockSettings(folders: [folderA, folderB]);
  _expect(
    _same(layout(withExtras, entries: 3, pinned: {0}), [
      'launcher',
      'divider:leading',
      'p0',
      'divider:pinned',
      'r1',
      'r2',
      'divider:trailing',
      'folder:Documents',
      'folder:Projects',
      'trash',
    ]),
    'extras ${layout(withExtras, entries: 3, pinned: {0})}',
  );

  // Trash switched off with no folders: no accessory group, no divider.
  _expect(
    _same(
      layout(const DockSettings(showTrash: false), entries: 2, pinned: {0}),
      ['launcher', 'divider:leading', 'p0', 'divider:pinned', 'r1'],
    ),
    'trash off',
  );

  // Launcher on the trailing edge follows the accessories, as it does today.
  _expect(
    _same(
      layout(
        const DockSettings(launcherSide: DockSide.right),
        entries: 1,
        pinned: {0},
      ),
      ['p0', 'divider:trailing', 'trash', 'launcher'],
    ),
    'launcher right',
  );

  // Accessories on the leading edge keep the trash last inside their group.
  _expect(
    _same(
      layout(
        const DockSettings(extrasSide: DockSide.left, folders: [folderA]),
        entries: 1,
        pinned: {0},
      ),
      ['launcher', 'folder:Documents', 'trash', 'divider:leading', 'p0'],
    ),
    'extras left',
  );

  // Hiding the accessories and the launcher leaves just the applications.
  _expect(
    _same(
      layout(
        const DockSettings(
          launcherSide: DockSide.hidden,
          extrasSide: DockSide.hidden,
        ),
        entries: 1,
        pinned: {0},
      ),
      ['p0'],
    ),
    'apps only',
  );

  // A dock with nothing in it paints nothing at all.
  _expect(
    layout(
      const DockSettings(
        launcherSide: DockSide.hidden,
        extrasSide: DockSide.hidden,
      ),
      entries: 0,
      pinned: {},
    ).isEmpty,
    'empty dock',
  );

  // No applications but a launcher and a trash can: both paint, no divider.
  _expect(
    _same(layout(DockSettings.defaults, entries: 0, pinned: {}), [
      'launcher',
      'trash',
    ]),
    'launcher and trash',
  );

  // Both sides populated: two dividers around the applications.
  final full = layout(
    const DockSettings(folders: [folderA]),
    entries: 2,
    pinned: {0},
  );
  _expect(
    _same(full, [
      'launcher',
      'divider:leading',
      'p0',
      'divider:pinned',
      'r1',
      'divider:trailing',
      'folder:Documents',
      'trash',
    ]),
    'full $full',
  );
}

bool _same(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
