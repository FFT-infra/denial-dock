import 'dart:async';
import 'dart:math' as math;

import 'package:denial_flutter_sdk/models.dart';
import 'package:denial_flutter_sdk/rendering.dart';
import 'package:denial_flutter_sdk/services.dart';
import 'package:denial_flutter_sdk/state.dart';
import 'package:denial_flutter_sdk/theme.dart';
import 'package:denial_shell_kit/continuous_corners.dart';
import 'package:denial_shell_kit/kit_glass.dart';
import 'package:denial_shell_kit/kit_material.dart';
import 'package:denial_shell_kit/kit_motion.dart';
import 'package:denial_shell_kit/kit_springs.dart';
import 'package:denial_shell_kit/kit_style.dart';
import 'package:denial_shell_kit/kit_widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bar_icons.dart';
import '../bar_panel.dart';
import '../bar_preferences.dart';
import '../bar_settings.dart';
import '../bar_type.dart';
import '../debug_remote.dart';
import '../l10n.dart';
import 'mac_kit.dart';
import 'nc_card.dart';
import 'nc_motion.dart';
import 'nc_parts.dart';
import 'tile_grid.dart';
import 'widget_gallery.dart';
import 'widgets.dart';

double get notificationCenterWidth => NcLook.layout.width;

/// Opens the column of notifications and widgets at the bar's far end. There
/// is no slab under it: every card and every widget is a piece of its own on
/// the wallpaper, which is dimmed behind the column so the text reads.
///
/// Non-macOS shell archetypes open their native Notification Centre layout:
/// - GNOME: centered-clock dual-pane Notifications (left + DND) & Calendar (right)
/// - Windows 11: bottom-right Fluent Notifications + collapsible Calendar card
/// - Omarchy / COSMIC / HyprPanel / Material / Noctalia / Caelestia / Plasma / Ax-Shell:
///   framed anchored panel matching the active look's chrome & palette.
void showNotificationCenter({
  required WidgetRef ref,
  required ShellServices services,
  required PanelEdge side,
  required double barHeight,
  GlobalKey? anchor,
  bool notifications = true,
  bool widgets = true,
  String panelId = 'clock',
}) {
  if (kitOpenPanel.value == panelId) {
    closeKitPanel();
    return;
  }
  final style = kitStyle.value;
  final arch = style.archetype;
  final sceneWidth =
      MediaQuery.maybeSizeOf(ref.context)?.width ?? double.infinity;

  if (anchor != null && arch == KitShellArchetype.gnome) {
    final dualWidth = math.min(640.0, sceneWidth - 24);
    showBarPanel(
      ref: ref,
      panelId: panelId,
      anchor: anchor,
      side: side,
      barHeight: barHeight,
      placement: BarPanelAnchor.centred,
      width: dualWidth,
      builder: (context, close) => _GnomeDateMenu(
        services: services,
        side: side,
        barHeight: barHeight,
        onClose: close,
      ),
    );
    return;
  }

  if (anchor != null && arch == KitShellArchetype.windows) {
    showBarPanel(
      ref: ref,
      panelId: panelId,
      anchor: anchor,
      side: side,
      barHeight: barHeight,
      placement: BarPanelAnchor.clock,
      width: math.min(368.0, sceneWidth - 16),
      builder: (context, close) => _WindowsNotificationCenter(
        services: services,
        side: side,
        barHeight: barHeight,
        onClose: close,
      ),
    );
    return;
  }

  final framedArchetype =
      arch != KitShellArchetype.macos &&
      arch != KitShellArchetype.denial &&
      arch != KitShellArchetype.cutefish;
  if (anchor != null &&
      (NcMotion.hangs(square: style.square, anchored: true) ||
          framedArchetype)) {
    final showDnd =
        arch == KitShellArchetype.hyprpanel ||
        arch == KitShellArchetype.material ||
        arch == KitShellArchetype.noctalia ||
        arch == KitShellArchetype.caelestia;
    final placement =
        arch == KitShellArchetype.plasma || arch == KitShellArchetype.axshell
        ? BarPanelAnchor.clock
        : BarPanelAnchor.centred;
    showBarPanel(
      ref: ref,
      panelId: panelId,
      anchor: anchor,
      side: side,
      barHeight: barHeight,
      gap: style.panelStyle == KitPanelStyle.attached ? 0 : null,
      placement: placement,
      width: NcMotion.hangWidth(
        plate: NcLook.layout.width,
        reach: NcCard.reach,
        sceneWidth: sceneWidth,
      ),
      builder: (context, close) => _Column(
        services: services,
        side: side,
        barHeight: barHeight,
        notifications: notifications,
        widgets: widgets,
        framed: true,
        showDndToggle: showDnd,
        onClose: close,
      ),
    );
    return;
  }
  showKitLayer(
    ref: ref,
    keyName: kitPanelKey,
    panelId: panelId,
    // The column goes out on a spring, so it says when it is gone; the
    // durations only time the layer's own progress, which nothing here draws.
    contentEndsClose: true,
    open: KitMotion.settle,
    close: KitMotion.enter,
    builder: (context, close) => _Column(
      services: services,
      side: side,
      barHeight: barHeight,
      notifications: notifications,
      widgets: widgets,
      onClose: close,
    ),
  );
}

/// A row on its way out: how long it waits, and whether it has already been
/// dragged out of sight.
typedef _Going = ({Duration delay, bool swiped});

class _Column extends ConsumerStatefulWidget {
  const _Column({
    required this.services,
    required this.side,
    required this.barHeight,
    required this.notifications,
    required this.widgets,
    required this.onClose,
    this.framed = false,
    this.showDndToggle = false,
  });

  /// Hung in a framed panel under a bar item; see [NcHost.framed].
  final bool framed;

  /// Only shown for shell archetypes that natively place a DND switch in NC
  /// (e.g. HyprPanel / Material / Noctalia / Caelestia); never on macOS/Denial.
  final bool showDndToggle;
  final ShellServices services;
  final PanelEdge side;
  final double barHeight;
  final bool notifications;
  final bool widgets;
  final VoidCallback onClose;

  @override
  ConsumerState<_Column> createState() => _ColumnState();
}

