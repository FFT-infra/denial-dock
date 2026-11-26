import 'dart:async';

import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'kit_feedback.dart';
import 'kit_motion.dart';
import 'kit_springs.dart';
import 'kit_style.dart';

export 'kit_feedback.dart';

/// Whether the last pointer seen was a finger. A hover hint has to be drawn
/// all the time for a finger, which never hovers.
final ValueNotifier<bool> touchInput = ValueNotifier<bool>(false);

/// Whether the last input was a key rather than a pointer: the only time a
/// focus ring shows, and the only time focus follows into a detail page.
/// The framework's own highlight mode cannot say, since a mouse counts as
/// "traditional" there just as a keyboard does.
final ValueNotifier<bool> keyboardInput = ValueNotifier<bool>(false);

bool _inputWatched = false;

/// Starts telling fingers from pointers and keys from both. Safe to call
/// from every control; only the first call does anything.
void watchKitInput() {
  if (_inputWatched) return;
  _inputWatched = true;
  GestureBinding.instance.pointerRouter.addGlobalRoute((event) {
    if (event is PointerDownEvent) keyboardInput.value = false;
    if (event is! PointerDownEvent && event is! PointerHoverEvent) return;
    touchInput.value =
        event.kind == PointerDeviceKind.touch ||
        event.kind == PointerDeviceKind.stylus;
  });
  HardwareKeyboard.instance.addHandler((event) {
    if (event is KeyDownEvent) keyboardInput.value = true;
    return false;
  });
}

/// The keys that press whatever holds the focus.
const Map<ShortcutActivator, Intent> kitActivateKeys =
    <ShortcutActivator, Intent>{
      SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
      SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
      SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
    };

/// Answers a press: its child shrinks a little on the look's spring, and
/// with [wash] dims or lifts a shade as well. It is a keyboard stop too:
/// Enter or Space taps it, and it draws a ring while keys hold the focus.
class Pressable extends StatefulWidget {
  const Pressable({
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.96,
    this.builder,
    this.wash = false,
    this.shape,
    this.onHighlight,
    this.disabled = false,
    this.onSecondaryTap,
    super.key,
  });

  /// The two sizes of press a panel uses: a whole tile or a row of one
  /// gives a little, a small round control gives more.
  static const double large = 0.97;
  static const double small = 0.88;

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;

  /// Rebuilds the child with the hover and pressed state when given.
  final Widget Function(BuildContext context, bool hovered, bool pressed)?
  builder;

  /// Lays a shade of the ink over the child while hovered and pressed.
  final bool wash;

  /// The outline the wash and the focus ring follow; a row's corners in the
  /// look in force unless given.
  final BorderRadius? shape;

  /// Reports the hover and pressed state to a parent that draws them.
  final void Function(bool hovered, bool pressed)? onHighlight;

  /// Shows the control as unavailable: dimmed, with no answer to a pointer
  /// or a key. A control that merely has nothing to do passes no callbacks
  /// instead, and keeps its full ink.
  final bool disabled;

  final VoidCallback? onSecondaryTap;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;
  Timer? _release;
  final Stopwatch _down = Stopwatch();

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

  @override
  void dispose() {
    keyboardInput.removeListener(_inputChanged);
    _release?.cancel();
    super.dispose();
  }

  void _set({bool? hovered, bool? pressed}) {
    final h = hovered ?? _hovered;
    final p = pressed ?? _pressed;
    if (h == _hovered && p == _pressed) return;
    setState(() {
      _hovered = h;
      _pressed = p;
    });
    widget.onHighlight?.call(h, p);
  }

  void _press() {
    _release?.cancel();
    _down
      ..reset()
      ..start();
    _set(pressed: true);
  }

