import 'dart:math' as math;

import 'dock_math.dart';

/// Launch feedback: a ballistic hop that repeats while the application starts,
/// then a short glide back to the row once a window exists.
///
/// Kept free of Flutter so the timing rules can be tested without a shell. The
/// constants follow NextKDE's dock: 0.65 of an icon of height, a 0.48 s hop, a
/// 0.13 s landing, and a 500 ms floor so a fast application still shows its
/// first frames of feedback.
abstract final class DockLaunch {
  static const double bounceSeconds = 0.48;
  static const double landingSeconds = 0.13;
  static const double heightRatio = 0.65;
  static const int minimumFeedbackMs = 500;
  static const int timeoutMs = 15000;

  /// Upward offset for [phase] in 0..1 of the hop, in logical pixels.
  static double hopLift(double phase, double iconSize) =>
      -iconSize * heightRatio * DockMath.launchBounce(phase);

  /// The glide starts from the lift at the moment the window appeared and
  /// decays quadratically, so the icon lands instead of dropping.
  static double landingLift(double startLift, double progress) {
    final remaining = 1.0 - progress.clamp(0.0, 1.0);
    return startLift * remaining * remaining;
  }

  /// Whether the hop should stop: a window is ready and the floor has passed,
  /// or the timeout ran out. A launch that fails stops immediately.
  static bool release({
    required Duration elapsed,
    required bool windowReady,
    required bool failed,
  }) {
    if (failed) return true;
    final ms = elapsed.inMilliseconds;
    if (ms >= timeoutMs) return true;
    return windowReady && ms >= minimumFeedbackMs;
  }

  static double advancePhase(double phase, double deltaSeconds) {
    if (!deltaSeconds.isFinite || deltaSeconds <= 0) return phase;
    return (phase + deltaSeconds / bounceSeconds) % 1.0;
  }

  static double advanceLanding(double progress, double deltaSeconds) {
    if (!deltaSeconds.isFinite || deltaSeconds <= 0) return progress;
    return math.min(1.0, progress + deltaSeconds / landingSeconds);
  }
}
