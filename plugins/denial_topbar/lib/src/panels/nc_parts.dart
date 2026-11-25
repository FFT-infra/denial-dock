import 'dart:async';
import 'dart:math' as math;

import 'package:denial_flutter_sdk/theme.dart';
import 'package:denial_shell_kit/kit_motion.dart';
import 'package:denial_shell_kit/kit_springs.dart';
import 'package:denial_shell_kit/kit_style.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../bar_icons.dart';
import '../bar_type.dart';
import 'nc_motion.dart';

/// A tuning from the centre's own table, in the kit's type.
KitSpringTuning ncSpring(NcTuning tuning) =>
    KitSpringTuning(tuning.stiffness, tuning.dampingRatio);

/// What the pieces of the notification centre ask of the column they are in.
abstract class NcHost {
  /// Whether the keyboard is what the user is steering with. Focus only
  /// shows, and only reveals a card's controls, while it is.
  ValueListenable<bool> get keys;

  /// 1 when a card leaves to the right, -1 to the left: toward the screen
  /// edge the column sits at.
  double get outward;

  /// A card's own focus node, so the arrow keys can walk the cards.
  void attach(int id, FocusNode node);
  void detach(int id, FocusNode node);

  /// Moves the focus off the card [id] before it goes, to the card that
  /// will take its place.
  void leave(int id);

  /// Opens a small menu under [anchor], a rectangle in the scene.
  void showMenu(Rect anchor, List<NcMenuItem> items);
}

class NcScope extends InheritedWidget {
  const NcScope({required this.host, required super.child, super.key});

  final NcHost host;

  static NcHost of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<NcScope>()!.host;

  @override
  bool updateShouldNotify(NcScope old) => host != old.host;
}

bool ncActivates(KeyEvent event) =>
    event is KeyDownEvent &&
    (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter ||
        event.logicalKey == LogicalKeyboardKey.space);

/// The fill of a small control lying on the slab. No blur and no shadow of
/// its own: the slab is the only glass in the column.
Color ncChipFill(ShellThemeData theme, {bool hovered = false}) =>
    theme.colors.textPrimary.withValues(alpha: hovered ? 0.17 : 0.10);

/// The fill of a control that sits over a card's text, so it has to cover
/// what is under it.
Color ncSolidFill(ShellThemeData theme, {bool hovered = false}) {
  final base = theme
      .panelColor(theme.colors.panelBackground)
      .withValues(alpha: 1);
  return Color.alphaBlend(
    theme.colors.textPrimary.withValues(alpha: hovered ? 0.24 : 0.15),
    base,
  );
}

/// The outline of a small control: a hairline, or the look's accent while
/// the keyboard is on it.
Border ncChipBorder(BuildContext context, {bool focused = false}) {
  final theme = context.shellTheme;
  return focused
      ? Border.all(color: KitStyle.of(context).accent(theme), width: 1.5)
      : Border.all(color: theme.colors.hairline, width: 0.5);
}

/// Something to press: it springs under the pointer as the look's controls
/// do, takes the keyboard's focus, and answers Return and Space.
class NcTap extends StatefulWidget {
  const NcTap({
    required this.onTap,
    required this.builder,
    this.scale = 0.94,
    this.focusable = true,
    this.enabled = true,
    this.focusNode,
    super.key,
  });

  final VoidCallback onTap;

  /// [focused] is true only while the keyboard is in use.
  final Widget Function(
    BuildContext context,
    bool hovered,
    bool pressed,
    bool focused,
  )
  builder;
  final double scale;

  /// Whether the keyboard can reach it at all, and whether it can right now.
  final bool focusable;
  final bool enabled;
  final FocusNode? focusNode;

  @override
  State<NcTap> createState() => _NcTapState();
}

class _NcTapState extends State<NcTap> {
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final keys = NcScope.of(context).keys;
    final body = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: Sprung(
          target: _pressed ? widget.scale : 1,
          tuning: KitStyle.of(context).pressTuning,
          builder: (context, value, child) =>
              Transform.scale(scale: value, child: child),
          child: ValueListenableBuilder<bool>(
            valueListenable: keys,
            builder: (context, keyboard, _) => widget.builder(
              context,
              _hovered,
              _pressed,
              _focused && keyboard,
            ),
          ),
        ),
      ),
    );
    if (!widget.focusable) return body;
    return Focus(
      focusNode: widget.focusNode,
      canRequestFocus: widget.enabled,
      skipTraversal: !widget.enabled,
      onFocusChange: (focused) => setState(() => _focused = focused),
      onKeyEvent: (node, event) {
        if (!ncActivates(event)) return KeyEventResult.ignored;
        widget.onTap();
        return KeyEventResult.handled;
      },
      child: body,
    );
  }
}

/// A small pill with a label: Clear All, Show Less, Edit Widgets.
class NcChip extends StatelessWidget {
  const NcChip({
    required this.label,
    required this.onTap,
    this.enabled = true,
    this.solid = false,
    super.key,
  });

  final String label;
  final VoidCallback onTap;
  final bool enabled;

  /// Covers what is under it, for a pill over a card's text.
  final bool solid;

