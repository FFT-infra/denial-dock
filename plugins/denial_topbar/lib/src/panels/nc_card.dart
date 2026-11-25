import 'dart:math' as math;

import 'package:denial_flutter_sdk/models.dart';
import 'package:denial_flutter_sdk/services.dart';
import 'package:denial_flutter_sdk/theme.dart';
import 'package:denial_shell_kit/kit_motion.dart';
import 'package:denial_shell_kit/kit_springs.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../bar_icons.dart';
import '../bar_type.dart';
import '../l10n.dart';
import 'nc_motion.dart';
import 'nc_parts.dart';

String ncAppName(DesktopNotification notification) =>
    notification.appName.isEmpty ? notification.sender : notification.appName;

String _when(BuildContext context, int timeMs) {
  if (timeMs <= 0) return '';
  final time = DateTime.fromMillisecondsSinceEpoch(timeMs);
  final now = DateTime.now();
  final days = DateTime(
    now.year,
    now.month,
    now.day,
  ).difference(DateTime(time.year, time.month, time.day)).inDays;
  if (days <= 0) {
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}';
  }
  return days == 1 ? context.tr('Yesterday') : context.tr('{}d ago', days);
}

/// A notification card: a plate of glass of its own, straight on the
/// wallpaper.
///
/// Drag it toward the screen edge to clear it; the other way it gives a
/// little and comes back. Under the pointer, or under the keyboard's focus,
/// it shows its controls without changing size: a close dot at its corner, a
/// chevron in place of the time, and the sender's actions over its lower
/// edge.
class NcCard extends StatefulWidget {
  const NcCard({
    required this.notification,
    required this.services,
    required this.index,
    required this.gap,
    required this.clearable,
    required this.onTap,
    required this.onDismiss,
    required this.onAction,
    this.unfold,
    this.more = 0,
    this.peeks = 0,
    this.stacked = false,
    this.settled = true,
    this.reachable = true,
    this.leaving = false,
    this.onUnfold,
    super.key,
  });

  /// How far a card's controls reach past its plate. The card's box takes
  /// this in on the left, the right and the top, so the close dot that sits
  /// over the plate's corner is still inside what the pointer can reach.
  static const double reach = 6;

  final DesktopNotification notification;
  final ShellServices services;

  /// The card's place in its stack: 0 is the one in front.
  final int index;

  /// The space above the plate.
  final double gap;
  final bool clearable;
  final VoidCallback onTap;

  /// Clears the card. True when it has already been dragged out of sight.
  final ValueChanged<bool> onDismiss;

  /// Runs one of the sender's actions by key.
  final ValueChanged<String> onAction;

  /// How far the card's stack is open, 0 folded to 1 open. It moves the
  /// plate of a card behind from the edge it shows to its own shape.
  final ValueListenable<double>? unfold;

  /// How many more cards the folded stack holds.
  final int more;

  /// How many cards show their lower edge under this one while its stack is
  /// folded. They are part of this card, so they go where it is dragged.
  final int peeks;

  /// The front card of a folded stack: clearing it clears the stack.
  final bool stacked;

  /// The card lies clear of the others, so it may blur what is behind it. A
  /// card behind does not until its stack has come to rest open.
  final bool settled;

  /// Whether the keyboard can land on it.
  final bool reachable;
  final bool leaving;

  /// Opens the stack, from the chevron.
  final VoidCallback? onUnfold;

  @override
  State<NcCard> createState() => _NcCardState();
}

class _NcCardState extends State<NcCard> with TickerProviderStateMixin {
  static final RegExp _breaks = RegExp(r'\s*\n\s*');
  static const ValueListenable<double> _open = AlwaysStoppedAnimation<double>(
    1,
  );
  static const int _bodyLines = 3;
  static const int _bodyLinesOpen = 12;
  static const double _pillLimit = 132;

  final FocusNode _node = FocusNode(debugLabel: 'nc-card');
  final ValueNotifier<double> _dx = ValueNotifier<double>(0);
  late final AnimationController _exit = AnimationController(vsync: this)
    ..addListener(_onExit);