class _ColumnState extends ConsumerState<_Column>
    with TickerProviderStateMixin
    implements NcHost {
  /// The column on screen and where its slide is. One opened in the frame
  /// another is taken down, as when the bar's item is pressed again while
  /// the column leaves, carries on from there instead of starting over from
  /// the edge.
  static _ColumnState? _live;
  static double _liveValue = 0;
  static double _liveVelocity = 0;

  late final DesktopNotificationsController _controller;

  // ── The slide ──
  late final KitSpring _slide = KitSpring(0, ncSpring(NcMotion.slide));
  late final KitSprings _springs = KitSprings(this, <KitSpring>[_slide]);
  final ValueNotifier<Offset> _shift = ValueNotifier<Offset>(Offset.zero);

  /// How far in the column is, for the dimming behind it.
  final ValueNotifier<double> _shown = ValueNotifier<double>(0);

  /// Whether cards blur what is behind them: enabled from frame 0 inside the
  /// column's single [BackdropGroup] so cards and widgets slide in with their
  /// final glass material and never flash or jump after landing.
  final ValueNotifier<bool> _glass = ValueNotifier<bool>(true);
  Animation<double>? _layer;
  VoidCallback? _finish;
  double _travel = notificationCenterWidth + 24;
  bool _opened = false;
  bool _closing = false;

  // ── What is shown ──
  /// The older stacks are listed too, after a press on the pill that stood
  /// for them.
  bool _all = false;
  bool _editing = false;
  final bool _ready = true;
  bool _readScheduled = false;
  List<DesktopNotificationGroup> _groups = const <DesktopNotificationGroup>[];
  final Set<String> _seen = <String>{};
  final Set<String> _fresh = <String>{};

  // ── What is leaving ──
  final Map<String, _Going> _groupsGoing = <String, _Going>{};
  final Map<int, _Going> _cardsGoing = <int, _Going>{};
  bool _clearing = false;
  Timer? _clearTimer;

  // ── Keyboard ──
  final ValueNotifier<bool> _keys = ValueNotifier<bool>(false);
  final FocusScopeNode _scope = FocusScopeNode(debugLabel: 'nc');
  final Map<int, FocusNode> _nodes = <int, FocusNode>{};
  final ScrollController _scroll = ScrollController();

  // ── The menu of a card's further actions ──
  final GlobalKey _sceneKey = GlobalKey();
  ({Rect anchor, List<NcMenuItem> items})? _menu;
  FocusNode? _menuReturn;

  ShellServices get services => widget.services;
  PanelEdge get side => widget.side;
  double get barHeight => widget.barHeight;
  bool get notifications => widget.notifications;
  bool get widgets => widget.widgets;
  VoidCallback get onClose => widget.onClose;

  @override
  bool get framed => widget.framed;

  @override
  void initState() {
    super.initState();
    _controller = ref.read(desktopNotificationsProvider.notifier);
    debugCommand.addListener(_debug);
    if (framed) {
      // The panel that frames it does the coming and going.
      _slide.value = 1;
    } else {
      _slide
        ..value = _liveValue.clamp(0.0, 1.0)
        ..velocity = _liveVelocity;
      _live = this;
    }
    _springs
      ..addListener(_place)
      ..onRest = _rested;
    // The spring starts once the first frame is out. That frame builds the
    // column, the heaviest one there is, and a motion that begins inside it
    // would spend its opening on a frame nobody sees move.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _opened = true;
      _springs.kick(reduceMotion: KitMotion.reduced(context));
      _scope.requestFocus();
      final first = _focusable().firstOrNull;
      if (first != null) _nodes[first]?.requestFocus();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final layer = KitLayer.of(context);
    _finish = layer.finish;
    if (layer.animation != _layer) {
      _layer?.removeStatusListener(_onStatus);
      _layer = layer.animation..addStatusListener(_onStatus);
      _slide.target = layer.animation.status == AnimationStatus.reverse ? 0 : 1;
    }
  }

  @override
  void dispose() {
    debugCommand.removeListener(_debug);
    _layer?.removeStatusListener(_onStatus);
    _clearTimer?.cancel();
    if (_live == this) {
      _live = null;
      // Kept until this frame is over, for a column that replaces this one.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_live == null) {
          _liveValue = 0;
          _liveVelocity = 0;
        }
      });
    }
    // What the user cleared just before closing is still cleared.
    final controller = _controller;
    final all = _clearing;
    final groups = _groupsGoing.keys.toList();
    final cards = _cardsGoing.keys.toList();
    if (all || groups.isNotEmpty || cards.isNotEmpty) {
      scheduleMicrotask(() {
        if (all) {
          controller.clearAll();
          return;
        }
        groups.forEach(controller.dismissGroupFromHistory);
        cards.forEach(controller.dismissFromHistory);
      });
    }
    _springs.dispose();
    _shift.dispose();
    _shown.dispose();
    _glass.dispose();
    _keys.dispose();
    _scope.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ── The slide ──

  void _onStatus(AnimationStatus status) {
    final open = switch (status) {
      AnimationStatus.forward => true,
      AnimationStatus.reverse => false,
      _ => null,
    };
    if (open == null) return;
    if (framed) {
      if (_closing == open) setState(() => _closing = !open);
      return;
    }
    // The same spring both ways: a close while the column is still coming in
    // turns it round from where it is, at the speed it has.
    _slide.target = open ? 1 : 0;
    if (_closing == open) setState(() => _closing = !open);
    if (_opened) _springs.kick(reduceMotion: KitMotion.reduced(context));
  }

  void _place() {
    final sign = side == PanelEdge.left ? -1.0 : 1.0;
    _shift.value = Offset(sign * _travel * (1 - _slide.value), 0);
    _shown.value = _slide.value.clamp(0.0, 1.0);
    if (_live == this) {
      _liveValue = _slide.value;
      _liveVelocity = _slide.velocity;
    }
  }

  void _rested() {
    if (_slide.target == 0) {
      if (_live == this) {
        _liveValue = 0;
        _liveVelocity = 0;
      }
      // Reduced motion gets here inside the call that started the close.
      final finish = _finish;
      if (_closing && finish != null) scheduleMicrotask(finish);
    } else if (mounted) {
      // Lets the build below mark what is listed as read, now that doing so
      // no longer rebuilds the column while it is moving.
      setState(() {});
    }
  }

  // ── Debug commands ──

  void _debug() {
    final words = debugWords();
    if (words.isEmpty) return;
    switch (words.first) {
      case 'ncedit':
        setState(() => _editing = !_editing);
      case 'widgets' when words.length > 1:
        _save(words[1].split(','));
      case 'wide' when words.length > 1:
        _resize(words[1]);
    }
  }

  // ── Widgets ──

  void _save(List<String> ids) => ref
      .read(barSettingsProvider.notifier)
      .save((s) => s.copyWith(widgets: ids));

  void _resizeTo(String id, TileSize next) =>
      ref.read(barSettingsProvider.notifier).save((s) {
        final sizes = parseTileSizes(s.tileSizes);
        return s.copyWith(
          tileSizes: writeTileSizes(<String, TileSize>{
            ...sizes,
            widgetSizeKey(id): next,
          }),
        );
      });

  void _resize(String id) {
    final s = ref.read(barSettingsProvider).value ?? BarSettings.defaults;
    final sizes = parseTileSizes(s.tileSizes);
    final spec = kitWidgetRegistry.byId(id);
    if (spec == null || !spec.resizable) return;
    final cur = resolveWidgetSize(id, sizes) ?? spec.defaultSize;
    final next = spec.nextSize(cur);
    _resizeTo(id, TileSize(next.w, next.h));
  }

  void _showWidgetMenu(
    BuildContext context,
    String id,
    Rect anchor,
    List<String> order,
    Map<String, TileSize> sizes,
  ) {
    final spec = kitWidgetRegistry.byId(id);
    if (spec == null) return;
    final cur = resolveWidgetSize(id, sizes) ?? spec.defaultSize;
    final items = <NcMenuItem>[
      for (final sz in spec.supportedSizes)
        NcMenuItem(
          label:
              '${sz == cur ? '✓ ' : '   '}${context.tr(sz.label)} (${sz.gridLabel})',
          onTap: () => _resizeTo(id, TileSize(sz.w, sz.h)),
        ),
      if (id == 'clock')
        NcMenuItem(
          label: context.tr(
            widgetClockDigital.value ? 'Analog Clock' : 'Digital Clock',
          ),
          onTap: () => setWidgetClockDigital(!widgetClockDigital.value),
        ),
      NcMenuItem(
        label: context.tr(
          kitWidgetStyle.value == KitWidgetStyle.glass
              ? 'Use Color Cards'
              : 'Use Glass Cards',
        ),
        onTap: () => kitWidgetStyle.value =
            kitWidgetStyle.value == KitWidgetStyle.glass
            ? KitWidgetStyle.color
            : KitWidgetStyle.glass,
      ),
      NcMenuItem(
        label: context.tr('Edit Widgets'),
        onTap: () => setState(() => _editing = true),
      ),
      NcMenuItem(
        label: context.tr('Remove Widget'),
        onTap: () => _save(<String>[
          for (final other in order)
            if (other != id) other,
        ]),
      ),
    ];
    showMenu(anchor, items);
  }

  List<Widget> _widgets(BuildContext context, double width) {
    ensureCustomWidgetsLoaded();
    final theme = context.shellTheme;
    final wStyle = kitWidgetStyle.value;
    final sizes = parseTileSizes(
      ref.watch(
        barSettingsProvider.select(
          (state) => state.value?.tileSizes ?? const <String>[],
        ),
      ),
    );
    final order = ref.watch(
      barSettingsProvider.select(
        (state) => state.value?.widgets ?? defaultWidgets,
      ),
    );
    final shown = <String>[
      for (final id in order)
        if (widgetTileSize(id, sizes) != null) id,
    ];
    final side = NcMotion.widgetCell(width);
    final cell = Size.square(side);
    const gap = NcMotion.widgetGap;
    final Widget grid;
    if (_ready) {
      grid = TileGrid(
        tiles: <Tile>[
          for (final id in shown)
            Tile(
              id: id,
              size: widgetTileSize(id, sizes)!,
              supportedSizes: widgetSupportedTileSizes(id),
              onResize: widgetResizable(id) ? () => _resize(id) : null,
              onResizeTo: widgetResizable(id)
                  ? (next) => _resizeTo(id, next)
                  : null,
              onSecondaryTap: (anchor) =>
                  _showWidgetMenu(context, id, anchor, order, sizes),
              child: _Surface(
                fill: widgetPlate(id, theme, style: wStyle),
                child: buildBarWidget(
                  id,
                  services,
                  side,
                  size: resolveWidgetSize(id, sizes)!,
                  widgetStyle: wStyle,
                  onClosePanel: onClose,
                ),
              ),
            ),
        ],
        columns: NcMotion.widgetColumns,
        cell: cell,
        gap: gap,
        editing: _editing,
        onReorder: _save,
        onRemove: (id) => _save(<String>[
          for (final other in order)
            if (other != id) other,
        ]),
      );
    } else {
      // The widgets come one frame after the column, so the frame that
      // opens it is only the cards. Their room is kept, so nothing moves
      // when they arrive.
      final rows = packTiles(<TileSize>[
        for (final id in shown) widgetTileSize(id, sizes)!,
      ], NcMotion.widgetColumns).rows;
      grid = SizedBox(height: NcMotion.widgetsHeight(rows, width));
    }
    return <Widget>[
      grid,
      if (_ready)
        Reveal(
          open: _editing,
          child: Padding(
            padding: const EdgeInsets.only(top: gap),
            child: _Surface(
              child: WidgetGallery(
                activeIds: order,
                onAdd: (id, size) {
                  _resizeTo(id, TileSize(size.w, size.h));
                  _save(<String>[...order, id]);
                },
              ),
            ),
          ),
        ),
      const SizedBox(height: 14),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          if (_editing) ...<Widget>[
            NcChip(
              label: context.tr('Reset'),
              large: true,
              onTap: () => _save(defaultWidgets),
            ),
            const SizedBox(width: 8),
          ],
          NcChip(
            label: context.tr(_editing ? 'Done' : 'Edit Widgets'),
            large: true,
            onTap: () => setState(() => _editing = !_editing),
          ),
          const SizedBox(width: 8),
          // Closes the column, as a press on the wallpaper does.
          NcDot(extent: _floatDot, floating: true, onTap: onClose),
        ],
      ),
    ];
  }

  // ── Clearing ──

  void _clearGroup(String key, bool swiped) {
    if (_groupsGoing.containsKey(key)) return;
    setState(() => _groupsGoing[key] = (delay: Duration.zero, swiped: swiped));
    _keepFocus();
  }

  void _groupGone(String key) {
    // Clear All takes everything at once when its last row has gone.
    if (_clearing || !_groupsGoing.containsKey(key)) return;
    _controller.dismissGroupFromHistory(key);
    // A group its sender does not let go is still listed after this, and
    // comes back into its place.
    setState(() => _groupsGoing.remove(key));
  }

  void _clearCard(int id, bool swiped) {
    if (_cardsGoing.containsKey(id)) return;
    setState(() => _cardsGoing[id] = (delay: Duration.zero, swiped: swiped));
    _keepFocus();
  }

  void _cardGone(int id) {
    if (_clearing || !_cardsGoing.containsKey(id)) return;
    _controller.dismissFromHistory(id);
    setState(() => _cardsGoing.remove(id));
  }

  /// Clears the list one row after another, top first, and tells the store
  /// once the last has gone. Rows the list has not built have nothing to
  /// play, so the wait is timed rather than counted.
  void _clearAll() {
    final leaving = <DesktopNotificationGroup>[
      for (final group in _groups)
        if (group.clearable && !_groupsGoing.containsKey(group.key)) group,
    ];
    if (leaving.isEmpty || _clearing) return;
    setState(() {
      _clearing = true;
      for (var i = 0; i < leaving.length; i++) {
        _groupsGoing[leaving[i].key] = (
          delay: Duration(milliseconds: NcMotion.clearDelay(i).round()),
          swiped: false,
        );
      }
    });
    final wait = KitMotion.duration(
      context,
      Duration(milliseconds: NcMotion.clearDelay(leaving.length - 1).round()) +
          KitMotion.fade +
          KitMotion.rebound,
    );
    _clearTimer?.cancel();
    _clearTimer = Timer(wait, () {
      if (!mounted) return;
      _controller.clearAll();
      setState(() {
        _clearing = false;
        _groupsGoing.clear();
        _cardsGoing.clear();
      });
    });
    _scope.requestScopeFocus();
  }

  // ── Keyboard ──

  @override
  ValueListenable<bool> get keys => _keys;

  @override
  ValueListenable<bool> get glass => _glass;

  @override
  double get outward => side == PanelEdge.left ? -1 : 1;

  @override
  void attach(int id, FocusNode node) => _nodes[id] = node;

  @override
  void detach(int id, FocusNode node) {
    if (_nodes[id] == node) _nodes.remove(id);
  }

  /// The cards the keyboard can land on, top to bottom.
  List<int> _focusable() => <int>[
    for (final group in _groups)
      if (!_groupsGoing.containsKey(group.key))
        for (final record in group.members)
          if (!_cardsGoing.containsKey(record.notification.id) &&
              (_nodes[record.notification.id]?.canRequestFocus ?? false) &&
              _nodes[record.notification.id]!.context != null)
            record.notification.id,
  ];

  @override
  void leave(int id) {
    if (!(_nodes[id]?.hasFocus ?? false)) return;
    final ids = _focusable();
    final at = ids.indexOf(id);
    final next = at < 0
        ? null
        : at + 1 < ids.length
        ? ids[at + 1]
        : at > 0
        ? ids[at - 1]
        : null;
    if (next == null) {
      _scope.requestScopeFocus();
    } else {
      _nodes[next]?.requestFocus();
    }
  }

  /// After something that held the focus has gone, the column takes it back,
  /// so the keys keep reaching it.
  void _keepFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_scope.hasFocus) _scope.requestFocus();
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    // Escape belongs to the layer, which closes the column.
    if (key == LogicalKeyboardKey.escape || _closing) {
      return KeyEventResult.ignored;
    }
    final arrow =
        key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowUp;
    final steers =
        arrow ||
        key == LogicalKeyboardKey.tab ||
        key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.backspace ||
        ncActivates(event);
    if (steers && !_keys.value) {
      // The first key only shows where the focus is. Until then nothing
      // marks the card it is on, and a key must not act on a card the user
      // cannot see is chosen.
      _keys.value = true;
      final ids = _focusable();
      if (ids.any((id) => _nodes[id]!.hasFocus)) return KeyEventResult.handled;
      if (ids.isNotEmpty) {
        _nodes[ids.first]!.requestFocus();
        return KeyEventResult.handled;
      }
    }
    if (key == LogicalKeyboardKey.tab) {
      final back = HardwareKeyboard.instance.isShiftPressed;
      final focus = FocusManager.instance.primaryFocus;
      if (focus == null || focus == _scope || focus.context == null) {
        _focusEdge(last: back);
      } else if (back) {
        focus.previousFocus();
      } else {
        focus.nextFocus();
      }
      return KeyEventResult.handled;
    }
    if (arrow) {
      final ids = _focusable();
      if (ids.isEmpty) return KeyEventResult.handled;
      final down = key == LogicalKeyboardKey.arrowDown;
      final at = ids.indexWhere((id) => _nodes[id]!.hasFocus);
      final next = at < 0
          ? (down ? 0 : ids.length - 1)
          : (at + (down ? 1 : -1)).clamp(0, ids.length - 1);
      _nodes[ids[next]]!.requestFocus();
      return KeyEventResult.handled;
    }
    final page = switch (key) {
      LogicalKeyboardKey.pageDown => 0.8,
      LogicalKeyboardKey.pageUp => -0.8,
      LogicalKeyboardKey.end => double.infinity,
      LogicalKeyboardKey.home => double.negativeInfinity,
      _ => null,
    };
    if (page == null || !_scroll.hasClients) return KeyEventResult.ignored;
    final position = _scroll.position;
    final to = (position.pixels + page * position.viewportDimension).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    final time = KitMotion.duration(context, KitMotion.enter);
    if (time == Duration.zero) {
      _scroll.jumpTo(to);
    } else {
      _scroll.animateTo(to, duration: time, curve: KitMotion.out);
    }
    return KeyEventResult.handled;
  }

  void _focusEdge({required bool last}) {
    final ids = _focusable();
    if (ids.isEmpty) return;
    _nodes[last ? ids.last : ids.first]!.requestFocus();
  }

  // ── The menu ──

  @override
  void showMenu(Rect anchor, List<NcMenuItem> items) {
    final scene = _sceneKey.currentContext?.findRenderObject();
    final local = scene is RenderBox && scene.hasSize
        ? Rect.fromPoints(
            scene.globalToLocal(anchor.topLeft),
            scene.globalToLocal(anchor.bottomRight),
          )
        : anchor;
    _menuReturn = FocusManager.instance.primaryFocus;
    setState(() => _menu = (anchor: local, items: items));
  }

  void _closeMenu() {
    if (_menu == null) return;
    setState(() => _menu = null);
    final back = _menuReturn;
    _menuReturn = null;
    if (back != null && back.context != null && back.canRequestFocus) {
      back.requestFocus();
    } else {
      _keepFocus();
    }
  }

  // ── The column ──

  /// The round controls that stand on the wallpaper.
  static const double _floatDot = 28;

  /// The heading, written straight on the wallpaper, and the round button
  /// that clears the list. The button says what it does under the pointer.
  Widget _title(BuildContext context, bool canClear) {
    final dnd = widget.showDndToggle
        ? ref.watch(
            desktopNotificationsProvider.select((s) => s.doNotDisturb),
          )
        : false;
    final theme = context.shellTheme;
    final style = KitStyle.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NcCard.reach + 8,
        2,
        NcCard.reach + 2,
        0,
      ),
      child: SizedBox(
        height: 34,
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                context.tr('Notification Center'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: BarType.title.copyWith(
                  fontSize: framed ? 16 : 22,
                  fontWeight: FontWeight.w700,
                  color: ncGroundInk(context, framed: framed),
                  shadows: ncGroundShadow(context),
                ),
              ),
            ),
            if (widget.showDndToggle) ...<Widget>[
              Pressable(
                onTap: () => ref
                    .read(desktopNotificationsProvider.notifier)
                    .toggleDoNotDisturb(),
                shape: BorderRadius.circular(style.corner(12)),
                child: Container(
                  height: 26,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: dnd
                        ? style.accent(theme)
                        : theme.colors.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(style.corner(12)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      BarGlyph(
                        BarIcons.moonFill,
                        size: 12,
                        color: dnd
                            ? style.onAccent(theme)
                            : theme.colors.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        context.tr('Focus'),
                        style: BarType.caption.copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: dnd
                              ? style.onAccent(theme)
                              : theme.colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
            ],
            IgnorePointer(
              ignoring: !canClear,
              child: AnimatedOpacity(
                duration: KitMotion.duration(context, KitMotion.fill),
                opacity: canClear ? 1 : 0,
                child: NcDot(
                  extent: _floatDot,
                  floating: true,
                  label: context.tr('Clear All'),
                  enabled: canClear,
                  onTap: _clearAll,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) =>
      NcScope(host: this, child: Builder(builder: _body));

  Widget _body(BuildContext context) {
    final scene = MediaQuery.sizeOf(context);
    final state = ref.watch(desktopNotificationsProvider);
    final groups = notifications
        ? state.groups
        : const <DesktopNotificationGroup>[];
    _groups = groups;
    // Whatever is listed here has been seen, including what arrives while
    // the column is open. The state may not change during a build, and the
    // column is not rebuilt for it while it slides.
    if (notifications &&
        state.unreadCount > 0 &&
        !_readScheduled &&
        _opened &&
        !_springs.moving) {
      _readScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _readScheduled = false;
        if (mounted) _controller.markAllRead();
      });
    }
    // The newest stacks are listed; the older ones wait behind a pill.
    final listed = NcMotion.groupsListed(groups.length, all: _all);
    final shown = groups.sublist(0, listed);
    var older = 0;
    for (final group in groups.skip(listed)) {
      older += group.members.length;
    }
    // A stack that turns up once the column is open grows into its place,
    // whether it has just arrived or has come out from behind the pill.
    final keys = <String>{for (final group in shown) group.key};
    for (final key in keys) {
      if (_seen.add(key) && _opened) _fresh.add(key);
    }
    _seen.retainAll(keys);
    if (_fresh.isNotEmpty) {
      // Only the frame a stack arrives in: a row built later, because it
      // scrolled into view, is simply there.
      WidgetsBinding.instance.addPostFrameCallback((_) => _fresh.clear());
    }

    // The cards are [plate] wide and stand [NcLook.edge] from the screen's
    // edge. The column's own box is wider by what a card's close dot reaches
    // past its plate.
    final plate = framed
        ? NcMotion.hangPlate(
            width: NcMotion.hangWidth(
              plate: NcLook.layout.width,
              reach: NcCard.reach,
              sceneWidth: scene.width,
            ),
            reach: NcCard.reach,
          )
        : math.min(NcLook.layout.width, scene.width - NcLook.layout.edge * 2);
    final width = plate + NcCard.reach * 2;
    final inset = NcLook.layout.edge - NcCard.reach;
    final onLeft = side == PanelEdge.left;
    _travel = width + 24;
    _place();

    final staying = <DesktopNotificationGroup>[
      for (final group in groups)
        if (!_groupsGoing.containsKey(group.key)) group,
    ];
    final canClear = !_clearing && staying.any((group) => group.clearable);

    final rows = <Widget>[
      if (notifications)
        KeyedSubtree(
          key: const ValueKey<String>('title'),
          child: _title(context, canClear),
        ),
      if (notifications || !widgets)
        NcPresence(
          key: const ValueKey<String>('empty'),
          // Once the list is really empty, so it follows a Clear All rather
          // than opening its room among cards that are still going.
          present: groups.isEmpty,
          child: SizedBox(
            height: widgets ? 46 : 72,
            child: Center(
              child: Text(
                context.tr('No Notifications'),
                style: BarType.menuRow.copyWith(
                  color: ncGroundInk(context, dim: true, framed: framed),
                  shadows: ncGroundShadow(context),
                ),
              ),
            ),
          ),
        ),
      for (final group in shown)
        NcPresence(
          key: ValueKey<String>('group:${group.key}'),
          present: !_groupsGoing.containsKey(group.key),
          delay: _groupsGoing[group.key]?.delay ?? Duration.zero,
          swiped: _groupsGoing[group.key]?.swiped ?? false,
          appear: _fresh.contains(group.key),
          onGone: () => _groupGone(group.key),
          child: _GroupStack(
            group: group,
            services: services,
            going: _cardsGoing,
            leaving: _groupsGoing.containsKey(group.key),
            onActivate: (id) {
              _controller.invokeDefaultAction(id);
              onClose();
            },
            onAction: (id, key) {
              _controller.invokeAction(id, key);
              onClose();
            },
            onClearCard: _clearCard,
            onCardGone: _cardGone,
            onClearGroup: (swiped) => _clearGroup(group.key, swiped),
          ),
        ),
      if (notifications)
        NcPresence(
          key: const ValueKey<String>('older'),
          present: older > 0 && !_clearing,
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Center(
              child: NcChip(
                label: context.tr('{} More Notifications', older),
                large: true,
                enabled: older > 0,
                onTap: () {
                  setState(() => _all = true);
                  _keepFocus();
                },
              ),
            ),
          ),
        ),
      if (widgets)
        Padding(
          key: const ValueKey<String>('widgets'),
          padding: const EdgeInsets.fromLTRB(NcCard.reach, 16, NcCard.reach, 0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _widgets(context, plate),
          ),
        ),
    ];
    final places = <Key, int>{
      for (var i = 0; i < rows.length; i++) rows[i].key!: i,
    };
    final menu = _menu;

    // One reading of the screen for every card's blur.
    final list = BackdropGroup(
      // What scrolls is cut above and below, where the column ends. Its
      // sides are open: a card dragged away leaves across the screen's
      // edge, and a shadow is not cut off beside its card.
      child: ClipRect(
        clipper: const NcBandClip(),
        // From the first row's top to the last one's bottom the whole
        // width scrolls, under a wheel or a drag, the space between the
        // cards included. On the wallpaper a tap in that space closes the
        // column, as a press beside it does; in a framed panel the space is
        // the panel's and does nothing.
        child: _GapTap(
          onTap: framed ? null : onClose,
          child: CustomScrollView(
            controller: _scroll,
            shrinkWrap: true,
            clipBehavior: Clip.none,
            hitTestBehavior: HitTestBehavior.opaque,
            slivers: <Widget>[
              SliverPadding(
                padding: const EdgeInsets.only(bottom: 4),
                sliver: SliverList(
                  // Every row keeps the repaint boundary the delegate gives
                  // it, so a scroll moves painted cards.
                  delegate: SliverChildBuilderDelegate(
                    (context, index) =>
                        _Row(key: rows[index].key, child: rows[index]),
                    childCount: rows.length,
                    findChildIndexCallback: (key) => places[key],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final layers = <Widget>[
      if (menu != null && !_closing)
        Positioned.fill(
          child: NcMenu(
            anchor: menu.anchor,
            items: menu.items,
            keyboard: _keys.value,
            onClose: _closeMenu,
          ),
        ),
    ];

    final Widget body;
    if (framed) {
      // The panel around it is the frame, the fill and the motion; this is
      // only the list, held to its share of the screen.
      body = ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: NcMotion.hangHeight(scene.height),
        ),
        child: IgnorePointer(
          ignoring: _closing,
          child: Stack(
            key: _sceneKey,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.all(NcMotion.hangPad),
                child: list,
              ),
              ...layers,
            ],
          ),
        ),
      );
    } else {
      body = Stack(
        key: _sceneKey,
        fit: StackFit.expand,
        children: <Widget>[
          // The wallpaper darkens toward the edge the column is at. It is
          // paint only, and follows the slide without a build.
          Positioned(
            left: onLeft ? 0 : null,
            right: onLeft ? null : 0,
            top: 0,
            bottom: 0,
            width: math.min(
              scene.width,
              width +
                  inset +
                  NcLook.layout.dimReach +
                  (onLeft || side == PanelEdge.right ? barHeight : 0),
            ),
            child: IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _DimPainter(shown: _shown, fromLeft: onLeft),
                ),
              ),
            ),
          ),
          Positioned(
            left: onLeft ? barHeight + inset : null,
            right: onLeft
                ? null
                : (side == PanelEdge.right ? barHeight + inset : inset),
            top: side == PanelEdge.top ? barHeight + 8 : 10,
            bottom: side == PanelEdge.bottom ? barHeight + 8 : 10,
            width: width,
            // The slide moves a layer that is already painted: no frame of
            // it builds, lays out or paints the column again.
            child: CompositedTranslation(
              translation: _shift,
              devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
              // A column on its way out takes no more input.
              child: IgnorePointer(
                ignoring: _closing,
                child: Align(alignment: Alignment.topCenter, child: list),
              ),
            ),
          ),
          ...layers,
        ],
      );
    }

    return NcScope(
      host: this,
      child: FocusScope(
        node: _scope,
        onKeyEvent: _onKey,
        child: FocusTraversalGroup(
          child: Listener(
            onPointerDown: (_) => _keys.value = false,
            child: body,
          ),
        ),
      ),
    );
  }
}

/// Marks a row of the column, so a press can be told from one that fell in
/// the space between rows.
class _Row extends SingleChildRenderObjectWidget {
  const _Row({required Widget super.child, super.key});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderRow();
}

class _RenderRow extends RenderProxyBox {}

/// Tells a tap in the space between the rows below it from everything else.
///
/// The list under it takes every press in its box, so a wheel or a drag
/// scrolls from anywhere in the column. A press that reached no row is in a
/// gap: it joins the same contest as the list's drag, and counts as a tap
/// only if the pointer comes up without having scrolled.
class _GapTap extends SingleChildRenderObjectWidget {
  const _GapTap({required this.onTap, required Widget super.child});

  final VoidCallback? onTap;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderGapTap()..onTap = onTap;

  @override
  void updateRenderObject(BuildContext context, _RenderGapTap renderObject) =>
      renderObject.onTap = onTap;
}

class _RenderGapTap extends RenderProxyBox {
  final TapGestureRecognizer _tap = TapGestureRecognizer(
    debugOwner: 'notification centre gap',
  );

  VoidCallback? get onTap => _tap.onTap;
  set onTap(VoidCallback? value) => _tap.onTap = value;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!size.contains(position)) return false;
    final before = result.path.length;
    final taken = hitTestChildren(result, position: position);
    final onRow = result.path
        .skip(before)
        .any((entry) => entry.target is _RenderRow);
    // Only a press in a gap is this box's own; one on a row belongs to the
    // row, and what it leaves alone stays alone.
    if (taken && !onRow && onTap != null) {
      result.add(BoxHitTestEntry(this, position));
    }
    return taken;
  }

  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    if (event is PointerDownEvent) _tap.addPointer(event);
  }

  @override
  void dispose() {
    _tap.dispose();
    super.dispose();
  }
}