  static TextStyle style(ShellThemeData theme) => BarType.caption.copyWith(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: theme.colors.textPrimary,
  );

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    return NcTap(
      onTap: onTap,
      scale: 0.92,
      enabled: enabled,
      builder: (context, hovered, pressed, focused) => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: solid
              ? ncSolidFill(theme, hovered: hovered || pressed)
              : ncChipFill(theme, hovered: hovered || pressed),
          border: ncChipBorder(context, focused: focused),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style(theme),
          ),
        ),
      ),
    );
  }
}

/// The round control in a card's corner: a cross that clears it. With a
/// [label] it opens into a pill under the pointer, or while [open].
class NcDot extends StatelessWidget {
  const NcDot({
    required this.onTap,
    this.icon = BarIcons.xmark,
    this.label,
    this.open = false,
    this.enabled = true,
    super.key,
  });

  static const double size = 20;

  final VoidCallback onTap;
  final IconData icon;
  final String? label;
  final bool open;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final label = this.label;
    return NcTap(
      onTap: onTap,
      scale: 0.88,
      enabled: enabled,
      builder: (context, hovered, pressed, focused) => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size / 2),
          color: ncSolidFill(theme, hovered: hovered || pressed),
          border: ncChipBorder(context, focused: focused),
        ),
        child: AnimatedSize(
          duration: KitMotion.loop(context, KitMotion.ease),
          curve: KitMotion.outCubic,
          alignment: Alignment.centerLeft,
          child: SizedBox(
            height: size,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                SizedBox(
                  width: size,
                  child: BarGlyph(
                    icon,
                    size: 9,
                    color: theme.colors.textPrimary,
                  ),
                ),
                if (label != null && (hovered || focused || open))
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(
                      label,
                      maxLines: 1,
                      style: NcChip.style(theme).copyWith(fontSize: 11.5),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A row of the column that can come and go. Going, it shrinks a little and
/// fades, then gives its room up on a spring so what is below rises into the
/// gap; coming, the room opens while it fades in. Whatever holds the column
/// follows, because the room is real layout.
class NcPresence extends StatefulWidget {
  const NcPresence({
    required this.present,
    required this.child,
    this.delay = Duration.zero,
    this.swiped = false,
    this.appear = false,
    this.onGone,
    super.key,
  });

  final bool present;

  /// Waited before going, so a list can clear one row after another.
  final Duration delay;

  /// The row has already been dragged out of sight; only its room is left
  /// to close.
  final bool swiped;

  /// Start out of sight and come in, for a row added to an open column.
  final bool appear;

  /// Called once the row has gone and its room is closed.
  final VoidCallback? onGone;
  final Widget child;

  @override
  State<NcPresence> createState() => _NcPresenceState();
}

class _NcPresenceState extends State<NcPresence> with TickerProviderStateMixin {
  late final bool _startShown = widget.present && !widget.appear;
  late final AnimationController _fade = AnimationController(
    vsync: this,
    value: _startShown ? 1 : 0,
  );
  late final Animation<double> _scale = Tween<double>(
    begin: 0.94,
    end: 1,
  ).animate(_fade);
  late final KitSpring _room = KitSpring(
    _startShown ? 1 : 0,
    ncSpring(NcMotion.gap),
  );
  late final KitSprings _springs = KitSprings(this, <KitSpring>[
    _room,
  ], tolerance: 0.002);
  Timer? _wait;
  int _run = 0;

  @override
  void initState() {
    super.initState();
    _springs.onRest = _rested;
    if (!widget.present) {
      // Built already gone, as a row the list dropped while it was leaving
      // and builds again: there is nothing left to play.
      scheduleMicrotask(() {
        if (mounted && !widget.present) widget.onGone?.call();
      });
    }
    if (widget.present && widget.appear) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.present) _enter();
      });
    }
  }

  @override
  void didUpdateWidget(NcPresence old) {
    super.didUpdateWidget(old);
    if (widget.present == old.present) return;
    if (widget.present) {
      _enter();
    } else {
      _leave();
    }
  }

  @override
  void dispose() {
    _wait?.cancel();
    _fade.dispose();
    _springs.dispose();
    super.dispose();
  }

  void _tune() => _room.tune(
    ncSpring(KitStyle.of(context).liquid ? NcMotion.gapLiquid : NcMotion.gap),
  );

  void _enter() {
    _run++;
    _wait?.cancel();
    _tune();
    _room.target = 1;
    _springs.kick(reduceMotion: KitMotion.reduced(context));
    _fade.animateTo(
      1,
      duration: KitMotion.duration(context, KitMotion.reveal),
      curve: KitMotion.out,
    );
  }

  void _leave() {
    final run = ++_run;
    _wait?.cancel();
    void go() {
      if (!mounted || run != _run) return;
      if (widget.swiped) {
        _fade.value = 0;
        _close();
        return;
      }
      _fade
          .animateTo(
            0,
            duration: KitMotion.duration(context, KitMotion.fade),
            curve: KitMotion.inOut,
          )
          .whenCompleteOrCancel(() {
            if (mounted && run == _run) _close();
          });
    }

    final delay = KitMotion.duration(context, widget.delay);
    if (delay == Duration.zero) {
      go();
    } else {
      _wait = Timer(delay, go);
    }
  }

  void _close() {
    _tune();
    _room.target = 0;
    _springs.kick(reduceMotion: KitMotion.reduced(context));
  }

  void _rested() {
    if (widget.present || _room.target != 0) return;
    // This can be reached from a build, when motion is reduced and the room
    // closes at once; the owner is told after it.
    scheduleMicrotask(() {
      if (mounted && !widget.present) widget.onGone?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _springs,
      builder: (context, child) {
        final room = math.max(0.0, _room.value);
        return ClipRect(
          clipBehavior: room < 0.999 ? Clip.hardEdge : Clip.none,
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: room,
            child: child,
          ),
        );
      },
      child: IgnorePointer(
        ignoring: !widget.present,
        child: FadeTransition(
          opacity: _fade,
          child: ScaleTransition(scale: _scale, child: widget.child),
        ),
      ),
    );
  }
}