  /// How much of the plate is glass. It starts as a plain fill and turns
  /// once the card is at rest in a column at rest.
  late final AnimationController _glass = AnimationController(vsync: this);
  bool _glassOn = false;
  late final KitSpring _home = KitSpring(0, ncSpring(NcMotion.rebound));
  late final KitSprings _springs = KitSprings(this, <KitSpring>[
    _home,
  ], tolerance: 0.05);

  NcHost? _host;
  String _summary = '';
  String _body = '';
  List<DesktopNotificationAction> _actions =
      const <DesktopNotificationAction>[];

  bool _hovered = false;
  bool _focused = false;
  bool _primary = false;
  bool _dragging = false;
  bool _gone = false;
  bool _expanded = false;
  double _raw = 0;
  double _from = 0;
  double _span = 0;
  double _lead = 1;

  bool? _truncated;
  double _truncatedAt = 0;
  int? _fit;
  double _fitAt = 0;

  @override
  void initState() {
    super.initState();
    _read();
    _node.addListener(_onNode);
    _dx.addListener(_aimGlass);
    _springs.addListener(() {
      if (!_dragging && !_gone) _dx.value = _home.value;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final host = NcScope.of(context);
    if (host == _host) return;
    _host?.keys.removeListener(_onKeys);
    _host?.glass.removeListener(_aimGlass);
    _host?.detach(widget.notification.id, _node);
    _host = host
      ..keys.addListener(_onKeys)
      ..glass.addListener(_aimGlass)
      ..attach(widget.notification.id, _node);
    _aimGlass();
  }

  @override
  void didUpdateWidget(NcCard old) {
    super.didUpdateWidget(old);
    if (!identical(widget.notification, old.notification)) {
      if (widget.notification.id != old.notification.id) {
        _host?.detach(old.notification.id, _node);
        _host?.attach(widget.notification.id, _node);
      }
      _read();
    }
    // A card that was dragged away and then kept, because its sender does
    // not let it go, comes back.
    if (old.leaving && !widget.leaving && _gone) {
      _gone = false;
      _return();
    }
    _aimGlass();
  }

  @override
  void dispose() {
    _host?.keys.removeListener(_onKeys);
    _host?.glass.removeListener(_aimGlass);
    _host?.detach(widget.notification.id, _node);
    _node.dispose();
    _exit.dispose();
    _glass.dispose();
    _springs.dispose();
    _dx.dispose();
    super.dispose();
  }

  /// The text as the card shows it, worked out once per notification rather
  /// than on every build.
  void _read() {
    final note = widget.notification;
    _summary = note.summary.replaceAll(_breaks, ' ');
    _body = note.body.replaceAll(_breaks, ' ');
    _actions = <DesktopNotificationAction>[
      // The card itself is the default action.
      for (final action in note.actions)
        if (action.key != 'default') action,
    ];
    _truncated = null;
    _fit = null;
  }

  /// The ring is the card's own; it goes when the focus moves to one of the
  /// card's controls, which leaves the card's `hasFocus` as it was.
  void _onNode() {
    if (_node.hasPrimaryFocus != _primary && mounted) {
      setState(() => _primary = _node.hasPrimaryFocus);
    }
  }

  void _onKeys() {
    if (_focused && mounted) setState(() {});
  }

  /// Glass only while nothing moves the card: not while the column slides,
  /// not while the card is dragged, on its way out, or still under another.
  /// A plate that moves is a plain fill, which costs the frame nothing, and
  /// the blur comes back across a short fade once it is home.
  void _aimGlass() {
    final on =
        (_host?.glass.value ?? false) &&
        widget.settled &&
        !widget.leaving &&
        !_dragging &&
        !_gone &&
        _dx.value == 0;
    if (on == _glassOn || !mounted) return;
    _glassOn = on;
    _glass.animateTo(
      on ? 1 : 0,
      duration: KitMotion.duration(
        context,
        on ? KitMotion.fill : KitMotion.tap,
      ),
    );
  }

  double get _outward => _host?.outward ?? 1;

  // ── Clearing ──

  void _dismiss(bool swiped) {
    _host?.leave(widget.notification.id);
    widget.onDismiss(swiped);
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    // Until a key has shown where the focus is, the column takes the key.
    if (event is! KeyDownEvent || !(_host?.keys.value ?? false)) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.backspace) {
      if (!widget.clearable || widget.leaving) return KeyEventResult.ignored;
      _dismiss(false);
      return KeyEventResult.handled;
    }
    if (node.hasPrimaryFocus && ncActivates(event)) {
      widget.onTap();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _onFocus(bool focused) {
    if (focused == _focused) return;
    setState(() => _focused = focused);
    if (!focused || !(_host?.keys.value ?? false)) return;
    // Keep what the keyboard is on in view, whichever way it came from.
    final time = KitMotion.duration(context, KitMotion.enter);
    for (final policy in <ScrollPositionAlignmentPolicy>[
      ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      ScrollPositionAlignmentPolicy.keepVisibleAtStart,
    ]) {
      Scrollable.ensureVisible(
        context,
        duration: time,
        curve: KitMotion.out,
        alignmentPolicy: policy,
      );
    }
  }

  // ── The sideways drag ──

  void _dragStart(DragStartDetails details) {
    if (_gone) return;
    // The spring has no stop; it is parked at rest and ignored while held.
    _dragging = true;
    _home
      ..value = 0
      ..velocity = 0
      ..target = 0;
    _raw = NcMotion.swipeRaw(_dx.value * _outward);
    setState(() {});
    _aimGlass();
  }

  void _dragUpdate(DragUpdateDetails details) {
    if (_gone || !_dragging) return;
    _raw += (details.primaryDelta ?? 0) * _outward;
    final double offset;
    if (widget.clearable || _raw < 0) {
      offset = NcMotion.swipeFollow(_raw, slop: 0);
    } else {
      // A card that cannot be cleared gives the same little either way.
      offset = -NcMotion.swipeFollow(-_raw, slop: 0);
    }
    _dx.value = offset * _outward;
  }

  void _dragEnd(DragEndDetails details, double width) {
    if (_gone || !_dragging) return;
    setState(() => _dragging = false);
    final offset = _dx.value * _outward;
    final velocity = (details.primaryVelocity ?? 0) * _outward;
    if (!widget.clearable ||
        !NcMotion.swipeClears(
          offset: offset,
          velocity: velocity,
          width: width,
        )) {
      _return();
      return;
    }
    _gone = true;
    _from = offset;
    _span = math.max(1, width + NcCard.reach * 2 + 24 - offset);
    final exit = NcMotion.swipeExit(remaining: _span, velocity: velocity);
    _lead = exit.lead;
    final time = KitMotion.duration(
      context,
      Duration(microseconds: (exit.ms * 1000).round()),
    );
    if (time == Duration.zero) {
      _dx.value = (_from + _span) * _outward;
      _dismiss(true);
      return;
    }
    _exit
      ..duration = time
      ..forward(from: 0).whenCompleteOrCancel(() {
        if (mounted && _gone) _dismiss(true);
      });
  }

  void _dragCancel() {
    if (!_dragging) return;
    setState(() => _dragging = false);
    if (!_gone) _return();
    _aimGlass();
  }

  void _onExit() {
    if (!_gone) return;
    _dx.value =
        (_from + _span * NcMotion.exitCurve(_lead, _exit.value)) * _outward;
  }

  /// Home from wherever the card is, starting at rest so it cannot pass.
  void _return() {
    _exit.stop();
    _home
      ..value = _dx.value
      ..velocity = 0
      ..target = 0;
    _springs.kick(reduceMotion: KitMotion.reduced(context));
    _aimGlass();
  }

  // ── What fits ──

  double _textWidth(String text, TextStyle style, {int lines = 1}) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: DefaultTextStyle.of(context).style.merge(style),
      ),
      maxLines: lines,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  /// Whether the body is cut short at [width]. Asked only once the card
  /// shows its controls, so opening the column lays no text out twice.
  bool _cut(double width, TextStyle style) {
    if (_truncated != null && _truncatedAt == width) return _truncated!;
    final painter = TextPainter(
      text: TextSpan(
        text: _body,
        style: DefaultTextStyle.of(context).style.merge(style),
      ),
      maxLines: _bodyLines,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: math.max(0, width));
    _truncatedAt = width;
    _truncated = painter.didExceedMaxLines;
    painter.dispose();
    return _truncated!;
  }

  /// How many action pills go side by side in [width].
  int _fits(double width, TextStyle style) {
    if (_fit != null && _fitAt == width) return _fit!;
    _fitAt = width;
    return _fit = NcMotion.actionsThatFit(<double>[
      for (final action in _actions)
        math.min(_textWidth(action.label, style), _pillLimit) + 21,
    ], width);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final host = NcScope.of(context);
    final ink = theme.colors.textPrimary;
    final note = widget.notification;
    final hot =
        !widget.leaving &&
        (_hovered || _dragging || (_focused && host.keys.value));
    final iconId = note.desktopEntry.isNotEmpty
        ? note.desktopEntry
        : note.appName;
    final unfold = widget.unfold ?? _open;
    final bodyStyle = BarType.menuRow.copyWith(
      color: ink.withValues(alpha: 0.86),
    );
    final reachable = widget.reachable && !widget.leaving;

    return FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: FocusTraversalOrder(
        order: const NumericFocusOrder(0),
        child: Focus(
          focusNode: _node,
          canRequestFocus: reachable,
          skipTraversal: !reachable,
          onFocusChange: _onFocus,
          onKeyEvent: _key,
          child: MouseRegion(
            // The card's box takes in the space above its plate and the
            // reach at its sides. A press there is a press on the
            // wallpaper, which closes the column, so the region lets it by.
            opaque: false,
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: LayoutBuilder(
              builder: (context, box) {
                final width = box.maxWidth - NcCard.reach * 2;
                final textWidth = width - 26 - NcLook.icon - 10;
                final canGrow =
                    _body.isNotEmpty &&
                    (_expanded || (hot && _cut(textWidth, bodyStyle)));
                final chevron = hot && (widget.onUnfold != null || canGrow)
                    ? (widget.onUnfold ??
                          () => setState(() => _expanded = !_expanded))
                    : null;

                final face = Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: SizedBox(
                          width: NcLook.icon,
                          height: NcLook.icon,
                          child: iconId.isEmpty
                              ? BarGlyph(
                                  BarIcons.bellFill,
                                  size: 24,
                                  color: theme.colors.textSecondary,
                                )
                              : widget.services.buildApplicationIcon(
                                  context,
                                  iconId,
                                ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                Expanded(
                                  child: Text(
                                    _summary.isEmpty
                                        ? ncAppName(note)
                                        : _summary,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: BarType.title.copyWith(color: ink),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                _Trailing(
                                  when: _when(context, note.timeMs),
                                  up: _expanded && widget.onUnfold == null,
                                  onChevron: chevron,
                                ),
                              ],
                            ),
                            if (_body.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 1),
                                child: AnimatedSize(
                                  duration: KitMotion.loop(
                                    context,
                                    KitMotion.settle,
                                  ),
                                  curve: KitMotion.outCubic,
                                  alignment: Alignment.topLeft,
                                  child: Text(
                                    _body,
                                    maxLines: _expanded
                                        ? _bodyLinesOpen
                                        : _bodyLines,
                                    overflow: TextOverflow.ellipsis,
                                    style: bodyStyle,
                                  ),
                                ),
                              ),
                            if (widget.more > 0)
                              // The count belongs to the folded stack and
                              // goes as the stack opens.
                              ValueListenableBuilder<double>(
                                valueListenable: unfold,
                                builder: (context, t, child) {
                                  final shown = 1 - t.clamp(0.0, 1.0);
                                  return Align(
                                    alignment: Alignment.topLeft,
                                    heightFactor: shown,
                                    child: Opacity(
                                      opacity: shown,
                                      child: child,
                                    ),
                                  );
                                },
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 3),
                                  child: Text(
                                    context.tr('{} more', widget.more),
                                    style: BarType.caption.copyWith(
                                      color: theme.colors.textSecondary,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );

                final plate = Stack(
                  children: <Widget>[
                    Positioned.fill(
                      child: NcPlate(
                        index: widget.index,
                        unfold: unfold,
                        glass: _glass,
                        lift: widget.gap,
                        peeks: widget.peeks,
                        blur: widget.settled,
                        ring: _primary && host.keys.value,
                      ),
                    ),
                    // A card behind keeps to the room its stack has opened
                    // for it, and its text waits for the second half.
                    ClipRect(
                      clipper: widget.index == 0
                          ? null
                          : _RoomClip(unfold, widget.gap),
                      child: ValueListenableBuilder<double>(
                        valueListenable: unfold,
                        builder: (context, t, child) => Opacity(
                          opacity: widget.index == 0 ? 1 : NcMotion.reveal(t),
                          child: child,
                        ),
                        child: face,
                      ),
                    ),
                  ],
                );

                final shownActions = _actions.isEmpty
                    ? 0
                    : _fits(width - 16, NcChip.style(theme));
                final rest = _actions.skip(shownActions).toList();

                final card = Stack(
                  children: <Widget>[
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        NcCard.reach,
                        widget.gap,
                        NcCard.reach,
                        0,
                      ),
                      child: NcTap(
                        onTap: widget.onTap,
                        scale: 0.985,
                        focusable: false,
                        builder: (context, hovered, pressed, focused) => plate,
                      ),
                    ),
                    if (_actions.isNotEmpty)
                      Positioned(
                        right: NcCard.reach + 8,
                        bottom: 8,
                        child: _Shown(
                          shown: hot,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              for (var i = 0; i < shownActions; i++)
                                Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: FocusTraversalOrder(
                                    order: NumericFocusOrder(2.0 + i),
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: _pillLimit + 21,
                                      ),
                                      child: NcChip(
                                        label: _actions[i].label,
                                        solid: true,
                                        enabled: hot,
                                        onTap: () =>
                                            widget.onAction(_actions[i].key),
                                      ),
                                    ),
                                  ),
                                ),
                              if (rest.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: FocusTraversalOrder(
                                    order: const NumericFocusOrder(50),
                                    child: _MorePill(
                                      enabled: hot,
                                      onOpen: (anchor) =>
                                          host.showMenu(anchor, <NcMenuItem>[
                                            for (final action in rest)
                                              NcMenuItem(
                                                label: action.label,
                                                onTap: () =>
                                                    widget.onAction(action.key),
                                              ),
                                          ]),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    if (widget.clearable)
                      Positioned(
                        left: 0,
                        top: widget.gap - NcCard.reach,
                        child: _Shown(
                          shown: hot,
                          child: FocusTraversalOrder(
                            order: const NumericFocusOrder(90),
                            child: NcDot(
                              enabled: hot,
                              label: widget.stacked
                                  ? context.tr('Clear All')
                                  : null,
                              // Said outright while the stack is dragged
                              // or the keyboard is on it: clearing here
                              // takes every card of the stack.
                              open:
                                  widget.stacked &&
                                  (_dragging || (_primary && host.keys.value)),
                              onTap: () => _dismiss(false),
                            ),
                          ),
                        ),
                      ),
                  ],
                );

                return RawGestureDetector(
                  behavior: HitTestBehavior.translucent,
                  gestures: <Type, GestureRecognizerFactory>{
                    _Swipe: GestureRecognizerFactoryWithHandlers<_Swipe>(
                      () => _Swipe(debugOwner: this),
                      (recognizer) => recognizer
                        ..onStart = _dragStart
                        ..onUpdate = _dragUpdate
                        ..onEnd = ((details) => _dragEnd(details, width))
                        ..onCancel = _dragCancel,
                    ),
                  },
                  child: ValueListenableBuilder<double>(
                    valueListenable: _dx,
                    builder: (context, dx, child) {
                      final out = dx * host.outward;
                      return Transform.translate(
                        offset: Offset(dx, 0),
                        child: Opacity(
                          opacity: ncSwipeOpacity(out, width),
                          child: child,
                        ),
                      );
                    },
                    child: card,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// How solid a card is once dragged [out] toward the edge.
double ncSwipeOpacity(double out, double width) =>
    out <= 0 || width <= 0 ? 1.0 : 1 - (out / width).clamp(0.0, 1.0) * 0.85;

/// Starts a sideways drag after a short travel with a mouse, a trackpad or a
/// pen. A finger keeps the platform's distance, because there the drag
/// competes with scrolling the list and a shorter one would steal it.
class _Swipe extends HorizontalDragGestureRecognizer {
  _Swipe({super.debugOwner});

  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) {
    if (pointerDeviceKind == PointerDeviceKind.touch) {
      return super.hasSufficientGlobalDistanceToAccept(
        pointerDeviceKind,
        deviceTouchSlop,
      );
    }
    return globalDistanceMoved.abs() > NcMotion.swipeSlop;
  }
}

/// A control that is only there while the card is hot. It fades, and while
/// hidden it takes no press.
class _Shown extends StatelessWidget {
  const _Shown({required this.shown, required this.child});

  final bool shown;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !shown,
      child: AnimatedOpacity(
        duration: KitMotion.duration(context, KitMotion.ease),
        opacity: shown ? 1 : 0,
        child: child,
      ),
    );
  }
}

/// The time a card arrived, or, while the card is hot and has more to show,
/// a chevron in its place.
class _Trailing extends StatelessWidget {
  const _Trailing({
    required this.when,
    required this.up,
    required this.onChevron,
  });

  final String when;
  final bool up;
  final VoidCallback? onChevron;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final onChevron = this.onChevron;
    // One height for both faces, so the swap never moves the card's text.
    return SizedBox(
      height: 16,
      child: AnimatedSwitcher(
        duration: KitMotion.duration(context, KitMotion.ease),
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.centerRight,
          children: <Widget>[...previous, ?current],
        ),
        child: onChevron == null
            ? Text(
                when,
                key: const ValueKey<String>('time'),
                style: BarType.caption.copyWith(
                  color: theme.colors.textSecondary,
                ),
              )
            : FocusTraversalOrder(
                key: const ValueKey<String>('chevron'),
                order: const NumericFocusOrder(1),
                child: NcTap(
                  onTap: onChevron,
                  scale: 0.86,
                  builder: (context, hovered, pressed, focused) => Container(
                    width: 24,
                    height: 16,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: ncChipFill(theme, hovered: hovered || pressed),
                      border: focused
                          ? ncChipBorder(context, focused: true)
                          : null,
                    ),
                    child: BarGlyph(
                      up ? BarIcons.chevronUp : BarIcons.chevronDown,
                      size: 9,
                      color: theme.colors.textPrimary,
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

/// The pill that opens the actions there was no room for.
class _MorePill extends StatelessWidget {
  const _MorePill({required this.enabled, required this.onOpen});

  final bool enabled;
  final ValueChanged<Rect> onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    return NcTap(
      enabled: enabled,
      scale: 0.92,
      onTap: () {
        final box = context.findRenderObject();
        if (box is! RenderBox || !box.hasSize) return;
        onOpen(box.localToGlobal(Offset.zero) & box.size);
      },
      builder: (context, hovered, pressed, focused) => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: ncSolidFill(theme, hovered: hovered || pressed),
          border: ncChipBorder(context, focused: focused),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // An empty run of the pill's type, so it is as tall as the
              // labelled pills beside it.
              Text('\u200b', style: NcChip.style(theme)),
              BarGlyph(
                BarIcons.ellipsis,
                size: 12,
                color: theme.colors.textPrimary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Keeps a card behind to the height its stack has opened for it so far.
class _RoomClip extends CustomClipper<Rect> {
  _RoomClip(this.unfold, this.gap) : super(reclip: unfold);

  final ValueListenable<double> unfold;
  final double gap;

  @override
  Rect getClip(Size size) {
    final t = unfold.value;
    if (t >= 1) return Offset.zero & size;
    final open = math.max(0.0, t) * (size.height + gap) - gap;
    return Rect.fromLTWH(0, 0, size.width, math.max(0, open));
  }

  @override
  bool shouldReclip(_RoomClip old) => old.unfold != unfold || old.gap != gap;
}
