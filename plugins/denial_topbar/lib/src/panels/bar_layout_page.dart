part of 'bar_settings_panel.dart';

/// What the settings call each part, and the glyph beside the name.
(String, IconData) _partInfo(String id) {
  final item = BarPart.statusItemOf(id);
  if (item != null) {
    return _BarSettingsPanelState._statusItems[item] ??
        (item, BarIcons.circleFill);
  }
  return switch (id) {
    'dock.launcher' => ('Launcher', BarIcons.grid),
    'dock.stacks' => ('Folders and files', BarIcons.folder),
    'dock.trash' => ('Trash', BarIcons.trash),
    'dock.divider' => ('Separator', BarIcons.minus),
    BarPart.system => ('System menu', BarIcons.circleFill),
    BarPart.workspaces => ('Workspaces', BarIcons.squareGrid),
    BarPart.app => ('Application name', BarIcons.macwindow),
    BarPart.island => ('Dynamic Island', BarIcons.capsuleFill),
    BarPart.clock => ('Clock', BarIcons.clock),
    BarPart.status => ('Status items', BarIcons.rectangle3),
    BarPart.spacer => ('Flexible space', BarIcons.resize),
    BarPart.separator => ('Separator', BarIcons.minus),
    _ => ('Gap', BarIcons.ellipsis),
  };
}

const List<String> _zoneNames = <String>['Start', 'Centre', 'End'];

const List<String> _dockZoneNames = <String>['Before', 'After'];
const List<String> _dockZoneKeys = <String>['leading', 'trailing'];

/// The layout page: presets, the parts of the three zones, the bar's shape
/// and its measures.
class _LayoutPage extends ConsumerStatefulWidget {
  const _LayoutPage({required this.settings, required this.save});

  final BarSettings settings;
  final _Save save;

  @override
  ConsumerState<_LayoutPage> createState() => _LayoutPageState();
}

class _LayoutPageState extends ConsumerState<_LayoutPage> {
  /// The part picked for moving: its zone and its place in it.
  (int, int)? _picked;

  /// The zone a part from the palette goes into.
  int _target = 2;

  /// The groups a part is dragged in, the bar's and the dock's, whose boxes
  /// the drag is measured in; and the rows of their zones.
  final List<GlobalKey> _groupKeys = <GlobalKey>[GlobalKey(), GlobalKey()];
  final List<List<GlobalKey>> _rowKeys = <List<GlobalKey>>[
    <GlobalKey>[for (var zone = 0; zone < BarZones.count; zone++) GlobalKey()],
    <GlobalKey>[GlobalKey(), GlobalKey()],
  ];
  final Map<(int, int, int), GlobalKey> _chipKeys =
      <(int, int, int), GlobalKey>{};

  /// The part being dragged: its group (the bar's is 0, the dock's 1), its
  /// zone and place, the box it had when the drag began and how far the
  /// pointer has carried it since.
  int _dragGroup = 0;
  (int, int)? _dragged;
  Rect _dragBox = Rect.zero;
  Offset _dragFrom = Offset.zero;
  Offset _dragBy = Offset.zero;

  /// Where the dragged part would land: its zone and the chips before it.
  (int, int)? _drop;
  Rect? _caret;

  /// The same for the dock's two zones.
  (int, int)? _dockPicked;
  int _dockTarget = 1;

  BarSettings get _s => widget.settings;

  GlobalKey _chipKey(int group, int zone, int at) =>
      _chipKeys.putIfAbsent((group, zone, at), GlobalKey.new);

  /// The zones of a drag group, or null when there is no dock to show.
  List<List<String>>? _zonesOf(int group) => group == 0
      ? <List<String>>[_s.zones.start, _s.zones.center, _s.zones.end]
      : _dockZones;

  /// The box of [key]'s widget inside its drag group.
  Rect? _boxOf(int group, GlobalKey key) {
    final frame = _groupKeys[group].currentContext?.findRenderObject();
    final box = key.currentContext?.findRenderObject();
    if (frame is! RenderBox || box is! RenderBox || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero, ancestor: frame) & box.size;
  }

  void _dragStart(int group, int zone, int at, Offset global) {
    final box = _boxOf(group, _chipKey(group, zone, at));
    if (box == null) return;
    setState(() {
      if (group == 0) {
        _picked = (zone, at);
      } else {
        _dockPicked = (zone, at);
      }
      _dragGroup = group;
      _dragged = (zone, at);
      _dragBox = box;
      _dragFrom = global;
      _dragBy = Offset.zero;
      _drop = null;
      _caret = null;
    });
  }

  void _dragMove(Offset global) {
    final dragged = _dragged;
    final group = _dragGroup;
    final frame = _groupKeys[group].currentContext?.findRenderObject();
    if (dragged == null || frame is! RenderBox) return;
    final zones = _zonesOf(group);
    if (zones == null || dragged.$2 >= zones[dragged.$1].length) {
      return _dragEnd(false);
    }
    final at = frame.globalToLocal(global);
    final rows = <Rect>[
      for (final key in _rowKeys[group]) _boxOf(group, key) ?? Rect.zero,
    ];
    // The island grows from the middle of the screen and sits nowhere else.
    final island = group == 0 && zones[dragged.$1][dragged.$2] == BarPart.island;
    final zone = island
        ? 1
        : PartDrop.zone(<(double, double)>[
            for (final row in rows) (row.top, row.bottom),
          ], at.dy);
    final chips = <Rect>[
      for (var i = 0; i < zones[zone].length; i++)
        _boxOf(group, _chipKey(group, zone, i)) ?? Rect.zero,
    ];
    final slot = PartDrop.slot(
      <PartBox>[
        for (final chip in chips)
          (
            left: chip.left,
            top: chip.top,
            right: chip.right,
            bottom: chip.bottom,
          ),
      ],
      at.dx,
      at.dy,
    );
    final Rect caret;
    if (chips.isEmpty) {
      // Where the first chip of the row would sit.
      caret = Rect.fromLTWH(rows[zone].left + 64, rows[zone].top + 8, 2, 26);
    } else if (slot < chips.length) {
      caret = Rect.fromLTWH(
        chips[slot].left - 4,
        chips[slot].top,
        2,
        chips[slot].height,
      );
    } else {
      caret = Rect.fromLTWH(
        chips.last.right + 2,
        chips.last.top,
        2,
        chips.last.height,
      );
    }
    setState(() {
      _dragBy = global - _dragFrom;
      _drop = (zone, slot);
      _caret = caret;
    });
  }

