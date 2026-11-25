import 'dart:async';
import 'dart:math' as math;

import 'package:denial_flutter_sdk/models.dart';
import 'package:denial_flutter_sdk/services.dart';
import 'package:denial_flutter_sdk/settings.dart';
import 'package:denial_flutter_sdk/state.dart';
import 'package:denial_flutter_sdk/theme.dart';
import 'package:denial_shell_kit/kit_entrance.dart';
import 'package:denial_shell_kit/kit_motion.dart';
import 'package:denial_shell_kit/kit_springs.dart';
import 'package:denial_shell_kit/kit_style.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'bar_icons.dart';
import 'bar_panel.dart';
import 'bar_type.dart';
import 'l10n.dart';
import 'panels/mac_kit.dart';
import 'workspace_overview_layout.dart';

/// Values that want to become settings once the settings page has room for
/// them. Until then they live here, in one place.
abstract final class OverviewTuning {
  /// Live pictures per card; further windows draw the plain stand-in.
  static const int liveLimitPerCard = 6;

  /// Whether windows of workspaces other than the current one try a live
  /// picture. The host keeps only the current workspace's surfaces fresh, so
  /// the stand-in is always drawn underneath.
  static const bool liveOnOtherWorkspaces = true;

  /// Whether a middle click on a window closes it.
  static const bool middleClickCloses = true;

  /// Whether minimised windows get their own row.
  static const bool showMinimised = true;

  /// The widest a card grows.
  static const double maxCardWidth = 300;

  static const double minimisedRow = 62;
  static const String panelId = 'spaces';
}

/// Opens the overview from the indicator at [anchor].
void showWorkspaceOverview({
  required WidgetRef ref,
  required BuildContext context,
  required GlobalKey anchor,
  required ShellServices services,
  required int monitorId,
  required PanelEdge side,
  required double barHeight,
}) {
  final scene = MediaQuery.sizeOf(context);
  final status = ref.read(services.workspace(monitorId));
  final bounds = ref.read(services.monitorBounds(monitorId));
  final vertical = side == PanelEdge.left || side == PanelEdge.right;
  final at = kitSceneRect(anchor);
  final maxHeight = vertical
      ? math.max(220.0, scene.height - (at?.top ?? 0) - 28)
      : math.min(scene.height * 0.8, scene.height - barHeight - 48);
  final grid = overviewGrid(
    count: status.count + 1,
    aspect: _aspect(bounds, scene),
    maxWidth: scene.width - 16 - (vertical ? barHeight + 12 : 0),
    maxHeight: maxHeight,
    maxCard: OverviewTuning.maxCardWidth,
  );
  showBarPanel(
    ref: ref,
    panelId: OverviewTuning.panelId,
    anchor: anchor,
    side: side,
    barHeight: barHeight,
    placement: BarPanelAnchor.centred,
    width: grid.width,
    builder: (context, close) => WorkspaceOverview(
      services: services,
      monitorId: monitorId,
      maxHeight: maxHeight,
      onClose: close,
    ),
  );
}

double _aspect(Rect? bounds, Size scene) {
  final size = bounds?.size ?? scene;
  return size.height > 0 ? size.width / size.height : 16 / 9;
}

OvRect _ov(Rect r) => OvRect(r.left, r.top, r.width, r.height);

class _Drag {
  _Drag(this.window, this.at);

  final DenialWindow window;
  Offset at;
  int? target;
  Offset? point;
}

/// Every workspace as a miniature of the screen, its windows where they
/// are. Tap a card to go there, tap a window to bring it up, drag a window
/// onto another card to move it.
class WorkspaceOverview extends ConsumerStatefulWidget {
  const WorkspaceOverview({
    required this.services,
    required this.monitorId,
    required this.maxHeight,
    required this.onClose,
    super.key,
  });

  final ShellServices services;
  final int monitorId;
  final double maxHeight;
  final VoidCallback onClose;

