import 'dock_settings.dart';

/// One painted slot in the dock row, in paint order.
enum DockSlotKind {
  /// A pinned or running application icon.
  app,

  /// The launcher tile.
  launcher,

  /// A folder shortcut.
  folder,

  /// A single pinned file.
  file,

  /// The trash can.
  trash,

  /// A hairline separator between groups.
  divider,

  /// A part another plugin registered, drawn in a cell of its own.
  part,
}

class DockSectionSlot {
  const DockSectionSlot.app(this.index)
    : kind = DockSlotKind.app,
      folder = null,
      file = null,
      dividerKey = null,
      partId = null;

  const DockSectionSlot.launcher()
    : kind = DockSlotKind.launcher,
      index = null,
      folder = null,
      file = null,
      dividerKey = null,
      partId = null;

  const DockSectionSlot.folder(this.folder)
    : kind = DockSlotKind.folder,
      index = null,
      file = null,
      dividerKey = null,
      partId = null;

  const DockSectionSlot.file(this.file)
    : kind = DockSlotKind.file,
      index = null,
      folder = null,
      dividerKey = null,
      partId = null;

  const DockSectionSlot.trash()
    : kind = DockSlotKind.trash,
      index = null,
      folder = null,
      file = null,
      dividerKey = null,
      partId = null;

  const DockSectionSlot.divider(this.dividerKey)
    : kind = DockSlotKind.divider,
      index = null,
      folder = null,
      file = null,
      partId = null;

  const DockSectionSlot.part(this.partId)
    : kind = DockSlotKind.part,
      index = null,
      folder = null,
      file = null,
      dividerKey = null;

  final DockSlotKind kind;

  /// Index into the entry list for [DockSlotKind.app].
  final int? index;

  /// Folder record for [DockSlotKind.folder].
  final DockFolder? folder;

  /// File record for [DockSlotKind.file].
  final DockFile? file;

  /// Stable identity for a divider, so the layout and the widget tree agree on
  /// which line moved.
  final String? dividerKey;

  /// The id of the part for [DockSlotKind.part].
  final String? partId;

  bool get growable =>
      kind != DockSlotKind.divider && kind != DockSlotKind.part;
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

    final zones = settings.zones;
    final leading = _zone('leading', zones.leading, settings);
    final trailing = _zone('trailing', zones.trailing, settings);

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

  /// The slots of one end. The two ends are data: each id of a zone stands
  /// for the dock's own launcher, stacks, trash or a divider, or names a
  /// part of another plugin.
  static List<DockSectionSlot> _zone(
    String name,
    List<String> ids,
    DockSettings settings,
  ) {
    final slots = <DockSectionSlot>[];
    var dividers = 0;
    for (final id in ids) {
      switch (id) {
        case DockPart.launcher:
          slots.add(const DockSectionSlot.launcher());
        case DockPart.stacks:
          for (final folder in settings.folders) {
            slots.add(DockSectionSlot.folder(folder));
          }
          for (final file in settings.files) {
            slots.add(DockSectionSlot.file(file));
          }
        case DockPart.trash:
          slots.add(const DockSectionSlot.trash());
        case DockPart.divider:
          slots.add(DockSectionSlot.divider('$name.${dividers++}'));
        default:
          if (!DockPart.own(id)) slots.add(DockSectionSlot.part(id));
      }
    }
    // A divider with nothing on one side of it separates nothing.
    while (slots.isNotEmpty && slots.first.kind == DockSlotKind.divider) {
      slots.removeAt(0);
    }
    while (slots.isNotEmpty && slots.last.kind == DockSlotKind.divider) {
      slots.removeLast();
    }
    return slots;
  }

  /// How many slots of a built row belong to its start and to its end, the
  /// divider that parts each from the applications included. A dock that
  /// lies along its whole edge holds these at the edge's two ends.
  static ({int leading, int trailing}) ends({
    required int entryCount,
    required DockSettings settings,
  }) {
    final zones = settings.zones;
    final leading = _zone('leading', zones.leading, settings).length;
    final trailing = _zone('trailing', zones.trailing, settings).length;
    final divided = entryCount > 0 ? 1 : 0;
    return (
      leading: leading == 0 ? 0 : leading + divided,
      trailing: trailing == 0 ? 0 : trailing + divided,
    );
  }

  static bool appsEmpty(
    List<DockSectionSlot> pinned,
    List<DockSectionSlot> running,
  ) => pinned.isEmpty && running.isEmpty;
}
