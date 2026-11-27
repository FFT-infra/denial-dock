import 'dart:async';
import 'dart:math' as math;

import 'package:denial_flutter_sdk/theme.dart';
import 'package:denial_shell_kit/kit_control_math.dart';
import 'package:denial_shell_kit/kit_motion.dart';
import 'package:denial_shell_kit/kit_pressable.dart';
import 'package:denial_shell_kit/kit_springs.dart';
import 'package:denial_shell_kit/kit_style.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../bar_icons.dart';
import '../bar_type.dart';

export 'package:denial_shell_kit/kit_pressable.dart';

const Color macBlue = Color(0xff0a84ff);
const Color macPurple = Color(0xff5e5ce6);
const Color macOrange = Color(0xffff9f0a);
const Color macYellow = Color(0xffffd60a);
const Color macGreen = Color(0xff30d158);
const Color macRed = Color(0xffff453a);

/// A glyph whose colour eases to a new one instead of switching.
class MacGlyph extends StatelessWidget {
  const MacGlyph(
    this.icon, {
    required this.size,
    required this.color,
    super.key,
  });

  final IconData icon;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: color),
      duration: KitMotion.duration(context, KitMotion.enter),
      curve: KitMotion.outCubic,
      builder: (context, value, _) =>
          BarGlyph(icon, size: size, color: value ?? color),
    );
  }
}

