/// Wheel-to-step translation for the dock.
///
/// A notched wheel arrives as a whole 120 px step; a touchpad arrives as a
/// stream of small deltas that would otherwise walk several workspaces in one
/// swipe. The gate accumulates small deltas into one step, refuses to fire
/// again for [deadTimeMs], and drops anything that arrives inside that window
/// instead of banking it for later — Dash to Dock's rule.
class DockScrollGate {
  DockScrollGate({
    this.deadTimeMs = 200,
    this.stepPixels = 120,
    this.touchpadPixels = 480,
  });

  /// Silence required between two steps.
  final int deadTimeMs;

  /// One notched wheel step. Denial reports a notch as 120 logical pixels.
  final double stepPixels;

  /// A touchpad swipe is finer-grained and keeps going; it needs a longer
  /// travel before it counts as one step, as DankMaterialShell does.
  final double touchpadPixels;

  double _accumulated = 0;
  int? _lastStepMs;

  /// Returns the step direction for [deltaY] at [nowMs], or null while the
  /// delta is too small or the dead time has not elapsed. Positive means down.
  int? feed(double deltaY, int nowMs) {
    if (!deltaY.isFinite || deltaY == 0) return null;
    final last = _lastStepMs;
    if (last != null && nowMs - last < deadTimeMs) {
      // Inside the dead time the wheel is still spinning; banking this delta
      // would fire the moment the window closes.
      _accumulated = 0;
      return null;
    }
    final direction = deltaY > 0 ? 1 : -1;
    if (_accumulated != 0 && _accumulated.sign != direction) {
      // A reversal starts a fresh gesture rather than cancelling the old one.
      _accumulated = 0;
    }
    _accumulated += deltaY;
    final threshold = _isNotch(deltaY) ? stepPixels : touchpadPixels;
    if (_accumulated.abs() < threshold) return null;
    _lastStepMs = nowMs;
    _accumulated = 0;
    return direction;
  }

  /// A whole notch is a multiple of [stepPixels]; anything else came from a
  /// touchpad or a high-resolution wheel.
  bool _isNotch(double deltaY) {
    final remainder = deltaY.abs() % stepPixels;
    return remainder < 0.5 || (stepPixels - remainder) < 0.5;
  }

  /// Drops the carried delta, so a new gesture does not inherit the tail of an
  /// old one.
  void reset() {
    _accumulated = 0;
    _lastStepMs = null;
  }
}

/// Next workspace id for a wheel step. Most docks stop at the last workspace
/// instead of wrapping; [wrap] turns that around, as Noctalia and Plasma 6.6
/// offer, and it stays off by default because a touchpad overshoot at the end
/// would otherwise jump across the whole set.
int? nextWorkspace({
  required int count,
  required int active,
  required int step,
  bool wrap = false,
}) {
  if (count <= 0) return null;
  final target = active + step;
  if (target >= 1 && target <= count) return target;
  if (!wrap) return null;
  return (target - 1) % count + 1;
}
