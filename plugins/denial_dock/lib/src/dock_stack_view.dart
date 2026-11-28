import 'dart:async' show unawaited;
import 'dart:io';
import 'dart:math' as math;

import 'package:denial_shell_kit/glass_card.dart';
import 'package:denial_shell_kit/kit_material.dart' show KitTier;
import 'package:denial_shell_kit/kit_motion.dart';
import 'package:denial_shell_kit/kit_style.dart';
import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/gestures.dart'
    show PointerScrollEvent, PointerSignalEvent;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'dock_look_style.dart';
import 'dock_drag.dart';
import 'dock_mac_icons.dart';
import 'dock_menu.dart';
import 'dock_mime_icons.dart';
import 'dock_settings.dart' show DockPosition, DockStackMode, DockStackSortMode;
import 'dock_pile.dart';
import 'dock_spring.dart';
import 'dock_stack_fan.dart';
import 'dock_stack_files.dart';
import 'dock_stack_grid.dart';
import 'dock_stack_thumbs.dart';

/// A folder stack opened above (or beside) its dock icon.
///
/// One pointer region covers the whole scene and asks the geometry which row is
/// under the pointer, so a row that grows on hover keeps its hit area. A press
/// that lands on no row — the empty desktop, or the folder icon itself — folds
/// the stack back into the icon, which is how it closes.
class DockStackView extends StatefulWidget {
  const DockStackView({
    required this.entries,
    required this.anchor,
    required this.bounds,
    this.folderPath,
    this.sort = DockStackSortMode.added,
    this.order = const <String>[],
    this.anchorNow,
    this.workArea,
    required this.position,
    required this.mode,
    this.title,
    required this.zh,
    required this.onDismiss,
    required this.onOpenFolder,
    this.onOpenPath,
    required this.onOpenEntry,
    this.onReorder,
    this.onTrash,
    this.trashRect,
    super.key,
  });

  final List<DockStackEntry> entries;
  final String? folderPath;
  final DockStackSortMode sort;
  final List<String> order;

  /// The folder icon's rectangle in scene coordinates.
  final Rect anchor;

  /// The icon's rectangle right now, for the cards' flight. The dock lifts and
  /// slides its icons as the pointer moves, so the rect measured when the fan
  /// opened is stale by the time the rows fold back: they would land beside
  /// the icon instead of on it. Null falls back to [anchor].
  final Rect Function()? anchorNow;

  /// The monitor's rectangle in scene coordinates, so the stack stays on it.
  final Rect bounds;

  /// The output minus the system bar strip. A fan that grew into the full
  /// output would climb under the top bar, so the rows stop at this edge.
  final Rect? workArea;

  /// Which edge the dock sits on, so a side dock opens beside the icon rather
  /// than above it.
  final DockPosition position;

  /// The view the user picked. `auto` falls back to a grid once the fan would
  /// not fit, the way Finder does.
  final DockStackMode mode;

  /// The folder's name, drawn as the grid panel's header the way macOS titles
  /// it.
  final String? title;

  final bool zh;

  /// Called once the rows have folded back, so the portal can be dropped.
  final VoidCallback onDismiss;
  final VoidCallback onOpenFolder;

  /// Opens a specific folder path (e.g. a drilled-down subfolder in Grid view).
  final ValueChanged<String>? onOpenPath;
  final ValueChanged<DockStackEntry> onOpenEntry;

  /// Called with the file names in their new order after a drag, in either
  /// view. Null leaves the stack read-only.
  final ValueChanged<List<String>>? onReorder;

  /// Called when a row is dropped on the trash target.
  final ValueChanged<DockStackEntry>? onTrash;

  /// The trash icon's rectangle in scene coordinates. Drawn as a drop target
  /// only while a row is being dragged.
  final Rect? trashRect;

  @override
  State<DockStackView> createState() => _DockStackViewState();
}

