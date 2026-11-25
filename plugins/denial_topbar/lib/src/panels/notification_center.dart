import 'dart:async';
import 'dart:math' as math;

import 'package:denial_flutter_sdk/models.dart';
import 'package:denial_flutter_sdk/rendering.dart';
import 'package:denial_flutter_sdk/services.dart';
import 'package:denial_flutter_sdk/state.dart';
import 'package:denial_flutter_sdk/theme.dart';
import 'package:denial_shell_kit/kit_motion.dart';
import 'package:denial_shell_kit/kit_springs.dart';
import 'package:denial_shell_kit/kit_style.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
import 'widgets.dart';

const double notificationCenterWidth = 360;

/// Opens the column of notifications and widgets at the bar's far end: one
/// slab of glass, with the entries as flat cards on it.
void showNotificationCenter({
  required WidgetRef ref,
  required ShellServices services,
  required PanelEdge side,
  required double barHeight,
  bool notifications = true,
  bool widgets = true,
  String panelId = 'clock',
}) {
  if (kitOpenPanel.value == panelId) {
    closeKitPanel();
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
  });

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

  late final DesktopNotificationsController _controller = ref.read(
    desktopNotificationsProvider.notifier,
  );

  // ── The slide ──
  late final KitSpring _slide = KitSpring(0, ncSpring(NcMotion.slide));
  late final KitSprings _springs = KitSprings(this, <KitSpring>[_slide]);
  final ValueNotifier<Offset> _shift = ValueNotifier<Offset>(Offset.zero);
  Animation<double>? _layer;
  VoidCallback? _finish;
  double _travel = notificationCenterWidth + 24;
  bool _opened = false;
  bool _closing = false;

  // ── What is shown ──
  bool _editing = false;
  bool _ready = false;
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
  void initState() {
    super.initState();
    debugCommand.addListener(_debug);
    _slide
      ..value = _liveValue.clamp(0.0, 1.0)
      ..velocity = _liveVelocity;
    _live = this;
    _springs
      ..addListener(_place)
      ..onRest = _rested;
    // The spring starts once the first frame is out. That frame builds the
    // column, the heaviest one there is, and a motion that begins inside it
    // would spend its opening on a frame nobody sees move.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _opened = true;
      setState(() => _ready = true);
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
    // The same spring both ways: a close while the column is still coming in
    // turns it round from where it is, at the speed it has.
    _slide.target = open ? 1 : 0;
    if (_closing == open) setState(() => _closing = !open);
    if (_opened) _springs.kick(reduceMotion: KitMotion.reduced(context));
  }

  void _place() {
    final sign = side == PanelEdge.left ? -1.0 : 1.0;
    _shift.value = Offset(sign * _travel * (1 - _slide.value), 0);
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

  void _resize(String id) => ref.read(barSettingsProvider.notifier).save((s) {
    final sizes = parseTileSizes(s.tileSizes);
    final key = widgetSizeKey(id);
    final wide = (sizes[key]?.w ?? 1) > 1;
    return s.copyWith(
      tileSizes: writeTileSizes(<String, TileSize>{
        ...sizes,
        key: TileSize(wide ? 1 : 2, 1),
      }),
    );
  });

  List<Widget> _widgets(BuildContext context, double width) {
    final theme = context.shellTheme;
    final sizes = parseTileSizes(
      ref.watch(
        barSettingsProvider.select(
          (state) => state.value?.tileSizes ?? const <String>[],
        ),
      ),
    );
    bool wide(String id) => (sizes[widgetSizeKey(id)]?.w ?? 1) > 1;
    final order = ref.watch(
      barSettingsProvider.select(
        (state) => state.value?.widgets ?? defaultWidgets,
      ),
    );
    final shown = <String>[
      for (final id in order)
        if (widgetSize(id) != null) id,
    ];
    final cell = Size((width - widgetGap) / 2, widgetCellHeight);
    final Widget grid;
    if (_ready) {
      grid = TileGrid(
        tiles: <Tile>[
          for (final id in shown)
            Tile(
              id: id,
              size: widgetSize(id, wide: wide(id))!,
              onResize: widgetResizable(id) ? () => _resize(id) : null,
              child: _Surface(
                child: buildBarWidget(id, services, width, wide: wide(id)),
              ),
            ),
        ],
        columns: 2,
        cell: cell,
        gap: widgetGap,
        editing: _editing,
        onReorder: _save,
        onRemove: (id) => _save(<String>[
          for (final other in order)
            if (other != id) other,
        ]),
      );
    } else {
      // The widgets come one frame after the column, so the frame that
      // opens it is only the slab and the cards. Their room is kept, so
      // nothing moves when they arrive.
      final rows = packTiles(<TileSize>[
        for (final id in shown) widgetSize(id, wide: wide(id))!,
      ], 2).rows;
      grid = SizedBox(
        height: rows == 0 ? 0 : rows * cell.height + (rows - 1) * widgetGap,
      );
    }
    final spare = <TileChoice>[
      if (_ready)
        for (final choice in widgetLibrary)
          if (!order.contains(choice.id))
            TileChoice(
              id: choice.id,
              icon: choice.icon,
              label: context.tr(choice.label),
            ),
    ];
    return <Widget>[
      grid,
      if (_ready)
        Reveal(
          open: _editing,
          child: Padding(
            padding: const EdgeInsets.only(top: widgetGap),
            child: _Surface(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        context.tr('Add Widgets'),
                        style: BarType.section.copyWith(
                          color: theme.colors.textSecondary,
                        ),
                      ),
                    ),
                    TileLibrary(
                      choices: spare,
                      empty: context.tr('Everything is already here.'),
                      onAdd: (id) => _save(<String>[...order, id]),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      const SizedBox(height: 12),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          if (_editing) ...<Widget>[
            NcChip(
              label: context.tr('Reset'),
              onTap: () => _save(defaultWidgets),
            ),
            const SizedBox(width: 8),
          ],
          NcChip(
            label: context.tr(_editing ? 'Done' : 'Edit Widgets'),
            onTap: () => setState(() => _editing = !_editing),
          ),
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
      Duration(
            milliseconds: NcMotion.clearDelay(leaving.length - 1).round(),
          ) +
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
        ? scene.globalToLocal(anchor.topLeft) & anchor.size
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

  Widget _title(BuildContext context, bool canClear) {
    final theme = context.shellTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 0),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              context.tr('Notification Center'),
              style: BarType.title.copyWith(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: theme.colors.textPrimary,
              ),
            ),
          ),
          IgnorePointer(
            ignoring: !canClear,
            child: AnimatedOpacity(
              duration: KitMotion.duration(context, KitMotion.fill),
              opacity: canClear ? 1 : 0,
              child: NcChip(
                label: context.tr('Clear All'),
                enabled: canClear,
                onTap: _clearAll,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scene = MediaQuery.sizeOf(context);
    final theme = context.shellTheme;
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
    // A group that turns up once the column is open grows into its place.
    final listed = <String>{for (final group in groups) group.key};
    for (final key in listed) {
      if (_seen.add(key) && _opened) _fresh.add(key);
    }
    _seen.retainAll(listed);
    if (_fresh.isNotEmpty) {
      // Only the frame a group arrives in: a row built later, because it
      // scrolled into view, is simply there.
      WidgetsBinding.instance.addPostFrameCallback((_) => _fresh.clear());
    }

    final width = math.min(notificationCenterWidth, scene.width - 20);
    final onLeft = side == PanelEdge.left;
    _travel = width + 24;
    _place();

    final staying = <DesktopNotificationGroup>[
      for (final group in groups)
        if (!_groupsGoing.containsKey(group.key)) group,
    ];
    final canClear = !_clearing && staying.any((group) => group.clearable);
    // The plates sit ten in from the slab's edge. Six of that is each card's
    // own, where its close dot reaches past the plate.
    final inner = width - 20;

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
                  color: theme.colors.textSecondary,
                ),
              ),
            ),
          ),
        ),
      for (final group in groups)
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
      if (widgets)
        Padding(
          key: const ValueKey<String>('widgets'),
          padding: const EdgeInsets.fromLTRB(6, 10, 6, 0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _widgets(context, inner),
          ),
        ),
    ];
    final places = <Key, int>{
      for (var i = 0; i < rows.length; i++) rows[i].key!: i,
    };
    final menu = _menu;

    return NcScope(
      host: this,
      child: FocusScope(
        node: _scope,
        onKeyEvent: _onKey,
        child: FocusTraversalGroup(
          child: Listener(
            onPointerDown: (_) => _keys.value = false,
            child: Stack(
              key: _sceneKey,
              fit: StackFit.expand,
              children: <Widget>[
                Positioned(
                  left: onLeft ? barHeight + 10 : null,
                  right: onLeft
                      ? null
                      : (side == PanelEdge.right ? barHeight + 10 : 10),
                  top: side == PanelEdge.top ? barHeight + 8 : 10,
                  bottom: side == PanelEdge.bottom ? barHeight + 8 : 10,
                  width: width,
                  // The slide moves a layer that is already painted: no
                  // frame of it builds, lays out or paints the column again.
                  child: CompositedTranslation(
                    translation: _shift,
                    devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
                    // A column on its way out takes no more input.
                    child: IgnorePointer(
                      ignoring: _closing,
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: KitCardGroup(
                          child: KitCard(
                            radius: 26,
                            elevation: 0.9,
                            // The list paints on its own layer, so a scroll,
                            // a hover or a ticking clock leaves the slab's
                            // shadow, clip and blur as they are. It fills
                            // the slab and keeps its margins inside itself:
                            // what scrolls is cut at the slab's own edge,
                            // not at a band inside it.
                            child: RepaintBoundary(
                              child: CustomScrollView(
                                controller: _scroll,
                                shrinkWrap: true,
                                slivers: <Widget>[
                                  SliverPadding(
                                    padding: const EdgeInsets.fromLTRB(
                                      4,
                                      2,
                                      4,
                                      10,
                                    ),
                                    sliver: SliverList(
                                      delegate: SliverChildBuilderDelegate(
                                        (context, index) => rows[index],
                                        childCount: rows.length,
                                        findChildIndexCallback: (key) =>
                                            places[key],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (menu != null && !_closing)
                  NcMenu(
                    anchor: menu.anchor,
                    items: menu.items,
                    keyboard: _keys.value,
                    onClose: _closeMenu,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A widget's plate on the slab.
class _Surface extends StatelessWidget {
  const _Surface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    return Listener(
      behavior: HitTestBehavior.opaque,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(
            KitStyle.of(context).radius(theme, 16),
          ),
          color: ncPlateColor(theme),
        ),
        child: child,
      ),
    );
  }
}

/// One application's notifications. Two or more sit as a stack with the
/// older cards showing as strips underneath; a tap fans the stack open.
///
/// One number moves all of it: how far the stack is open. Each card's room,
/// its plate, its text, the group's title and the space the strips need are
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
  final ValueNotifier<double> _shift = ValueNotifier<double>(0);

  /// Asked to be open, and whether the cards behind are built. They are
  /// from the moment the stack starts to open until it has folded again;
  /// folded, the strips stand in for them.
  bool _open = false;
  bool _spread = false;

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
      _aim();
    }
  }

  @override
  void dispose() {
    _springs.dispose();
    _t.dispose();
    _shift.dispose();
    super.dispose();
  }

  void _setOpen(bool open) {
    if (open == _open || (open && !widget.group.stacked)) return;
    setState(() {
      _open = open;
      if (open) _spread = true;
    });
    updateKeepAlive();
    _aim();
  }

  void _aim() {
    _fold
      ..tune(
        ncSpring(
          KitStyle.of(context).liquid ? NcMotion.unfoldLiquid : NcMotion.unfold,
        ),
      )
      ..target = _open ? 1 : 0;
    _springs.kick(reduceMotion: KitMotion.reduced(context));
  }

  void _rested() {
    if (_open || !_spread) return;
    // This can be reached from a build, when motion is reduced.
    scheduleMicrotask(() {
      if (!mounted || _open || !_spread) return;
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
          gap: 8,
          unfold: _t,
          more: index == 0 ? count - 1 : 0,
          stacked: index == 0 && folded,
          reachable: index == 0 || _open,
          leaving: widget.leaving || going != null,
          clearable: folded ? group.clearable : note.clearable,
          shift: index == 0 ? _shift : null,
          onUnfold: index == 0 && folded ? () => _setOpen(true) : null,
          onTap: folded
              ? () => _setOpen(true)
              : () => widget.onActivate(note.id),
          // Folded, the stack is one thing and goes as one: its close dot
          // says so, and its strips travel with the card while it is
          // dragged.
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
    final theme = context.shellTheme;
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
        if (!_spread && count > 1)
          NcStrips(count: NcMotion.peeks(count), shift: _shift),
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
              padding: const EdgeInsets.fromLTRB(12, 10, 6, 0),
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
                        color: theme.colors.textPrimary,
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
