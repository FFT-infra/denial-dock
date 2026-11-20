import 'dart:math' as math;

/// Mathematical physics engine for the macOS-style Dock, implementing
/// Quintic Smootherstep wave magnification, analytic integral displacement,
/// and first-order exponential decay response.
abstract final class DockMath {
  /// Exact first-order exponential response for smooth target tracking
  /// regardless of display refresh rate (60Hz, 120Hz, 144Hz, 240Hz).
  ///
  /// [current]: Current value.
  /// [target]: Target value.
  /// [deltaSeconds]: Elapsed time since last frame in seconds.
  /// [responseSeconds]: Time constant tau (default 0.026s / 26ms).
  /// [epsilon]: Settle threshold to avoid continuous rendering.
  static double advance(
    double current,
    double target,
    double deltaSeconds, {
    double responseSeconds = 0.026,
    double epsilon = 0.0005,
  }) {
    final distance = target - current;
    if (distance.abs() <= epsilon) {
      return target;
    }
    if (!deltaSeconds.isFinite || deltaSeconds <= 0) {
      return current;
    }
    final next = target - distance * math.exp(-deltaSeconds / responseSeconds);
    return (target - next).abs() <= epsilon ? target : next;
  }

  /// Quintic smootherstep spatial influence field:
  /// f(t) = 1 - 10*t^3 + 15*t^4 - 6*t^5
  ///
  /// Guarantees that first and second derivatives are strictly zero at t=0 and t=1,
  /// avoiding sharp corners or sudden velocity spikes across icon boundaries.
  static double influenceAt(double distance, double radius) {
    final support = math.max(1.0, radius);
    final t = math.min(1.0, distance.abs() / support);
    return 1.0 - t * t * t * (10.0 + t * (-15.0 + 6.0 * t));
  }

  /// Analytic integral of (1 - 10*u^3 + 15*u^4 - 6*u^5):
  /// F(u) = u - 2.5*u^4 + 3.0*u^5 - u^6
  ///
  /// Used to compute exact horizontal displacement (dx) so neighboring icons
  /// are pushed aside gracefully without visual collision or jitter.
  static double integralAt(double u) {
    final clamped = math.max(0.0, math.min(1.0, u));
    final u4 = clamped * clamped * clamped * clamped;
    return clamped - u4 * (2.5 + clamped * (-3.0 + clamped));
  }

  /// Computes the horizontal push displacement (dx) for an icon at distance [d]
  /// from the pointer.
  static double computeDisplacement({
    required double d,
    required double density,
    required double shoulder,
    required double support,
    required double amplitude,
  }) {
    if (amplitude <= 0) return 0.0;
    final distance = d.abs();
    final u = math.min(1.0, math.max(0.0, distance - shoulder) / support);
    final integral = integralAt(u);
    final sign = d == 0 ? 0.0 : (d > 0 ? 1.0 : -1.0);
    return sign *
        density *
        (math.min(distance, shoulder) + support * integral) *
        amplitude;
  }

  /// Ballistic launch bounce curve:
  /// Simulates a natural parabolic jump followed by an elastic landing.
  /// [phase] ranges from 0.0 to 1.0.
  static double launchBounce(double phase) {
    const flight = 0.82;
    final t = math.max(0.0, math.min(1.0, phase / flight));
    return 4.0 * t * (1.0 - t);
  }

  /// Determines which icon owns the name label based on continuous
  /// midpoint cell boundaries.
  static int? resolveNameOwner({
    required List<double> iconCenters,
    required List<double> iconHalfWidths,
    required double pointerX,
  }) {
    if (!pointerX.isFinite || iconCenters.isEmpty) return null;

    final n = iconCenters.length;
    for (var i = 0; i < n; ++i) {
      final center = iconCenters[i];
      final half = iconHalfWidths[i];

      final leftBound = i > 0
          ? (iconCenters[i - 1] + center) / 2.0
          : center - half - 10.0;

      final rightBound = i < n - 1
          ? (center + iconCenters[i + 1]) / 2.0
          : center + half + 10.0;

      if (pointerX >= leftBound && pointerX <= rightBound) {
        return i;
      }
    }
    return null;
  }
}
