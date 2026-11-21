import 'dock_settings.dart';

/// One painted slot in the dock row, in paint order.
enum DockSlotKind {
  /// A pinned or running application icon.
  app,

  /// The launcher tile.
  launcher,

  /// A folder shortcut.
  folder,

  /// The trash can.
  trash,

  /// A hairline separator between groups.
  divider,
}

class DockSectionSlot {
  const DockSectionSlot.app(this.index)
    : kind = DockSlotKind.app,
      folder = null,
      dividerKey = null;

  const DockSectionSlot.launcher()
    : kind = DockSlotKind.launcher,
      index = null,
      folder = null,
      dividerKey = null;

  const DockSectionSlot.folder(this.folder)
    : kind = DockSlotKind.folder,
      index = null,
      dividerKey = null;

  const DockSectionSlot.trash()
    : kind = DockSlotKind.trash,
      index = null,
      folder = null,
      dividerKey = null;

  const DockSectionSlot.divider(this.dividerKey)
    : kind = DockSlotKind.divider,
      index = null,
      folder = null;

  final DockSlotKind kind;

  /// Index into the entry list for [DockSlotKind.app].
  final int? index;

  /// Folder record for [DockSlotKind.folder].
  final DockFolder? folder;

  /// Stable identity for a divider, so the layout and the widget tree agree on
  /// which line moved.
  final String? dividerKey;

  bool get growable => kind != DockSlotKind.divider;
}

/// Places applications, the launcher, folders and the trash can into the macOS
/// arrangement: applications in the middle, one divider before the running
/// section, and — when accessories are present — a second divider before them.
///
/// The accessories (folders, then the trash) sit on the trailing end by
/// default, matching macOS, where the trash can is the last item; the user can
/// move the group to the leading end from the settings sheet. The trash stays
/// last inside the group either way. The launcher is not an accessory: it is
/// the launchpad stand-in and may sit on either end.
///
/// A divider only appears when both of its sides are non-empty, so a dock with
/// no running applications shows one line, and a dock with no accessories shows
/// only the applications and the launcher.
abstract final class DockSections {
  static List<DockSectionSlot> build({
    required int entryCount,
    required bool Function(int index) isPinned,
    required DockSettings settings,
  }) {
    final pinned = <DockSectionSlot>[];
    final running = <DockSectionSlot>[];
    for (var i = 0; i < entryCount; i++) {
      (isPinned(i) ? pinned : running).add(DockSectionSlot.app(i));
    }

    final launcher = settings.launcherSide == DockSide.hidden
        ? null
        : const DockSectionSlot.launcher();
    final extras = <DockSectionSlot>[
      if (settings.extrasSide != DockSide.hidden)
        for (final folder in settings.folders) DockSectionSlot.folder(folder),
      if (settings.extrasSide != DockSide.hidden && settings.showTrash)
        const DockSectionSlot.trash(),
    ];

    // Accessories lead or trail as a whole group; the trash stays last inside
    // the group either way.
    final leading = <DockSectionSlot>[
      if (launcher != null && settings.launcherSide == DockSide.left) launcher,
      if (settings.extrasSide == DockSide.left) ...extras,
    ];
    final trailing = <DockSectionSlot>[
      if (settings.extrasSide == DockSide.right) ...extras,
      if (launcher != null && settings.launcherSide == DockSide.right) launcher,
    ];

    final slots = <DockSectionSlot>[...leading];
    if (appsEmpty(pinned, running) && trailing.isEmpty) return slots;

    if (leading.isNotEmpty && (pinned.isNotEmpty || running.isNotEmpty)) {
      slots.add(const DockSectionSlot.divider('leading'));
    }
    slots.addAll(pinned);
    if (pinned.isNotEmpty && running.isNotEmpty) {
      slots.add(const DockSectionSlot.divider('pinned'));
    }
    slots.addAll(running);
    if (trailing.isNotEmpty && (pinned.isNotEmpty || running.isNotEmpty)) {
      slots.add(const DockSectionSlot.divider('trailing'));
    }
    slots.addAll(trailing);
    return slots;
  }

  static bool appsEmpty(
    List<DockSectionSlot> pinned,
    List<DockSectionSlot> running,
  ) => pinned.isEmpty && running.isEmpty;
}
