import 'dart:math' as math;

import 'package:denial_shell_kit/kit_motion_pace.dart';

import 'dock_launch.dart';
import 'dock_math.dart';
import 'dock_settings.dart';

/// How the dock's own animations advance.
///
/// Everything the dock body animates by itself goes through here: the values
/// its tickers chase, its timed glides, its hops and the durations of its
/// implicit position and size animations. The shell's pace decides the speed
/// and the system's reduced-motion setting decides whether anything travels;
/// at normal speed with motion allowed every number is exactly what the dock
/// always computed. With reduced motion on, positions and sizes are at their
/// targets at once and nothing hops; what a hop was saying is said by a
/// change of opacity instead. The pace is honoured here so that the call
/// sites do not each have to ask.
///
/// Kept free of Flutter so the rules can be tested without a shell.
class DockMotion {
  const DockMotion({required this.pace});

  /// The shell's speed and the system's reduced-motion flag.
  final KitMotionPace pace;

  /// The system asks for less motion.
  bool get reduced => pace.reduced;

  /// [DockMath.advance], or [target] itself with reduced motion.
  double advance(
    double current,
    double target,
    double deltaSeconds, {
    required double responseSeconds,
  }) => reduced
      ? target
      : DockMath.advance(
          current,
          target,
          deltaSeconds * pace.speed,
          responseSeconds: responseSeconds,
        );

  /// Progress of a glide that lasts [seconds], another [deltaSeconds] later.
  /// With reduced motion the glide is over as soon as it is asked about. The
  /// result may pass one; the caller clamps it.
  double glide(double progress, double deltaSeconds, double seconds) =>
      reduced ? 1.0 : progress + deltaSeconds * pace.speed / seconds;

  /// How long an implicit animation of a position or a size runs.
  Duration duration(Duration full) => pace.duration(full);

  /// The launch feedback in effect. The hop is movement, so with reduced
  /// motion a launch shows as the pulse: it says the same and nothing travels.
  DockLaunchFeedback launchFeedback(DockLaunchFeedback chosen) =>
      reduced && chosen == DockLaunchFeedback.hop
      ? DockLaunchFeedback.pulse
      : chosen;

  /// One attention period at normal speed: a hop, then a pause.
  static const Duration attentionPeriod = Duration(milliseconds: 1200);

  /// The share of an attention period the hop takes; the rest is a pause.
  /// With [attentionPeriod] the hop lasts as long as one launch hop, so the
  /// two read as the same gesture.
  static const double attentionHopShare = 0.4;

  /// How high the attention hop goes, in icon sizes. Lower than a launch hop,
  /// which answers a click and can afford to be loud, but high enough to
  /// clear the row: at a fifth of an icon it was easy to miss.
  static const double attentionHeightRatio = 0.45;

  /// The attention signal for [phase] in 0..1 of its period, from zero to one
  /// and back: one hop at the start of each period, then a rest.
  static double attentionWave(double phase) =>
      phase > 0 && phase < attentionHopShare
      ? math.sin(phase / attentionHopShare * math.pi)
      : 0.0;

  /// How far an icon that asks for attention is off the row, in logical
  /// pixels away from the screen edge.
  double attentionLift(double phase, double iconSize) =>
      reduced ? 0.0 : attentionWave(phase) * iconSize * attentionHeightRatio;

  /// With reduced motion the icon stays on the row and dims in the rhythm it
  /// would have hopped in, down to the floor the launch pulse uses.
  double attentionOpacity(double phase) => reduced
      ? 1.0 - (1.0 - DockLaunch.pulseFloor) * attentionWave(phase)
      : 1.0;
}