/// The dimming behind the column: dark at the screen's edge and gone a
/// little way past the column. It comes and goes with the slide.
class _DimPainter extends CustomPainter {
  _DimPainter({required this.shown, required this.fromLeft})
    : super(repaint: shown);

  final ValueListenable<double> shown;
  final bool fromLeft;

  @override
  void paint(Canvas canvas, Size size) {
    final strength = NcLook.layout.dim * shown.value.clamp(0.0, 1.0);
    if (strength <= 0 || size.isEmpty) return;
    Color dark(double share) =>
        Color.fromRGBO(0, 0, 0, (strength * share).clamp(0.0, 1.0));
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: fromLeft ? Alignment.centerLeft : Alignment.centerRight,
          end: fromLeft ? Alignment.centerRight : Alignment.centerLeft,
          // Even under the column, then eased out to nothing.
          colors: <Color>[dark(1), dark(0.82), dark(0.3), dark(0)],
          stops: const <double>[0, 0.55, 0.82, 1],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_DimPainter old) =>
      old.shown != shown || old.fromLeft != fromLeft;
}

/// A widget's card: follows unified [KitGlass] (all 5 [KitSurfaceMode]s, shared
/// in the column's [BackdropGroup]) when [KitWidgetStyle.glass] is active, or
/// draws its signature opaque/paper colour plate when [KitWidgetStyle.color] is
/// chosen.
class _Surface extends StatelessWidget {
  const _Surface({required this.child, this.fill});

