import 'package:flutter/widgets.dart';

import 'kit_motion_pace.dart';
import 'kit_style.dart';

export 'kit_motion_pace.dart';

/// The shell's motion language: the curves and durations the bar and the dock
/// share, and the pace that turns them into what the user actually sees.
///
/// Every name here is the value at normal speed with reduced motion off;
/// [duration] applies the user's speed, and reduced motion zeroes a
/// transition. A loop keeps its length under reduced motion, because a still
/// frame is not the same as a zero-length repeat; [loop] is for those.
abstract final class KitMotion {
  // ── Curves ───────────────────────────────────────────────────────────────
  /// The default for something that moves: quick away, soft into place.
  static const Curve out = Curves.easeOut;
  static const Curve outCubic = Curves.easeOutCubic;

  /// A surface leaving, mirroring [outCubic].
  static const Curve inCubic = Curves.easeInCubic;

  /// A control growing under the pointer, a little past its size.
  static const Curve outBack = Curves.easeOutBack;

  /// A loop that reverses, symmetric at both ends.
  static const Curve inOut = Curves.easeInOut;

  /// The bar's own settle: about 4% past the target, then home.
  static const Cubic spring = Cubic(0.18, 1.04, 0.22, 1.0);

  // ── Durations ────────────────────────────────────────────────────────────
  // Each value is a literal the bar already drew, so at normal speed nothing
  // changes. The names say what the time is for; where one value served more
  // than one role they share the token, and values that differ only slightly
  // stay separate rather than being merged.

  /// A menu appearing under its title.
  static const Duration menuOpen = Duration(milliseconds: 60);

  /// A press's answer: a control easing under a finger, a menu's rows fading
  /// in, a panel opening under a title.
  static const Duration tap = Duration(milliseconds: 90);

  /// A pointer's wash crossing a list row.
  static const Duration wash = Duration(milliseconds: 110);

  /// A small plate settling: a sidebar item, a dialog button.
  static const Duration fade = Duration(milliseconds: 120);

  /// A tooltip, a slider's knob, a panel leaving a menu, a level bar.
  static const Duration ease = Duration(milliseconds: 140);

  /// A menu leaving.
  static const Duration menuExit = Duration(milliseconds: 150);

  /// A control's fill or opacity after a change.
  static const Duration fill = Duration(milliseconds: 160);

  /// A whole layer leaving.
  static const Duration layerExit = Duration(milliseconds: 170);

  /// A face turning over: a settings page, a segment filling.
  static const Duration turn = Duration(milliseconds: 180);

  /// A panel entering, and a larger plate settling.
  static const Duration enter = Duration(milliseconds: 200);

  /// One face replacing another in the island, a workspace number.
  static const Duration swap = Duration(milliseconds: 220);

  /// A window entering, a chevron turning, a dragged row sliding home.
  static const Duration enterLarge = Duration(milliseconds: 240);

  /// The tile grid's drag wobble, repeated.
  static const Duration wobble = Duration(milliseconds: 260);

  /// A ring filling to a new level, a reveal opening.
  static const Duration reveal = Duration(milliseconds: 300);

  /// Content moving into place, a layer entering.
  static const Duration travel = Duration(milliseconds: 320);

  /// The bar sliding away when it auto-hides.
  static const Duration slide = Duration(milliseconds: 340);

  /// A card settling to a new size.
  static const Duration settle = Duration(milliseconds: 360);

  /// A group or a dot growing: a notice stack, an active workspace.
  static const Duration unfold = Duration(milliseconds: 380);

  /// A card springing back, a width returning.
  static const Duration rebound = Duration(milliseconds: 420);

  /// A widget's ring filling slowly.
  static const Duration fillSlow = Duration(milliseconds: 500);

  /// A live dot breathing.
  static const Duration pulse = Duration(milliseconds: 900);

  /// One cycle of the equaliser.
  static const Duration wave = Duration(milliseconds: 2400);

  /// The one read of the system's reduced-motion flag in the shell. The
  /// platform value is the fallback for a context with no [MediaQuery], such
  /// as a state before its first build.
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ??
      WidgetsBinding
          .instance
          .platformDispatcher
          .accessibilityFeatures
          .disableAnimations;

  /// The speed multiplier in force, without the context needed to read the
  /// reduced-motion flag.
  static double get speed => kitSpeed.value;

  /// The pace in force. It reads the speed setting, so callers in a build
  /// method see a change as soon as the setting marks the tree for rebuild.
  static KitMotionPace pace(BuildContext context) =>
      KitMotionPace(speed: kitSpeed.value, reduced: reduced(context));

  /// The pace where a context is not available: a controller created in
  /// initState, or the spring ticker, which runs outside any build.
  static KitMotionPace get now => KitMotionPace(
    speed: kitSpeed.value,
    reduced: WidgetsBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations,
  );

  /// The pace of a transition that plays once: the user's speed times the
  /// look's own, so a brisk look shortens every such transition. Loops and
  /// springs keep to [pace].
  static KitMotionPace timed(BuildContext context) => KitMotionPace(
    speed: kitSpeed.value * kitStyle.value.pace,
    reduced: reduced(context),
  );

  /// [nominal] with the user's speed and the look's pace applied; zero under
  /// reduced motion.
  static Duration duration(BuildContext context, Duration nominal) =>
      timed(context).duration(nominal);

  /// [nominal] with only the speed applied: for a repeating animation, and
  /// for an AnimatedSize, which re-dirties itself during layout when its
  /// duration is zero and so keeps its length under reduced motion, as before.
  static Duration loop(BuildContext context, Duration nominal) =>
      pace(context).scaled(nominal);
}