  void _dragEnd(bool land) {
    final dragged = _dragged;
    final drop = _drop;
    if (dragged == null) return;
    final group = _dragGroup;
    (int, int)? landed;
    VoidCallback? store;
    if (land && drop != null) {
      if (group == 0) {
        final zones = _s.zones;
        final (moved, zone, at) = PartDrop.moved(
          zones,
          dragged.$1,
          dragged.$2,
          drop.$1,
          drop.$2,
        );
        landed = (zone, at);
        if (moved != zones) store = () => _setZones(moved);
      } else {
        final zones = _dockZones;
        if (zones != null) {
          final (moved, zone, at) = PartDrop.movedIn(
            zones,
            dragged.$1,
            dragged.$2,
            drop.$1,
            drop.$2,
          );
          landed = (zone, at);
          if ((zone, at) != dragged) store = () => _setDockZones(moved);
        }
      }
    }
    setState(() {
      if (landed != null) {
        if (group == 0) {
          _picked = landed;
        } else {
          _dockPicked = landed;
        }
      }
      _dragged = null;
      _drop = null;
      _caret = null;
    });
    store?.call();
  }

  /// A chip that can be carried to another place: at once with a mouse, and
  /// after a held press by touch, where a plain drag scrolls the page.
  Widget _carried(int group, int zone, int at, Widget chip) => GestureDetector(
    supportedDevices: const <PointerDeviceKind>{PointerDeviceKind.mouse},
    onPanStart: (d) => _dragStart(group, zone, at, d.globalPosition),
    onPanUpdate: (d) => _dragMove(d.globalPosition),
    onPanEnd: (_) => _dragEnd(true),
    onPanCancel: () => _dragEnd(false),
    child: GestureDetector(
      supportedDevices: const <PointerDeviceKind>{
        PointerDeviceKind.touch,
        PointerDeviceKind.stylus,
      },
      onLongPressStart: (d) => _dragStart(group, zone, at, d.globalPosition),
      onLongPressMoveUpdate: (d) => _dragMove(d.globalPosition),
      onLongPressEnd: (_) => _dragEnd(true),
      onLongPressCancel: () => _dragEnd(false),
      child: KeyedSubtree(
        key: _chipKey(group, zone, at),
        child: AnimatedOpacity(
          duration: KitMotion.duration(context, KitMotion.fill),
          opacity: _dragGroup == group && _dragged == (zone, at) ? 0.35 : 1,
          child: chip,
        ),
      ),
    ),
  );

  /// The mark where a dragged part of [group] would land, and the part
  /// itself under the pointer; nothing while that group has no drag.
  List<Widget> _dragLayer(int group, ShellThemeData theme) {
    final dragged = _dragged;
    final zones = _zonesOf(group);
    if (dragged == null ||
        _dragGroup != group ||
        zones == null ||
        dragged.$2 >= zones[dragged.$1].length) {
      return const <Widget>[];
    }
    final caret = _caret;
    return <Widget>[
      if (caret != null)
        Positioned.fromRect(
          rect: caret,
          child: IgnorePointer(
            child: ColoredBox(color: KitStyle.of(context).accent(theme)),
          ),
        ),
      Positioned(
        left: _dragBox.left + _dragBy.dx,
        top: _dragBox.top + _dragBy.dy,
        child: IgnorePointer(
          child: _PartChip(
            id: zones[dragged.$1][dragged.$2],
            selected: true,
            onTap: () {},
          ),
        ),
      ),
    ];
  }

