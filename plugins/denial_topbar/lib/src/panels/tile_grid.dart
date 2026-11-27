import 'dart:math' as math;

import 'package:denial_flutter_sdk/theme.dart';
import 'package:denial_shell_kit/kit_entrance.dart';
import 'package:denial_shell_kit/kit_motion.dart';
import 'package:denial_shell_kit/kit_style.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../bar_icons.dart';
import '../bar_type.dart';
import 'mac_kit.dart';
import 'tile_pack.dart';

export 'tile_pack.dart';

class Tile {
  const Tile({
    required this.id,
    required this.size,
    required this.child,
    this.onResize,
    this.supportedSizes,
    this.onResizeTo,
    this.onSecondaryTap,
  });

  final String id;
  final TileSize size;
  final Widget child;

  /// Switches the tile to its next size on tap, when it has one.
  final VoidCallback? onResize;

  /// Supported footprint sizes for magnetic corner drag resizing in edit mode.
  final List<TileSize>? supportedSizes;

  /// Commits a specific snapped [TileSize] after magnetic corner dragging.
  final ValueChanged<TileSize>? onResizeTo;

  /// Optional right-click handler (outside edit mode) receiving global anchor rect.
  final ValueChanged<Rect>? onSecondaryTap;
}

/// A grid of tiles. While [editing] the tiles jiggle, carry a remove badge,
/// and can be dragged into a new order.
class TileGrid extends StatefulWidget {
  const TileGrid({
    required this.tiles,
    required this.columns,
    required this.cell,
    required this.gap,
    required this.editing,
    required this.onReorder,
    required this.onRemove,
    super.key,
  });

  final List<Tile> tiles;
  final int columns;
  final Size cell;
  final double gap;
  final bool editing;
  final ValueChanged<List<String>> onReorder;
  final ValueChanged<String> onRemove;

  @override
  State<TileGrid> createState() => _TileGridState();
}

