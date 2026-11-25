/// The arithmetic behind the kit's hand-driven controls: where a slider's
/// value sits under a pointer, how a switch decides which way to fall, and
/// how one progress value is cut into overlapping phases.
///
/// No Flutter import, so it runs as an ordinary Dart test.
library;

/// What one notch of a wheel moves a slider by.
const double sliderWheelStep = 0.05;

/// What one arrow key press moves a slider by.
const double sliderKeyStep = 1 / 16;

/// The value under a pointer at [dx] on a slider [width] wide whose knob is
/// [knob] wide. The knob's centre is the value, so the first and last half
/// knob of the track are already the ends.
double sliderValueAt(double dx, double width, double knob) {
  final run = width - knob;
  if (run <= 0) return 0;
  return ((dx - knob / 2) / run).clamp(0.0, 1.0).toDouble();
}

/// The knob's centre for [value], the inverse of [sliderValueAt].
double sliderCentreFor(double value, double width, double knob) =>
    knob / 2 + value.clamp(0.0, 1.0) * (width - knob);

/// [value] moved by [step] and held inside the track. There is no rubber
/// band: the ends are hard.
double sliderNudge(double value, double step) =>
    (value + step).clamp(0.0, 1.0).toDouble();

/// A switch knob's place, -1 off to 1 on, after a drag of [dx] across a
/// track whose knob can travel [travel].
double switchDragTo(double from, double dx, double travel) {
  if (travel <= 0) return from;
  return (from + dx / travel * 2).clamp(-1.0, 1.0).toDouble();
}

/// Which way a released switch falls: a flick faster than [fling] decides by
/// its direction, anything slower by the half the knob was let go in.
bool switchRelease({
  required double at,
  required double velocity,
  double fling = 200,
}) => velocity.abs() > fling ? velocity > 0 : at > 0;

/// The share of the stretch [from]..[to] that [progress] has covered, held
/// to 0..1. One spring can then drive several things that start and end at
/// different points of its travel, and an overshoot never leaves the range.
double kitPhase(double progress, double from, double to) {
  if (to <= from) return progress >= to ? 1 : 0;
  return ((progress - from) / (to - from)).clamp(0.0, 1.0).toDouble();
}

/// When a staggered item starts, as a share of the whole entrance: later
/// rows wait longer, columns a little, and nothing waits past [cap], so a
/// tall grid does not trail in.
double staggerDelay(int row, int col, {double cap = 0.36}) {
  final delay = row * 0.085 + col * 0.025;
  return delay > cap ? cap : delay;
}

/// What a scroll of ([dx], [dy]) pixels moves a slider by. Up and right
/// raise it. A wheel notch is worth [sliderWheelStep]; a touchpad's stream
/// of small deltas adds up to about the same over the same distance.
double sliderWheelDelta(double dx, double dy) {
  final along = dx.abs() > dy.abs() ? dx : -dy;
  if (along == 0) return 0;
  final share = (along.abs() / 50).clamp(0.1, 1.0);
  return (along > 0 ? 1 : -1) * sliderWheelStep * share;
}

/// What Escape or a press outside does to a panel with levels. A detail page
/// goes back first, an edit ends next, and only a panel at rest closes.
enum PanelBackStep { leaveDetail, endEditing, close }

PanelBackStep panelBackStep({required bool detail, required bool editing}) =>
    detail
    ? PanelBackStep.leaveDetail
    : editing
    ? PanelBackStep.endEditing
    : PanelBackStep.close;

/// The share of a track that has played, 0 when its length is unknown.
double mediaProgress(int positionMicros, int lengthMicros) {
  if (lengthMicros <= 0) return 0;
  return (positionMicros / lengthMicros).clamp(0.0, 1.0).toDouble();
}
