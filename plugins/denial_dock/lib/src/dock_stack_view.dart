import 'dart:io';
import 'dart:math' as math;

import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/gestures.dart'
    show PointerScrollEvent, PointerSignalEvent;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'dock_drag.dart';
import 'dock_settings.dart' show DockPosition, DockStackMode;
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
    required this.position,
    required this.mode,
    required this.zh,
    required this.onDismiss,
    required this.onOpenFolder,
    required this.onOpenEntry,
    this.onReorder,
    this.onTrash,
    this.trashRect,
    super.key,
  });

  final List<DockStackEntry> entries;

  /// The folder icon's rectangle in scene coordinates.
  final Rect anchor;

  /// The monitor's rectangle in scene coordinates, so the stack stays on it.
  final Rect bounds;

  /// Which edge the dock sits on, so a side dock opens beside the icon rather
  /// than above it.
  final DockPosition position;

  /// The view the user picked. `auto` falls back to a grid once the fan would
  /// not fit, the way Finder does.
  final DockStackMode mode;

  final bool zh;

  /// Called once the rows have folded back, so the portal can be dropped.
  final VoidCallback onDismiss;
  final VoidCallback onOpenFolder;
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
  late final AnimationController _open = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  )..forward();

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

  /// The stagger between rows leaving the icon, and how long one row takes.
  static const double _stagger = 0.026;
  static const double _rowSeconds = 0.2;

  @override
  void dispose() {
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
      DockStackThumbs.warm().then((_) {
        if (!mounted || _closing) return;
        setState(() {
          _layout = null;
          _awaitingThumbs = false;
        });
      });
    }
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _escape,
        const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
            _moveSelection(-1),
        const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
            _moveSelection(1),
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
              builder: (context, _) => Stack(
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
                      _buildFanRow(context, layout, i),
                    _buildOpenButton(context, layout),
                  ] else
                    _buildGrid(context, layout),
                  if (_searchable) _buildSearch(context, layout),
                  if (_dragging && widget.trashRect != null)
                    _buildTrashTarget(context),
                  if (_dragging) _buildGhost(context, layout),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Escape clears a search before it closes the stack, so one key backs out
  /// one step at a time.
  void _escape() {
    if (_query.text.isEmpty) {
      _dismiss();
      return;
    }
    _query.clear();
    setState(() => _layout = null);
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
    if (to == null ||
        to == from ||
        from >= names.length ||
        to >= names.length ||
        layout.rows[to].entry == null) {
      return;
    }
    widget.onReorder?.call(DockDrag.moved(names, from, to));
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
      widget.onOpenFolder();
    } else {
      widget.onOpenEntry(entry);
    }
  }

  /// Folds the rows back into the icon, then drops the portal.
  void _dismiss() {
    if (_closing) return;
    _closing = true;
    if (_hovered != null) setState(() => _hovered = null);
    _open.reverse().whenComplete(() {
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
      identityHashCode(widget.entries),
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
    final style = theme.text.systemBarCaption.copyWith(
      color: theme.colors.textPrimary,
    );
    final entries = _visible;
    if (entries.isEmpty) {
      return _messageLayout(
        style,
        widget.entries.isEmpty
            ? (widget.zh ? '文件夹是空的' : 'Empty folder')
            : (widget.zh ? '没有匹配的项目' : 'No matches'),
      );
    }
    // The fan is what a folder of a few files opens into. `auto` falls back to
    // a grid when it cannot fit; `fan` truncates instead, because a grid is not
    // what the user asked for.
    if (widget.mode != DockStackMode.grid) {
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
      DockStackFiles.filter(widget.entries, _query.text);

  /// A search field is worth drawing only when there are enough files that
  /// finding one by eye is work.
  bool get _searchable => widget.entries.length > 8;

  /// The scene y the rows grow from, and the scene y they must stay under.
  ///
  /// A search field takes the top of the room, so the rows start below it
  /// rather than under it.
  ({double top, double bottom}) get _room {
    const searchHeight = 38.0;
    // A bottom dock's fan carries the open button above its last row, so the
    // rows have to stop short of the screen edge by that much.
    const openRoom = DockStackFan.openSize + DockStackFan.gap;
    final reserve = switch (widget.mode) {
      DockStackMode.grid => 0.0,
      _ => widget.position == DockPosition.bottom ? openRoom : 0.0,
    };
    return (
      top: widget.bounds.top + 8 + (_searchable ? searchHeight : 0) + reserve,
      bottom: widget.position == DockPosition.bottom
          ? widget.anchor.top - DockStackFan.gap
          : widget.bounds.bottom - 8,
    );
  }

  /// The x the rows start from, for a side dock.
  double? get _sideEdge => switch (widget.position) {
    DockPosition.bottom => null,
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
    final widths = <double>[
      for (final entry in entries) _rowWidth(entry.name, style),
    ];
    final slots = DockStackFan.fitRows(
      bottom: _room.bottom,
      top: _room.top,
      widths: widths,
    );
    // Too tall for a real fan: a grid carries more files in less room.
    if (!truncate && slots < 2 && entries.length > 1) return null;
    final overflows = slots < entries.length;
    final shown = overflows
        ? math.max(0, slots - 1)
        : math.min(slots, entries.length);
    final rows = <_StackRow>[
      for (var i = 0; i < shown; i++) _StackRow.entry(entries[i]),
      if (overflows) _StackRow.more(_moreLabel(entries.length - shown)),
    ];
    if (rows.isEmpty) return null;
    final rowWidths = <double>[
      for (final row in rows) _rowWidth(row.label, style),
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
    );
  }

  /// A side dock's stack: rows in a column beside the icon, centred on it, so
  /// the labels never trail back across the dock they came from.
  _StackLayout _sideLayout(
    TextStyle style,
    List<DockStackEntry> entries,
    double edge, {
    required bool truncate,
  }) {
    final room = _room.bottom - _room.top;
    final slots = math.max(1, (room / DockStackFan.rowStep).floor());
    final overflows = !truncate && slots < entries.length;
    final shown = overflows
        ? math.max(0, slots - 1)
        : math.min(slots, entries.length);
    final rows = <_StackRow>[
      for (var i = 0; i < shown; i++) _StackRow.entry(entries[i]),
      if (overflows) _StackRow.more(_moreLabel(entries.length - shown)),
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

  _StackLayout _gridLayout(ShellThemeData theme, List<DockStackEntry> entries) {
    final grid = DockStackGrid.layout(
      count: entries.length,
      width: widget.bounds.width - 32,
      maxHeight: _room.bottom - _room.top,
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
    return _StackLayout.grid(
      [for (final entry in entries) _StackRow.entry(entry)],
      grid: grid.cells,
      columns: grid.columns,
      width: grid.width,
      height: grid.height,
      contentHeight: grid.contentHeight,
      scrolls: grid.scrolls,
      origin: Offset(left, _room.bottom - grid.height),
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
    return _StackLayout.fan([_StackRow.more(label)], geometry);
  }

  String _moreLabel(int count) =>
      widget.zh ? '还有 $count 个，在文件管理器中显示' : '$count more in Files';

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

  double _rowWidth(String label, TextStyle style) =>
      DockStackFan.rowWidth(_measure(label, style));

  double _measure(String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: DockStackFan.labelMaxWidth);
    final width = painter.width;
    painter.dispose();
    return width;
  }

  // -- painting ------------------------------------------------------------

  /// The filter field, drawn above the stack and pinned to the dock's edge so
  /// it sits where the eye already is.
  Widget _buildSearch(BuildContext context, _StackLayout layout) {
    final theme = context.shellTheme;
    final width = math.min(240.0, widget.bounds.width - 32);
    final left = (widget.anchor.center.dx - width / 2)
        .clamp(
          widget.bounds.left + 16,
          math.max(widget.bounds.left + 16, widget.bounds.right - width - 16),
        )
        .toDouble();
    final top = _room.top;
    _searchRect = Rect.fromLTWH(left, top, width, 30);
    return Positioned(
      left: left,
      top: top,
      width: width,
      child: Opacity(
        opacity: Curves.easeOut.transform(_open.value),
        child: SizedBox(
          height: 30,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: theme.panelColor(theme.colors.surfaceContainerHigh),
              borderRadius: theme.borderRadius(15),
              border: Border.all(color: theme.colors.hairline),
            ),
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
                      cursorColor: theme.accent,
                      style: theme.text.systemBarCaption.copyWith(
                        color: theme.colors.textPrimary,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText: widget.zh ? '搜索' : 'Search',
                        hintStyle: theme.text.systemBarCaption.copyWith(
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

  Widget _buildFanRow(BuildContext context, _StackLayout layout, int index) {
    final theme = context.shellTheme;
    final row = layout.rows[index];
    final box = layout.fan[index];
    final eased = _progressOf(index, layout.rows.length);
    final lit = _hovered == index || _selected == index;
    final lifting = _dragFrom == index;
    final dropTarget = _dragging && _dragTo == index && !lifting;
    final centre = Offset(box.centerX, box.centerY);
    // The rows fly out of the icon: one that has not started yet sits on it.
    final at = Offset.lerp(
      Offset(widget.anchor.center.dx, widget.anchor.center.dy),
      centre,
      eased,
    )!;
    return Positioned(
      left: 0,
      top: 0,
      child: Transform.translate(
        offset: at - Offset(box.width / 2, box.height / 2),
        // The row turns about its preview end, the way a macOS stack does:
        // the cards keep their column and only the names fan out.
        child: Transform.rotate(
          angle: box.angle,
          alignment: layout.iconLeading
              ? Alignment.centerLeft
              : Alignment.centerRight,
          child: Transform.scale(
            scale: (0.35 + 0.65 * eased) * (lit ? DockStackFan.hoverScale : 1),
            child: Opacity(
              // The row being dragged leaves a hole behind; the ghost carries
              // the picture under the pointer.
              opacity: lifting ? 0.35 : eased,
              child: IgnorePointer(
                child: SizedBox(
                  width: box.width,
                  height: box.height,
                  child: _StackRowTile(
                    row: row,
                    theme: theme,
                    lit: lit,
                    dropTarget: dropTarget,
                    iconLeading: layout.iconLeading,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The round "open in Files" button macOS puts above a stack. It is the one
  /// way out of the stack that does not need a row, so a folder of files the
  /// dock cannot show is still reachable.
  Widget _buildOpenButton(BuildContext context, _StackLayout layout) {
    if (layout.fan.isEmpty) return const SizedBox.shrink();
    final theme = context.shellTheme;
    final top = layout.fan.last;
    const size = DockStackFan.openSize;
    final eased = _progressOf(layout.rows.length, layout.rows.length + 1);
    // The button sits on the icon column, above the top row, so the eye reads
    // one line from the dock to the button.
    return Positioned(
      left: top.iconX - size / 2,
      top: top.top - DockStackFan.gap - size,
      width: size,
      height: size,
      child: Opacity(
        opacity: eased,
        child: Transform.scale(
          scale: 0.7 + 0.3 * eased,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _closing ? null : widget.onOpenFolder,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.panelColor(theme.colors.surfaceContainerHigh),
                border: Border.all(color: theme.colors.hairline),
              ),
              child: Icon(
                Icons.arrow_outward_rounded,
                size: size * 0.44,
                color: theme.colors.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGrid(BuildContext context, _StackLayout layout) {
    final theme = context.shellTheme;
    final width = layout.width;
    final left = (widget.anchor.center.dx - width / 2)
        .clamp(
          widget.bounds.left + 16,
          math.max(widget.bounds.left + 16, widget.bounds.right - width - 16),
        )
        .toDouble();
    final max = math.max(0.0, layout.contentHeight - layout.height);
    final scroll = _scroll.clamp(0.0, max);
    final progress = Curves.easeOutCubic.transform(_open.value);
    return Positioned(
      left: left,
      top: _room.bottom - layout.height,
      width: width,
      height: layout.height,
      child: Opacity(
        opacity: progress,
        child: Transform.scale(
          scale: 0.94 + 0.06 * progress,
          alignment: Alignment.bottomCenter,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: theme.panelColor(theme.colors.surfaceContainerHigh),
              border: Border.all(color: theme.colors.hairline),
              borderRadius: theme.borderRadius(DockStackFan.radius),
            ),
            child: ClipRRect(
              borderRadius: theme.borderRadius(DockStackFan.radius),
              child: SingleChildScrollView(
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
    final accent = context.shellTheme.accent;
    return Positioned.fromRect(
      rect: rect,
      child: IgnorePointer(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: _overTrash ? 0.26 : 0.10),
            borderRadius: BorderRadius.circular(14),
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
                borderRadius: BorderRadius.circular(10),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 12,
                    offset: Offset(0, 4),
                  ),
                ],
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

  /// A row's own progress on the one timeline, staggered so the pack leaves
  /// the icon in order and folds back from the top.
  double _progressOf(int index, int count) {
    final slot = _closing ? count - 1 - index : index;
    final start = (_open.value - slot * _stagger) / _rowSeconds;
    return Curves.easeOutCubic.transform(start.clamp(0.0, 1.0));
  }
}

class _StackLayout {
  const _StackLayout.fan(this.rows, this.fan, {this.iconLeading = false})
    : grid = const [],
      columns = 1,
      width = 0,
      height = 0,
      contentHeight = 0,
      scrolls = false,
      isFan = true,
      origin = Offset.zero;

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
       iconLeading = false;

  final List<_StackRow> rows;
  final List<DockFanRow> fan;
  final List<DockGridCell> grid;
  final int columns;
  final double width;
  final double height;
  final double contentHeight;
  final bool scrolls;
  final bool isFan;

  /// The grid panel's top-left corner in scene coordinates.
  final Offset origin;

  /// True when a fan leans left, so each row draws its preview before its
  /// label: the picture stays on the outside of the arc.
  final bool iconLeading;

  int? hitTest(Offset point, double scroll) => isFan
      ? DockStackFan.hitTest(fan, point.dx, point.dy)
      : DockStackGrid.hitTest(
          grid,
          point.dx - origin.dx,
          point.dy - origin.dy,
          scroll: scroll,
        );
}

/// One fan row: the file's icon or thumbnail on the right and its name in a
/// pill, which is the shape the reference docks draw.
class _StackRowTile extends StatelessWidget {
  const _StackRowTile({
    required this.row,
    required this.theme,
    required this.lit,
    this.dropTarget = false,
    this.iconLeading = false,
  });

  final _StackRow row;
  final ShellThemeData theme;
  final bool lit;
  final bool dropTarget;

  /// A left-leaning fan keeps its previews on the left, so the card leads.
  final bool iconLeading;

  @override
  Widget build(BuildContext context) {
    final card = _previewCard();
    final pill = _labelPill();
    return Row(
      children: iconLeading
          ? [card, const SizedBox(width: DockStackFan.thumbGap), pill]
          : [pill, const SizedBox(width: DockStackFan.thumbGap), card],
    );
  }

  /// The name on its own pill: a macOS stack separates the label from the
  /// preview, so the two read as a list of names with pictures beside them.
  Widget _labelPill() {
    final fill = dropTarget
        ? Color.alphaBlend(
            theme.accent.withValues(alpha: 0.32),
            theme.panelColor(theme.colors.surfaceContainerHigh),
          )
        : lit
        ? Color.alphaBlend(
            theme.accent.withValues(alpha: 0.16),
            theme.panelColor(theme.colors.surfaceContainerHigh),
          )
        : theme.panelColor(theme.colors.surfaceContainerHigh);
    // The pill hugs its text: a macOS name plate is a thin capsule beside the
    // preview, not a panel as tall as the card. A Row would stretch it to the
    // card's height, so the height is set and the pill centred.
    return Flexible(
      child: Align(
        alignment: iconLeading ? Alignment.centerRight : Alignment.centerLeft,
        child: SizedBox(
          height: DockStackFan.pillHeight,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: fill,
              // Fully round ends: the reference draws a capsule, not a
              // rounded rectangle.
              borderRadius: BorderRadius.circular(DockStackFan.pillHeight / 2),
              border: Border.all(
                color: dropTarget ? theme.accent : theme.colors.hairline,
              ),
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
                  row.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.text.systemBarCaption.copyWith(
                    color: theme.colors.textPrimary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The preview card: the file's own picture where there is one, otherwise
  /// its type icon on the same card so a row never changes height.
  Widget _previewCard() {
    return SizedBox(
      width: DockStackFan.thumbSize,
      height: DockStackFan.thumbSize,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.panelColor(theme.colors.surfaceContainerHigh),
          borderRadius: theme.borderRadius(8),
          border: Border.all(
            color: lit
                ? theme.accent.withValues(alpha: 0.55)
                : theme.colors.hairline,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: _StackIcon(
            entry: row.entry,
            thumbnail: row.thumbnail,
            size: DockStackFan.thumbSize - 6,
          ),
        ),
      ),
    );
  }
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
              ? theme.accent.withValues(alpha: 0.28)
              : lit
              ? theme.accent.withValues(alpha: 0.16)
              : null,
          borderRadius: theme.borderRadius(8),
          border: dropTarget ? Border.all(color: theme.accent) : null,
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
                style: theme.text.systemBarCaption.copyWith(
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
      return Icon(Icons.folder_rounded, size: size * 0.8, color: theme.accent);
    }
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
    if (entry.isDirectory) {
      return Icon(Icons.folder_rounded, size: size * 0.8, color: theme.accent);
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

  const _StackRow.more(this.moreLabel) : entry = null, thumbnail = null;

  final DockStackEntry? entry;

  /// The picture to draw, resolved once when the row is built: the layout is
  /// rebuilt on every hover, and a lookup stats the file.
  final String? thumbnail;

  final String moreLabel;

  String get label => entry?.name ?? moreLabel;

  static String? _previewOf(DockStackEntry? entry) =>
      entry == null ? null : DockStackThumbs.preview(entry.path);
}