  @override
  ConsumerState<WorkspaceOverview> createState() => _WorkspaceOverviewState();
}

class _WorkspaceOverviewState extends ConsumerState<WorkspaceOverview> {
  final FocusNode _focus = FocusNode(debugLabel: 'workspace overview');
  final GlobalKey _gridKey = GlobalKey();
  final Map<int, DenialWindow> _last = <int, DenialWindow>{};
  final Map<int, DenialWindow> _ghosts = <int, DenialWindow>{};
  final Set<int> _closing = <int>{};
  final List<Timer> _timers = <Timer>[];
  late final _bridge = ref.read(denialBridgeProvider);

  OverviewGrid? _grid;
  Rect _bounds = Rect.zero;
  int _count = 0;
  int _selected = -1;
  bool _keys = false;
  bool _settled = false;
  _Drag? _drag;
  ({DenialWindow window, int workspace})? _previewed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focus.requestFocus();
      _settled = true;
    });
  }

  @override
  void dispose() {
    _endPreview();
    for (final timer in _timers) {
      timer.cancel();
    }
    _focus.dispose();
    super.dispose();
  }

  void _later(Duration after, VoidCallback run) {
    late final Timer timer;
    timer = Timer(after, () {
      _timers.remove(timer);
      if (mounted) setState(run);
    });
    _timers.add(timer);
  }

  // ── Actions ──────────────────────────────────────────────────────────────

  void _go(int workspace, {bool close = true}) {
    widget.services.switchWorkspace(
      monitorId: widget.monitorId,
      workspaceId: workspace,
    );
    if (close) widget.onClose();
  }

  void _raise(DenialWindow window) {
    widget.services.switchWorkspace(
      monitorId: widget.monitorId,
      workspaceId: window.workspaceId,
    );
    widget.services.activateWindow(window.objectId);
    widget.onClose();
  }

  void _closeWindow(DenialWindow window) {
    if (_closing.contains(window.objectId)) return;
    setState(() => _closing.add(window.objectId));
    _bridge.closeWindow(window);
    // A window that asks before closing may stay; show it again then.
    _later(
      const Duration(milliseconds: 1500),
      () => _closing.remove(window.objectId),
    );
  }

  void _addWorkspace() {
    if (_count >= maximumWorkspaceCount) return;
    ref.read(shellSettingsProvider.notifier).setWorkspaceCount(_count + 1.0);
  }

  void _removeWorkspace() {
    if (_count <= minimumWorkspaceCount) return;
    ref.read(shellSettingsProvider.notifier).setWorkspaceCount(_count - 1.0);
  }

  void _activate(int index) {
    if (index < 0) return;
    if (index >= _count) {
      _addWorkspace();
    } else {
      _go(index + 1);
    }
  }

  // ── Keyboard ─────────────────────────────────────────────────────────────

  static final Map<LogicalKeyboardKey, OverviewMove> _moves =
      <LogicalKeyboardKey, OverviewMove>{
        LogicalKeyboardKey.arrowLeft: OverviewMove.left,
        LogicalKeyboardKey.arrowRight: OverviewMove.right,
        LogicalKeyboardKey.arrowUp: OverviewMove.up,
        LogicalKeyboardKey.arrowDown: OverviewMove.down,
      };

  static final List<LogicalKeyboardKey> _numpad = <LogicalKeyboardKey>[
    LogicalKeyboardKey.numpad0,
    LogicalKeyboardKey.numpad1,
    LogicalKeyboardKey.numpad2,
    LogicalKeyboardKey.numpad3,
    LogicalKeyboardKey.numpad4,
    LogicalKeyboardKey.numpad5,
    LogicalKeyboardKey.numpad6,
    LogicalKeyboardKey.numpad7,
    LogicalKeyboardKey.numpad8,
    LogicalKeyboardKey.numpad9,
  ];

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final grid = _grid;
    if (grid == null || event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final move = _moves[key];
    if (move != null) {
      setState(() {
        _keys = true;
        _selected = overviewMoveSelection(
          index: _selected,
          count: grid.count,
          columns: grid.columns,
          move: move,
        );
      });
      return KeyEventResult.handled;
    }
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space) {
      _activate(_selected);
      return KeyEventResult.handled;
    }
    final pad = _numpad.indexOf(key);
    final digit = pad >= 0 ? pad : int.tryParse(key.keyLabel);
    final target = digit == null ? null : overviewDigitTarget(digit, _count);
    if (target != null) {
      // Stays open, so the highlight is seen travelling to the new card.
      setState(() {
        _keys = true;
        _selected = target - 1;
      });
      _go(target, close: false);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ── Dragging a window to another workspace ───────────────────────────────

  void _dragStart(DenialWindow window, Offset global) {
    setState(() => _drag = _Drag(window, global)..target = null);
    _dragMove(global);
  }

  void _dragMove(Offset global) {
    final drag = _drag;
    final grid = _grid;
    final box = _gridKey.currentContext?.findRenderObject();
    if (drag == null || grid == null || box is! RenderBox) return;
    final local = box.globalToLocal(global);
    final hit = grid.cardAt(local.dx, local.dy);
    final target = hit != null && hit < _count ? hit : null;
    Offset? point;
    int? space;
    if (target != null && target + 1 != drag.window.workspaceId) {
      space = target + 1;
      final card = grid.cardRect(target);
      final p = cardPointToScreen(
        x: local.dx - card.left,
        y: local.dy - card.top,
        screen: _ov(_bounds),
        cardWidth: card.width,
        cardHeight: card.height,
      );
      point = Offset(p.x, p.y);
    }
    final moved = point != drag.point || target != drag.target;
    setState(() {
      drag
        ..at = global
        ..target = target
        ..point = point;
    });
    if (!moved) return;
    if (point == null || space == null) {
      _endPreview();
    } else {
      final previous = _previewed;
      if (previous != null && previous.workspace != space) _endPreview();
      _previewed = (window: drag.window, workspace: space);
      _bridge.previewWindowDropOnWorkspace(
        drag.window,
        monitorId: widget.monitorId,
        workspaceId: space,
        point: point,
      );
    }
  }

  void _endPreview() {
    final previewed = _previewed;
    if (previewed == null) return;
    _previewed = null;
    _bridge.previewWindowDropOnWorkspace(
      previewed.window,
      monitorId: widget.monitorId,
      workspaceId: previewed.workspace,
    );
  }

  void _dragEnd({bool cancelled = false}) {
    final drag = _drag;
    if (drag == null) return;
    _endPreview();
    setState(() => _drag = null);
    final target = drag.target;
    final point = drag.point;
    if (cancelled || target == null || point == null) return;
    _bridge.dropWindowOnWorkspace(
      drag.window,
      monitorId: widget.monitorId,
      workspaceId: target + 1,
      point: point,
    );
  }

  // ── Windows that went away keep their place while they fade ──────────────

  void _track(List<DenialWindow> windows, Duration exit) {
    final now = <int, DenialWindow>{for (final w in windows) w.objectId: w};
    for (final entry in _last.entries) {
      if (now.containsKey(entry.key) || exit == Duration.zero) continue;
      final id = entry.key;
      _ghosts[id] = entry.value;
      _later(exit, () {
        _ghosts.remove(id);
        _closing.remove(id);
      });
    }
    for (final id in now.keys) {
      _ghosts.remove(id);
    }
    _last
      ..clear()
      ..addAll(now);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final style = KitStyle.of(context);
    final ink = theme.colors.textPrimary;
    final accent = style.accent(theme);
    final services = widget.services;
    final status = ref.watch(services.workspace(widget.monitorId));
    final scene = MediaQuery.sizeOf(context);
    final bounds =
        ref.watch(services.monitorBounds(widget.monitorId)) ??
        (Offset.zero & scene);
    final windows = ref
        .watch(shellControllerProvider)
        .openAppWindows
        .where((w) => w.monitorId == widget.monitorId)
        .toList();
    _track(windows, KitMotion.duration(context, KitMotion.enterLarge));
    _bounds = bounds;
    _count = status.count;
    if (_selected < 0) _selected = status.active - 1;

    final minimised = OverviewTuning.showMinimised
        ? windows.where((w) => w.minimized).toList()
        : const <DenialWindow>[];
    final canAdd = status.count < maximumWorkspaceCount;
    final radius = style.radius(theme, 12);
    final inner = math.max(0.0, radius - 2);
    final frame = math.max(2.0, style.borderWidth);
    final drag = _drag;

    return Focus(
      focusNode: _focus,
      onKeyEvent: _onKey,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final grid = overviewGrid(
            count: status.count + (canAdd ? 1 : 0),
            aspect: _aspect(bounds, scene),
            maxWidth: constraints.maxWidth,
            maxHeight: widget.maxHeight,
            footer: minimised.isEmpty ? 0 : OverviewTuning.minimisedRow,
            maxCard: OverviewTuning.maxCardWidth,
          );
          _grid = grid;
          _selected = _selected.clamp(0, grid.count - 1).toInt();

          Widget thumb(
            DenialWindow window,
            OvRect rect, {
            required bool live,
            required bool current,
            bool ghost = false,
            bool movable = true,
          }) {
            final leaving = ghost || _closing.contains(window.objectId);
            return AnimatedPositioned(
              key: ValueKey<int>(window.objectId),
              duration: KitMotion.duration(context, KitMotion.fill),
              curve: KitMotion.outCubic,
              left: rect.left,
              top: rect.top,
              width: rect.width,
              height: rect.height,
              child: _Pop(
                appear: _settled,
                leaving: leaving,
                child: _WindowThumb(
                  services: services,
                  window: window,
                  live: live && !leaving,
                  standIn: !current || !live,
                  faded: drag?.window.objectId == window.objectId,
                  radius: math.max(0.0, style.corner(5)),
                  onTap: () => _raise(window),
                  onClose: () => _closeWindow(window),
                  onDragStart: movable
                      ? (at) => _dragStart(window, at)
                      : null,
                  onDragMove: _dragMove,
                  onDragEnd: () => _dragEnd(),
                  onDragCancel: () => _dragEnd(cancelled: true),
                ),
              ),
            );
          }

          Widget card(int index) {
            final space = index + 1;
            final rect = grid.cardRect(index);
            final active = space == status.active;
            final hot = drag != null && drag.target == index;
            final mine = <DenialWindow>[
              for (final w in windows)
                if (w.workspaceId == space && !w.minimized) w,
            ];
            final gone = <DenialWindow>[
              for (final w in _ghosts.values)
                if (w.workspaceId == space && !w.minimized) w,
            ];
            OvRect place(DenialWindow w) => mapWindowToCard(
              window: _ov(w.presentationCoordinateRect),
              screen: _ov(bounds),
              cardWidth: rect.width,
              cardHeight: rect.height,
            );
            Widget? slot;
            if (drag != null && hot && drag.point != null) {
              final size = place(drag.window);
              final box = _gridKey.currentContext?.findRenderObject();
              final at = box is RenderBox
                  ? box.globalToLocal(drag.at)
                  : Offset.zero;
              slot = Positioned(
                left: (at.dx - rect.left - size.width / 2)
                    .clamp(0.0, rect.width - size.width)
                    .toDouble(),
                top: (at.dy - rect.top - size.height / 2)
                    .clamp(0.0, rect.height - size.height)
                    .toDouble(),
                width: size.width,
                height: size.height,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(style.corner(5)),
                    border: Border.all(color: accent, width: 1.5),
                  ),
                ),
              );
            }
            return Positioned(
              left: rect.left,
              top: rect.top,
              width: rect.width,
              height: grid.cellHeight,
              child: KitEntranceItem(
                row: index ~/ grid.columns,
                col: index % grid.columns,
                child: Column(
                  children: <Widget>[
                    Pressable(
                      scale: Pressable.large,
                      onTap: () => _go(space),
                      child: AnimatedContainer(
                        duration: KitMotion.duration(context, KitMotion.fill),
                        width: rect.width,
                        height: rect.height,
                        decoration: BoxDecoration(
                          color: hot
                              ? accent.withValues(alpha: 0.16)
                              : ink.withValues(alpha: active ? 0.09 : 0.06),
                          borderRadius: BorderRadius.circular(radius),
                          border: Border.all(
                            color: hot
                                ? accent
                                : style.borderFromAccent
                                ? accent.withValues(alpha: 0.4)
                                : ink.withValues(alpha: 0.10),
                            width: hot ? frame : 1,
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(inner),
                          child: Stack(
                            children: <Widget>[
                              if (mine.isEmpty)
                                Center(
                                  child: Text(
                                    '$space',
                                    style: BarType.caption.copyWith(
                                      fontSize: rect.height * 0.34,
                                      fontWeight: FontWeight.w600,
                                      color: ink.withValues(alpha: 0.12),
                                    ),
                                  ),
                                ),
                              for (var i = 0; i < mine.length; i++)
                                thumb(
                                  mine[i],
                                  place(mine[i]),
                                  current: active,
                                  live:
                                      _hasSurface(mine[i]) &&
                                      (active ||
                                          OverviewTuning
                                              .liveOnOtherWorkspaces) &&
                                      overviewLiveSlot(
                                        i,
                                        mine.length,
                                        OverviewTuning.liveLimitPerCard,
                                      ),
                                ),
                              for (final w in gone)
                                thumb(
                                  w,
                                  place(w),
                                  current: active,
                                  live: false,
                                  ghost: true,
                                ),
                              ?slot,
                            ],
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      height: grid.labelHeight,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          Flexible(
                            child: Text(
                              context.tr('Desktop {}', space),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: BarType.caption.copyWith(
                                fontSize: 12,
                                fontWeight: active
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: active
                                    ? ink
                                    : theme.colors.textSecondary,
                              ),
                            ),
                          ),
                          if (space == status.count &&
                              status.count > minimumWorkspaceCount)
                            Pressable(
                              scale: Pressable.small,
                              onTap: _removeWorkspace,
                              child: Padding(
                                padding: const EdgeInsets.all(5),
                                child: BarGlyph(
                                  BarIcons.minus,
                                  size: 11,
                                  color: theme.colors.textSecondary,
                                  semanticLabel: context.tr('Remove'),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          Widget addCard() {
            final rect = grid.cardRect(status.count);
            return Positioned(
              left: rect.left,
              top: rect.top,
              width: rect.width,
              height: rect.height,
              child: KitEntranceItem(
                row: status.count ~/ grid.columns,
                col: status.count % grid.columns,
                child: Pressable(
                  scale: Pressable.large,
                  onTap: _addWorkspace,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: ink.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(radius),
                      border: Border.all(color: ink.withValues(alpha: 0.08)),
                    ),
                    child: Center(
                      child: BarGlyph(
                        BarIcons.plus,
                        size: math.min(22, rect.height * 0.3),
                        color: ink.withValues(alpha: 0.45),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }

          final activeRect = grid.cardRect(
            (status.active - 1).clamp(0, grid.count - 1).toInt(),
          );
          final selectedRect = grid.cardRect(_selected);
          final tuning = style.panelGrow;

          Widget floating() {
            final box = _gridKey.currentContext?.findRenderObject();
            if (drag == null || box is! RenderBox) {
              return const SizedBox.shrink();
            }
            final at = box.globalToLocal(drag.at);
            final size = mapWindowToCard(
              window: _ov(drag.window.presentationCoordinateRect),
              screen: _ov(bounds),
              cardWidth: grid.cardWidth,
              cardHeight: grid.cardHeight,
            );
            return Positioned(
              left: at.dx - size.width / 2,
              top: at.dy - size.height / 2,
              width: size.width,
              height: size.height,
              child: IgnorePointer(
                child: _WindowBlock(
                  services: services,
                  window: drag.window,
                  radius: style.corner(5),
                  lifted: true,
                ),
              ),
            );
          }

          return SizedBox(
            height: grid.height,
            child: Center(
              child: SizedBox(
                key: _gridKey,
                width: grid.width,
                height: grid.height,
                child: KitEntrance(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: <Widget>[
                      for (var i = 0; i < status.count; i++) card(i),
                      if (canAdd) addCard(),
                      // The current workspace's frame travels between cards.
                      Sprung(
                        target: activeRect.left,
                        tuning: tuning,
                        tolerance: 0.05,
                        builder: (context, x, _) => Sprung(
                          target: activeRect.top,
                          tuning: tuning,
                          tolerance: 0.05,
                          builder: (context, y, _) => Positioned(
                            left: x,
                            top: y,
                            width: activeRect.width,
                            height: activeRect.height,
                            child: IgnorePointer(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(radius),
                                  border: Border.all(
                                    color: accent,
                                    width: frame,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (_keys)
                        Positioned(
                          left: selectedRect.left - 4,
                          top: selectedRect.top - 4,
                          width: selectedRect.width + 8,
                          height: selectedRect.height + 8,
                          child: IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(
                                  radius == 0 ? 0 : radius + 4,
                                ),
                                border: Border.all(
                                  color: ink.withValues(alpha: 0.6),
                                  width: 1.5,
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (minimised.isNotEmpty)
                        Positioned(
                          left: grid.pad,
                          right: grid.pad,
                          bottom: grid.pad,
                          height: OverviewTuning.minimisedRow - 14,
                          child: _MinimisedRow(
                            windows: minimised,
                            ink: ink,
                            item: (window, size) => SizedBox(
                              width: size.width,
                              height: size.height,
                              child: Stack(
                                children: <Widget>[
                                  thumb(
                                    window,
                                    OvRect(0, 0, size.width, size.height),
                                    current: false,
                                    live: _hasSurface(window),
                                    movable: false,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      floating(),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Whether the host has something to draw for [window]. Where it has not,
/// it would draw a bare icon; the overview draws its own stand-in instead.
bool _hasSurface(DenialWindow window) =>
    !window.isLocalFlutter &&
    !window.presentationCoordinateRect.size.isEmpty &&
    window.mainVisibleSurfaceIds.isNotEmpty;

/// Minimised windows, side by side under the cards.
class _MinimisedRow extends StatelessWidget {
  const _MinimisedRow({
    required this.windows,
    required this.ink,
    required this.item,
  });

  final List<DenialWindow> windows;
  final Color ink;
  final Widget Function(DenialWindow window, Size size) item;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        return Row(
          children: <Widget>[
            BarGlyph(
              BarIcons.minus,
              size: 12,
              color: ink.withValues(alpha: 0.45),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: <Widget>[
                    for (final window in windows) ...<Widget>[
                      item(
                        window,
                        Size(_width(window, height), height),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  static double _width(DenialWindow window, double height) {
    final size = window.presentationCoordinateRect.size;
    final ratio = size.isEmpty ? 1.5 : size.width / size.height;
    return (height * ratio).clamp(height, height * 2.2).toDouble();
  }
}

/// Grows its child in when it is new and shrinks it out when it leaves.
class _Pop extends StatefulWidget {
  const _Pop({
    required this.appear,
    required this.leaving,
    required this.child,
  });

  /// Whether to grow in; the windows a panel opens with are simply there.
  final bool appear;
  final bool leaving;
  final Widget child;

  @override
  State<_Pop> createState() => _PopState();
}

class _PopState extends State<_Pop> with SingleTickerProviderStateMixin {
  late final KitSpring _shown = KitSpring(
    widget.appear && !widget.leaving ? 0 : 1,
    kitStyle.value.panelGrow,
  );
  late final KitSprings _springs = KitSprings(this, <KitSpring>[_shown]);

  @override
  void initState() {
    super.initState();
    _head();
  }

  @override
  void didUpdateWidget(_Pop old) {
    super.didUpdateWidget(old);
    if (old.leaving != widget.leaving) _head();
  }

  void _head() {
    final style = kitStyle.value;
    _shown
      ..tune(widget.leaving ? style.panelShrink : style.panelGrow)
      ..target = widget.leaving ? 0 : 1;
    if (_shown.value == _shown.target) return;
    _springs.kick(reduceMotion: KitMotion.now.reduced);
  }

  @override
  void dispose() {
    _springs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: widget.leaving,
      child: AnimatedBuilder(
        animation: _springs,
        builder: (context, child) {
          final v = _shown.value;
          if (v >= 1 && !_springs.moving) return child!;
          return Opacity(
            opacity: v.clamp(0.0, 1.0).toDouble(),
            child: Transform.scale(scale: 0.6 + 0.4 * v, child: child),
          );
        },
        child: widget.child,
      ),
    );
  }
}

/// A window drawn without its picture: a block in its place and shape, with
/// the application's icon and, where there is room, its title.
class _WindowBlock extends StatelessWidget {
  const _WindowBlock({
    required this.services,
    required this.window,
    required this.radius,
    this.lifted = false,
    this.mark = true,
    this.child,
  });

  final ShellServices services;
  final DenialWindow window;
  final double radius;
  final bool lifted;

  /// Whether the icon and title are drawn.
  final bool mark;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final style = KitStyle.of(context);
    final ink = theme.colors.textPrimary;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          ink.withValues(alpha: 0.14),
          theme.colors.surfaceContainer,
        ),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: ink.withValues(alpha: 0.18), width: 0.6),
        boxShadow: lifted && style.shadow > 0
            ? <BoxShadow>[
                BoxShadow(
                  color: theme.colors.shadow.withValues(
                    alpha: 0.4 * style.shadow,
                  ),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final h = constraints.maxHeight;
            final icon = math.min(30.0, math.min(w, h) * 0.5);
            final titled = w >= 72 && h >= 58 && window.title.isNotEmpty;
            return Stack(
              fit: StackFit.expand,
              children: <Widget>[
                if (mark)
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      SizedBox.square(
                        dimension: icon,
                        child: services.buildApplicationIcon(
                          context,
                          window.appId,
                        ),
                      ),
                      if (titled)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(6, 4, 6, 0),
                          child: Text(
                            window.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: BarType.caption.copyWith(
                              fontSize: 10,
                              color: theme.colors.textSecondary,
                            ),
                          ),
                        ),
                    ],
                  ),
                ?child,
              ],
            );
          },
        ),
      ),
    );
  }
}

/// One window inside a card: its picture or stand-in, its title and a close
/// button under the pointer, and the gestures that raise, close or move it.
class _WindowThumb extends StatefulWidget {
  const _WindowThumb({
    required this.services,
    required this.window,
    required this.live,
    required this.standIn,
    required this.faded,
    required this.radius,
    required this.onTap,
    required this.onClose,
    required this.onDragStart,
    required this.onDragMove,
    required this.onDragEnd,
    required this.onDragCancel,
  });

  final ShellServices services;
  final DenialWindow window;

  /// Whether the host's live picture is drawn.
  final bool live;

  /// Whether the icon and title sit under the picture, to show through
  /// where the picture has nothing.
  final bool standIn;

  /// Left behind while a copy is dragged.
  final bool faded;
  final double radius;
  final VoidCallback onTap;
  final VoidCallback onClose;
  final ValueChanged<Offset>? onDragStart;
  final ValueChanged<Offset> onDragMove;
  final VoidCallback onDragEnd;
  final VoidCallback onDragCancel;

  @override
  State<_WindowThumb> createState() => _WindowThumbState();
}

class _WindowThumbState extends State<_WindowThumb> {
  bool _hovered = false;

  // Which gesture owns the drag: the other one losing the arena also
  // reports a cancel, and that must not end this drag.
  bool _byPan = false;
  bool _byHold = false;

  static const Set<PointerDeviceKind> _pointers = <PointerDeviceKind>{
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
  };

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final style = KitStyle.of(context);
    final window = widget.window;
    final start = widget.onDragStart;
    final title = window.title.isEmpty ? window.appId : window.title;

    final Widget body = _WindowBlock(
      services: widget.services,
      window: window,
      radius: widget.radius,
      mark: widget.standIn,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final roomy = constraints.maxWidth >= 56;
          return Stack(
            fit: StackFit.expand,
            children: <Widget>[
              if (widget.live)
                widget.services.buildWindowPreview(context, window.objectId),
              if (roomy)
                Positioned(
                  left: 0,
                  top: 0,
                  right: 0,
                  child: AnimatedOpacity(
                    opacity: _hovered ? 1 : 0,
                    duration: KitMotion.duration(context, KitMotion.fade),
                    child: IgnorePointer(
                      ignoring: !_hovered,
                      child: Container(
                        height: 20,
                        padding: const EdgeInsets.only(left: 6),
                        color: theme.colors.panelBackground.withValues(
                          alpha: 0.86,
                        ),
                        child: Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: BarType.caption.copyWith(
                                  fontSize: 10,
                                  color: theme.colors.textPrimary,
                                ),
                              ),
                            ),
                            Pressable(
                              scale: Pressable.small,
                              onTap: widget.onClose,
                              child: SizedBox.square(
                                dimension: 20,
                                child: Center(
                                  child: BarGlyph(
                                    BarIcons.xmark,
                                    size: 9,
                                    color: theme.colors.textPrimary,
                                    semanticLabel: context.tr('Close Window'),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              if (_hovered)
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(widget.radius),
                        border: Border.all(
                          color: style
                              .accent(theme)
                              .withValues(alpha: 0.9),
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Listener(
        onPointerDown: (event) {
          if (OverviewTuning.middleClickCloses &&
              event.buttons == kMiddleMouseButton) {
            widget.onClose();
          }
        },
        // A finger holds, then drags; a pointer just drags.
        child: GestureDetector(
          onTap: widget.onTap,
          onLongPressStart: start == null
              ? null
              : (details) {
                  _byHold = true;
                  start(details.globalPosition);
                },
          onLongPressMoveUpdate: start == null
              ? null
              : (details) => widget.onDragMove(details.globalPosition),
          onLongPressEnd: start == null
              ? null
              : (_) {
                  _byHold = false;
                  widget.onDragEnd();
                },
          onLongPressCancel: start == null
              ? null
              : () {
                  if (!_byHold) return;
                  _byHold = false;
                  widget.onDragCancel();
                },
          child: GestureDetector(
            supportedDevices: _pointers,
            onPanStart: start == null
                ? null
                : (details) {
                    if (_byHold) return;
                    _byPan = true;
                    start(details.globalPosition);
                  },
            onPanUpdate: start == null
                ? null
                : (details) {
                    if (_byPan) widget.onDragMove(details.globalPosition);
                  },
            onPanEnd: start == null
                ? null
                : (_) {
                    if (!_byPan) return;
                    _byPan = false;
                    widget.onDragEnd();
                  },
            onPanCancel: start == null
                ? null
                : () {
                    if (!_byPan) return;
                    _byPan = false;
                    widget.onDragCancel();
                  },
            child: AnimatedOpacity(
              opacity: widget.faded ? 0.3 : 1,
              duration: KitMotion.duration(context, KitMotion.fade),
              child: body,
            ),
          ),
        ),
      ),
    );
  }
}
