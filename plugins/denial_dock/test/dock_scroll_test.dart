import 'package:denial_dock/src/dock_scroll.dart';

void main() {
  // One notched wheel click is exactly one step.
  final gate = DockScrollGate();
  _expect(gate.feed(120, 0) == 1, 'first notch');
  _expect(gate.feed(120, 100) == null, 'dead time holds');
  _expect(gate.feed(120, 300) == 1, 'resumes after dead time');

  // Direction follows the sign of the delta.
  _expect(gate.feed(-120, 700) == -1, 'upwards notch');

  // Deltas inside the dead time are dropped, not banked: a wheel that keeps
  // spinning must not release a burst the moment the window closes.
  final spinning = DockScrollGate();
  _expect(spinning.feed(120, 0) == 1, 'spin first');
  spinning.feed(120, 10);
  spinning.feed(120, 20);
  spinning.feed(120, 30);
  _expect(spinning.feed(120, 250) == 1, 'spin needs a fresh notch');

  // A high-resolution wheel splits one notch into several events; the
  // accumulator turns them into a single step.
  final fine = DockScrollGate();
  _expect(fine.feed(40, 0) == null, 'below threshold');
  _expect(fine.feed(40, 10) == null, 'still below threshold');
  _expect(fine.feed(40, 20) == null, 'touchpad threshold is higher');
  _expect(fine.feed(40, 30) == null, 'still accumulating');
  _expect(fine.feed(40, 40) == null, 'still accumulating 2');
  _expect(fine.feed(40, 50) == null, 'still accumulating 3');
  _expect(fine.feed(40, 60) == null, 'still accumulating 4');
  _expect(fine.feed(40, 70) == null, 'still accumulating 5');
  _expect(fine.feed(40, 80) == null, 'still accumulating 6');
  _expect(fine.feed(40, 90) == null, 'still accumulating 7');
  _expect(fine.feed(40, 100) == null, 'still accumulating 8');
  _expect(fine.feed(40, 110) == 1, 'touchpad reaches one step');

  // A reversal starts a fresh gesture instead of cancelling the old one.
  final reversing = DockScrollGate();
  reversing.feed(100, 0);
  _expect(reversing.feed(-100, 10) == null, 'reversal restarts');
  reversing.feed(-100, 20);
  reversing.feed(-100, 30);
  reversing.feed(-100, 40);
  _expect(reversing.feed(-100, 50) == -1, 'reversal accumulates down');

  // Nonsense deltas never move the dock.
  _expect(gate.feed(0, 1200) == null, 'zero delta');
  _expect(gate.feed(double.nan, 1200) == null, 'nan delta');
  _expect(gate.feed(double.infinity, 1200) == null, 'infinite delta');

  // Reset drops the carried delta so a new gesture starts clean.
  final carried = DockScrollGate();
  _expect(carried.feed(100, 0) == null, 'carry');
  carried.reset();
  _expect(carried.feed(100, 5000) == null, 'carry dropped');

  // Workspace stepping stops at the ends, as every reference dock does.
  _expect(nextWorkspace(count: 4, active: 2, step: 1) == 3, 'forward');
  _expect(nextWorkspace(count: 4, active: 2, step: -1) == 1, 'back');
  _expect(nextWorkspace(count: 4, active: 4, step: 1) == null, 'clamps end');
  _expect(nextWorkspace(count: 4, active: 1, step: -1) == null, 'clamps start');
  _expect(nextWorkspace(count: 0, active: 1, step: 1) == null, 'no workspaces');
  _expect(
    nextWorkspace(count: 4, active: 4, step: 1, wrap: true) == 1,
    'wraps forward',
  );
  _expect(
    nextWorkspace(count: 4, active: 1, step: -1, wrap: true) == 4,
    'wraps back',
  );
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
