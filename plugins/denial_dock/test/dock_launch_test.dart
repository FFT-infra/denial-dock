import 'package:denial_dock/src/dock_launch.dart';

void main() {
  // The hop peaks at 0.65 of an icon, matching the reference ratio.
  _expect(DockLaunch.hopLift(0, 48) == 0, 'hop start');
  _expect(
    (DockLaunch.hopLift(0.41, 48) + 48 * 0.65).abs() < 0.01,
    'hop peak ${DockLaunch.hopLift(0.41, 48)}',
  );
  _expect(DockLaunch.hopLift(0.82, 48) == 0, 'hop landed');
  _expect(DockLaunch.hopLift(1, 48) == 0, 'hop end');

  // The landing glide keeps the sign of the lift and reaches zero.
  _expect(DockLaunch.landingLift(-20, 0) == -20, 'landing start');
  _expect((DockLaunch.landingLift(-20, 0.5) + 5).abs() < 1e-9, 'landing half');
  _expect(DockLaunch.landingLift(-20, 1) == 0, 'landing end');

  // Screen offsets: up is negative. A hop must move the icon toward the top
  // of the screen, whether or not the pointer has also lifted it.
  _expect(DockLaunch.iconOffset(hoverLift: 0, launchLift: 0) == 0, 'still');
  _expect(
    DockLaunch.iconOffset(
          hoverLift: 0,
          launchLift: DockLaunch.hopLift(0.41, 48),
        ) <
        -30,
    'hop goes up',
  );
  _expect(
    DockLaunch.iconOffset(hoverLift: 12, launchLift: 0) == -12,
    'hover still goes up',
  );
  _expect(
    DockLaunch.iconOffset(
          hoverLift: 12,
          launchLift: DockLaunch.hopLift(0.41, 48),
        ) <
        -40,
    'hover and hop add up',
  );

  // Release rules: floor, readiness, timeout, failure.
  _expect(
    !DockLaunch.release(
      elapsed: const Duration(milliseconds: 300),
      windowReady: true,
      failed: false,
    ),
    'floor holds',
  );
  _expect(
    DockLaunch.release(
      elapsed: const Duration(milliseconds: 500),
      windowReady: true,
      failed: false,
    ),
    'released',
  );
  _expect(
    !DockLaunch.release(
      elapsed: const Duration(seconds: 3),
      windowReady: false,
      failed: false,
    ),
    'no window keeps hopping',
  );
  _expect(
    DockLaunch.release(
      elapsed: const Duration(seconds: 15),
      windowReady: false,
      failed: false,
    ),
    'timeout',
  );
  _expect(
    DockLaunch.release(
      elapsed: Duration.zero,
      windowReady: false,
      failed: true,
    ),
    'failure',
  );

  // Phase and landing advance with elapsed time, not frames.
  _expect(
    (DockLaunch.advancePhase(0.9, 0.24) - 0.4).abs() < 1e-9,
    'phase wraps',
  );
  _expect(DockLaunch.advancePhase(0.1, 0) == 0.1, 'phase still');
  _expect(
    (DockLaunch.advanceLanding(0, 0.065) - 0.5).abs() < 1e-9,
    'landing half',
  );
  _expect(DockLaunch.advanceLanding(0.9, 1) == 1, 'landing clamps');
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
