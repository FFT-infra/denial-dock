import 'dart:io';

import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'dock_stack_fan.dart';
import 'dock_stack_files.dart';
import 'dock_stack_thumbs.dart';

/// A folder stack opened as a fan above the dock icon.
///
/// One pointer region covers the whole scene and asks the geometry which row
/// is under the pointer, so a row that grows on hover keeps its hit area. A
/// press that lands on no row — the empty desktop, or the folder icon itself —
/// folds the fan back into the icon, which is how the stack closes.
class DockStackView extends StatefulWidget {
  const DockStackView({
    required this.entries,
    required this.anchor,
    required this.bounds,
    required this.zh,
    required this.onDismiss,
    required this.onOpenFolder,
    required this.onOpenEntry,
    super.key,
  });

  final List<DockStackEntry> entries;

  /// The folder icon's rectangle in scene coordinates.
  final Rect anchor;

  /// The monitor's rectangle in scene coordinates, so the fan stays on it.
  final Rect bounds;

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
    duration: const Duration(milliseconds: 300),
  )..forward();

  _FanLayout? _layout;
  Rect? _layoutAnchor;
  Rect? _layoutBounds;
  List<DockStackEntry>? _layoutEntries;

  int? _hovered;
  bool _closing = false;
  bool _awaitingThumbs = false;

  /// The stagger between rows leaving the icon, and how long one row takes.
  static const double _stagger = 0.026;
  static const double _rowSeconds = 0.2;

  @override
  void dispose() {
    _open.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final layout = _layoutFor(context);
    // A thumbnail index that was not ready when the fan opened resolves a
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
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): _dismiss},
      child: Focus(
        autofocus: true,
        child: MouseRegion(
          onHover: (event) {
            if (_closing) return;
            final index = DockStackFan.hitTest(
              layout.geometry,
              event.localPosition.dx,
              event.localPosition.dy,
            );
            if (index == _hovered) return;
            setState(() => _hovered = index);
          },
          onExit: (_) {
            if (_hovered == null) return;
            setState(() => _hovered = null);
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) => _press(details.localPosition, layout),
            child: AnimatedBuilder(
              animation: _open,
              builder: (context, _) => Stack(
                clipBehavior: Clip.none,
                children: [
                  for (var i = 0; i < layout.rows.length; i++)
                    _buildRow(theme, layout, i),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// A press opens the row under it; anything else closes the fan.
  void _press(Offset point, _FanLayout layout) {
    if (_closing) return;
    final index = DockStackFan.hitTest(layout.geometry, point.dx, point.dy);
    if (index == null) {
      _dismiss();
      return;
    }
    final entry = layout.rows[index].entry;
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

  /// Memoised: hovering a row rebuilds the view, and re-measuring every label
  /// and re-resolving every thumbnail on those frames is wasted work.
  _FanLayout _layoutFor(BuildContext context) {
    final cached = _layout;
    if (cached != null &&
        _layoutAnchor == widget.anchor &&
        _layoutBounds == widget.bounds &&
        identical(_layoutEntries, widget.entries)) {
      return cached;
    }
    final layout = _computeLayout(context);
    _layout = layout;
    _layoutAnchor = widget.anchor;
    _layoutBounds = widget.bounds;
    _layoutEntries = widget.entries;
    return layout;
  }

  _FanLayout _computeLayout(BuildContext context) {
    final theme = context.shellTheme;
    final style = theme.text.systemBarCaption.copyWith(
      color: theme.colors.textPrimary,
    );
    final slots = DockStackFan.fitRows(
      bottom: widget.anchor.top,
      top: widget.bounds.top,
    );
    final entries = widget.entries;
    final rows = <_StackRow>[];
    if (entries.isEmpty) {
      rows.add(_StackRow.more(widget.zh ? '文件夹是空的' : 'Empty folder'));
    } else {
      final overflows = entries.length > slots;
      final shown = overflows ? slots - 1 : entries.length;
      for (var i = 0; i < shown; i++) {
        final entry = entries[i];
        rows.add(_StackRow.entry(entry, DockStackThumbs.preview(entry.path)));
      }
      if (overflows) {
        rows.add(
          _StackRow.more(
            widget.zh
                ? '还有 ${entries.length - shown} 个，在文件管理器中显示'
                : '${entries.length - shown} more in Files',
          ),
        );
      }
    }
    final widths = <double>[
      for (final row in rows)
        DockStackFan.padX * 2 +
            DockStackFan.iconSize +
            DockStackFan.padX +
            _measure(row.label, style),
    ];
    // A fan taller than the room above the dock shrinks rather than losing its
    // top row off the screen.
    final room = widget.anchor.top - widget.bounds.top - DockStackFan.gap;
    final full = DockStackFan.rowStep * rows.length;
    final scale = full > room ? (room / full).clamp(0.6, 1.0) : 1.0;
    var geometry = DockStackFan.layout(
      widths: widths,
      anchorX: widget.anchor.center.dx,
      bottom: widget.anchor.top - DockStackFan.gap,
      scale: scale,
    );
    // A fan whose turned labels would leave the screen moves right as a whole,
    // arc intact.
    final left = DockStackFan.leftReach(geometry, scale: scale);
    final shortfall = widget.bounds.left + 8 - left;
    if (shortfall > 0) {
      geometry = [
        for (final row in geometry)
          DockFanRow(
            index: row.index,
            left: row.left + shortfall,
            top: row.top,
            width: row.width,
            height: row.height,
            angle: row.angle,
            iconX: row.iconX + shortfall,
            iconY: row.iconY,
          ),
      ];
    }
    return (rows: rows, geometry: geometry);
  }

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

  Widget _buildRow(ShellThemeData theme, _FanLayout layout, int index) {
    final row = layout.rows[index];
    final box = layout.geometry[index];
    final eased = _progressOf(index, layout.rows.length);
    final hovered = _hovered == index;
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
            scale:
                (0.35 + 0.65 * eased) * (hovered ? DockStackFan.hoverScale : 1),
            child: Opacity(
              opacity: eased,
              child: IgnorePointer(
                child: SizedBox(
                  width: box.width,
                  height: box.height,
                  child: _StackRowTile(
                    row: row,
                    theme: theme,
                    hovered: hovered,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
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

typedef _FanLayout = ({List<_StackRow> rows, List<DockFanRow> geometry});

/// One fan row: the file's icon or thumbnail on the right and its name in a
/// pill, which is the shape the reference docks draw.
class _StackRowTile extends StatelessWidget {
  const _StackRowTile({
    required this.row,
    required this.theme,
    required this.hovered,
  });

  final _StackRow row;
  final ShellThemeData theme;
  final bool hovered;

  @override
  Widget build(BuildContext context) {
    const pad = DockStackFan.padX;
    final fill = hovered
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
              child: _StackIcon(entry: row.entry, thumbnail: row.thumbnail),
            ),
          ],
        ),
      ),
    );
  }
}

/// A file's preview: a thumbnail, the image itself, or a type icon.
class _StackIcon extends StatelessWidget {
  const _StackIcon({required this.entry, required this.thumbnail});

  final DockStackEntry? entry;
  final String? thumbnail;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final entry = this.entry;
    const size = DockStackFan.iconSize;
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
    const size = DockStackFan.iconSize;
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
  const _StackRow.entry(this.entry, this.thumbnail) : moreLabel = '';

  const _StackRow.more(this.moreLabel) : entry = null, thumbnail = null;

  final DockStackEntry? entry;
  final String? thumbnail;
  final String moreLabel;

  String get label => entry?.name ?? moreLabel;
}