/// A switch whose knob stays under the finger: drag it across, flick it, or
/// tap. While held the knob lengthens. It shows the new state at once and
/// goes back if whatever it controls does not follow.
class MacSwitch extends StatefulWidget {
  const MacSwitch({
    required this.value,
    required this.onChanged,
    this.busy = false,
    super.key,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool busy;

  @override
  State<MacSwitch> createState() => _MacSwitchState();
}

class _MacSwitchState extends State<MacSwitch>
    with SingleTickerProviderStateMixin {
  static const double _width = 46;
  static const double _pad = 2;
  static const double _swell = 4;

  /// How long the knob waits on the side it was put before giving up.
  static const Duration _patience = Duration(milliseconds: 1200);

  late final KitSpring _at = KitSpring(
    widget.value ? 1 : -1,
    kitStyle.value.toggle,
  );
  late final KitSpring _held = KitSpring(0, kitStyle.value.pressTuning);
  late final KitSprings _springs = KitSprings(this, <KitSpring>[_at, _held]);

  /// The knob's place while a finger drags it, -1 to 1.
  double? _drag;

  /// The state asked for and not yet confirmed.
  bool? _wanted;
  Timer? _giveUp;
  bool _focused = false;

  bool get _ring => _focused && keyboardInput.value;

  void _inputChanged() {
    if (_focused) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    watchKitInput();
    keyboardInput.addListener(_inputChanged);
  }

  bool get _target => _wanted ?? widget.value;
  bool get _enabled => widget.onChanged != null && !widget.busy;

  void _kick() => _springs.kick(reduceMotion: KitMotion.reduced(context));

  void _head() {
    _at.target = _drag ?? (_target ? 1 : -1);
    _kick();
  }

  void _hold(bool held) {
    _held.target = held ? 1 : 0;
    _kick();
  }

  void _choose(bool next) {
    _giveUp?.cancel();
    if (next == widget.value) {
      setState(() => _wanted = null);
    } else {
      setState(() => _wanted = next);
      _giveUp = Timer(_patience, () {
        if (!mounted) return;
        setState(() => _wanted = null);
        _head();
      });
      widget.onChanged?.call(next);
    }
    _head();
  }

  @override
  void didUpdateWidget(MacSwitch old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      _wanted = null;
      _giveUp?.cancel();
    }
    if (_drag == null) _head();
  }

  @override
  void dispose() {
    keyboardInput.removeListener(_inputChanged);
    _giveUp?.cancel();
    _springs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final style = KitStyle.of(context);
    final enabled = _enabled;
    _at.tune(style.toggle);
    _held.tune(style.pressTuning);
    // Ink on the fill for Denial's knob and for a flat look's block; a white
    // bead with a shadow otherwise.
    final inked = style.liquid || style.flat;
    final knob = inked ? 22.0 : 28.0;
    final travel = _width - _pad * 2 - knob;
    final drag = _drag;
    final on = drag != null ? drag > 0 : _target;
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: FocusableActionDetector(
        enabled: enabled,
        mouseCursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        shortcuts: kitActivateKeys,
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              _choose(!_target);
              return null;
            },
          ),
        },
        onFocusChange: (value) {
          if (value != _focused) setState(() => _focused = value);
        },
        child: Listener(
          onPointerDown: enabled ? (_) => _hold(true) : null,
          onPointerUp: (_) => _hold(false),
          onPointerCancel: (_) => _hold(false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: enabled ? () => _choose(!_target) : null,
            onHorizontalDragStart: enabled
                ? (_) => setState(
                    () => _drag = _at.value.clamp(-1.0, 1.0).toDouble(),
                  )
                : null,
            onHorizontalDragUpdate: enabled
                ? (details) {
                    final next = switchDragTo(
                      _drag ?? _at.value,
                      details.delta.dx,
                      travel,
                    );
                    _at
                      ..value = next
                      ..target = next
                      ..velocity = 0;
                    setState(() => _drag = next);
                  }
                : null,
            onHorizontalDragEnd: enabled
                ? (details) {
                    final at = _drag ?? _at.value;
                    _drag = null;
                    _choose(
                      switchRelease(
                        at: at,
                        velocity: details.primaryVelocity ?? 0,
                      ),
                    );
                  }
                : null,
            onHorizontalDragCancel: () {
              if (_drag == null) return;
              setState(() => _drag = null);
              _head();
            },
            child: DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(style.pill(26)),
                border: Border.all(
                  color: style.accent(theme).withValues(alpha: _ring ? 1 : 0),
                  width: 2,
                  strokeAlign: BorderSide.strokeAlignOutside,
                ),
              ),
              child: SizedBox(
                width: _width,
                height: 26,
                child: LiquidFill(
                  level: drag != null ? (drag + 1) / 2 : (_target ? 1 : 0),
                  sideways: true,
                  color: style.accent(theme),
                  base: theme.colors.textPrimary.withValues(alpha: 0.18),
                  radius: BorderRadius.circular(style.pill(26)),
                  child: Container(
                    foregroundDecoration: BoxDecoration(
                      border: style.controlLine(theme),
                    ),
                    padding: const EdgeInsets.all(_pad),
                    child: AnimatedBuilder(
                      animation: _springs,
                      builder: (context, _) => Align(
                        alignment: Alignment(_at.value, 0),
                        child: Container(
                          width: knob + _swell * math.max(0, _held.value),
                          height: 22,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(style.pill(22)),
                            color: !inked
                                ? const Color(0xffffffff)
                                : on
                                ? style.onAccent(theme)
                                : theme.colors.textPrimary.withValues(
                                    alpha: 0.82,
                                  ),
                            boxShadow: inked
                                ? null
                                : style.cast(const <BoxShadow>[
                                    BoxShadow(
                                      color: Color(0x33000000),
                                      blurRadius: 4,
                                      offset: Offset(0, 1),
                                    ),
                                  ]),
                          ),
                        ),
                      ),
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
}

/// The round icon plate: a solid colour while on, a quiet grey while off.
class MacDisc extends StatelessWidget {
  const MacDisc({
    required this.icon,
    required this.on,
    this.size = 28,
    this.colour = macBlue,
    this.meaning = false,
    this.child,
    super.key,
  });

  final IconData icon;
  final bool on;
  final double size;
  final Color colour;

  /// Whether [colour] says something (a warning, a recording) and so stays
  /// where the look would otherwise pour its one accent.
  final bool meaning;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final style = KitStyle.of(context);
    final dark = theme.brightness == Brightness.dark;
    final arch = style.archetype;
    // macOS 26 Tahoe active round discs use a crisp white disc with the
    // control's own vibrant colour for the glyph (with subtle elevation in
    // light mode so the disc separates cleanly from frosted light glass).
    final macWhiteDisc =
        on && style.id == 'mac' && style.panelStyle == KitPanelStyle.floating;
    final fillColor = macWhiteDisc
        ? const Color(0xffffffff)
        : style.plate(theme, colour, meaning: meaning);
    final glyphColor = !on
        ? theme.colors.textPrimary
        : macWhiteDisc
        ? colour
        : style.onPlate(theme, meaning: meaning);
    final BorderRadius shape = switch (arch) {
      KitShellArchetype.omarchy => BorderRadius.zero,
      KitShellArchetype.windows ||
      KitShellArchetype.cosmic ||
      KitShellArchetype.plasma ||
      KitShellArchetype.hyprpanel => BorderRadius.circular(style.corner(6)),
      _ => style.disc(size),
    };
    return Container(
      width: size,
      height: size,
      decoration: macWhiteDisc && !dark
          ? BoxDecoration(
              borderRadius: shape,
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x1f000000),
                  blurRadius: 6,
                  offset: Offset(0, 1.5),
                ),
              ],
            )
          : null,
      foregroundDecoration: BoxDecoration(
        borderRadius: shape,
        border: style.controlLine(theme),
      ),
      child: LiquidFill(
        level: on ? 1 : 0,
        color: fillColor,
        base: theme.colors.textPrimary.withValues(alpha: dark ? 0.14 : 0.09),
        radius: shape,
        child: Center(
          child:
              child ??
              MacGlyph(icon, size: size * 0.5, color: glyphColor),
        ),
      ),
    );
  }
}