  /// The widget's signature colour under [KitWidgetStyle.color]; null uses
  /// unified [KitGlass].
  final Color? fill;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final style = KitStyle.of(context);
    final host = NcScope.of(context);
    final framed = host.framed;
    final radius = style.outer(theme, NcLook.widgetRadius);
    if (fill == null &&
        kitWidgetStyle.value == KitWidgetStyle.glass &&
        !framed) {
      return Listener(
        behavior: HitTestBehavior.opaque,
        child: ValueListenableBuilder<bool>(
          valueListenable: host.glass,
          builder: (context, blurs, child) => KitGlass(
            material: kitMaterialOf(context, KitTier.card),
            tier: KitTier.card,
            radius: radius,
            grouped: true,
            blur: blurs,
            child: child,
          ),
          child: child,
        ),
      );
    }
    final shape = ContinuousCorners(radius: radius);
    return Listener(
      behavior: HitTestBehavior.opaque,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          shape: shape,
          color: fill ?? NcLook.widgetFill(theme),
          shadows: framed ? null : style.cast(NcLook.widgetShadow(theme)),
        ),
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: ShapeDecoration(
            shape: ContinuousCorners(
              radius: shape.radius,
              side: style.flat
                  ? BorderSide(color: theme.colors.hairline)
                  : BorderSide(color: theme.colors.hairlineSoft, width: 0.5),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// One application's notifications. Two or more sit as a stack: the newest
/// card whole, and the lower edges of two more showing under it. A tap fans
/// the stack open.
///
/// One number moves all of it: how far the stack is open. Each card's room,
/// its plate, its text, the group's title and the space the edges need are
/// all read from that number, so they cannot fall out of step.
class _GroupStack extends StatefulWidget {
  const _GroupStack({
    required this.group,
    required this.services,
    required this.going,
    required this.leaving,
    required this.onActivate,
    required this.onAction,
    required this.onClearCard,
    required this.onCardGone,
    required this.onClearGroup,
  });

  final DesktopNotificationGroup group;
  final ShellServices services;

  /// The cards on their way out, by id.
  final Map<int, _Going> going;

  /// The whole group is on its way out.
  final bool leaving;
  final ValueChanged<int> onActivate;
  final void Function(int id, String key) onAction;
  final void Function(int id, bool swiped) onClearCard;
  final ValueChanged<int> onCardGone;
  final ValueChanged<bool> onClearGroup;

  @override
  State<_GroupStack> createState() => _GroupStackState();
}

class _GroupStackState extends State<_GroupStack>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  late final KitSpring _fold = KitSpring(0, ncSpring(NcMotion.unfold));
  late final KitSprings _springs = KitSprings(this, <KitSpring>[_fold]);
  final ValueNotifier<double> _t = ValueNotifier<double>(0);

  /// Asked to be open, and whether the cards behind are built. They are
  /// from the moment the stack starts to open until it has folded again;
  /// folded, the front card draws their edges itself.
  bool _open = false;
  bool _spread = false;

  /// Open and come to rest: the cards lie clear of one another, and those
  /// behind may blur what is behind them as the front one does.
  bool _still = false;

  /// An open stack stays open when the list scrolls it out of reach.
  @override
  bool get wantKeepAlive => _spread;

  @override
  void initState() {
    super.initState();
    _springs
      ..addListener(() => _t.value = _fold.value)
      ..onRest = _rested;
  }

  @override
  void didUpdateWidget(_GroupStack old) {
    super.didUpdateWidget(old);
    // A stack cleared down to one card is no stack; its title folds away.
    if (_open && !widget.group.stacked) {
      _open = false;
      _still = false;
      _aim();
    }
  }

  @override
  void dispose() {
    _springs.dispose();
    _t.dispose();
    super.dispose();
  }

  void _setOpen(bool open) {
    if (open == _open || (open && !widget.group.stacked)) return;
    setState(() {
      _open = open;
      _still = false;
      if (open) _spread = true;
    });
    updateKeepAlive();
    _aim();
  }

  void _aim() {
    _fold
      ..tune(
        ncTuning(
          context,
          plain: NcMotion.unfold,
          liquid: NcMotion.unfoldLiquid,
        ),
      )
      ..target = _open ? 1 : 0;
    _springs.kick(reduceMotion: KitMotion.reduced(context));
  }

  void _rested() {
    // This can be reached from a build, when motion is reduced.
    scheduleMicrotask(() {
      if (!mounted || _springs.moving) return;
      if (_open) {
        if (!_still) setState(() => _still = true);
        return;
      }
      if (!_spread) return;
      setState(() => _spread = false);
      updateKeepAlive();
    });
  }

  Widget _member(int index) {
    final group = widget.group;
    final count = group.members.length;
    final note = group.members[index].notification;
    final going = widget.going[note.id];
    final folded = group.stacked && !_open;
    return NcPresence(
      key: ValueKey<int>(note.id),
      present: going == null,
      swiped: going?.swiped ?? false,
      onGone: () => widget.onCardGone(note.id),
      child: ValueListenableBuilder<double>(
        valueListenable: _t,
        // A card behind takes its room as the stack opens. The front card's
        // room is its own from the start.
        builder: (context, t, child) => Align(
          alignment: Alignment.topCenter,
          heightFactor: index == 0 ? 1 : math.max(0, t),
          child: child,
        ),
        child: NcCard(
          notification: note,
          services: widget.services,
          index: index,
          gap: NcLook.layout.gap,
          unfold: _t,
          more: index == 0 ? count - 1 : 0,
          peeks: index == 0 && !_spread ? NcMotion.peeks(count) : 0,
          settled: index == 0 || (_open && _still),
          stacked: index == 0 && folded,
          reachable: index == 0 || _open,
          leaving: widget.leaving || going != null,
          clearable: folded ? group.clearable : note.clearable,
          onUnfold: index == 0 && folded ? () => _setOpen(true) : null,
          onTap: folded
              ? () => _setOpen(true)
              : () => widget.onActivate(note.id),
          // Folded, the stack is one thing and goes as one: its close dot
          // says so, and the edges under the card are the card's own, so
          // they travel with it while it is dragged.
          onDismiss: (swiped) => folded || count == 1
              ? widget.onClearGroup(swiped)
              : widget.onClearCard(note.id, swiped),
          onAction: (key) => widget.onAction(note.id, key),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final group = widget.group;
    final count = group.members.length;
    final built = _spread ? count : 1;

    // Laid out from the bottom up, so the list reads back to front: a card
    // is painted over the ones behind it, and the front card over them all.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      verticalDirection: VerticalDirection.up,
      children: <Widget>[
        ValueListenableBuilder<double>(
          valueListenable: _t,
          builder: (context, t, _) =>
              SizedBox(height: NcMotion.peekRoom(count, t)),
        ),
        for (var index = built - 1; index >= 0; index--) _member(index),
        if (_spread)
          ValueListenableBuilder<double>(
            valueListenable: _t,
            builder: (context, t, child) {
              final shown = t.clamp(0.0, 1.0);
              return ClipRect(
                child: Align(
                  alignment: Alignment.topCenter,
                  heightFactor: shown,
                  child: Opacity(
                    opacity: shown,
                    child: IgnorePointer(ignoring: shown < 0.5, child: child),
                  ),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                NcCard.reach + 8,
                14,
                NcCard.reach + 2,
                0,
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      ncAppName(group.newest.notification),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: BarType.title.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: ncGroundInk(context),
                        shadows: ncGroundShadow(context),
                      ),
                    ),
                  ),
                  NcChip(
                    label: context.tr('Show Less'),
                    enabled: _open,
                    onTap: () => _setOpen(false),
                  ),
                  if (group.clearable) ...<Widget>[
                    const SizedBox(width: 6),
                    NcChip(
                      label: context.tr('Clear'),
                      enabled: _open,
                      onTap: () => widget.onClearGroup(false),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// GNOME Shell centered-clock dual-pane popover: left notification list with
/// Do Not Disturb switch and Clear button; right date heading and interactive
/// month calendar.
class _GnomeDateMenu extends ConsumerWidget {
  const _GnomeDateMenu({
    required this.services,
    required this.side,
    required this.barHeight,
    required this.onClose,
  });

  final ShellServices services;
  final PanelEdge side;
  final double barHeight;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.shellTheme;
    final dnd = ref.watch(
      desktopNotificationsProvider.select((s) => s.doNotDisturb),
    );
    final hasAny = ref.watch(
      desktopNotificationsProvider.select((s) => s.groups.isNotEmpty),
    );
    return SizedBox(
      height: 416,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            flex: 11,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(
                  child: _Column(
                    services: services,
                    side: side,
                    barHeight: barHeight,
                    notifications: true,
                    widgets: false,
                    framed: true,
                    onClose: onClose,
                  ),
                ),
                Container(
                  height: 46,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: theme.colors.hairline, width: 0.8),
                    ),
                  ),
                  child: Row(
                    children: <Widget>[
                      Text(
                        context.tr('Focus'),
                        style: BarType.menuRow.copyWith(
                          color: theme.colors.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 10),
                      MacSwitch(
                        value: dnd,
                        onChanged: (_) => ref
                            .read(desktopNotificationsProvider.notifier)
                            .toggleDoNotDisturb(),
                      ),
                      const Spacer(),
                      Pressable(
                        onTap: hasAny
                            ? () => ref
                                  .read(desktopNotificationsProvider.notifier)
                                  .clearAll()
                            : null,
                        shape: BorderRadius.circular(14),
                        child: Container(
                          height: 28,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: theme.colors.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(
                            context.tr('Clear'),
                            style: BarType.caption.copyWith(
                              fontSize: 12,
                              color: hasAny
                                  ? theme.colors.textPrimary
                                  : theme.colors.textTertiary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(width: 1, color: theme.colors.hairline),
          const SizedBox(
            width: 268,
            child: Padding(
              padding: EdgeInsets.all(14),
              child: _CompactMonthCalendar(),
            ),
          ),
        ],
      ),
    );
  }
}

/// Windows 11 Fluent Notification Centre: stacked notifications with DND and
/// Clear All controls above a collapsible month calendar card.
class _WindowsNotificationCenter extends ConsumerStatefulWidget {
  const _WindowsNotificationCenter({
    required this.services,
    required this.side,
    required this.barHeight,
    required this.onClose,
  });

  final ShellServices services;
  final PanelEdge side;
  final double barHeight;
  final VoidCallback onClose;

  @override
  ConsumerState<_WindowsNotificationCenter> createState() =>
      _WindowsNotificationCenterState();
}

class _WindowsNotificationCenterState
    extends ConsumerState<_WindowsNotificationCenter> {
  bool _calendarOpen = true;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final now = DateTime.now();
    final zh = Localizations.maybeLocaleOf(context)?.languageCode == 'zh';
    final dateTitle = zh
        ? '${now.month}月${now.day}日'
        : '${_enMonths[now.month - 1]} ${now.day}';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320),
          child: _Column(
            services: widget.services,
            side: widget.side,
            barHeight: widget.barHeight,
            notifications: true,
            widgets: false,
            framed: true,
            showDndToggle: true,
            onClose: widget.onClose,
          ),
        ),
        Container(height: 1, color: theme.colors.hairline),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 8),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  dateTitle,
                  style: BarType.title.copyWith(
                    fontSize: 13.5,
                    color: theme.colors.textPrimary,
                  ),
                ),
              ),
              Pressable(
                onTap: () => setState(() => _calendarOpen = !_calendarOpen),
                shape: BorderRadius.circular(5),
                child: Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: theme.colors.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: theme.colors.hairline, width: 0.8),
                  ),
                  child: AnimatedRotation(
                    turns: _calendarOpen ? 0 : 0.5,
                    duration: KitMotion.duration(context, KitMotion.enter),
                    child: BarGlyph(
                      BarIcons.chevronDown,
                      size: 11,
                      color: theme.colors.textPrimary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_calendarOpen)
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: _CompactMonthCalendar(showHeader: false),
          ),
      ],
    );
  }
}

const List<String> _enMonths = <String>[
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

class _CompactMonthCalendar extends StatefulWidget {
  const _CompactMonthCalendar({this.showHeader = true});

  final bool showHeader;

  @override
  State<_CompactMonthCalendar> createState() => _CompactMonthCalendarState();
}

class _CompactMonthCalendarState extends State<_CompactMonthCalendar> {
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  void _step(int delta) =>
      setState(() => _month = DateTime(_month.year, _month.month + delta));

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final style = KitStyle.of(context);
    final today = DateTime.now();
    final zh = Localizations.maybeLocaleOf(context)?.languageCode == 'zh';
    final first = DateTime(_month.year, _month.month, 1);
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final leadBlanks = first.weekday % 7; // Sun = 0 .. Sat = 6
    final monthTitle = zh
        ? '${_month.year}年${_month.month}月'
        : '${_enMonths[_month.month - 1]} ${_month.year}';
    final weekdays = zh
        ? const <String>['日', '一', '二', '三', '四', '五', '六']
        : const <String>['S', 'M', 'T', 'W', 'T', 'F', 'S'];
    final accent = style.accent(theme);
    final onAccent = style.onAccent(theme);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (widget.showHeader) ...<Widget>[
          Text(
            zh ? '${today.month}月${today.day}日' : '${_enMonths[today.month - 1]} ${today.day}',
            style: BarType.title.copyWith(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: theme.colors.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
        ],
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                monthTitle,
                style: BarType.title.copyWith(
                  fontSize: 12.5,
                  color: theme.colors.textPrimary,
                ),
              ),
            ),
            Pressable(
              onTap: () => _step(-1),
              shape: BorderRadius.circular(12),
              wash: true,
              child: Padding(
                padding: const EdgeInsets.all(5),
                child: BarGlyph(
                  BarIcons.chevronLeft,
                  size: 11,
                  color: theme.colors.textSecondary,
                ),
              ),
            ),
            Pressable(
              onTap: () => _step(1),
              shape: BorderRadius.circular(12),
              wash: true,
              child: Padding(
                padding: const EdgeInsets.all(5),
                child: BarGlyph(
                  BarIcons.chevronRight,
                  size: 11,
                  color: theme.colors.textSecondary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            for (final wd in weekdays)
              Expanded(
                child: Center(
                  child: Text(
                    wd,
                    style: BarType.caption.copyWith(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: theme.colors.textTertiary,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        for (var row = 0; row < 6; row++)
          if (row * 7 - leadBlanks < daysInMonth)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(
                children: <Widget>[
                  for (var col = 0; col < 7; col++)
                    Expanded(
                      child: Builder(
                        builder: (context) {
                          final day = row * 7 + col - leadBlanks + 1;
                          if (day < 1 || day > daysInMonth) {
                            return const SizedBox(height: 26);
                          }
                          final isToday =
                              _month.year == today.year &&
                              _month.month == today.month &&
                              day == today.day;
                          return Center(
                            child: Container(
                              width: 26,
                              height: 26,
                              alignment: Alignment.center,
                              decoration: isToday
                                  ? BoxDecoration(
                                      color: accent,
                                      borderRadius: style.disc(26),
                                    )
                                  : null,
                              child: Text(
                                '$day',
                                style: BarType.caption.copyWith(
                                  fontSize: 11.5,
                                  fontWeight: isToday
                                      ? FontWeight.w700
                                      : FontWeight.w400,
                                  color: isToday
                                      ? onAccent
                                      : theme.colors.textPrimary,
                                  fontFeatures: const <FontFeature>[
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
      ],
    );
  }
}