class NcMenuItem {
  const NcMenuItem({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;
}

/// A short menu over the column, for the actions a card has no room for. It
/// is opaque: glass here would show the cards through it.
class NcMenu extends StatefulWidget {
  const NcMenu({
    required this.anchor,
    required this.items,
    required this.onClose,
    required this.keyboard,
    super.key,
  });

  /// Where the menu hangs from, in the coordinates of the box it fills.
  final Rect anchor;
  final List<NcMenuItem> items;
  final VoidCallback onClose;

  /// Whether to put the focus on the first row.
  final bool keyboard;

  @override
  State<NcMenu> createState() => _NcMenuState();
}

class _NcMenuState extends State<NcMenu> {
  late final List<FocusNode> _nodes = <FocusNode>[
    for (var i = 0; i < widget.items.length; i++)
      FocusNode(debugLabel: 'nc-menu-$i'),
  ];

  @override
  void initState() {
    super.initState();
    if (widget.keyboard && _nodes.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _nodes.first.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    for (final node in _nodes) {
      node.dispose();
    }
    super.dispose();
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      widget.onClose();
      return KeyEventResult.handled;
    }
    final down =
        key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.tab;
    if (!down && key != LogicalKeyboardKey.arrowUp) {
      return KeyEventResult.ignored;
    }
    final at = _nodes.indexWhere((node) => node.hasFocus);
    final next = at < 0
        ? 0
        : (at + (down ? 1 : -1)).clamp(0, _nodes.length - 1);
    _nodes[next].requestFocus();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final style = KitStyle.of(context);
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (_) => widget.onClose(),
        ),
        CustomSingleChildLayout(
          delegate: _MenuPlace(widget.anchor),
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: 1),
            duration: KitMotion.duration(context, KitMotion.tap),
            curve: KitMotion.out,
            builder: (context, value, child) => Opacity(
              opacity: value,
              child: Transform.scale(
                scale: 0.96 + 0.04 * value,
                alignment: Alignment.topRight,
                child: child,
              ),
            ),
            child: Listener(
              behavior: HitTestBehavior.opaque,
              child: Focus(
                canRequestFocus: false,
                skipTraversal: true,
                onKeyEvent: _key,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(
                      style.radius(theme, 11),
                    ),
                    color: ncSolidFill(theme),
                    border: Border.all(color: theme.colors.hairline, width: 1),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: theme.colors.shadow.withValues(alpha: 0.26),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(5),
                    child: IntrinsicWidth(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          for (var i = 0; i < widget.items.length; i++)
                            NcTap(
                              focusNode: _nodes[i],
                              scale: 1,
                              onTap: () {
                                widget.onClose();
                                widget.items[i].onTap();
                              },
                              builder: (context, hovered, pressed, focused) {
                                final row = style.menuRow(
                                  theme,
                                  hot: hovered || focused,
                                );
                                return Container(
                                  height: 26,
                                  alignment: Alignment.centerLeft,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 9,
                                  ),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(
                                      style.radius(theme, 6),
                                    ),
                                    color: row.fill,
                                  ),
                                  child: Text(
                                    widget.items[i].label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: BarType.menuRow.copyWith(
                                      color: row.ink,
                                    ),
                                  ),
                                );
                              },
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
      ],
    );
  }
}

/// Hangs the menu under its anchor with their right edges together, and
/// turns it above when there is no room below.
class _MenuPlace extends SingleChildLayoutDelegate {
  const _MenuPlace(this.anchor);

  final Rect anchor;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints(
        minWidth: 120,
        maxWidth: math.max(120, math.min(240, constraints.maxWidth - 16)),
        maxHeight: math.max(0, constraints.maxHeight - 16),
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final right = math.max(8.0, size.width - childSize.width - 8);
    final left = (anchor.right - childSize.width).clamp(8.0, right);
    final below = anchor.bottom + 4;
    final top = below + childSize.height <= size.height - 8
        ? below
        : math.max(8.0, anchor.top - 4 - childSize.height);
    return Offset(left, top);
  }

  @override
  bool shouldRelayout(_MenuPlace old) => old.anchor != anchor;
}