  void _shellChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    kitDock.addListener(_shellChanged);
    kitBarMode.addListener(_shellChanged);
    kitParts.addListener(_shellChanged);
  }

  @override
  void dispose() {
    kitDock.removeListener(_shellChanged);
    kitBarMode.removeListener(_shellChanged);
    kitParts.removeListener(_shellChanged);
    super.dispose();
  }

  /// The dock's two zones as it publishes them, or null with no dock.
  List<List<String>>? get _dockZones {
    final layout = kitDock.layout;
    if (layout == null) return null;
    return <List<String>>[
      for (final key in _dockZoneKeys)
        <String>[
          for (final id in layout[key] as List? ?? const <Object?>[])
            if (id is String) id,
        ],
    ];
  }

  void _setDockZones(List<List<String>> zones) => kitDock.apply(
    <String, Object?>{_dockZoneKeys[0]: zones[0], _dockZoneKeys[1]: zones[1]},
  );

  /// Moves the picked dock part one step along the dock, over the
  /// applications into the other zone when it is at the end of its own.
  void _dockMove(int by) {
    final picked = _dockPicked;
    final zones = _dockZones;
    if (picked == null || zones == null) return;
    final (zone, at) = picked;
    if (at >= zones[zone].length) return;
    final to = at + by;
    if (to >= 0 && to < zones[zone].length) {
      zones[zone].insert(to, zones[zone].removeAt(at));
      setState(() => _dockPicked = (zone, to));
    } else {
      final target = zone + by;
      if (target < 0 || target > 1) return;
      final id = zones[zone].removeAt(at);
      final place = by > 0 ? 0 : zones[target].length;
      zones[target].insert(place, id);
      setState(() => _dockPicked = (target, place));
    }
    _setDockZones(zones);
  }

  void _dockRemove() {
    final picked = _dockPicked;
    final zones = _dockZones;
    if (picked == null || zones == null) return;
    if (picked.$2 >= zones[picked.$1].length) return;
    zones[picked.$1].removeAt(picked.$2);
    setState(() => _dockPicked = null);
    _setDockZones(zones);
  }

  void _dockAdd(String id) {
    final zones = _dockZones;
    if (zones == null) return;
    if (kitParts[id]?.single ?? true) {
      for (final zone in zones) {
        zone.remove(id);
      }
    }
    zones[_dockTarget].add(id);
    setState(() => _dockPicked = (_dockTarget, zones[_dockTarget].length - 1));
    _setDockZones(zones);
  }

  void _setZones(BarZones zones, {bool island = false}) => widget.save(
    (s) => s.copyWith(zones: zones, islandEnabled: island ? true : null),
  );

  /// Moves the picked part one step along the bar, into the next zone when
  /// it is at the end of its own.
  void _move(int by) {
    final picked = _picked;
    if (picked == null) return;
    final zones = _s.zones;
    final (zone, at) = picked;
    final inside = at + by >= 0 && at + by < zones.zone(zone).length;
    final (next, toZone, toAt) = inside
        ? zones.shifted(zone, at, by)
        : zones.carried(zone, at, by);
    if (next == zones) return;
    setState(() => _picked = (toZone, toAt));
    _setZones(next);
  }

  void _remove() {
    final picked = _picked;
    if (picked == null) return;
    setState(() => _picked = null);
    _setZones(_s.zones.removedAt(picked.$1, picked.$2));
  }

  void _add(String id) {
    // The island grows from the middle of the screen and sits nowhere else.
    final zone = id == BarPart.island ? 1 : _target;
    final next = _s.zones.inserted(zone, id);
    setState(() => _picked = (zone, next.zone(zone).lastIndexOf(id)));
    _setZones(next, island: id == BarPart.island);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final s = _s;
    final save = widget.save;
    final zones = s.zones;
    final strip = s.shape == BarShape.strip;
    final plated = s.ground != BarGround.none;
    // The preset last applied; or, when the shell no longer matches it but
    // is exactly another one, that one.
    var current = ShellPreset.byId(kitPreset.value);
    var modified = shellPresetModified(current, s);
    if (modified) {
      for (final preset in ShellPreset.all) {
        if (shellPresetModified(preset, s)) continue;
        current = preset;
        modified = false;
        break;
      }
    }

    // A part that went away under the selection.
    var picked = _picked;
    if (picked != null && picked.$2 >= zones.zone(picked.$1).length) {
      picked = null;
    }
    final pickedId = picked == null ? null : zones.zone(picked.$1)[picked.$2];

    // The dock's zones, while a dock runs to edit.
    final dockLayout = kitDock.layout;
    final dockZones = _dockZones;
    var dockPicked = _dockPicked;
    if (dockPicked != null &&
        (dockZones == null ||
            dockPicked.$2 >= dockZones[dockPicked.$1].length)) {
      dockPicked = null;
    }
    final dockPickedId = dockPicked == null || dockZones == null
        ? null
        : dockZones[dockPicked.$1][dockPicked.$2];
    final dockPalette = <String>[
      if (dockZones != null)
        for (final id in kitParts.idsFor(KitHostKind.dock))
          if (!(kitParts[id]?.single ?? true) ||
              !dockZones.any((zone) => zone.contains(id)))
            id,
    ];

    final palette = <String>[
      for (final id in BarPart.all)
        if (id != BarPart.gap &&
            (BarPart.repeats(id) ||
                !zones.contains(id) ||
                (id == BarPart.island && !s.islandEnabled)))
          id,
    ];

    Widget slider(
      String label,
      double value,
      double min,
      double max,
      ValueChanged<double> set, {
      double step = 1,
      String Function(double value)? text,
      bool enabled = true,
    }) => _Cell(
      label: label,
      detail: text?.call(value) ?? _number(value),
      enabled: enabled,
      child: MacSlider(
        // This page scrolls, so the slider yields the wheel and vertical
        // drags to it.
        inList: true,
        value: ((value - min) / (max - min)).clamp(0.0, 1.0),
        onChanged: (v) {
          final next = ((min + v * (max - min)) / step).round() * step;
          if (next != value) set(next.clamp(min, max));
        },
      ),
    );

    Widget choice<T>(
      String label,
      T value,
      List<(T, String)> options,
      ValueChanged<T> set, {
      bool enabled = true,
    }) => _Cell(
      label: label,
      enabled: enabled,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: _Segments<T>(value: value, options: options, onChanged: set),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _Group(
          title: context.tr('Presets'),
          note: context.tr(
            'A preset sets the look and the layout of the bar. Which items show stays as you set it.',
          ),
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(10),
              // Four to a row, so a card stays wide enough to read.
              child: LayoutBuilder(
                builder: (context, constraints) {
                  const gap = 8.0;
                  final width = (constraints.maxWidth - gap * 3) / 4;
                  return Wrap(
                    spacing: gap,
                    runSpacing: 6,
                    children: <Widget>[
                      for (final preset in ShellPreset.all)
                        SizedBox(
                          width: width,
                          child: _PresetCard(
                            preset: preset,
                            selected: preset.id == current.id,
                            modified: preset.id == current.id && modified,
                            onTap: () {
                              setState(() {
                                _picked = null;
                                _dockPicked = null;
                              });
                              applyShellPreset(ref, preset);
                            },
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
        Stack(
          key: _groupKeys[0],
          clipBehavior: Clip.none,
          children: <Widget>[
            _Group(
              title: context.tr('Parts'),
              note: context.tr(
                'Drag a part to where it should sit; by touch, press and hold it first. Or pick a part, then move it along the bar with the arrows; at the end of a zone it goes on into the next. With pointed ends, a separator starts a new segment.',
              ),
              children: <Widget>[
                for (var zone = 0; zone < BarZones.count; zone++)
                  Padding(
                    key: _rowKeys[0][zone],
                    padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        SizedBox(
                          width: 52,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              context.tr(_zoneNames[zone]),
                              style: BarType.caption.copyWith(
                                fontSize: 12,
                                color: theme.colors.textSecondary,
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: zones.zone(zone).isEmpty
                              ? Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(
                                    context.tr('Empty'),
                                    style: BarType.caption.copyWith(
                                      fontSize: 12,
                                      color: theme.colors.textTertiary,
                                    ),
                                  ),
                                )
                              : Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: <Widget>[
                                    for (
                                      var at = 0;
                                      at < zones.zone(zone).length;
                                      at++
                                    )
                                      _carried(
                                        0,
                                        zone,
                                        at,
                                        _PartChip(
                                          id: zones.zone(zone)[at],
                                          selected: picked == (zone, at),
                                          dimmed:
                                              zones.zone(zone)[at] ==
                                                  BarPart.island &&
                                              !s.islandEnabled,
                                          onTap: () => setState(
                                            () => _picked = picked == (zone, at)
                                                ? null
                                                : (zone, at),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                        ),
                      ],
                    ),
                  ),
                _Row(
                  label: pickedId == null
                      ? context.tr('No part picked')
                      : context.tr(_partInfo(pickedId).$1),
                  enabled: pickedId != null,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      _IconButton(
                        icon: BarIcons.chevronLeft,
                        onTap: () => _move(-1),
                      ),
                      const SizedBox(width: 6),
                      _IconButton(
                        icon: BarIcons.chevronRight,
                        onTap: () => _move(1),
                      ),
                      const SizedBox(width: 6),
                      SizedBox(
                        width: 72,
                        child: _TextButton(
                          label: context.tr('Remove'),
                          onTap: _remove,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 10, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              context.tr('Add to'),
                              style: BarType.menuRow.copyWith(
                                color: theme.colors.textPrimary,
                              ),
                            ),
                          ),
                          _Segments<int>(
                            value: _target,
                            options: <(int, String)>[
                              for (var zone = 0; zone < BarZones.count; zone++)
                                (zone, context.tr(_zoneNames[zone])),
                            ],
                            onChanged: (zone) => setState(() => _target = zone),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: <Widget>[
                          for (final id in palette)
                            _PartChip(id: id, add: true, onTap: () => _add(id)),
                        ],
                      ),
                    ],
                  ),
                ),
                if (s.explicitZones != null)
                  _Row(
                    label: context.tr('Follow the switches on the other pages'),
                    trailing: SizedBox(
                      width: 72,
                      child: _TextButton(
                        label: context.tr('Reset'),
                        onTap: () {
                          setState(() => _picked = null);
                          save((s) => s.copyWith(zones: null));
                        },
                      ),
                    ),
                  ),
              ],
            ),
            ..._dragLayer(0, theme),
          ],
        ),
        _Group(
          title: context.tr('Shape'),
          children: <Widget>[
            _Pair(
              choice<BarShape>(
                context.tr('Shape'),
                s.shape,
                <(BarShape, String)>[
                  (BarShape.strip, context.tr('Strip')),
                  (BarShape.floating, context.tr('Floating')),
                  (BarShape.islands, context.tr('Islands')),
                ],
                (v) => save((s) => s.copyWith(shape: v)),
              ),
              choice<BarCap>(
                context.tr('Ends'),
                s.cap,
                <(BarCap, String)>[
                  (BarCap.round, context.tr('Round')),
                  (BarCap.square, context.tr('Square')),
                  (BarCap.arrow, context.tr('Pointed')),
                ],
                (v) => save((s) => s.copyWith(cap: v)),
                enabled: !strip,
              ),
            ),
            _Pair(
              choice<BarGround>(
                context.tr('Background'),
                s.ground,
                <(BarGround, String)>[
                  (BarGround.none, context.tr('None')),
                  (BarGround.plate, context.tr('Plate')),
                  (BarGround.glass, context.tr('Glass')),
                ],
                (v) => save((s) => s.copyWith(ground: v)),
              ),
              choice<BarGroundTint>(
                context.tr('Colour from'),
                s.groundTint,
                <(BarGroundTint, String)>[
                  (BarGroundTint.wallpaper, context.tr('Wallpaper')),
                  (BarGroundTint.panel, context.tr('Theme')),
                  (BarGroundTint.accent, context.tr('Accent')),
                ],
                (v) => save((s) => s.copyWith(groundTint: v)),
                enabled: plated,
              ),
            ),
            _Pair(
              slider(
                context.tr('Background opacity'),
                s.groundOpacity,
                BarMetric.opacityMin,
                BarMetric.opacityMax,
                (v) => save((s) => s.copyWith(groundOpacity: v)),
                step: 0.05,
                text: _percent,
                enabled: plated,
              ),
              slider(
                context.tr('Corner radius'),
                s.cornerRadius,
                BarMetric.cornerRadiusMin,
                BarMetric.cornerRadiusMax,
                (v) => save((s) => s.copyWith(cornerRadius: v)),
                enabled: !strip && s.cap == BarCap.round,
              ),
            ),
            _Pair(
              slider(
                context.tr('Border width'),
                s.borderWidth,
                BarMetric.borderWidthMin,
                BarMetric.borderWidthMax,
                (v) => save((s) => s.copyWith(borderWidth: v)),
                step: 0.2,
                enabled: plated,
              ),
              choice<BarBorderColour>(
                context.tr('Border colour'),
                s.borderColour,
                <(BarBorderColour, String)>[
                  (BarBorderColour.ink, context.tr('Ink')),
                  (BarBorderColour.accent, context.tr('Accent')),
                ],
                (v) => save((s) => s.copyWith(borderColour: v)),
                enabled: plated && s.borderWidth > 0,
              ),
            ),
          ],
        ),
        _Group(
          title: context.tr('Measures'),
          note: context.tr(
            'The height of the bar is set in the system settings.',
          ),
          children: <Widget>[
            _Pair(
              slider(
                context.tr('Text size'),
                s.textScale,
                BarMetric.textScaleMin,
                BarMetric.textScaleMax,
                (v) => save((s) => s.copyWith(textScale: v)),
                step: 0.05,
                text: _percent,
              ),
              slider(
                context.tr('Space between parts'),
                s.partGap,
                BarMetric.partGapMin,
                BarMetric.partGapMax,
                (v) => save((s) => s.copyWith(partGap: v)),
              ),
            ),
            _Pair(
              slider(
                context.tr('Gap to the screen edge'),
                s.edgeMargin,
                BarMetric.edgeMarginMin,
                BarMetric.edgeMarginMax,
                (v) => save((s) => s.copyWith(edgeMargin: v)),
                enabled: !strip,
              ),
              slider(
                context.tr('Inset at both ends'),
                s.endInset ??
                    (strip ? BarTokens.insetLeft : BarTokens.insetFloating),
                BarMetric.endInsetMin,
                BarMetric.endInsetMax,
                (v) => save((s) => s.copyWith(endInset: v)),
              ),
            ),
            _Pair(
              slider(
                context.tr('Padding inside the background'),
                s.contentPadding,
                BarMetric.contentPaddingMin,
                BarMetric.contentPaddingMax,
                (v) => save((s) => s.copyWith(contentPadding: v)),
              ),
              choice<BarWorkspaceStyle>(
                context.tr('Workspaces'),
                s.workspaceStyle,
                <(BarWorkspaceStyle, String)>[
                  (BarWorkspaceStyle.dots, context.tr('Dots')),
                  (BarWorkspaceStyle.numbers, context.tr('Numbers')),
                ],
                (v) => save((s) => s.copyWith(workspaceStyle: v)),
              ),
            ),
          ],
        ),
        _Group(
          title: context.tr('Top bar'),
          note: context.tr(
            'With the bar hidden or reduced to its island, a Dock that always shows keeps its edge free of windows.',
          ),
          children: <Widget>[
            _Row(
              label: context.tr('Top bar'),
              trailing: _Segments<KitBarMode>(
                value: kitBarMode.value,
                options: <(KitBarMode, String)>[
                  (KitBarMode.shown, context.tr('Shown')),
                  (KitBarMode.islandOnly, context.tr('Island only')),
                  (KitBarMode.hidden, context.tr('Hidden')),
                ],
                onChanged: (mode) => setState(() => kitBarMode.value = mode),
              ),
            ),
          ],
        ),
        if (dockZones != null && dockLayout != null)
          Stack(
            key: _groupKeys[1],
            clipBehavior: Clip.none,
            children: <Widget>[
              _Group(
                title: context.tr('Dock parts'),
                note: context.tr(
                  'What sits before and after the applications. Parts of the bar placed here open their panels from the Dock.',
                ),
                children: <Widget>[
                  for (var zone = 0; zone < 2; zone++)
                    Padding(
                      key: _rowKeys[1][zone],
                      padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          SizedBox(
                            width: 52,
                            child: Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                context.tr(_dockZoneNames[zone]),
                                style: BarType.caption.copyWith(
                                  fontSize: 12,
                                  color: theme.colors.textSecondary,
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: dockZones[zone].isEmpty
                                ? Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text(
                                      context.tr('Empty'),
                                      style: BarType.caption.copyWith(
                                        fontSize: 12,
                                        color: theme.colors.textTertiary,
                                      ),
                                    ),
                                  )
                                : Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: <Widget>[
                                      for (
                                        var at = 0;
                                        at < dockZones[zone].length;
                                        at++
                                      )
                                        _carried(
                                          1,
                                          zone,
                                          at,
                                          _PartChip(
                                            id: dockZones[zone][at],
                                            selected: dockPicked == (zone, at),
                                            // Placed, but no running plugin
                                            // offers it.
                                            dimmed:
                                                kitParts[dockZones[zone][at]] == null,
                                            onTap: () => setState(
                                              () => _dockPicked =
                                                  dockPicked == (zone, at)
                                                  ? null
                                                  : (zone, at),
                                            ),
                                        ),
                                        ),
                                    ],
                                  ),
                          ),
                        ],
                      ),
                    ),
                  _Row(
                    label: dockPickedId == null
                        ? context.tr('No part picked')
                        : context.tr(_partInfo(dockPickedId).$1),
                    enabled: dockPickedId != null,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        _IconButton(
                          icon: BarIcons.chevronLeft,
                          onTap: () => _dockMove(-1),
                        ),
                        const SizedBox(width: 6),
                        _IconButton(
                          icon: BarIcons.chevronRight,
                          onTap: () => _dockMove(1),
                        ),
                        const SizedBox(width: 6),
                        SizedBox(
                          width: 72,
                          child: _TextButton(
                            label: context.tr('Remove'),
                            onTap: _dockRemove,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 10, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                context.tr('Add to'),
                                style: BarType.menuRow.copyWith(
                                  color: theme.colors.textPrimary,
                                ),
                              ),
                            ),
                            _Segments<int>(
                              value: _dockTarget,
                              options: <(int, String)>[
                                for (var zone = 0; zone < 2; zone++)
                                  (zone, context.tr(_dockZoneNames[zone])),
                              ],
                              onChanged: (zone) =>
                                  setState(() => _dockTarget = zone),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: <Widget>[
                            for (final id in dockPalette)
                              _PartChip(
                                id: id,
                                add: true,
                                onTap: () => _dockAdd(id),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  _Pair(
                    choice<String>(
                      context.tr('Dock'),
                      dockLayout['shape'] == 'bar' ? 'bar' : 'floating',
                      <(String, String)>[
                        ('floating', context.tr('Floating')),
                        ('bar', context.tr('Edge bar')),
                      ],
                      (v) => kitDock.apply(<String, Object?>{'shape': v}),
                    ),
                    choice<String>(
                      context.tr('Application area'),
                      '${dockLayout['align'] ?? 'packed'}',
                      <(String, String)>[
                        ('packed', context.tr('One group')),
                        ('center', context.tr('Centred')),
                        ('start', context.tr('At the start')),
                      ],
                      (v) => kitDock.apply(<String, Object?>{'align': v}),
                      enabled: dockLayout['shape'] == 'bar',
                    ),
                  ),
                  _Switch(
                    label: context.tr('Always show'),
                    value: dockLayout['visibility'] == 'always',
                    onChanged: (v) => kitDock.apply(<String, Object?>{
                      'visibility': v ? 'always' : 'smart',
                    }),
                  ),
                ],
              ),
              ..._dragLayer(1, theme),
            ],
          ),
        _Group(
          note: context.tr(
            'The Dock is a plugin of its own. This switch works under every preset, and no preset changes it.',
          ),
          children: <Widget>[
            _Switch(
              label: context.tr('Show the Dock'),
              value: kitDockEnabled.value,
              onChanged: (v) => setState(() => kitDockEnabled.value = v),
            ),
          ],
        ),
      ],
    );
  }
}

String _number(double value) =>
    value == value.roundToDouble() ? '${value.round()}' : value.toStringAsFixed(1);

String _percent(double value) => '${(value * 100).round()}%';

/// Two settings side by side, so the page is half as long.
class _Pair extends StatelessWidget {
  const _Pair(this.first, this.second);

  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context) => SizedBox(
    // A fixed height: the slider measures itself from its constraints, so
    // the row cannot ask its cells how tall they would like to be.
    height: 76,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(child: first),
        SizedBox(
          width: 1,
          child: ColoredBox(
            color: context.shellTheme.colors.textPrimary.withValues(
              alpha: 0.07,
            ),
          ),
        ),
        Expanded(child: second),
      ],
    ),
  );
}

/// One setting with its name above its control.
class _Cell extends StatelessWidget {
  const _Cell({
    required this.label,
    required this.child,
    this.detail,
    this.enabled = true,
  });

  final String label;
  final String? detail;
  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    return IgnorePointer(
      ignoring: !enabled,
      child: AnimatedOpacity(
        duration: KitMotion.duration(context, KitMotion.fill),
        opacity: enabled ? 1 : 0.4,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 9, 12, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: BarType.menuRow.copyWith(
                        color: theme.colors.textPrimary,
                      ),
                    ),
                  ),
                  if (detail != null)
                    Text(
                      detail!,
                      style: BarType.caption.copyWith(
                        color: theme.colors.textTertiary,
                        fontFeatures: const <FontFeature>[
                          FontFeature.tabularFigures(),
                        ],
                      ),
                    ),
                ],
              ),
              Expanded(
                child: Align(alignment: Alignment.centerLeft, child: child),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconButton extends StatelessWidget {
  const _IconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = context.shellTheme.colors.textPrimary;
    return Pressable(
      onTap: onTap,
      scale: Pressable.small,
      child: Container(
        width: 34,
        height: 28,
        decoration: BoxDecoration(
          color: ink.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(KitStyle.of(context).corner(8)),
        ),
        child: BarGlyph(icon, size: 12, color: ink),
      ),
    );
  }
}

/// One part in a zone or in the palette.
class _PartChip extends StatelessWidget {
  const _PartChip({
    required this.id,
    required this.onTap,
    this.selected = false,
    this.dimmed = false,
    this.add = false,
  });

  final String id;
  final VoidCallback onTap;
  final bool selected;

  /// Placed but not drawn, such as an island that is switched off.
  final bool dimmed;

  /// A chip of the palette, which adds its part.
  final bool add;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final style = KitStyle.of(context);
    final (label, icon) = _partInfo(id);
    final ink = selected ? style.onAccent(theme) : theme.colors.textPrimary;
    return Pressable(
      onTap: onTap,
      scale: 0.95,
      child: AnimatedContainer(
        duration: KitMotion.duration(context, KitMotion.turn),
        curve: KitMotion.outCubic,
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: selected
              ? style.accent(theme)
              : theme.colors.textPrimary.withValues(alpha: add ? 0.05 : 0.10),
          borderRadius: BorderRadius.circular(style.corner(7)),
          border: add
              ? Border.all(
                  color: theme.colors.textPrimary.withValues(alpha: 0.12),
                )
              : null,
        ),
        child: Opacity(
          opacity: dimmed ? 0.45 : 1,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              BarGlyph(add ? BarIcons.plus : icon, size: 11, color: ink),
              const SizedBox(width: 5),
              Text(
                context.tr(label),
                maxLines: 1,
                style: BarType.caption.copyWith(fontSize: 12, color: ink),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PresetCard extends StatelessWidget {
  const _PresetCard({
    required this.preset,
    required this.selected,
    required this.modified,
    required this.onTap,
  });

  final ShellPreset preset;
  final bool selected;
  final bool modified;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final style = KitStyle.of(context);
    final look = KitStyle.byId(preset.look);
    final ink = theme.colors.textPrimary;
    return Pressable(
      onTap: onTap,
      scale: Pressable.large,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AnimatedContainer(
            duration: KitMotion.duration(context, KitMotion.turn),
            curve: KitMotion.outCubic,
            height: 54,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(style.corner(9)),
              border: Border.all(
                width: 2,
                color: selected
                    ? style.accent(theme)
                    : ink.withValues(alpha: 0),
              ),
            ),
            child: CustomPaint(
              painter: _BarSketch(
                settings: BarSettings.defaults.withLayout(preset.bar),
                look: look,
                ink: ink,
                accent: look.accent(theme),
                corner: style.corner(5),
                barMode: preset.barMode,
                dock: preset.dock,
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            preset.label,
            textAlign: TextAlign.center,
            maxLines: 1,
            style: BarType.caption.copyWith(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: ink,
            ),
          ),
          Text(
            modified ? context.tr('Modified') : '',
            textAlign: TextAlign.center,
            maxLines: 1,
            style: BarType.caption.copyWith(
              fontSize: 10,
              color: theme.colors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

/// A small drawing of a bar: its shape, where its parts sit, and a panel
/// under it in the look's corners and border.
class _BarSketch extends CustomPainter {
  const _BarSketch({
    required this.settings,
    required this.look,
    required this.ink,
    required this.accent,
    required this.corner,
    this.barMode = 'shown',
    this.dock = const <String, Object?>{},
  });

  final BarSettings settings;
  final KitStyle look;
  final Color ink;
  final Color accent;

  /// The corner of the tile the sketch is drawn on, in the look in force.
  final double corner;

  /// How much of itself the bar draws: `shown`, `islandOnly` or `hidden`.
  final String barMode;

  /// The dock's layout, drawn when it stands in for the bar.
  final Map<String, Object?> dock;

  static const double _dockHeight = 9;
  static const double _app = 5;

  static const double _bar = 10;
  static const double _gap = 2;

  static double _mark(String id) => switch (id) {
    BarPart.workspaces => 12,
    BarPart.app => 9,
    BarPart.clock => 10,
    BarPart.status => 14,
    BarPart.island => 14,
    BarPart.spacer => 5,
    BarPart.separator || BarPart.gap => 1,
    _ => 4,
  };

  static double _run(List<String> ids) => ids.isEmpty
      ? 0
      : ids.fold<double>(0, (sum, id) => sum + _mark(id)) +
            _gap * (ids.length - 1);

  @override
  void paint(Canvas canvas, Size size) {
    final s = settings;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(corner)),
      Paint()..color = ink.withValues(alpha: 0.07),
    );
    canvas.clipRRect(
      RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(corner)),
    );
    final strip = s.shape == BarShape.strip;
    final top = strip ? 0.0 : 3.0;
    final side = strip ? 0.0 : 4.0;
    final middle = top + _bar / 2;
    final arrow = s.cap == BarCap.arrow && !strip;
    final radius = strip || s.cap == BarCap.square
        ? 0.0
        : math.min(_bar / 2, s.cornerRadius * 0.36);
    final depth = barArrowDepth(_bar);
    final plate = s.ground == BarGround.none
        ? null
        : ink.withValues(alpha: 0.14 + 0.30 * s.groundOpacity);
    final alternate = accent.withValues(alpha: 0.75);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = s.borderColour == BarBorderColour.accent
          ? accent
          : ink.withValues(alpha: 0.35);

    void block(Rect rect, {BarSegmentEdges? edges, Color? fill}) {
      final colour = fill ?? plate;
      if (colour == null) return;
      final Path path;
      if (edges == null) {
        path = Path()
          ..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
      } else {
        final points = barSegmentOutline(
          width: rect.width,
          height: rect.height,
          depth: depth,
          left: edges.left,
          right: edges.right,
        );
        path = Path()
          ..moveTo(rect.left + points.first.x, rect.top + points.first.y);
        for (final point in points.skip(1)) {
          path.lineTo(rect.left + point.x, rect.top + point.y);
        }
        path.close();
      }
      canvas.drawPath(path, Paint()..color = colour);
      if (s.borderWidth > 0) canvas.drawPath(path, line);
    }

    void marks(List<String> ids, double x) {
      for (final id in ids) {
        final width = _mark(id);
        if (id != BarPart.spacer && id != BarPart.gap) {
          final island = id == BarPart.island;
          final height = island ? 6.0 : (id == BarPart.separator ? 6.0 : 3.0);
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(x, middle - height / 2, width, height),
              Radius.circular(island ? 3 : 1.5 * look.cornerScale),
            ),
            Paint()
              ..color = island
                  ? const Color(0xff000000)
                  : ink.withValues(alpha: id == BarPart.separator ? 0.3 : 0.7),
          );
        }
        x += width + _gap;
      }
    }

    final shown = barMode == 'shown';
    if (shown) {
      final zones = s.zones;
      final centre = s.showsIsland
          ? const <String>[BarPart.island]
          : <String>[
              for (final id in zones.center)
                if (id != BarPart.island) id,
            ];
      if (s.shape == BarShape.islands) {
        for (var zone = 0; zone < BarZones.count; zone++) {
          final ids = zone == 1 ? centre : zones.zone(zone);
          if (zone == 1 && s.showsIsland) {
            marks(ids, (size.width - _run(ids)) / 2);
            continue;
          }
          final runs = arrow
              ? BarZones.segments(ids)
              : <List<String>>[
                  if (ids.isNotEmpty) ids,
                ];
          if (runs.isEmpty) continue;
          final edges = arrow ? barZoneEdges(zone, runs.length) : null;
          double inset(int index, bool left) => edges == null
              ? 3
              : 2 +
                    barEdgeInset(
                      left ? edges[index].left : edges[index].right,
                      depth,
                    );
          final widths = <double>[
            for (var index = 0; index < runs.length; index++)
              _run(runs[index]) + inset(index, true) + inset(index, false),
          ];
          final total = widths.fold<double>(0, (sum, width) => sum + width);
          var x = switch (zone) {
            0 => side,
            1 => (size.width - total) / 2,
            _ => size.width - side - total,
          };
          for (var index = 0; index < runs.length; index++) {
            block(
              Rect.fromLTWH(x, top, widths[index], _bar),
              edges: edges?[index],
              fill: index.isOdd && plate != null ? alternate : null,
            );
            marks(runs[index], x + inset(index, true));
            x += widths[index];
          }
        }
      } else {
        block(
          Rect.fromLTWH(side, top, size.width - side * 2, _bar),
          edges: arrow ? const (left: BarEdge.point, right: BarEdge.point) : null,
        );
        final pad = side + (arrow ? depth : 0) + 3;
        marks(zones.start, pad);
        marks(centre, (size.width - _run(centre)) / 2);
        marks(zones.end, size.width - pad - _run(zones.end));
      }
    } else if (barMode == 'islandOnly') {
      marks(const <String>[
        BarPart.island,
      ], (size.width - _mark(BarPart.island)) / 2);
    }

    // With the bar away or down to its island, the dock is the bar.
    var dockTop = size.height;
    if (!shown) {
      List<String> ids(Object? value) => <String>[
        if (value is List)
          for (final id in value)
            if (id is String) id,
      ];
      double wide(String id) => BarPart.known(id) ? _mark(id) : 4;
      double run(List<String> parts) => parts.isEmpty
          ? 0
          : parts.fold<double>(0, (sum, id) => sum + wide(id)) +
                _gap * (parts.length - 1);
      final leading = ids(dock['leading']);
      final trailing = ids(dock['trailing']);
      const apps = 4;
      const appsRun = apps * _app + (apps - 1) * _gap;
      final edge = dock['shape'] == 'bar';
      final content =
          run(leading) +
          appsRun +
          run(trailing) +
          (leading.isEmpty ? 0 : 4) +
          (trailing.isEmpty ? 0 : 4);
      final body = edge
          ? Rect.fromLTWH(0, size.height - _dockHeight, size.width, _dockHeight)
          : Rect.fromCenter(
              center: Offset(size.width / 2, size.height - 3 - _dockHeight / 2),
              width: math.min(size.width - 8, content + 8),
              height: _dockHeight,
            );
      dockTop = body.top;
      final outline = RRect.fromRectAndRadius(
        body,
        Radius.circular(edge ? 0 : _dockHeight / 2 * look.cornerScale),
      );
      canvas.drawRRect(outline, Paint()..color = ink.withValues(alpha: 0.26));
      final centreY = body.center.dy;
      void parts(List<String> list, double x) {
        for (final id in list) {
          final width = wide(id);
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(x, centreY - 1.5, width, 3),
              Radius.circular(1.5 * look.cornerScale),
            ),
            Paint()..color = ink.withValues(alpha: 0.7),
          );
          x += width + _gap;
        }
      }

      void icons(double x) {
        for (var index = 0; index < apps; index++) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(x, centreY - _app / 2, _app, _app),
              Radius.circular(1.5 * look.cornerScale),
            ),
            Paint()..color = index == 0 ? accent : ink.withValues(alpha: 0.5),
          );
          x += _app + _gap;
        }
      }

      final left = body.left + 4;
      final right = body.right - 4;
      if (edge) {
        // Along an edge the two ends keep to the corners, and the
        // applications start after the leading parts or sit in the middle.
        parts(leading, left);
        parts(trailing, right - run(trailing));
        icons(
          dock['align'] == 'start'
              ? left + run(leading) + (leading.isEmpty ? 0 : 4)
              : (size.width - appsRun) / 2,
        );
      } else {
        var x = body.center.dx - content / 2;
        parts(leading, x);
        x += run(leading) + (leading.isEmpty ? 0 : 4);
        icons(x);
        x += appsRun + (trailing.isEmpty ? 0 : 4);
        parts(trailing, x);
      }
    }

    // A panel in the look's own corners and line: hanging under the bar, or
    // standing on the dock when the dock holds the parts that open it.
    final panel = shown
        ? Rect.fromLTRB(
            size.width - 34,
            top + _bar + 4,
            size.width - 5,
            size.height - 5,
          )
        : Rect.fromLTRB(size.width - 34, 5, size.width - 5, dockTop - 3);
    final shape = RRect.fromRectAndRadius(
      panel,
      Radius.circular(5 * look.cornerScale),
    );
    canvas.drawRRect(
      shape,
      Paint()..color = ink.withValues(alpha: look.opaque ? 0.22 : 0.12),
    );
    canvas.drawRRect(
      shape.deflate(look.borderFromAccent ? 0.75 : 0.3),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = look.borderFromAccent ? 1.5 : 0.6
        ..color = look.borderFromAccent ? accent : ink.withValues(alpha: 0.25),
    );
  }

  @override
  bool shouldRepaint(_BarSketch old) =>
      old.settings.layoutJson().toString() !=
          settings.layoutJson().toString() ||
      old.look != look ||
      old.ink != ink ||
      old.accent != accent ||
      old.corner != corner ||
      old.barMode != barMode ||
      old.dock.toString() != dock.toString();
}