class MacDivider extends StatelessWidget {
  const MacDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: SizedBox(
        height: 1,
        child: ColoredBox(color: context.shellTheme.colors.hairline),
      ),
    );
  }
}

class MacSection extends StatelessWidget {
  const MacSection(this.title, {this.trailing, super.key});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 4),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              title,
              style: BarType.section.copyWith(
                color: context.shellTheme.colors.textSecondary,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// The popover's title line with an optional switch at its end.
class MacHeader extends StatelessWidget {
  const MacHeader({required this.title, this.trailing, this.onBack, super.key});

  final String title;
  final Widget? trailing;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 2, 6, 2),
      child: SizedBox(
        height: 30,
        child: Row(
          children: <Widget>[
            if (onBack != null)
              Pressable(
                onTap: onBack,
                scale: Pressable.small,
                wash: true,
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: BarGlyph(
                    BarIcons.chevronLeft,
                    size: 14,
                    color: theme.colors.textPrimary,
                  ),
                ),
              ),
            Expanded(
              child: Text(
                title,
                style: BarType.title.copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: theme.colors.textPrimary,
                ),
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

/// One list row: an optional disc, a title, optional detail and trailing.
class MacRow extends StatelessWidget {
  const MacRow({
    required this.title,
    this.leading,
    this.detail,
    this.trailing,
    this.onTap,
    this.height = 38,
    super.key,
  });

  final Widget? leading;
  final String title;
  final String? detail;
  final Widget? trailing;
  final VoidCallback? onTap;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    return Pressable(
      onTap: onTap,
      scale: 0.985,
      child: const SizedBox.shrink(),
      builder: (context, hovered, pressed) => AnimatedContainer(
        duration: KitMotion.duration(context, KitMotion.wash),
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: theme.colors.textPrimary.withValues(
            alpha: onTap == null
                ? 0
                : pressed
                ? 0.14
                : hovered
                ? 0.08
                : 0,
          ),
          borderRadius: BorderRadius.circular(KitStyle.of(context).corner(9)),
        ),
        child: Row(
          children: <Widget>[
            if (leading != null) ...<Widget>[
              leading!,
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: BarType.menuRow.copyWith(
                      color: theme.colors.textPrimary,
                    ),
                  ),
                  if (detail != null && detail!.isNotEmpty)
                    Text(
                      detail!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: BarType.caption.copyWith(
                        color: theme.colors.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

/// A thin track with an accent fill and a white pill for a knob.
///
/// Under a finger the fill deepens and the knob grows a little into a clear
/// lens: the track shows through it, magnified, inside a bright rim. Letting
/// go springs it back. The knob is under the pointer from the first frame of
/// a press; a value changed from outside eases over instead of jumping; a
/// wheel and the arrow keys step it. The ends are hard, with no rubber band.
class MacSlider extends StatefulWidget {
  const MacSlider({
    required this.value,
    required this.onChanged,
    this.onChangeStart,
    this.onChangeEnd,
    this.leading,
    this.trailing,
    this.trailingWidget,
    this.height = 18,
    this.inList = false,
    this.enabled = true,
    super.key,
  });

  final double value;

  /// Whether there is a level to show and change. A slider without one is
  /// dimmed and takes no input: a source that has not reported yet, or a
  /// screen with no backlight to set.
  final bool enabled;
  final ValueChanged<double> onChanged;
  final VoidCallback? onChangeStart;
  final ValueChanged<double>? onChangeEnd;
  final IconData? leading;
  final IconData? trailing;

  /// Optional interactive widget placed at the trailing end (e.g. audio output
  /// picker disc on macOS 26 Sound slider).
  final Widget? trailingWidget;

  /// Height of the resting knob.
  final double height;

  /// Inside a list that scrolls: the slider then waits to see which way a
  /// drag goes before taking it, and leaves the wheel to the list.
  final bool inList;

  @override
  State<MacSlider> createState() => _MacSliderState();
}

class _MacSliderState extends State<MacSlider>
    with SingleTickerProviderStateMixin {
  /// A value arriving from outside: no overshoot, there in a quarter second.
  static const KitSpringTuning _follow = KitSpringTuning(420, 1);

  /// How long a value just set stands in for the one the system reports.
  static const Duration _echoWait = Duration(milliseconds: 400);

  /// How long after the last wheel notch or key the change counts as done.
  static const Duration _stepWait = Duration(milliseconds: 300);

  late final KitSpring _shown = KitSpring(
    widget.value.clamp(0.0, 1.0).toDouble(),
    _follow,
  );
  late final KitSpring _held = KitSpring(0, kitStyle.value.pressTuning);
  late final KitSprings _springs = KitSprings(this, <KitSpring>[_shown, _held]);

  /// Repaints after a value is put under the finger directly, when no
  /// spring is running to do it.
  final ValueNotifier<int> _poke = ValueNotifier<int>(0);

  /// The value under the finger.
  double? _pending;

  /// The value being stepped by the wheel or the keys.
  double? _stepping;
  Timer? _stepEnd;

  /// The value just let go of, shown until the system reports it back, so
  /// the knob does not twitch towards a stale reading.
  double? _echo;
  Timer? _echoEnd;

  bool _dragging = false;
  bool _focused = false;
  double _width = 0;

  bool get _ring => _focused && keyboardInput.value;

  void _inputChanged() {
    if (_focused) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    watchKitInput();
    keyboardInput.addListener(_inputChanged);
  }

  double get _knob => widget.height * 1.5;

  void _kick() => _springs.kick(reduceMotion: KitMotion.reduced(context));

  void _followTo(double value) {
    final next = value.clamp(0.0, 1.0).toDouble();
    if (_shown.target == next) return;
    _shown.target = next;
    _kick();
  }

  void _put(double value) {
    _shown
      ..value = value
      ..target = value
      ..velocity = 0;
    _poke.value++;
  }

  void _expectEcho(double value) {
    _echo = value;
    _echoEnd?.cancel();
    _echoEnd = Timer(_echoWait, () {
      _echo = null;
      if (mounted) _followTo(widget.value);
    });
  }

  void _grab(double dx) {
    final next = sliderValueAt(dx, _width, _knob);
    if (_pending == null) {
      _finishSteps();
      _echoEnd?.cancel();
      _echo = null;
      widget.onChangeStart?.call();
      _held.target = 1;
      _kick();
    }
    _pending = next;
    _put(next);
    widget.onChanged(next);
  }

  void _release() {
    final value = _pending;
    if (value == null) return;
    _pending = null;
    _expectEcho(value);
    _held.target = 0;
    _kick();
    widget.onChangeEnd?.call(value);
  }

  void _step(double delta) {
    if (_pending != null || delta == 0) return;
    final from = _stepping ?? _echo ?? widget.value;
    final next = sliderNudge(from, delta);
    if (_stepping == null) {
      _echoEnd?.cancel();
      _echo = null;
      widget.onChangeStart?.call();
    }
    _stepping = next;
    _followTo(next);
    widget.onChanged(next);
    _stepEnd?.cancel();
    _stepEnd = Timer(_stepWait, _finishSteps);
  }

  void _finishSteps() {
    final value = _stepping;
    _stepEnd?.cancel();
    if (value == null) return;
    _stepping = null;
    if (mounted) _expectEcho(value);
    widget.onChangeEnd?.call(value);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft) {
      _step(-sliderKeyStep);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _step(sliderKeyStep);
    } else if (key == LogicalKeyboardKey.home) {
      _step(-1);
    } else if (key == LogicalKeyboardKey.end) {
      _step(1);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  void _onSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (event) {
      final scroll = (event as PointerScrollEvent).scrollDelta;
      _step(sliderWheelDelta(scroll.dx, scroll.dy));
    });
  }

  @override
  void didUpdateWidget(MacSlider old) {
    super.didUpdateWidget(old);
    if (_pending != null || _stepping != null) return;
    final echo = _echo;
    if (echo != null) {
      if ((widget.value - echo).abs() > 0.015) return;
      _echo = null;
      _echoEnd?.cancel();
    }
    _followTo(widget.value);
  }

  @override
  void dispose() {
    keyboardInput.removeListener(_inputChanged);
    _echoEnd?.cancel();
    _stepEnd?.cancel();
    // A change the wheel left open is closed, once the tree has settled.
    final open = _stepping ?? _pending;
    final end = widget.onChangeEnd;
    if (open != null && end != null) scheduleMicrotask(() => end(open));
    _springs.dispose();
    _poke.dispose();
    super.dispose();
  }

  Widget _surface(BuildContext context) {
    final theme = context.shellTheme;
    final style = KitStyle.of(context);
    final paint = CustomPaint(
      painter: _SliderPainter(
        repaint: Listenable.merge(<Listenable>[_springs, _poke]),
        shown: _shown,
        held: _held,
        knobHeight: widget.height,
        accent: style.accent(theme),
        ink: theme.colors.textPrimary,
        ring: _ring,
        square: style.square,
        flat: style.flat,
        shade: style.shadow,
      ),
      child: SizedBox(height: widget.height + 14, width: double.infinity),
    );
    if (widget.inList) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => _grab(d.localPosition.dx),
        onTapUp: (_) => _release(),
        onTapCancel: () {
          if (!_dragging) _release();
        },
        onHorizontalDragStart: (d) {
          _dragging = true;
          _grab(d.localPosition.dx);
        },
        onHorizontalDragUpdate: (d) => _grab(d.localPosition.dx),
        onHorizontalDragEnd: (_) {
          _dragging = false;
          _release();
        },
        onHorizontalDragCancel: () {
          _dragging = false;
          _release();
        },
        child: paint,
      );
    }
    // Taking the pointer on the way down is what puts the knob under it at
    // once: a tap waits out a deadline and a drag a slop before they answer.
    return Listener(
      onPointerSignal: _onSignal,
      child: RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: <Type, GestureRecognizerFactory>{
          _EagerSlide: GestureRecognizerFactoryWithHandlers<_EagerSlide>(
            _EagerSlide.new,
            (recognizer) {
              recognizer
                ..onDown = ((d) => _grab(d.localPosition.dx))
                ..onUpdate = ((d) => _grab(d.localPosition.dx))
                ..onEnd = ((_) => _release())
                ..onCancel = _release;
            },
          ),
        },
        child: paint,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    _held.tune(KitStyle.of(context).pressTuning);
    Widget glyph(IconData icon) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: BarGlyph(icon, size: 15, color: theme.colors.textSecondary),
    );
    final row = Row(
      children: <Widget>[
        if (widget.leading != null) glyph(widget.leading!),
        Expanded(
          child: Focus(
            canRequestFocus: widget.enabled,
            onKeyEvent: _onKey,
            onFocusChange: (focused) {
              if (focused != _focused) setState(() => _focused = focused);
            },
            child: LayoutBuilder(
              builder: (context, constraints) {
                _width = constraints.maxWidth;
                return _surface(context);
              },
            ),
          ),
        ),
        if (widget.trailingWidget != null)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: widget.trailingWidget!,
          )
        else if (widget.trailing != null)
          glyph(widget.trailing!),
      ],
    );
    return IgnorePointer(
      ignoring: !widget.enabled,
      child: AnimatedOpacity(
        opacity: widget.enabled ? 1 : 0.4,
        duration: KitMotion.duration(context, KitMotion.tap),
        child: row,
      ),
    );
  }
}

/// Wins the pointer as it lands, so a slider answers a press at once and no
/// tap deadline or drag slop stands between the finger and the knob.
class _EagerSlide extends HorizontalDragGestureRecognizer {
  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
  }
}

class _SliderPainter extends CustomPainter {
  _SliderPainter({
    required Listenable repaint,
    required this.shown,
    required this.held,
    required this.knobHeight,
    required this.accent,
    required this.ink,
    required this.ring,
    required this.square,
    required this.flat,
    required this.shade,
  }) : super(repaint: repaint);

  final KitSpring shown;
  final KitSpring held;
  final double knobHeight;
  final Color accent;
  final Color ink;
  final bool ring;

  /// The look's own: square ends, a flat block for a knob with no lens, and
  /// how much of the knob's shadow is cast.
  final bool square;
  final bool flat;
  final double shade;

  static const Color _white = Color(0xffffffff);
  static const Color _black = Color(0xff000000);

  @override
  void paint(Canvas canvas, Size size) {
    final h = knobHeight;
    // The size may ride the spring past its end; the colours may not.
    final swell = held.value;
    final glass = swell.clamp(0.0, 1.0).toDouble();
    final cy = size.height / 2;
    final track = h / 3;
    final centre = sliderCentreFor(shown.value, size.width, h * 1.5);
    final fill = Color.lerp(accent, _black, 0.24 * glass)!;
    final groove = ink.withValues(alpha: 0.16);
    final radius = Radius.circular(square ? 0 : track / 2);

    canvas.drawRRect(
      RRect.fromLTRBR(0, cy - track / 2, size.width, cy + track / 2, radius),
      Paint()..color = groove,
    );
    canvas.drawRRect(
      RRect.fromLTRBR(0, cy - track / 2, centre, cy + track / 2, radius),
      Paint()..color = fill,
    );

    final knobHeightNow = h + h / 6 * swell;
    final box = Rect.fromCenter(
      center: Offset(centre, cy),
      width: h * 1.5 + h / 3 * swell,
      height: knobHeightNow,
    );
    final knob = RRect.fromRectAndRadius(
      box,
      Radius.circular(square ? 0 : knobHeightNow / 2),
    );

    if (flat) {
      // A flat look's knob is a block of ink that takes the accent while it
      // is held: no lens, no shadow, no rim.
      canvas.drawRRect(knob, Paint()..color = Color.lerp(ink, accent, glass)!);
      if (ring) _drawRing(canvas, knob);
      return;
    }

    // The shadow falls around the knob only: under a clear lens it would
    // read as dirt on the glass.
    canvas
      ..save()
      ..clipPath(
        Path.combine(
          PathOperation.difference,
          Path()..addRect(box.inflate(24)),
          Path()..addRRect(knob),
        ),
      )
      ..drawRRect(
        knob.shift(const Offset(0, 1)),
        Paint()
          ..color = _black.withValues(alpha: (0.26 - 0.08 * glass) * shade)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 2.5 + 2.5 * glass),
      )
      ..restore();

    canvas
      ..save()
      ..clipRRect(knob);
    if (glass > 0) {
      // What the lens shows: the track beneath it, thicker than it is.
      final thick = track * (1 + 1.5 * glass);
      canvas
        ..drawRect(
          Rect.fromLTRB(centre, cy - thick / 2, box.right, cy + thick / 2),
          Paint()..color = groove,
        )
        ..drawRect(
          Rect.fromLTRB(box.left, cy - thick / 2, centre, cy + thick / 2),
          Paint()..color = fill,
        );
    }
    canvas.drawRect(
      box,
      Paint()..color = _white.withValues(alpha: 1 - 0.84 * glass),
    );
    if (glass > 0) {
      canvas.drawRect(
        Rect.fromLTRB(box.left, box.top, box.right, cy),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              _white.withValues(alpha: 0.34 * glass),
              _white.withValues(alpha: 0),
            ],
          ).createShader(box),
      );
    }
    canvas.restore();

    if (glass > 0) {
      canvas.drawRRect(
        knob.deflate(0.6),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              _white.withValues(alpha: 0.95 * glass),
              _white.withValues(alpha: 0.4 * glass),
            ],
          ).createShader(box),
      );
    }
    if (ring) _drawRing(canvas, knob);
  }

  void _drawRing(Canvas canvas, RRect knob) => canvas.drawRRect(
    knob.inflate(3),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = accent,
  );

  @override
  bool shouldRepaint(_SliderPainter old) =>
      old.knobHeight != knobHeight ||
      old.accent != accent ||
      old.ink != ink ||
      old.ring != ring ||
      old.square != square ||
      old.flat != flat ||
      old.shade != shade;
}

/// Fades and sizes between a collapsed and an expanded child.
class Reveal extends StatelessWidget {
  const Reveal({required this.open, required this.child, super.key});

  final bool open;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: AnimatedAlign(
        duration: KitMotion.duration(context, KitMotion.reveal),
        curve: KitMotion.outCubic,
        alignment: Alignment.topCenter,
        heightFactor: open ? 1 : 0,
        child: AnimatedOpacity(
          duration: KitMotion.duration(context, KitMotion.enter),
          opacity: open ? 1 : 0,
          child: child,
        ),
      ),
    );
  }
}