class _TileGridState extends State<TileGrid>
    with SingleTickerProviderStateMixin {
  late final AnimationController _jiggle = AnimationController(
    vsync: this,
    duration: KitMotion.now.scaled(KitMotion.wobble),
  );

  String? _dragId;
  Offset _dragAt = Offset.zero;
  List<String>? _order;
  DateTime _swapped = DateTime(0);

  // Magnetic corner resize state (NextKDE WidgetResizeHandle style).
  String? _resizeId;
  Offset _resizeDelta = Offset.zero;
  TileSize? _resizePreview;

  /// A repeat keeps the period it started with, so a speed change re-arms the
  /// running wobble from its current value instead of restarting it.
  void _repace() {
    _jiggle.duration = KitMotion.now.scaled(KitMotion.wobble);
    if (_jiggle.isAnimating) _jiggle.repeat(reverse: true);
  }

  @override
  void initState() {
    super.initState();
    kitSpeed.addListener(_repace);
    _syncJiggle();
  }

  @override
  void didUpdateWidget(TileGrid old) {
    super.didUpdateWidget(old);
    if (old.editing != widget.editing) _syncJiggle();
  }

  void _syncJiggle() {
    if (widget.editing) {
      _jiggle.repeat(reverse: true);
    } else {
      _jiggle.stop();
      _jiggle.value = 0.5;
      _dragId = null;
      _order = null;
      _resizeId = null;
      _resizePreview = null;
      _resizeDelta = Offset.zero;
    }
  }

  @override
  void dispose() {
    kitSpeed.removeListener(_repace);
    _jiggle.dispose();
    super.dispose();
  }

  double _span(int cells, double unit) =>
      cells * unit + (cells - 1) * widget.gap;

  List<Tile> get _tiles {
    final order = _order;
    if (order == null) return widget.tiles;
    final byId = <String, Tile>{for (final t in widget.tiles) t.id: t};
    return <Tile>[
      for (final id in order)
        if (byId[id] != null) byId[id]!,
    ];
  }

  Rect _rect(Tile tile, ({int col, int row}) at) => Rect.fromLTWH(
    at.col * (widget.cell.width + widget.gap),
    at.row * (widget.cell.height + widget.gap),
    _span(math.min(tile.size.w, widget.columns), widget.cell.width),
    _span(tile.size.h, widget.cell.height),
  );

  void _dragMove(Offset delta, Map<String, Rect> rects) {
    final id = _dragId;
    if (id == null) return;
    _dragAt += delta;
    final centre = _dragAt + rects[id]!.size.center(Offset.zero);
    final order = List<String>.of(_order ?? rects.keys);
    final now = DateTime.now();
    if (now.difference(_swapped).inMilliseconds < 220) {
      setState(() {});
      return;
    }
    for (final entry in rects.entries) {
      if (entry.key == id || !entry.value.contains(centre)) continue;
      final from = order.indexOf(id);
      final to = order.indexOf(entry.key);
      order
        ..removeAt(from)
        ..insert(to, id);
      _swapped = now;
      break;
    }
    setState(() => _order = order);
  }

  void _dragEnd() {
    final order = _order;
    setState(() {
      _dragId = null;
      _order = null;
    });
    if (order != null) widget.onReorder(order);
  }

  TileSize _snapSize(Tile tile, Offset delta) {
    final supported = tile.supportedSizes;
    if (supported == null || supported.length <= 1) return tile.size;
    final startW = _span(tile.size.w, widget.cell.width);
    final startH = _span(tile.size.h, widget.cell.height);
    final targetW = math.max(widget.cell.width * 0.5, startW + delta.dx);
    final targetH = math.max(widget.cell.height * 0.5, startH + delta.dy);
    var best = tile.size;
    var bestDist = double.infinity;
    for (final candidate in supported) {
      final cw = _span(math.min(candidate.w, widget.columns), widget.cell.width);
      final ch = _span(candidate.h, widget.cell.height);
      final dist = (cw - targetW).abs() + (ch - targetH).abs();
      if (dist < bestDist) {
        bestDist = dist;
        best = candidate;
      }
    }
    return best;
  }

  void _resizeStart(Tile tile) {
    setState(() {
      _resizeId = tile.id;
      _resizeDelta = Offset.zero;
      _resizePreview = tile.size;
    });
  }

  void _resizeUpdate(Tile tile, Offset delta) {
    if (_resizeId != tile.id) return;
    _resizeDelta += delta;
    final snapped = _snapSize(tile, _resizeDelta);
    if (snapped.w != _resizePreview?.w || snapped.h != _resizePreview?.h) {
      setState(() => _resizePreview = snapped);
    } else {
      setState(() {});
    }
  }

  void _resizeEnd(Tile tile) {
    if (_resizeId != tile.id) return;
    final target = _resizePreview;
    setState(() {
      _resizeId = null;
      _resizePreview = null;
      _resizeDelta = Offset.zero;
    });
    if (target != null &&
        (target.w != tile.size.w || target.h != tile.size.h)) {
      tile.onResizeTo?.call(target);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tiles = _tiles;
    final packed = packTiles(<TileSize>[
      for (final t in tiles) t.size,
    ], widget.columns);
    final rects = <String, Rect>{
      for (var i = 0; i < tiles.length; i++)
        tiles[i].id: _rect(tiles[i], packed.cells[i]),
    };
    final height = packed.rows == 0
        ? 0.0
        : _span(packed.rows, widget.cell.height);

    Widget tileOf(int index) {
      final tile = tiles[index];
      final rect = rects[tile.id]!;
      final dragging = _dragId == tile.id;
      final resizing = _resizeId == tile.id;
      Widget body = IgnorePointer(ignoring: widget.editing, child: tile.child);
      if (!widget.editing && tile.onSecondaryTap != null) {
        body = GestureDetector(
          behavior: HitTestBehavior.translucent,
          onSecondaryTapUp: (details) {
            final pos = details.globalPosition;
            tile.onSecondaryTap!(Rect.fromLTWH(pos.dx, pos.dy, 1, 1));
          },
          child: body,
        );
      }
      if (widget.editing) {
        final canResize =
            tile.onResize != null ||
            (tile.onResizeTo != null &&
                (tile.supportedSizes?.length ?? 0) > 1);
        body = RawGestureDetector(
          behavior: HitTestBehavior.opaque,
          gestures: <Type, GestureRecognizerFactory>{
            _EagerPan: GestureRecognizerFactoryWithHandlers<_EagerPan>(
              _EagerPan.new,
              (recognizer) {
                recognizer.onStart = (_) => setState(() {
                  _dragId = tile.id;
                  _dragAt = rect.topLeft;
                  _order = <String>[for (final t in tiles) t.id];
                });
                recognizer.onUpdate = (d) => _dragMove(d.delta, rects);
                recognizer.onEnd = (_) => _dragEnd();
                recognizer.onCancel = _dragEnd;
              },
            ),
          },
          child: AnimatedBuilder(
            animation: _jiggle,
            // With reduced motion the tiles hold still; the badges on them
            // already say the grid is being edited.
            builder: (context, child) => Transform.rotate(
              angle: dragging || resizing || KitMotion.reduced(context)
                  ? 0
                  : (_jiggle.value - 0.5) *
                        (index.isEven ? 1 : -1) *
                        0.9 /
                        math.max(rect.width, rect.height) *
                        4,
              child: child,
            ),
            child: AnimatedScale(
              duration: KitMotion.duration(context, KitMotion.fill),
              scale: dragging ? 1.05 : 1,
              child: body,
            ),
          ),
        );
        body = Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            Positioned.fill(child: body),
            if (!dragging && !resizing)
              Positioned(
                left: -6,
                top: -6,
                child: _Badge(
                  icon: BarIcons.minus,
                  onTap: () => widget.onRemove(tile.id),
                ),
              ),
            if (!dragging && canResize)
              Positioned(
                right: -6,
                bottom: -6,
                child: tile.onResizeTo != null &&
                        (tile.supportedSizes?.length ?? 0) > 1
                    ? _MagneticResizeHandle(
                        onTap: () {
                          if (tile.onResize != null) {
                            tile.onResize!();
                          } else {
                            final sup = tile.supportedSizes!;
                            final idx = sup.indexWhere(
                              (s) =>
                                  s.w == tile.size.w && s.h == tile.size.h,
                            );
                            tile.onResizeTo!(sup[(idx + 1) % sup.length]);
                          }
                        },
                        onDragStart: () => _resizeStart(tile),
                        onDragUpdate: (d) => _resizeUpdate(tile, d),
                        onDragEnd: () => _resizeEnd(tile),
                      )
                    : _Badge(icon: BarIcons.resize, onTap: tile.onResize!),
              ),
          ],
        );
      }
      // Inside a surface that stages its entrance the tiles arrive row by
      // row; anywhere else this is the tile itself.
      final cell = packed.cells[index];
      body = KitEntranceItem(row: cell.row, col: cell.col, child: body);
      final at = dragging ? _dragAt : rect.topLeft;
      return AnimatedPositioned(
        key: ValueKey<String>(tile.id),
        duration: dragging
            ? Duration.zero
            : KitMotion.duration(context, KitMotion.travel),
        curve: KitMotion.outCubic,
        left: at.dx,
        top: at.dy,
        width: rect.width,
        height: rect.height,
        child: body,
      );
    }

    final dragIndex = tiles.indexWhere((t) => t.id == _dragId);
    final resizeIndex = tiles.indexWhere((t) => t.id == _resizeId);
    final previewRect = resizeIndex >= 0 && _resizePreview != null
        ? Rect.fromLTWH(
            rects[tiles[resizeIndex].id]!.left,
            rects[tiles[resizeIndex].id]!.top,
            _span(
              math.min(_resizePreview!.w, widget.columns),
              widget.cell.width,
            ),
            _span(_resizePreview!.h, widget.cell.height),
          )
        : null;
    final accent = KitStyle.of(context).accent(context.shellTheme);
    return AnimatedSize(
      duration: KitMotion.loop(context, KitMotion.travel),
      curve: KitMotion.outCubic,
      alignment: Alignment.topCenter,
      child: SizedBox(
        width: _span(widget.columns, widget.cell.width),
        height: height,
        child: Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            for (var i = 0; i < tiles.length; i++)
              if (i != dragIndex) tileOf(i),
            if (dragIndex >= 0) tileOf(dragIndex),
            if (previewRect != null)
              AnimatedPositioned(
                duration: KitMotion.duration(context, KitMotion.tap),
                curve: KitMotion.outCubic,
                left: previewRect.left,
                top: previewRect.top,
                width: previewRect.width,
                height: previewRect.height,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(
                        KitStyle.of(context).corner(20),
                      ),
                      border: Border.all(
                        color: accent.withValues(alpha: 0.85),
                        width: 2,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Claims the pointer at once, so a drag on a tile never scrolls the list
/// the grid sits in.
class _EagerPan extends PanGestureRecognizer {
  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.onTap, this.colour});

  final IconData icon;
  final VoidCallback onTap;
  final Color? colour;

  @override
  Widget build(BuildContext context) {
    final style = KitStyle.of(context);
    return Pressable(
      onTap: onTap,
      scale: Pressable.small,
      wash: true,
      shape: style.disc(26),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            borderRadius: style.disc(20),
            color: colour ?? const Color(0xff8e8e93),
            boxShadow: style.cast(const <BoxShadow>[
              BoxShadow(color: Color(0x40000000), blurRadius: 4),
            ]),
          ),
          child: BarGlyph(icon, size: 11, color: const Color(0xffffffff)),
        ),
      ),
    );
  }
}