class _DockStackViewState extends State<DockStackView>
    with SingleTickerProviderStateMixin {
  /// The stack's one clock, running from zero to one over [_total] seconds
  /// of spring time. Every row reads its own spring off it.
  late final AnimationController _open = AnimationController(vsync: this);

  bool _launched = false;
  double _stagger = 0;
  double _total = 1;

  /// Grid subfolder drill-down stack: each frame holds the folder path, label,
  /// and cached directory listing.
  final List<({String path, String label, List<DockStackEntry> entries})>
      _drillStack =
      <({String path, String label, List<DockStackEntry> entries})>[];

  List<DockStackEntry> get _activeEntries =>
      _drillStack.isEmpty ? widget.entries : _drillStack.last.entries;

  String? get _activeTitle =>
      _drillStack.isEmpty ? widget.title : _drillStack.last.label;

  void _drillInto(DockStackEntry folder) {
    final entries = DockStackFiles.list(folder.path, sort: widget.sort);
    final files = <String>[
      for (final e in entries)
        if (!e.isDirectory) e.path,
    ];
    if (files.isNotEmpty) {
      unawaited(DockStackThumbs.request(files));
      unawaited(DockMimeIcons.request(files));
    }
    _query.clear();
    setState(() {
      _drillStack.add((path: folder.path, label: folder.name, entries: entries));
      _layout = null;
      _scroll = 0;
      _hovered = null;
      _selected = -1;
    });
  }

  void _drillBack() {
    if (_drillStack.isEmpty) return;
    _query.clear();
    setState(() {
      _drillStack.removeLast();
      _layout = null;
      _scroll = 0;
      _hovered = null;
      _selected = -1;
    });
  }

  void _openActiveFolder() {
    if (_drillStack.isNotEmpty && widget.onOpenPath != null) {
      widget.onOpenPath!(_drillStack.last.path);
    } else {
      widget.onOpenFolder();
    }
  }

  /// The spring a row rides out of the pile on.
  late DockSpring _out;

  /// The spring the rows ride back on, set once the stack starts to close,
  /// with where each row was when it did.
  DockSpring? _back;
  List<double> _foldFrom = const [];
  double _foldPanelFrom = 1;
  int _foldRows = 1;
  double _foldStagger = 0;
  double _foldTotal = 1;

  _StackLayout? _layout;
  Object? _layoutKey;

  int? _hovered;
  bool _closing = false;
  bool _awaitingThumbs = false;

  /// The search field's text. Typing narrows the stack to the names that
  /// contain it; an empty query shows everything.
  final TextEditingController _query = TextEditingController();
  final FocusNode _queryFocus = FocusNode(debugLabel: 'Stack search');

  /// Keyboard selection; -1 until an arrow key moves it, so Enter does nothing
  /// on a stack the user has only clicked open.
  int _selected = -1;

  /// Scroll offset of the grid, in pixels.
  double _scroll = 0;

  /// Drag: the row picked up, the row under the pointer, and where the pointer
  /// is now.
  int? _dragFrom;
  int? _dragTo;
  Offset? _dragPoint;

  /// True while the pointer is over the trash target.
  bool _overTrash = false;

  /// The search field's rectangle, remembered so a pan starting in it is left
  /// to the field.
  Rect? _searchRect;

  bool get _dragging => _dragFrom != null;

  /// A row leaving the pile. A liquid look runs past its place once and
  /// comes back; the other lands dead-beat, as every spring outside a
  /// liquid look does. Going back
  /// uses the look's own shrink tuning, which never overshoots, so a card
  /// cannot dip past the icon it lands on.
  static const KitSpringTuning _liquidOut = KitSpringTuning(420, 0.62);
  static const KitSpringTuning _plainOut = KitSpringTuning(520, 1);

  /// The smallest gap between one row leaving the pile and the next, in
  /// seconds, and the longest the whole cascade may run. A stack of three
  /// keeps a visible beat between cards; a tall fan tightens the beat so its
  /// last row still lands in about the same time a short one takes.
  static const double _staggerSeconds = 0.028;
  static const double _staggerCap = 0.26;

  static double _staggerFor(int count) =>
      count < 2 ? 0 : math.min(_staggerSeconds, _staggerCap / (count - 1));

  static DockSpring _springOf(KitSpringTuning tuning) => DockSpring(
    stiffness: tuning.stiffness,
    dampingRatio: tuning.dampingRatio,
  );

  /// [seconds] of spring time as the clock's length at the shell's speed.
  static Duration _paced(double seconds) => KitMotion.now.scaled(
    Duration(microseconds: (seconds * 1e6).round()),
  );

  @override
  void initState() {
    super.initState();
    dockThumbsRevision.addListener(_onThumbsReady);
    _requestStackThumbs();
  }

  @override
  void didUpdateWidget(covariant DockStackView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entries != widget.entries) {
      _requestStackThumbs();
    }
  }

  void _requestStackThumbs() {
    final paths = <String>[
      for (final e in widget.entries)
        if (!e.isDirectory) e.path,
    ];
    if (paths.isNotEmpty) DockStackThumbs.request(paths);
  }

  void _onThumbsReady() {
    if (!mounted || _closing) return;
    setState(() => _layout = null);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_launched) return;
    _launched = true;
    final style = KitStyle.of(context);
    _out = _springOf(style.spring(style.liquid ? _liquidOut : _plainOut));
    if (KitMotion.reduced(context)) {
      // With motion turned off the stack has to be usable at once; the spring
      // would otherwise still stagger every row in.
      _total = _out.seconds;
      _open.value = 1;
      return;
    }
    // The number of rows is known before the layout runs, and the whole
    // cascade is one clock: a fixed window per row would either rush a tall
    // fan or crawl through a short one. The extra row is the one that opens
    // the folder.
    final count = math.max(1, widget.entries.length + 1);
    _stagger = _staggerFor(count);
    _total = _stagger * (count - 1) + _out.seconds;
    _open.duration = _paced(_total);
    _open.forward();
  }

  @override
  void dispose() {
    DockStackThumbs.cancelPending();
    dockThumbsRevision.removeListener(_onThumbsReady);
    _gridControllerInstance?.dispose();
    _query.dispose();
    _queryFocus.dispose();
    _open.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final layout = _layoutFor(context);
    // A thumbnail index that was not ready when the stack opened resolves a
    // moment later; redrawing then is what puts the previews in.
    if (!_awaitingThumbs && DockStackThumbs.stale) {
      _awaitingThumbs = true;
      DockStackThumbs.warm().then(
        (_) {
          if (!mounted || _closing) return;
          setState(() {
            _layout = null;
            _awaitingThumbs = false;
          });
        },
        onError: (_) {
          if (!mounted) return;
          _awaitingThumbs = false;
        },
      );
    }
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _escape,
        const SingleActivator(LogicalKeyboardKey.slash): () {
          if (_searchable) _queryFocus.requestFocus();
        },
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () {
          if (_searchable) _queryFocus.requestFocus();
        },
        const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
            _arrow(up: true),
        const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
            _arrow(up: false),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
            _moveSelection(-layout.columns),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
            _moveSelection(layout.columns),
        const SingleActivator(LogicalKeyboardKey.enter): _activateSelection,
        const SingleActivator(LogicalKeyboardKey.numpadEnter):
            _activateSelection,
      },
      child: Focus(
        autofocus: true,
        child: MouseRegion(
          onHover: (event) => _hoverAt(event.localPosition, layout),
          onExit: (_) => _hoverAt(null, layout),
          child: Listener(
            onPointerSignal: (event) => _wheel(event, layout),
            child: AnimatedBuilder(
              animation: _open,
              builder: (context, _) {
                // Measured once per frame rather than per row: the rows all
                // fold into the same icon.
                final icon = widget.anchorNow?.call() ?? widget.anchor;
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // One catcher under everything answers presses and pans in
                    // scene coordinates. It sits below the rows rather than
                    // around them, so the search field above it keeps its own
                    // text selection.
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapUp: (details) =>
                            _press(details.localPosition, layout),
                        onPanStart: (details) =>
                            _dragStart(details.localPosition, layout),
                        onPanUpdate: (details) =>
                            _dragUpdate(details.localPosition, layout),
                        onPanEnd: (_) => _dragEnd(layout),
                        onPanCancel: _dragCancel,
                        // A grid tall enough to scroll gives the plain drag to
                        // the scroll view, so holding a cell first is what picks
                        // it up — the gesture a phone launcher uses.
                        onLongPressStart: (details) =>
                            _dragStart(details.localPosition, layout),
                        onLongPressMoveUpdate: (details) =>
                            _dragUpdate(details.localPosition, layout),
                        onLongPressEnd: (_) => _dragEnd(layout),
                        onLongPressCancel: _dragCancel,
                      ),
                    ),
                    if (layout.isFan) ...[
                      for (var i = 0; i < layout.rows.length; i++)
                        _buildFanRow(context, layout, i, icon),
                    ] else if (layout.isList)
                      _buildList(context, layout)
                    else
                      _buildGrid(context, layout),
                    if (_searchable &&
                        (!layout.isFan ||
                            _query.text.isNotEmpty ||
                            _queryFocus.hasFocus))
                      _buildSearch(context, layout),
                    if (_dragging && widget.trashRect != null)
                      _buildTrashTarget(context),
                    if (_dragging) _buildGhost(context, layout),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  /// Escape clears a search, then steps up from a drilled subfolder, before
  /// closing the stack.
  void _escape() {
    if (_query.text.isNotEmpty) {
      _query.clear();
      setState(() => _layout = null);
      return;
    }
    if (_drillStack.isNotEmpty) {
      _drillBack();
      return;
    }
    _dismiss();
  }

  // -- input ---------------------------------------------------------------

  void _hoverAt(Offset? point, _StackLayout layout) {
    if (_closing) return;
    final index = point == null ? null : layout.hitTest(point, _scroll);
    if (index == _hovered) return;
    setState(() => _hovered = index);
  }

  /// A press opens the row under it; anything else closes the stack.
  void _press(Offset point, _StackLayout layout) {
    if (_closing) return;
    final index = layout.hitTest(point, _scroll);
    if (index == null) {
      _dismiss();
      return;
    }
    _activate(layout.rows[index]);
  }

  /// A pan begins on a file row, in either view. The search field and the
  /// panel's own empty space keep their presses, so text selection is not
  /// taken over by the drag.
  ///
  /// Reordering is off while a query narrows the list: the rows are a subset,
  /// and saving their order would push every hidden file behind them.
  void _dragStart(Offset point, _StackLayout layout) {
    final reorderable = widget.onReorder != null && _query.text.trim().isEmpty;
    if (_closing || !reorderable && widget.onTrash == null) return;
    if (_searchRect?.contains(point) ?? false) return;
    final index = layout.hitTest(point, _scroll);
    if (index == null) return;
    final row = layout.rows[index];
    if (row.entry == null) return;
    setState(() {
      _dragFrom = index;
      _dragTo = index;
      _dragPoint = point;
      _overTrash = false;
    });
  }

  /// While the pointer moves, the row under it becomes the drop target and the
  /// trash icon lights up when the pointer is over it. A pointer dragged past
  /// the last row keeps the last one rather than dropping the file on nothing.
  void _dragUpdate(Offset point, _StackLayout layout) {
    if (_dragFrom == null) return;
    final index = layout.hitTest(point, _scroll) ?? _dragTo;
    final overTrash = widget.trashRect?.contains(point) ?? false;
    setState(() {
      _dragPoint = point;
      _dragTo = index;
      _overTrash = overTrash;
    });
  }

  /// Releasing over the trash removes the file; releasing on another row
  /// reorders; releasing anywhere else changes nothing.
  void _dragEnd(_StackLayout layout) {
    final from = _dragFrom;
    if (from == null) return;
    final to = _dragTo;
    final entry = from < layout.rows.length ? layout.rows[from].entry : null;
    final trash = _overTrash;
    final names = DockStackFiles.names(_visible);
    setState(() {
      _dragFrom = null;
      _dragTo = null;
      _dragPoint = null;
      _overTrash = false;
    });
    if (entry == null) return;
    if (trash) {
      widget.onTrash?.call(entry);
      return;
    }
    if (_query.text.trim().isNotEmpty) return;
    if (to == null || to == from || layout.rows[to].entry == null) return;
    // A side stack leads with the row that opens the folder, so a row's place
    // among the files is its index less the rows ahead of it that are not
    // files.
    final lead = layout.rows.first.entry == null ? 1 : 0;
    final fromFile = from - lead;
    final toFile = to - lead;
    if (fromFile < 0 ||
        toFile < 0 ||
        fromFile >= names.length ||
        toFile >= names.length) {
      return;
    }
    widget.onReorder?.call(DockDrag.moved(names, fromFile, toFile));
  }

  /// A cancelled pan changes nothing, so the file is not trashed or moved by a
  /// gesture the system took back.
  void _dragCancel() {
    if (_dragFrom == null) return;
    setState(() {
      _dragFrom = null;
      _dragTo = null;
      _dragPoint = null;
      _overTrash = false;
    });
  }

  void _wheel(PointerSignalEvent event, _StackLayout layout) {
    if (_closing || layout.isFan || !layout.scrolls) return;
    if (event is! PointerScrollEvent) return;
    final max = math.max(0.0, layout.contentHeight - layout.height);
    final next = (_scroll + event.scrollDelta.dy).clamp(0.0, max);
    if (next == _scroll) return;
    setState(() => _scroll = next);
  }

  /// Up and Down. In a fan that rises from the dock the first row is the
  /// lowest, so Up walks away from the dock; everywhere else the rows read
  /// downward and Up is the row before.
  void _arrow({required bool up}) {
    final layout = _layout;
    if (layout == null || _closing || layout.rows.isEmpty) return;
    if (!layout.isFan) {
      _moveSelection(up ? -1 : 1);
      return;
    }
    final next = DockStackFan.step(
      current: _selected,
      count: layout.rows.length,
      towardDock: layout.rises ? !up : up,
    );
    setState(() {
      _selected = next;
      _hovered = next;
    });
  }

  void _moveSelection(int delta) {
    final layout = _layout;
    if (layout == null || _closing || layout.rows.isEmpty) return;
    final next = _selected < 0
        ? (delta > 0 ? 0 : layout.rows.length - 1)
        : (_selected + delta).clamp(0, layout.rows.length - 1);
    setState(() {
      _selected = next;
      _hovered = next;
    });
  }

  void _activateSelection() {
    final layout = _layout;
    if (layout == null || _closing) return;
    if (_selected < 0 || _selected >= layout.rows.length) return;
    _activate(layout.rows[_selected]);
  }

  void _activate(_StackRow row) {
    final entry = row.entry;
    if (entry == null) {
      _openActiveFolder();
      return;
    }
    final layout = _layout;
    if (entry.isDirectory &&
        layout != null &&
        !layout.isFan &&
        !layout.isList) {
      _drillInto(entry);
      return;
    }
    widget.onOpenEntry(entry);
  }

  /// Folds the rows back into the icon, then drops the portal.
  ///
  /// The way back runs on its own spring from wherever each row is, so a
  /// stack closed while it is still opening turns round instead of jumping,
  /// and the last row out is the first one home.
  void _dismiss() {
    if (_closing) return;
    _closing = true;
    if (_hovered != null) setState(() => _hovered = null);
    if (KitMotion.reduced(context)) {
      widget.onDismiss();
      return;
    }
    final layout = _layout;
    final rows = layout != null && layout.isFan ? layout.rows.length : 1;
    final from = [for (var i = 0; i < rows; i++) _progressOf(i)];
    final panel = _panelProgress;
    final back = _springOf(KitStyle.of(context).panelShrink);
    _foldFrom = from;
    _foldPanelFrom = panel;
    _foldRows = rows;
    _foldStagger = _staggerFor(rows);
    _foldTotal = _foldStagger * (rows - 1) + back.seconds;
    _back = back;
    _open.duration = _paced(_foldTotal);
    _open.reverse(from: 1).whenComplete(() {
      if (mounted) widget.onDismiss();
    });
  }

  // -- layout --------------------------------------------------------------

  /// Memoised: hovering a row rebuilds the view, and re-measuring every label
  /// and re-resolving every thumbnail on those frames is wasted work.
  _StackLayout _layoutFor(BuildContext context) {
    final key = (
      widget.anchor,
      widget.bounds,
      widget.position,
      widget.mode,
      identityHashCode(_activeEntries),
      _drillStack.length,
    );
    final cached = _layout;
    if (cached != null && _layoutKey == key) return cached;
    final layout = _computeLayout(context);
    _layout = layout;
    _layoutKey = key;
    return layout;
  }

  _StackLayout _computeLayout(BuildContext context) {
    final theme = context.shellTheme;
    final style = _plateStyle(theme);
    final entries = _visible;
    if (entries.isEmpty) {
      if (_drillStack.isNotEmpty) {
        return _gridLayout(theme, const <DockStackEntry>[]);
      }
      return _messageLayout(
        style,
        _activeEntries.isEmpty
            ? (widget.zh ? '文件夹是空的' : 'Empty folder')
            : (widget.zh ? '没有匹配的项目' : 'No matches'),
      );
    }
    // An explicit list is a menu of names, the way Finder's List view opens a
    // stack; it never falls back to another shape.
    if (widget.mode == DockStackMode.list) return _listLayout(entries, style);
    // The fan is what a folder of a few files opens into. `auto` falls back to
    // a grid when it cannot fit; `fan` truncates instead, because a grid is not
    // what the user asked for. A drilled subfolder always stays in Grid view.
    if (_drillStack.isEmpty &&
        widget.mode != DockStackMode.grid &&
        widget.position != DockPosition.top) {
      final fan = _fanLayout(
        style,
        entries,
        truncate: widget.mode == DockStackMode.fan,
      );
      if (fan != null) return fan;
    }
    return _gridLayout(theme, entries);
  }

  /// The entries the query leaves, which is what the stack draws.
  List<DockStackEntry> get _visible =>
      DockStackFiles.filter(_activeEntries, _query.text);

  /// A search field is worth drawing only when there are enough files that
  /// finding one by eye is work.
  bool get _searchable => _activeEntries.length > 8;

  /// The scene y the rows grow from, and the scene y they must stay under.
  ///
  /// A search field takes the top of the room, so the rows start below it
  /// rather than under it.
  ({double top, double bottom}) get _room {
    const searchHeight = 38.0;
    // The work area already excludes the system bar, so the rows start at its
    // edge; without one, fall back to the output with a small inset.
    final top = widget.position == DockPosition.top
        ? widget.anchor.bottom + DockStackFan.gap
        : (widget.workArea?.top ?? widget.bounds.top);
    return (
      top: top + 8 + (_searchable ? searchHeight : 0),
      bottom: widget.position == DockPosition.bottom
          ? widget.anchor.top - DockStackFan.gap
          : widget.bounds.bottom - 8,
    );
  }

  /// The x the rows start from, for a side dock.
  double? get _sideEdge => switch (widget.position) {
    DockPosition.bottom || DockPosition.top => null,
    DockPosition.left => widget.anchor.right + DockStackFan.gap,
    DockPosition.right => widget.anchor.left - DockStackFan.gap,
  };

  _StackLayout? _fanLayout(
    TextStyle style,
    List<DockStackEntry> entries, {
    required bool truncate,
  }) {
    final side = _sideEdge;
    if (side != null) {
      return _sideLayout(style, entries, side, truncate: truncate);
    }
    final maxLabel = _maxLabelWidthFor(widget.anchor.center.dx, null);
    // The top row is the way into the folder itself, so it takes a slot of
    // its own above the files.
    final widths = <double>[
      for (final entry in entries)
        _rowWidth(entry.name, style, maxWidth: maxLabel),
      _rowWidth(_openLabel, style, maxWidth: maxLabel),
    ];
    // Automatic view follows macOS: a fan that would have to leave files out
    // is replaced by the grid panel, which shows all of them. Only an explicit
    // fan truncates, and then its top row says how many it left out.
    if (!truncate &&
        !DockStackFan.fits(
          files: entries.length,
          bottom: _room.bottom,
          top: _room.top,
          widths: widths,
        )) {
      return null;
    }
    final slots = DockStackFan.fitRows(
      bottom: _room.bottom,
      top: _room.top,
      widths: widths,
    );
    final overflows = slots < entries.length + 1;
    final shown = overflows ? math.max(0, slots - 1) : entries.length;
    final rows = <_StackRow>[
      for (var i = 0; i < shown; i++) _StackRow.entry(entries[i]),
      _StackRow.open(
        overflows ? _moreLabel(entries.length - shown) : _openLabel,
      ),
    ];
    final reach = math.min(
      DockStackFan.shiftMax,
      DockStackFan.shift * math.pow(rows.length - 1, DockStackFan.shiftPower),
    );
    final lean = DockStackFan.leanFor(
      anchorX: widget.anchor.center.dx,
      left: widget.bounds.left + 8,
      right: widget.bounds.right - 8,
      reach: reach,
    );
    final leanMaxLabel = _maxLabelWidthFor(widget.anchor.center.dx, lean);
    final rowWidths = <double>[
      for (final row in rows)
        _rowWidth(row.label, style, maxWidth: leanMaxLabel),
    ];
    final geometry = _clampFan(
      DockStackFan.layout(
        widths: rowWidths,
        anchorX: widget.anchor.center.dx,
        bottom: _room.bottom,
        lean: lean,
      ),
    );
    return _StackLayout.fan(
      rows,
      geometry,
      iconLeading: lean == DockFanLean.left,
      rises: true,
    );
  }

  /// A side dock's stack: rows in a column beside the icon, centred on it, so
  /// the labels never trail back across the dock they came from.
  _StackLayout? _sideLayout(
    TextStyle style,
    List<DockStackEntry> entries,
    double edge, {
    required bool truncate,
  }) {
    final room = _room.bottom - _room.top;
    final slots = math.min(
      DockStackFan.maxRows,
      math.max(1, (room / DockStackFan.rowStep).floor()),
    );
    if (!truncate && slots < entries.length + 1) return null;
    final overflows = slots < entries.length + 1;
    final shown = overflows ? math.max(0, slots - 1) : entries.length;
    // The column reads downward, so the row that opens the folder leads it:
    // that keeps it the top item here as it is in a fan.
    final rows = <_StackRow>[
      _StackRow.open(
        overflows ? _moreLabel(entries.length - shown) : _openLabel,
      ),
      for (var i = 0; i < shown; i++) _StackRow.entry(entries[i]),
    ];
    final rowWidths = <double>[
      for (final row in rows) _rowWidth(row.label, style),
    ];
    final widest = rowWidths.reduce(math.max);
    final toRight = widget.position == DockPosition.left;
    // A right-edge dock opens leftward; if the rows would run off the screen
    // they move inward, keeping their right edge on the icon's column.
    final anchorEdge = toRight
        ? edge
        : math.max(widget.bounds.left + 8, edge - widest);
    final geometry = DockStackFan.layoutSide(
      widths: rowWidths,
      anchorY: widget.anchor.center.dy,
      edgeX: anchorEdge,
      toRight: toRight,
    );
    return _StackLayout.fan(rows, geometry, iconLeading: !toRight);
  }

  /// Rows of names in one panel, the height of the screen's room or the
  /// folder, whichever is shorter.
  _StackLayout _listLayout(List<DockStackEntry> entries, TextStyle style) {
    const rowHeight = 30.0;
    const pad = 6.0;
    final width = math.min(280.0, math.max(180.0, widget.bounds.width - 32));
    final room = _room.bottom - _room.top;
    final header = _activeTitle == null ? 0.0 : 28.0;
    const footer = 32.0;
    final content = entries.length * rowHeight + pad * 2 + header + footer;
    final height = math.min(content, room);
    final left = (widget.anchor.center.dx - width / 2)
        .clamp(
          widget.bounds.left + 16,
          math.max(widget.bounds.left + 16, widget.bounds.right - width - 16),
        )
        .toDouble();
    final top = widget.position == DockPosition.top
        ? _room.top
        : _room.bottom - height;
    return _StackLayout.list(
      [for (final entry in entries) _StackRow.entry(entry)],
      width: width,
      height: height,
      contentHeight: content,
      scrolls: content > height,
      origin: Offset(left, top),
    );
  }

  _StackLayout _gridLayout(ShellThemeData theme, List<DockStackEntry> entries) {
    const footer = 32.0;
    final header = _activeTitle != null || _drillStack.isNotEmpty ? 30.0 : 0.0;
    final grid = DockStackGrid.layout(
      count: math.max(1, entries.length),
      width: widget.bounds.width - 32,
      maxHeight: math.max(96.0, _room.bottom - _room.top - header - footer),
    );
    // The panel is centred on the icon and clamped onto the screen; the cells
    // are measured from its corner, so the hit test needs that corner.
    final left = (widget.anchor.center.dx - grid.width / 2)
        .clamp(
          widget.bounds.left + 16,
          math.max(
            widget.bounds.left + 16,
            widget.bounds.right - grid.width - 16,
          ),
        )
        .toDouble();
    final gridTop = widget.position == DockPosition.top
        ? _room.top + header
        : _room.bottom - grid.height - footer;
    return _StackLayout.grid(
      [for (final entry in entries) _StackRow.entry(entry)],
      grid: entries.isEmpty ? const <DockGridCell>[] : grid.cells,
      columns: grid.columns,
      width: grid.width,
      height: grid.height,
      contentHeight: grid.contentHeight,
      scrolls: grid.scrolls,
      origin: Offset(left, gridTop),
    );
  }

  _StackLayout _messageLayout(TextStyle style, String label) {
    final geometry = _clampFan(
      DockStackFan.layout(
        widths: [_rowWidth(label, style)],
        anchorX: widget.anchor.center.dx,
        bottom: _room.bottom,
      ),
    );
    return _StackLayout.fan([_StackRow.open(label)], geometry, rises: true);
  }

  String get _openLabel => widget.zh ? '在文件管理器中打开' : 'Open in Files';

  String _moreLabel(int count) =>
      widget.zh ? '还有 $count 项，在文件管理器中打开' : '$count More in Files';

  /// Moves a fan that would leave the screen back onto it, arc intact.
  List<DockFanRow> _clampFan(List<DockFanRow> rows) {
    final box = DockStackFan.bounds(rows);
    final shift = box.left < widget.bounds.left + 8
        ? widget.bounds.left + 8 - box.left
        : box.right > widget.bounds.right - 8
        ? widget.bounds.right - 8 - box.right
        : 0.0;
    if (shift == 0) return rows;
    return [
      for (final row in rows)
        DockFanRow(
          index: row.index,
          left: row.left + shift,
          top: row.top,
          width: row.width,
          height: row.height,
          angle: row.angle,
          iconX: row.iconX + shift,
          iconY: row.iconY,
        ),
    ];
  }

  double _maxLabelWidthFor(double anchorX, DockFanLean? lean) {
    final available = switch (lean) {
      DockFanLean.right => anchorX - widget.bounds.left,
      DockFanLean.left => widget.bounds.right - anchorX,
      null => math.max(
        anchorX - widget.bounds.left,
        widget.bounds.right - anchorX,
      ),
    };
    final free =
        available -
        DockStackFan.thumbSize -
        DockStackFan.padX * 2 -
        DockStackFan.thumbGap -
        28;
    // Let long filenames expand cleanly into the free space beside the dock
    // (macOS Fan stack parity), truncating only at the actual screen edge.
    return DockStackFan.maxLabelFor(availableWidth: free);
  }

  double _rowWidth(
    String label,
    TextStyle style, {
    double maxWidth = DockStackFan.labelMaxWidth,
  }) => DockStackFan.rowWidth(_measure(label, style, maxWidth: maxWidth));

  double _measure(
    String text,
    TextStyle style, {
    double maxWidth = DockStackFan.labelMaxWidth,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    final width = painter.width;
    painter.dispose();
    return width;
  }

  // -- painting ------------------------------------------------------------

  /// The filter field, drawn above the stack and pinned to the dock's edge so
  /// it sits where the eye already is.
  Widget _buildSearch(BuildContext context, _StackLayout layout) {
    final theme = context.shellTheme;
    final width = math.min(
      240.0,
      layout.isFan ? widget.bounds.width - 32 : layout.width - 16,
    );
    final anchorCenterX = layout.isFan
        ? widget.anchor.center.dx
        : layout.origin.dx + layout.width / 2;
    final left = (anchorCenterX - width / 2)
        .clamp(
          widget.bounds.left + 16,
          math.max(widget.bounds.left + 16, widget.bounds.right - width - 16),
        )
        .toDouble();
    final double top;
    if (layout.isFan) {
      top = _room.top;
    } else if (widget.position == DockPosition.top) {
      top = math.min(
        widget.bounds.bottom - 38,
        layout.origin.dy + layout.height + 8,
      );
    } else {
      top = math.max(_room.top, layout.origin.dy - 38);
    }
    _searchRect = Rect.fromLTWH(left, top, width, 30);
    return Positioned(
      left: left,
      top: top,
      width: width,
      child: Opacity(
        opacity: _panelProgress.clamp(0.0, 1.0),
        child: SizedBox(
          height: 30,
          child: GlassCard(
            tier: KitTier.popover,
            minOpacity: 0.78,
            radius: 15,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  Icon(
                    Icons.search,
                    size: 14,
                    color: theme.colors.textTertiary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller: _query,
                      focusNode: _queryFocus,
                      onChanged: (_) => setState(() {
                        _layout = null;
                        _selected = -1;
                      }),
                      cursorColor: theme.kitAccent,
                      style: theme.text.systemBarCaption.inLook.copyWith(
                        color: theme.colors.textPrimary,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText: widget.zh ? '搜索' : 'Search',
                        hintStyle: theme.text.systemBarCaption.inLook.copyWith(
                          color: theme.colors.textTertiary,
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
    );
  }

  Widget _buildFanRow(
    BuildContext context,
    _StackLayout layout,
    int index,
    Rect icon,
  ) {
    final theme = context.shellTheme;
    final row = layout.rows[index];
    final box = layout.fan[index];
    final eased = _progressOf(index);
    final lit = _hovered == index || _selected == index;
    final lifting = _dragFrom == index;
    final dropTarget = _dragging && _dragTo == index && !lifting;
    final centre = Offset(box.centerX, box.centerY);
    // The row is drawn with its card on the end away from the dock, so the
    // card — not the row's centre — is what has to leave and rejoin the pile.
    // Placing the row by its centre left the card short of the dock icon on
    // the way back, which read as the stack folding into empty space.
    final thumb = DockStackFan.thumbSize;
    final sign = layout.iconLeading ? -1.0 : 1.0;
    final cardFrom = Offset(sign * (box.width - thumb) / 2, 0);
    final pivot = Offset(sign * box.width / 2, 0);
    // A card's centre relative to the row's centre once the tile has turned
    // about its dock-side end and the row has scaled about its own centre —
    // the order the two transforms apply in, outermost last.
    Offset cardRel(double scale, double angle) {
      final v = cardFrom - pivot;
      final cos = math.cos(angle);
      final sin = math.sin(angle);
      final turned =
          pivot + Offset(v.dx * cos - v.dy * sin, v.dx * sin + v.dy * cos);
      return turned * scale;
    }

    // Cards past the third share the deepest offset rather than flying in
    // from off the icon. The rect is read every frame: the dock magnifies and
    // slides its icons, so the rect captured when the fan opened no longer
    // covers the icon the rows have to fold back into.
    final pile = math.min(index, DockPile.count - 1);
    final pileCentre = Offset(
      icon.center.dx + icon.width * DockPile.offset(pile).dx,
      icon.center.dy + icon.width * DockPile.offset(pile).dy,
    );
    final rest = eased.clamp(0.0, 1.0);
    final angle =
        DockPile.angle(pile) + (box.angle - DockPile.angle(pile)) * rest;
    // The card starts at the size the pile drew it, so the hand-off is a
    // continuation rather than a pop.
    final from = icon.width * DockPile.edge(pile) / thumb;
    final scale = from + (1 - from) * eased;
    final target = Offset.lerp(
      pileCentre,
      centre + cardRel(1, box.angle),
      eased,
    )!;
    final at = target - cardRel(scale, angle);
    // The flight bows outward from the icon column, so the cards spread along
    // the fan's arc instead of drawing one straight line of travel. The bow
    // is zero at both ends, which keeps the landing exact.
    final flight = centre - pileCentre;
    final behind = flight.distance;
    final bend = behind == 0
        ? 0.0
        : math.sin(math.pi * rest) * DockStackFan.gap * 1.4;
    final across = behind == 0
        ? Offset.zero
        : Offset(-flight.dy / behind, flight.dx / behind);
    final travel = at + across * bend;
    // The name plate stays out of the way until the card has cleared the pile.
    final label = ((eased - 0.30) / 0.55).clamp(0.0, 1.0);
    return Positioned(
      key: ValueKey('stack-row-$index'),
      left: 0,
      top: 0,
      child: Transform.translate(
        offset: travel - Offset(box.width / 2, box.height / 2),
        // The row swells under the pointer rather than snapping to its larger
        // size, and the plate's colour arrives with it.
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(end: lit ? 1 : 0),
          duration: KitMotion.duration(context, KitMotion.fade),
          curve: KitMotion.out,
          builder: (context, hover, _) => Transform.scale(
            scale: scale * (1 + (DockStackFan.hoverScale - 1) * hover),
            child: Opacity(
              // The row being dragged leaves a hole behind; the ghost carries
              // the picture under the pointer. The card is opaque as soon as
              // it lifts, so the hand-off from the pile's own card is
              // seamless.
              opacity: lifting ? 0.35 : (eased * 3).clamp(0.0, 1.0),
              child: IgnorePointer(
                child: SizedBox(
                  width: box.width,
                  height: box.height,
                  child: _StackRowTile(
                    row: row,
                    theme: theme,
                    hover: hover,
                    tilt: angle,
                    label: label,
                    dropTarget: dropTarget,
                    iconLeading: layout.iconLeading,
                    maxLabelWidth: math.max(
                      DockStackFan.labelMaxWidth,
                      box.width -
                          DockStackFan.thumbSize -
                          DockStackFan.thumbGap,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The list panel: one row per name, folders opening a submenu of their own
  /// contents the way Finder's List view does.
  Widget _buildList(BuildContext context, _StackLayout layout) {
    final theme = context.shellTheme;
    final progress = _panelProgress;
    final max = math.max(0.0, layout.contentHeight - layout.height);
    final scroll = _scroll.clamp(0.0, max);
    return Positioned(
      left: layout.origin.dx,
      top: layout.origin.dy,
      width: layout.width,
      height: layout.height,
      child: Opacity(
        opacity: progress.clamp(0.0, 1.0),
        child: Transform.scale(
          scale: 0.60 + 0.40 * progress,
          alignment: widget.position == DockPosition.top
              ? Alignment.topCenter
              : Alignment.bottomCenter,
          child: GlassCard(
            tier: KitTier.popover,
            minOpacity: 0.78,
            radius: DockStackFan.radius,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(kitStyle.value.outer(theme, DockStackFan.radius)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_activeTitle case final title?)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.text.systemBarCaption.inLook.copyWith(
                          color: theme.colors.textTertiary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: _gridController(scroll),
                      physics: layout.scrolls
                          ? const ClampingScrollPhysics()
                          : const NeverScrollableScrollPhysics(),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final row in layout.rows)
                              _buildListRow(context, row),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const DockMenuSeparator(),
                  DockMenuRow(
                    icon: Icons.open_in_new_rounded,
                    label: _openLabel,
                    onTap: _openActiveFolder,
                  ),
                  const SizedBox(height: 2),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildListRow(BuildContext context, _StackRow row) {
    final entry = row.entry;
    if (entry == null) {
      return DockMenuRow(label: row.label, onTap: _dismiss);
    }
    if (entry.isDirectory) {
      return DockMenuSubmenuRow(
        icon: Icons.folder_rounded,
        label: entry.name,
        submenu: (_) => _directoryMenu(entry.path, 0),
      );
    }
    return DockMenuRow(
      icon: stackFileIcon(entry.extension),
      label: entry.name,
      onTap: () => _activate(row),
    );
  }

  /// A folder's contents as menu rows. Nested folders recurse a couple of
  /// levels, which is as deep as a dock submenu stays usable.
  Widget _directoryMenu(String path, int depth) {
    final entries = DockStackFiles.list(path, sort: DockStackSortMode.name);
    final shown = entries.take(40).toList();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in shown)
          if (entry.isDirectory && depth < 2)
            DockMenuSubmenuRow(
              icon: Icons.folder_rounded,
              label: entry.name,
              submenu: (_) => _directoryMenu(entry.path, depth + 1),
            )
          else
            DockMenuRow(
              icon: entry.isDirectory
                  ? Icons.folder_rounded
                  : stackFileIcon(entry.extension),
              label: entry.name,
              onTap: () {
                widget.onOpenEntry(entry);
                _dismiss();
              },
            ),
      ],
    );
  }

  Widget _buildGrid(BuildContext context, _StackLayout layout) {
    final theme = context.shellTheme;
    final width = layout.width;
    final left = layout.origin.dx;
    final max = math.max(0.0, layout.contentHeight - layout.height);
    final scroll = _scroll.clamp(0.0, max);
    final progress = _panelProgress;
    // The header sits above layout.origin.dy and the footer sits below
    // layout.origin.dy + layout.height so cell hit testing stays aligned with
    // layout.origin.
    final hasHeader = _activeTitle != null || _drillStack.isNotEmpty;
    final header = hasHeader ? 30.0 : 0.0;
    const footer = 32.0;
    final breadcrumb = _drillStack.isEmpty
        ? (_activeTitle ?? '')
        : <String>[
            if (widget.title != null && widget.title!.isNotEmpty) widget.title!,
            for (final frame in _drillStack) frame.label,
          ].join(' / ');
    return Positioned(
      left: left,
      top: layout.origin.dy - header,
      width: width,
      height: layout.height + header + footer,
      child: Opacity(
        opacity: progress.clamp(0.0, 1.0),
        child: Transform.scale(
          scale: 0.60 + 0.40 * progress,
          alignment: widget.position == DockPosition.top
              ? Alignment.topCenter
              : Alignment.bottomCenter,
          child: GlassCard(
            tier: KitTier.popover,
            minOpacity: 0.78,
            radius: DockStackFan.radius,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(
                kitStyle.value.outer(theme, DockStackFan.radius),
              ),
              child: Column(
                children: [
                  if (hasHeader)
                    SizedBox(
                      height: header,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          children: [
                            if (_drillStack.isNotEmpty)
                              GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: _drillBack,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 4,
                                  ),
                                  child: Icon(
                                    Icons.arrow_back_ios_new_rounded,
                                    size: 13,
                                    color: theme.kitAccent,
                                  ),
                                ),
                              ),
                            Expanded(
                              child: Center(
                                child: Text(
                                  breadcrumb,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.text.systemBarCaption.inLook
                                      .copyWith(
                                        color: theme.colors.textPrimary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                              ),
                            ),
                            if (_drillStack.isNotEmpty)
                              const SizedBox(width: 21),
                          ],
                        ),
                      ),
                    ),
                  Expanded(
                    child: layout.rows.isEmpty
                        ? Center(
                            child: Text(
                              widget.zh ? '文件夹是空的' : 'Empty folder',
                              style: theme.text.systemBarCaption.inLook
                                  .copyWith(color: theme.colors.textTertiary),
                            ),
                          )
                        : SingleChildScrollView(
                            controller: _gridController(scroll),
                            physics: layout.scrolls
                                ? const ClampingScrollPhysics()
                                : const NeverScrollableScrollPhysics(),
                            child: SizedBox(
                              width: width,
                              height: layout.contentHeight,
                              child: Stack(
                                children: [
                                  for (final cell in layout.grid)
                                    Positioned(
                                      left: cell.left,
                                      top: cell.top,
                                      width: cell.size,
                                      height: cell.size,
                                      child: IgnorePointer(
                                        child: _GridCellTile(
                                          row: layout.rows[cell.index],
                                          theme: theme,
                                          lit:
                                              _hovered == cell.index ||
                                              _selected == cell.index,
                                          lifting: _dragFrom == cell.index,
                                          dropTarget:
                                              _dragging &&
                                              _dragTo == cell.index &&
                                              _dragFrom != cell.index,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                  ),
                  SizedBox(
                    height: footer,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(color: theme.colors.hairline),
                        ),
                      ),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _openActiveFolder,
                        child: Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.open_in_new_rounded,
                                size: 13,
                                color: theme.colors.textSecondary,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                _openLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.text.systemBarCaption.inLook
                                    .copyWith(
                                      color: theme.colors.textSecondary,
                                      fontWeight: FontWeight.w500,
                                    ),
                              ),
                            ],
                          ),
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
    );
  }

  /// A halo around the dock's own trash icon while a row is held. The icon is
  /// already drawn by the dock underneath, so this lights it rather than
  /// drawing a second one, and it fades in only during a drag.
  Widget _buildTrashTarget(BuildContext context) {
    final rect = widget.trashRect!.inflate(6);
    final accent = context.shellTheme.kitAccent;
    return Positioned.fromRect(
      rect: rect,
      child: IgnorePointer(
        child: AnimatedContainer(
          duration: KitMotion.duration(context, KitMotion.fade),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: _overTrash ? 0.26 : 0.10),
            borderRadius: BorderRadius.circular(kitStyle.value.corner(14)),
            border: Border.all(
              color: accent.withValues(alpha: _overTrash ? 1 : 0.45),
              width: _overTrash ? 2 : 1,
            ),
          ),
        ),
      ),
    );
  }

  /// The file under the pointer while it is being dragged: a small preview
  /// that follows the pointer, the way a Finder stack drags one item.
  Widget _buildGhost(BuildContext context, _StackLayout layout) {
    final point = _dragPoint;
    final from = _dragFrom;
    if (point == null || from == null || from >= layout.rows.length) {
      return const SizedBox.shrink();
    }
    final row = layout.rows[from];
    const size = 52.0;
    return Positioned(
      left: point.dx - size / 2,
      top: point.dy - size / 2,
      width: size,
      height: size,
      child: IgnorePointer(
        child: Opacity(
          opacity: 0.9,
          child: Transform.scale(
            scale: _overTrash ? 0.86 : 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: context.shellTheme.panelColor(
                  context.shellTheme.colors.surfaceContainerHigh,
                ),
                borderRadius: BorderRadius.circular(
                  kitStyle.value.corner(10),
                ),
                boxShadow: kitStyle.value.cast(const [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 12,
                    offset: Offset(0, 4),
                  ),
                ]),
              ),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: _StackIcon(
                  entry: row.entry,
                  thumbnail: row.thumbnail,
                  size: size - 12,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// One controller for the grid, kept across frames so a wheel-driven offset
  /// and the scroll view agree.
  ScrollController? _gridControllerInstance;

  ScrollController _gridController(double offset) {
    final existing = _gridControllerInstance;
    if (existing != null) {
      if (existing.hasClients && (existing.offset - offset).abs() > 0.5) {
        existing.jumpTo(offset);
      }
      return existing;
    }
    return _gridControllerInstance = ScrollController(
      initialScrollOffset: offset,
    );
  }

  /// A row's own progress on the one clock. Each row's spring starts after
  /// the row before it has left the pile, so the stack reads as cards being
  /// dealt off the front rather than one block sliding out. On the way back
  /// the order turns round: the last card out folds first, which puts the
  /// newest file onto the pile last.
  double _progressOf(int index) {
    final back = _back;
    if (back == null) return _out.at(_open.value * _total - index * _stagger);
    final from = index < _foldFrom.length ? _foldFrom[index] : 1.0;
    final wait = math.max(0, _foldRows - 1 - index) * _foldStagger;
    return from * (1 - back.at((1 - _open.value) * _foldTotal - wait));
  }

  /// The grid and list panels have no rows to stagger, so they run on the
  /// spring alone rather than waiting out the fan's cascade.
  double get _panelProgress {
    final back = _back;
    if (back == null) return _out.at(_open.value * _total);
    return _foldPanelFrom * (1 - back.at((1 - _open.value) * _foldTotal));
  }
}

class _StackLayout {
  const _StackLayout.fan(
    this.rows,
    this.fan, {
    this.iconLeading = false,
    this.rises = false,
  }) : grid = const [],
      columns = 1,
      width = 0,
      height = 0,
      contentHeight = 0,
      scrolls = false,
      isFan = true,
      isList = false,
      origin = Offset.zero;

  const _StackLayout.list(
    this.rows, {
    required this.width,
    required this.height,
    required this.contentHeight,
    required this.scrolls,
    required this.origin,
  }) : fan = const [],
       grid = const [],
       columns = 1,
       isFan = false,
       isList = true,
       iconLeading = false,
       rises = false;

  const _StackLayout.grid(
    this.rows, {
    required this.grid,
    required this.columns,
    required this.width,
    required this.height,
    required this.contentHeight,
    required this.scrolls,
    required this.origin,
  }) : fan = const [],
       isFan = false,
       isList = false,
       iconLeading = false,
       rises = false;

  final List<_StackRow> rows;
  final List<DockFanRow> fan;
  final List<DockGridCell> grid;
  final int columns;
  final double width;
  final double height;
  final double contentHeight;
  final bool scrolls;
  final bool isFan;

  /// The file list: rows stacked vertically in one panel, the way Finder's
  /// List view opens a stack.
  final bool isList;

  /// The grid panel's top-left corner in scene coordinates.
  final Offset origin;

  /// True when a fan leans left, so each row draws its preview before its
  /// label: the picture stays on the outside of the arc.
  final bool iconLeading;

  /// True for a fan that climbs away from a bottom dock, whose first row is
  /// its lowest. A side dock's column reads downward instead.
  final bool rises;

  int? hitTest(Offset point, double scroll) => isFan
      ? DockStackFan.hitTest(fan, point.dx, point.dy)
      : isList
      ? null
      : DockStackGrid.hitTest(
          grid,
          point.dx - origin.dx,
          point.dy - origin.dy,
          scroll: scroll,
        );
}

/// The name plates of a fan: dark and translucent with white ink in every
/// theme. A fan floats over whatever window is behind it with no blur of its
/// own, so a plate that followed a light theme would wash out over a bright
/// wallpaper.
const Color _plateFill = Color(0xB81C1C1E);
const Color _plateInk = Color(0xFFFFFFFF);

TextStyle _plateStyle(ShellThemeData theme) => theme.text.systemBarCaption.inLook
    .copyWith(color: _plateInk, fontWeight: FontWeight.w500);

/// A plate under the pointer or the keyboard, [hover] of the way there.
/// macOS keeps its signature dark translucent pill; non-mac looks follow the
/// active theme's surface and ink tokens.
({Color fill, Color ink, Color edge}) _plateColours(
  BuildContext context,
  ShellThemeData theme,
  double hover,
) {
  final style = KitStyle.of(context);
  final mac = style.archetype == KitShellArchetype.macos;
  final baseFill = mac
      ? _plateFill
      : theme.panelColor(theme.colors.surfaceContainerHigh).withValues(alpha: 0.92);
  final baseInk = mac ? _plateInk : theme.colors.textPrimary;
  final accent = style.accent(theme);
  final hot = style.accentMenuRows
      ? accent
      : Color.alphaBlend(
          baseInk.withValues(alpha: 0.16),
          baseFill.withValues(alpha: 0.96),
        );
  return (
    fill: Color.lerp(baseFill, hot, hover)!,
    ink: style.accentMenuRows
        ? Color.lerp(baseInk, style.onAccent(theme), hover)!
        : baseInk,
    edge: Color.lerp(
      mac ? _plateInk.withValues(alpha: 0.12) : theme.colors.hairline,
      accent.withValues(alpha: style.accentMenuRows ? 0 : 0.75),
      hover,
    )!,
  );
}

/// The fill under a preview card, which keeps a floor for the same reason.
Color _cardFill(ShellThemeData theme) {
  final fill = theme.panelColor(theme.colors.surfaceContainerHigh);
  return fill.a < 0.9 ? fill.withValues(alpha: 0.9) : fill;
}

List<BoxShadow> _plateShadow(ShellThemeData theme) => kitStyle.value.cast([
  BoxShadow(
    color: theme.colors.shadow.withValues(alpha: 0.22),
    blurRadius: 10,
    offset: const Offset(0, 3),
  ),
]);

/// One fan row: the file's name on a pill and its preview beside it, which is
/// the shape a macOS stack draws.
class _StackRowTile extends StatelessWidget {
  const _StackRowTile({
    required this.row,
    required this.theme,
    required this.hover,
    required this.tilt,
    this.label = 1,
    this.dropTarget = false,
    this.iconLeading = false,
    this.maxLabelWidth = DockStackFan.labelMaxWidth,
  });

  final _StackRow row;
  final ShellThemeData theme;

  /// How far the row is lit, from zero to one: the pointer or the keyboard
  /// selection is on it.
  final double hover;
  final bool dropTarget;

  /// How much of the name plate is shown. The card leads the motion out of
  /// the pile and the name arrives once it has cleared the stack.
  final double label;

  /// A left-leaning fan keeps its previews on the left, so the card leads.
  final bool iconLeading;

  final double maxLabelWidth;

  /// The row's turn, in radians. The whole row turns — preview and name
  /// together — pivoting on the end nearest the dock icon, which is what a
  /// macOS stack draws: the arc is in the items, not only in their names.
  final double tilt;

  @override
  Widget build(BuildContext context) {
    final colours = _plateColours(context, theme, hover);
    final card = row.entry == null ? _openMark(colours) : _previewCard();
    final name = _labelPill(colours);
    // The row is exactly as wide as its parts. The box the layout hands it is
    // the widest name in the fan, so letting the row fill that box stretched
    // the short names' pills out into long empty capsules.
    final body = Align(
      alignment: iconLeading ? Alignment.centerLeft : Alignment.centerRight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: iconLeading
            ? [card, const SizedBox(width: DockStackFan.thumbGap), name]
            : [name, const SizedBox(width: DockStackFan.thumbGap), card],
      ),
    );
    // Turning the row about the end nearest the dock icon keeps that end
    // level with the icon column while the far end lifts, so the items trace
    // the same arc their names do.
    return Transform.rotate(
      angle: tilt,
      alignment: iconLeading ? Alignment.centerLeft : Alignment.centerRight,
      child: body,
    );
  }

  /// The name on its own pill: a macOS stack separates the label from the
  /// preview, so the two read as a list of names with pictures beside them.
  Widget _labelPill(({Color fill, Color ink, Color edge}) colours) {
    final fill = dropTarget
        ? Color.alphaBlend(theme.kitAccent.withValues(alpha: 0.45), _plateFill)
        : colours.fill;
    // The pill hugs its text: a macOS name plate is a thin capsule beside the
    // preview, not a panel as tall as the card. A Row would stretch it to the
    // card's height, so the height is set and the pill centred. It stays at
    // its text's width too — flexing it out to the row's full width left a
    // long empty capsule, which the reference never draws.
    return Opacity(
      opacity: label,
      child: SizedBox(
        height: DockStackFan.pillHeight,
        child: IntrinsicWidth(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: maxLabelWidth + DockStackFan.padX * 2,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: fill,
                // Fully round ends: the reference draws a capsule, not a
                // rounded rectangle.
                borderRadius: BorderRadius.circular(
                  DockStackFan.pillHeight / 2,
                ),
                border: Border.all(
                  color: dropTarget ? theme.kitAccent : colours.edge,
                ),
                boxShadow: _plateShadow(theme),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: DockStackFan.padX,
                ),
                child: Align(
                  alignment: iconLeading
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Text(
                    _fitLabel(row.label, _plateStyle(theme), maxLabelWidth),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _plateStyle(theme).copyWith(color: colours.ink),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The round arrow of the row that opens the folder, centred in the space a
  /// preview card takes so it sits on the same column as the cards under it.
  Widget _openMark(({Color fill, Color ink, Color edge}) colours) {
    return SizedBox.square(
      dimension: DockStackFan.thumbSize,
      child: Center(
        child: SizedBox.square(
          dimension: DockStackFan.openSize,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: kitStyle.value.disc(DockStackFan.openSize),
              color: colours.fill,
              border: Border.all(color: colours.edge),
              boxShadow: _plateShadow(theme),
            ),
            child: Padding(
              padding: const EdgeInsets.all(11),
              child: CustomPaint(painter: _CurvedOpenArrowPainter(colours.ink)),
            ),
          ),
        ),
      ),
    );
  }

  static String _fitLabel(String label, TextStyle style, double maxWidth) {
    if (label.length < 16) return label;
    double measure(String s) {
      final p = TextPainter(
        text: TextSpan(text: s, style: style),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      final w = p.width;
      p.dispose();
      return w;
    }

    if (measure(label) <= maxWidth) return label;
    final runes = label.runes.length;
    var lo = 5;
    var hi = runes;
    var best = DockStackFan.middleEllipsize(label, 5);
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final candidate = DockStackFan.middleEllipsize(label, mid);
      if (measure(candidate) <= maxWidth) {
        best = candidate;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return best;
  }

  /// The preview card: natural-aspect thumbnail directly without a heavy box
  /// when an image/video/PDF preview exists, else a clean type icon card.
  Widget _previewCard() {
    final thumbPath = row.thumbnail;
    if (thumbPath != null && !(row.entry?.isDirectory ?? false)) {
      final ratio = DockStackThumbs.aspectRatioCached(thumbPath) ?? 1.0;
      final w = ratio >= 1.0
          ? DockStackFan.thumbSize
          : math.max(30.0, DockStackFan.thumbSize * ratio);
      final h = ratio >= 1.0
          ? math.max(30.0, DockStackFan.thumbSize / ratio)
          : DockStackFan.thumbSize;
      final radius = BorderRadius.circular(kitStyle.value.radius(theme, 6));
      return SizedBox(
        width: DockStackFan.thumbSize,
        height: DockStackFan.thumbSize,
        child: Center(
          child: Container(
            width: w,
            height: h,
            decoration: BoxDecoration(
              borderRadius: radius,
              border: hover > 0.01
                  ? Border.all(
                      color: theme.kitAccent.withValues(alpha: 0.75 * hover),
                      width: 1.5,
                    )
                  : null,
              boxShadow: _plateShadow(theme),
            ),
            child: ClipRRect(
              borderRadius: radius,
              child: Image.file(
                File(thumbPath),
                width: w,
                height: h,
                fit: BoxFit.contain,
                cacheWidth: (w * 3).round(),
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => _fallbackCard(),
              ),
            ),
          ),
        ),
      );
    }
    return _fallbackCard();
  }

  Widget _fallbackCard() {
    return SizedBox(
      width: DockStackFan.thumbSize,
      height: DockStackFan.thumbSize,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _cardFill(theme),
          borderRadius: BorderRadius.circular(kitStyle.value.radius(theme, 8)),
          border: Border.all(
            color: Color.lerp(
              theme.colors.hairline,
              theme.kitAccent.withValues(alpha: 0.7),
              hover,
            )!,
          ),
          boxShadow: _plateShadow(theme),
        ),
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: _StackIcon(
            entry: row.entry,
            thumbnail: null,
            size: DockStackFan.thumbSize - 6,
          ),
        ),
      ),
    );
  }
}

class _CurvedOpenArrowPainter extends CustomPainter {
  const _CurvedOpenArrowPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final curve = Path()
      ..moveTo(w * 0.22, h * 0.78)
      ..cubicTo(w * 0.22, h * 0.36, w * 0.42, h * 0.28, w * 0.80, h * 0.28);
    final head = Path()
      ..moveTo(w * 0.56, h * 0.10)
      ..lineTo(w * 0.84, h * 0.28)
      ..lineTo(w * 0.56, h * 0.46);
    canvas
      ..drawPath(curve, paint)
      ..drawPath(head, paint);
  }

  @override
  bool shouldRepaint(_CurvedOpenArrowPainter old) => old.color != color;
}

/// One grid cell: the preview over a centred name.
class _GridCellTile extends StatelessWidget {
  const _GridCellTile({
    required this.row,
    required this.theme,
    required this.lit,
    this.lifting = false,
    this.dropTarget = false,
  });

  final _StackRow row;
  final ShellThemeData theme;
  final bool lit;
  final bool lifting;
  final bool dropTarget;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: lifting ? 0.35 : 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: dropTarget
              ? theme.kitAccent.withValues(alpha: 0.28)
              : lit
              ? theme.kitAccent.withValues(alpha: 0.16)
              : null,
          borderRadius: BorderRadius.circular(kitStyle.value.radius(theme, 8)),
          border: dropTarget ? Border.all(color: theme.kitAccent) : null,
        ),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 40,
                height: 40,
                child: _StackIcon(
                  entry: row.entry,
                  thumbnail: row.thumbnail,
                  size: 40,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                row.label,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: theme.text.systemBarCaption.inLook.copyWith(
                  color: theme.colors.textPrimary,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A file's preview: a thumbnail, the image itself, or a type icon.
class _StackIcon extends StatelessWidget {
  const _StackIcon({
    required this.entry,
    required this.thumbnail,
    required this.size,
  });

  final DockStackEntry? entry;
  final String? thumbnail;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final entry = this.entry;
    if (entry == null) {
      return Icon(
        Icons.folder_rounded,
        size: size * 0.8,
        color: theme.kitAccent,
      );
    }
    if (entry.isDirectory) return DockFolderIcon(size: size);
    final path = thumbnail;
    if (path == null) return _glyph(entry, theme);
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.18),
      child: Image.file(
        File(path),
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: (size * 3).round(),
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => _glyph(entry, theme),
      ),
    );
  }

  Widget _glyph(DockStackEntry entry, ShellThemeData theme) {
    if (entry.isDirectory) return DockFolderIcon(size: size);
    final mimeIcon = DockMimeIcons.iconPathCached(entry.path);
    if (mimeIcon != null) {
      return Image.file(
        File(mimeIcon),
        width: size * 0.84,
        height: size * 0.84,
        fit: BoxFit.contain,
        cacheWidth: (size * 2).round(),
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => Icon(
          stackFileIcon(entry.extension),
          size: size * 0.72,
          color: stackFileColor(entry.extension),
        ),
      );
    }
    return Icon(
      stackFileIcon(entry.extension),
      size: size * 0.72,
      color: stackFileColor(entry.extension),
    );
  }
}

/// A muted colour per file family, so a fan of mixed files reads at a glance
/// instead of as a column of identical grey glyphs.
Color stackFileColor(String extension) {
  switch (extension) {
    case 'png' || 'jpg' || 'jpeg' || 'gif' || 'webp' || 'bmp' || 'svg':
      return const Color(0xFF4E9A6B);
    case 'mp4' || 'mov' || 'm4v' || 'webm' || 'mkv' || 'avi':
      return const Color(0xFF7C6BC4);
    case 'mp3' || 'flac' || 'wav' || 'ogg' || 'm4a' || 'opus':
      return const Color(0xFFC2668A);
    case 'pdf':
      return const Color(0xFFC4553F);
    case 'zip' || 'tar' || 'gz' || 'xz' || 'zst' || '7z' || 'rar':
      return const Color(0xFFC08A3E);
    case 'dart' || 'rs' || 'c' || 'h' || 'cpp' || 'py' || 'js' || 'ts':
      return const Color(0xFF4A82C0);
    default:
      return const Color(0xFF8A8F98);
  }
}

/// A type icon for a file, chosen from its extension. The shell exposes no
/// MIME lookup, so the common families are mapped here and everything else
/// falls back to a generic document.
IconData stackFileIcon(String extension) {
  switch (extension) {
    case 'png' || 'jpg' || 'jpeg' || 'gif' || 'webp' || 'bmp' || 'svg':
      return Icons.image_outlined;
    case 'mp4' || 'mov' || 'm4v' || 'webm' || 'mkv' || 'avi':
      return Icons.movie_outlined;
    case 'mp3' || 'flac' || 'wav' || 'ogg' || 'm4a' || 'opus':
      return Icons.audiotrack_outlined;
    case 'pdf':
      return Icons.picture_as_pdf_outlined;
    case 'zip' || 'tar' || 'gz' || 'xz' || 'zst' || '7z' || 'rar':
      return Icons.folder_zip_outlined;
    case 'dart' || 'rs' || 'c' || 'h' || 'cpp' || 'py' || 'js' || 'ts':
      return Icons.code;
    case 'txt' || 'md' || 'org':
      return Icons.description_outlined;
    case 'desktop' || 'appimage' || 'exe':
      return Icons.terminal;
    default:
      return Icons.insert_drive_file_outlined;
  }
}

class _StackRow {
  _StackRow.entry(DockStackEntry this.entry)
    : moreLabel = '',
      thumbnail = _previewOf(entry);

  /// The row that opens the folder in the file manager; it has no file of
  /// its own and draws a round arrow where a preview would be.
  const _StackRow.open(this.moreLabel) : entry = null, thumbnail = null;

  final DockStackEntry? entry;

  /// The picture to draw, resolved once when the row is built: the layout is
  /// rebuilt on every hover, and a lookup stats the file.
  final String? thumbnail;

  final String moreLabel;

  String get label => entry?.name ?? moreLabel;

  static String? _previewOf(DockStackEntry? entry) =>
      entry == null ? null : DockStackThumbs.preview(entry.path);
}
