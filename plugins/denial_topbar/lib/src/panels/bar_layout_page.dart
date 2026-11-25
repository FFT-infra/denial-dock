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

/// Chinese for the labels this page added for the dock and the bar's mode.
/// Anything not here goes through the bar's own tables.
const Map<String, String> _layoutZh = <String, String>{
  'Launcher': '启动台',
  'Folders and files': '文件夹与文件',
  'Trash': '废纸篓',
  'Before': '应用前',
  'After': '应用后',
  'Top bar': '顶栏栏体',
  'Shown': '显示',
  'Island only': '仅灵动岛',
  'Hidden': '隐藏',
  'Dock': '程序坞',
  'Edge bar': '贴边通栏',
  'Applications': '应用区',
  'One group': '整体居中',
  'Centred': '居中',
  'At the start': '靠起始',
  'Dock parts': '程序坞部件',
  'With the bar hidden or reduced to its island, a Dock that always shows keeps its edge free of windows.':
      '栏体隐藏或只留灵动岛时，始终显示的程序坞会让窗口避开它所在的边。',
  'What sits before and after the applications. Parts of the bar placed here open their panels from the Dock.':
      '应用图标前后放什么。放到这里的顶栏部件会从程序坞一侧展开面板。',
  'Always show': '始终显示',
};

extension on BuildContext {
  /// A label of this page in the shell's language.
  String lt(String en) =>
      Localizations.maybeLocaleOf(this)?.languageCode == 'zh'
      ? _layoutZh[en] ?? tr(en)
      : tr(en);
}

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

  /// The same for the dock's two zones.
  (int, int)? _dockPicked;
  int _dockTarget = 1;

  BarSettings get _s => widget.settings;

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
        _Group(
          title: context.tr('Parts'),
          note: context.tr(
            'Pick a part, then move it along the bar with the arrows; at the end of a zone it goes on into the next. With pointed ends, a separator starts a new segment.',
          ),
          children: <Widget>[
            for (var zone = 0; zone < BarZones.count; zone++)
              Padding(
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
          title: context.lt('Top bar'),
          note: context.lt(
            'With the bar hidden or reduced to its island, a Dock that always shows keeps its edge free of windows.',
          ),
          children: <Widget>[
            _Row(
              label: context.lt('Top bar'),
              trailing: _Segments<KitBarMode>(
                value: kitBarMode.value,
                options: <(KitBarMode, String)>[
                  (KitBarMode.shown, context.lt('Shown')),
                  (KitBarMode.islandOnly, context.lt('Island only')),
                  (KitBarMode.hidden, context.lt('Hidden')),
                ],
                onChanged: (mode) => setState(() => kitBarMode.value = mode),
              ),
            ),
          ],
        ),
        if (dockZones != null && dockLayout != null)
          _Group(
            title: context.lt('Dock parts'),
            note: context.lt(
              'What sits before and after the applications. Parts of the bar placed here open their panels from the Dock.',
            ),
            children: <Widget>[
              for (var zone = 0; zone < 2; zone++)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      SizedBox(
                        width: 52,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            context.lt(_dockZoneNames[zone]),
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
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
              _Row(
                label: dockPickedId == null
                    ? context.tr('No part picked')
                    : context.lt(_partInfo(dockPickedId).$1),
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
                              (zone, context.lt(_dockZoneNames[zone])),
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
                  context.lt('Dock'),
                  dockLayout['shape'] == 'bar' ? 'bar' : 'floating',
                  <(String, String)>[
                    ('floating', context.tr('Floating')),
                    ('bar', context.lt('Edge bar')),
                  ],
                  (v) => kitDock.apply(<String, Object?>{'shape': v}),
                ),
                choice<String>(
                  context.lt('Applications'),
                  '${dockLayout['align'] ?? 'packed'}',
                  <(String, String)>[
                    ('packed', context.lt('One group')),
                    ('center', context.lt('Centred')),
                    ('start', context.lt('At the start')),
                  ],
                  (v) => kitDock.apply(<String, Object?>{'align': v}),
                  enabled: dockLayout['shape'] == 'bar',
                ),
              ),
              _Switch(
                label: context.lt('Always show'),
                value: dockLayout['visibility'] == 'always',
                onChanged: (v) => kitDock.apply(<String, Object?>{
                  'visibility': v ? 'always' : 'smart',
                }),
              ),
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
                context.lt(label),
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
  });

  final BarSettings settings;
  final KitStyle look;
  final Color ink;
  final Color accent;

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
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(5)),
      Paint()..color = ink.withValues(alpha: 0.07),
    );
    canvas.clipRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(5)),
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

    // A panel hanging under the bar, in the look's own corners and line.
    final panel = Rect.fromLTRB(
      size.width - 34,
      top + _bar + 4,
      size.width - 5,
      size.height - 5,
    );
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
      old.accent != accent;
}
