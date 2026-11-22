import 'dart:io';
import 'dart:math' as math;

import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/gestures.dart'
    show PointerScrollEvent, PointerSignalEvent;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

  /// Keyboard selection; -1 until an arrow key moves it, so Enter does nothing
  /// on a stack the user has only clicked open.
  int _selected = -1;

  /// Scroll offset of the grid, in pixels.
  double _scroll = 0;

  /// The stagger between rows leaving the icon, and how long one row takes.
  static const double _stagger = 0.026;
  static const double _rowSeconds = 0.2;

  @override
  void dispose() {
    _gridControllerInstance?.dispose();
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
        const SingleActivator(LogicalKeyboardKey.escape): _dismiss,
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
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (details) => _press(details.localPosition, layout),
              child: AnimatedBuilder(
                animation: _open,
                builder: (context, _) => Stack(
                  clipBehavior: Clip.none,
                  children: [
                    if (layout.isFan)
                      for (var i = 0; i < layout.rows.length; i++)
                        _buildFanRow(context, layout, i)
                    else
                      _buildGrid(context, layout),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
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
    if (widget.entries.isEmpty) {
      return _messageLayout(style, widget.zh ? '文件夹是空的' : 'Empty folder');
    }
    // The fan is what a folder of a few files opens into. `auto` falls back to
    // a grid when it cannot fit; `fan` truncates instead, because a grid is not
    // what the user asked for.
    if (widget.mode != DockStackMode.grid) {
      final fan = _fanLayout(style, truncate: widget.mode == DockStackMode.fan);
      if (fan != null) return fan;
    }
    return _gridLayout(theme);
  }

  /// The scene y the rows grow from, and the scene y they must stay under.
  ({double top, double bottom}) get _room => (
    top: widget.bounds.top + 8,
    bottom: widget.position == DockPosition.bottom
        ? widget.anchor.top - DockStackFan.gap
        : widget.bounds.bottom - 8,
  );

  /// The x the rows start from, for a side dock.
  double? get _sideEdge => switch (widget.position) {
    DockPosition.bottom => null,
    DockPosition.left => widget.anchor.right + DockStackFan.gap,
    DockPosition.right => widget.anchor.left - DockStackFan.gap,
  };

  _StackLayout? _fanLayout(TextStyle style, {required bool truncate}) {
    final side = _sideEdge;
    if (side != null) return _sideLayout(style, side, truncate: truncate);
    final entries = widget.entries;
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
    final shown = overflows ? math.max(0, slots - 1) : slots;
    final rows = <_StackRow>[
      for (var i = 0; i < shown; i++) _StackRow.entry(entries[i]),
      if (overflows) _StackRow.more(_moreLabel(entries.length - shown)),
    ];
    if (rows.isEmpty) return null;
    final rowWidths = <double>[
      for (final row in rows) _rowWidth(row.label, style),
    ];
    final reach =
        DockStackFan.shift * math.pow(rows.length - 1, DockStackFan.shiftPower);
    final lean = DockStackFan.leanFor(
      anchorX: widget.anchor.center.dx,
      left: widget.bounds.left + 8,
      right: widget.bounds.right - 8,
      reach: reach.toDouble(),
    );
    final geometry = _clampFan(
      DockStackFan.layout(
        widths: rowWidths,
        anchorX: widget.anchor.center.dx,
        bottom: _room.bottom,
        lean: lean,
      ),
    );
    return _StackLayout.fan(rows, geometry);
  }

  /// A side dock's stack: rows in a column beside the icon, centred on it, so
  /// the labels never trail back across the dock they came from.
  _StackLayout _sideLayout(
    TextStyle style,
    double edge, {
    required bool truncate,
  }) {
    final entries = widget.entries;
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
    return _StackLayout.fan(rows, geometry);
  }

  _StackLayout _gridLayout(ShellThemeData theme) {
    final grid = DockStackGrid.layout(
      count: widget.entries.length,
      width: widget.bounds.width - 32,
      maxHeight: _room.bottom - _room.top,
    );
    return _StackLayout.grid(
      [for (final entry in widget.entries) _StackRow.entry(entry)],
      grid: grid.cells,
      columns: grid.columns,
      width: grid.width,
      height: grid.height,
      contentHeight: grid.contentHeight,
      scrolls: grid.scrolls,
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
      DockStackFan.padX * 2 +
      DockStackFan.iconSize +
      DockStackFan.padX +
      _measure(label, style);

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

  Widget _buildFanRow(BuildContext context, _StackLayout layout, int index) {
    final theme = context.shellTheme;
    final row = layout.rows[index];
    final box = layout.fan[index];
    final eased = _progressOf(index, layout.rows.length);
    final lit = _hovered == index || _selected == index;
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
        child: Transform.rotate(
          angle: box.angle,
          child: Transform.scale(
            scale: (0.35 + 0.65 * eased) * (lit ? DockStackFan.hoverScale : 1),
            child: Opacity(
              opacity: eased,
              child: IgnorePointer(
                child: SizedBox(
                  width: box.width,
                  height: box.height,
                  child: _StackRowTile(row: row, theme: theme, lit: lit),
                ),
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
  const _StackLayout.fan(this.rows, this.fan)
    : grid = const [],
      columns = 1,
      width = 0,
      height = 0,
      contentHeight = 0,
      scrolls = false,
      isFan = true;

  const _StackLayout.grid(
    this.rows, {
    required this.grid,
    required this.columns,
    required this.width,
    required this.height,
    required this.contentHeight,
    required this.scrolls,
  }) : fan = const [],
       isFan = false;

  final List<_StackRow> rows;
  final List<DockFanRow> fan;
  final List<DockGridCell> grid;
  final int columns;
  final double width;
  final double height;
  final double contentHeight;
  final bool scrolls;
  final bool isFan;

  int? hitTest(Offset point, double scroll) => isFan
      ? DockStackFan.hitTest(fan, point.dx, point.dy)
      : DockStackGrid.hitTest(grid, point.dx, point.dy, scroll: scroll);
}

/// One fan row: the file's icon or thumbnail on the right and its name in a
/// pill, which is the shape the reference docks draw.
class _StackRowTile extends StatelessWidget {
  const _StackRowTile({
    required this.row,
    required this.theme,
    required this.lit,
  });

  final _StackRow row;
  final ShellThemeData theme;
  final bool lit;

  @override
  Widget build(BuildContext context) {
    const pad = DockStackFan.padX;
    final fill = lit
        ? Color.alphaBlend(
            theme.accent.withValues(alpha: 0.18),
            theme.panelColor(theme.colors.surfaceContainerHigh),
          )
        : theme.panelColor(theme.colors.surfaceContainerHigh);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: theme.borderRadius(DockStackFan.radius),
        border: Border.all(color: theme.colors.hairline),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: pad),
        child: Row(
          children: [
            Expanded(
              child: Text(
                row.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.text.systemBarCaption.copyWith(
                  color: theme.colors.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: pad),
            SizedBox(
              width: DockStackFan.iconSize,
              height: DockStackFan.iconSize,
              child: _StackIcon(
                entry: row.entry,
                thumbnail: row.thumbnail,
                size: DockStackFan.iconSize,
              ),
            ),
          ],
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
  });

  final _StackRow row;
  final ShellThemeData theme;
  final bool lit;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: lit ? theme.accent.withValues(alpha: 0.16) : null,
        borderRadius: theme.borderRadius(8),
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