/// NextKDE-inspired magnetic corner resize handle: tap cycles sizes, drag
/// stretches a live magnetic grid outline that snaps to supported footprints.
class _MagneticResizeHandle extends StatefulWidget {
  const _MagneticResizeHandle({
    required this.onTap,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  final VoidCallback onTap;
  final VoidCallback onDragStart;
  final ValueChanged<Offset> onDragUpdate;
  final VoidCallback onDragEnd;

  @override
  State<_MagneticResizeHandle> createState() => _MagneticResizeHandleState();
}

class _MagneticResizeHandleState extends State<_MagneticResizeHandle> {
  bool _dragging = false;
  Offset _moved = Offset.zero;

  @override
  Widget build(BuildContext context) {
    final style = KitStyle.of(context);
    final accent = style.accent(context.shellTheme);
    return MouseRegion(
      cursor: SystemMouseCursors.resizeUpLeftDownRight,
      child: RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: <Type, GestureRecognizerFactory>{
          _EagerPan: GestureRecognizerFactoryWithHandlers<_EagerPan>(
            _EagerPan.new,
            (recognizer) {
              recognizer.onStart = (_) {
                _moved = Offset.zero;
                _dragging = true;
                widget.onDragStart();
              };
              recognizer.onUpdate = (d) {
                _moved += d.delta;
                widget.onDragUpdate(d.delta);
              };
              recognizer.onEnd = (_) {
                final tap = _moved.distance < 6;
                _dragging = false;
                widget.onDragEnd();
                if (tap) widget.onTap();
              };
              recognizer.onCancel = () {
                _dragging = false;
                widget.onDragEnd();
              };
            },
          ),
        },
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              borderRadius: style.disc(22),
              color: _dragging ? accent : const Color(0xff636366),
              boxShadow: style.cast(const <BoxShadow>[
                BoxShadow(color: Color(0x48000000), blurRadius: 5),
              ]),
            ),
            child: const BarGlyph(
              BarIcons.resize,
              size: 11,
              color: Color(0xffffffff),
            ),
          ),
        ),
      ),
    );
  }
}

