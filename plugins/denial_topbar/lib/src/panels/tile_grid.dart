import 'dart:math' as math;

import 'package:denial_flutter_sdk/theme.dart';
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
  });

  final String id;
  final TileSize size;
  final Widget child;

  /// Switches the tile to its other size, when it has one.
  final VoidCallback? onResize;
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
      Widget body = IgnorePointer(ignoring: widget.editing, child: tile.child);
      if (widget.editing) {
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
            builder: (context, child) => Transform.rotate(
              angle: dragging
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
            if (!dragging)
              Positioned(
                left: -6,
                top: -6,
                child: _Badge(
                  icon: BarIcons.minus,
                  onTap: () => widget.onRemove(tile.id),
                ),
              ),
            if (!dragging && tile.onResize != null)
              Positioned(
                right: -6,
                bottom: -6,
                child: _Badge(icon: BarIcons.resize, onTap: tile.onResize!),
              ),
          ],
        );
      }
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
    return AnimatedSize(
      duration: KitMotion.duration(context, KitMotion.travel),
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
    return Pressable(
      onTap: onTap,
      scale: 0.8,
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colour ?? const Color(0xff8e8e93),
            boxShadow: const <BoxShadow>[
              BoxShadow(color: Color(0x40000000), blurRadius: 4),
            ],
          ),
          child: BarGlyph(icon, size: 11, color: const Color(0xffffffff)),
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
            scale: 0.94,
            child: Container(
              height: 34,
              padding: const EdgeInsets.only(left: 10, right: 5),
              decoration: BoxDecoration(
                color: theme.colors.textPrimary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(17),
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
    return Pressable(
      onTap: onTap,
      scale: 0.94,
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: strong
              ? KitStyle.of(context).accent(context.shellTheme)
              : theme.colors.textPrimary.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          label,
          style: BarType.caption.copyWith(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: strong
                ? KitStyle.of(context).onAccent(context.shellTheme)
                : theme.colors.textPrimary,
          ),
        ),
      ),
    );
  }
}