  /// A quick tap is over before the spring has moved, so the pressed state
  /// is held for the length of a press's answer.
  void _lift() {
    final hold = KitMotion.duration(context, KitMotion.tap) - _down.elapsed;
    _release?.cancel();
    if (hold <= Duration.zero) {
      _set(pressed: false);
    } else {
      _release = Timer(hold, () {
        if (mounted) _set(pressed: false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled =
        !widget.disabled &&
        (widget.onTap != null ||
            widget.onLongPress != null ||
            widget.onSecondaryTap != null);
    final theme = context.shellTheme;
    final style = KitStyle.of(context);
    final shade = widget.wash
        ? KitFeedback.wash(
            hovered: _hovered,
            pressed: _pressed,
            enabled: enabled,
          )
        : 0.0;
    // A flat look has no gloss to answer with, so the washed control draws
    // a line as well; the ring of a keyboard focus wins over it.
    final line = widget.wash
        ? KitFeedback.line(
            hovered: _hovered,
            pressed: _pressed,
            enabled: enabled,
            flat: style.flat,
          )
        : 0.0;
    // Always in the tree, so a ring coming or going never rebuilds the child
    // under a new parent.
    final body = AnimatedContainer(
      duration: KitMotion.duration(
        context,
        _pressed ? KitMotion.wash : KitMotion.enter,
      ),
      foregroundDecoration: BoxDecoration(
        color: theme.colors.textPrimary.withValues(alpha: shade),
        borderRadius: widget.shape ?? BorderRadius.circular(style.corner(9)),
        border: Border.all(
          color: _ring
              ? theme.kitAccent
              : theme.colors.textPrimary.withValues(alpha: line),
          width: _ring ? KitFeedback.ringWidth : 1,
          strokeAlign: _ring
              ? BorderSide.strokeAlignOutside
              : BorderSide.strokeAlignInside,
        ),
      ),
      child: widget.builder?.call(context, _hovered, _pressed) ?? widget.child,
    );
    final shown = widget.disabled
        ? Opacity(opacity: KitFeedback.disabledOpacity, child: body)
        : body;
    return FocusableActionDetector(
      enabled: enabled,
      mouseCursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      shortcuts: kitActivateKeys,
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            if (enabled) widget.onTap?.call();
            return null;
          },
        ),
      },
      onShowHoverHighlight: (value) => _set(hovered: value),
      onFocusChange: (value) {
        if (value != _focused) setState(() => _focused = value);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => _press() : null,
        onTapUp: (_) => _lift(),
        onTapCancel: () {
          _release?.cancel();
          _set(pressed: false);
        },
        onTap: enabled ? widget.onTap : null,
        onLongPress: enabled ? widget.onLongPress : null,
        onSecondaryTap: enabled ? widget.onSecondaryTap : null,
        child: Sprung(
          target: _pressed && enabled ? widget.scale : 1,
          tuning: style.pressTuning,
          builder: (context, value, child) =>
              Transform.scale(scale: value, child: child),
          child: shown,
        ),
      ),
    );
  }
}

/// A keyboard stop for a control that handles its own pointer, such as a
/// slider or a row of segments: the arrow keys step it, Enter or Space
/// presses it, and it draws the same ring a [Pressable] does while keys
/// hold the focus.
class KitKeyStop extends StatefulWidget {
  const KitKeyStop({
    required this.child,
    this.onStep,
    this.onActivate,
    this.shape,
    this.enabled = true,
    super.key,
  });

  final Widget child;

  /// Left and down step by -1, right and up by 1.
  final ValueChanged<int>? onStep;
  final VoidCallback? onActivate;

  /// The outline the ring follows; a row's corners in the look in force
  /// unless given.
  final BorderRadius? shape;
  final bool enabled;

  @override
  State<KitKeyStop> createState() => _KitKeyStopState();
}

class _KitKeyStopState extends State<KitKeyStop> {
  bool _focused = false;

  void _inputChanged() {
    if (_focused) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    watchKitInput();
    keyboardInput.addListener(_inputChanged);
  }

  @override
  void dispose() {
    keyboardInput.removeListener(_inputChanged);
    super.dispose();
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final step = widget.onStep;
    if (step != null) {
      if (key == LogicalKeyboardKey.arrowLeft ||
          key == LogicalKeyboardKey.arrowDown) {
        step(-1);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowRight ||
          key == LogicalKeyboardKey.arrowUp) {
        step(1);
        return KeyEventResult.handled;
      }
    }
    final activate = widget.onActivate;
    if (activate != null &&
        event is KeyDownEvent &&
        (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter ||
            key == LogicalKeyboardKey.space)) {
      activate();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final ring = _focused && keyboardInput.value;
    return Focus(
      canRequestFocus: widget.enabled,
      skipTraversal: !widget.enabled,
      onKeyEvent: _key,
      onFocusChange: (value) {
        if (value != _focused) setState(() => _focused = value);
      },
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius:
              widget.shape ??
              BorderRadius.circular(KitStyle.of(context).corner(9)),
          border: Border.all(
            color: context.shellTheme.kitAccent.withValues(alpha: ring ? 1 : 0),
            width: KitFeedback.ringWidth,
            strokeAlign: BorderSide.strokeAlignOutside,
          ),
        ),
        child: widget.child,
      ),
    );
  }
}