class TileChoice {
  const TileChoice({required this.id, required this.icon, required this.label});

  final String id;
  final IconData icon;
  final String label;
}

/// What can still be added, as a wrap of chips with a green plus.
class TileLibrary extends StatelessWidget {
  const TileLibrary({
    required this.choices,
    required this.onAdd,
    required this.empty,
    super.key,
  });

  final List<TileChoice> choices;
  final ValueChanged<String> onAdd;
  final String empty;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final style = KitStyle.of(context);
    if (choices.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Center(
          child: Text(
            empty,
            style: BarType.caption.copyWith(color: theme.colors.textSecondary),
          ),
        ),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (final choice in choices)
          Pressable(
            onTap: () => onAdd(choice.id),
            scale: Pressable.large,
            wash: true,
            shape: BorderRadius.circular(style.pill(34)),
            child: Container(
              height: 34,
              padding: const EdgeInsets.only(left: 10, right: 5),
              decoration: BoxDecoration(
                color: theme.colors.textPrimary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(style.pill(34)),
                border: style.controlLine(theme),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  BarGlyph(
                    choice.icon,
                    size: 14,
                    color: theme.colors.textPrimary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    choice.label,
                    style: BarType.caption.copyWith(
                      fontSize: 12,
                      color: theme.colors.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  IgnorePointer(
                    child: _Badge(
                      icon: BarIcons.plus,
                      colour: macGreen,
                      onTap: () {},
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// The pill under a grid: "Edit …" at rest, "Done" while editing.
class TileEditButton extends StatelessWidget {
  const TileEditButton({
    required this.label,
    required this.onTap,
    this.strong = false,
    super.key,
  });

  final String label;
  final VoidCallback onTap;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final style = KitStyle.of(context);
    return Pressable(
      onTap: onTap,
      scale: Pressable.large,
      wash: true,
      shape: BorderRadius.circular(style.pill(28)),
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: strong
              ? style.accent(theme)
              : theme.colors.textPrimary.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(style.pill(28)),
          border: strong ? null : style.controlLine(theme),
        ),
        child: Text(
          label,
          style: BarType.caption.copyWith(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: strong ? style.onAccent(theme) : theme.colors.textPrimary,
          ),
        ),
      ),
    );
  }
}
