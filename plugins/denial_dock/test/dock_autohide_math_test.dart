import 'package:denial_dock/src/dock_autohide_math.dart';
import 'package:denial_dock/src/dock_settings.dart'
    show DockHideScope, DockPosition;

void main() {
  // Which windows a smart-hiding dock reacts to.
  _expect(
    countsForHide(DockHideScope.all, active: false, maximized: false),
    'every window counts by default',
  );
  _expect(
    countsForHide(DockHideScope.active, active: true, maximized: false) &&
        !countsForHide(DockHideScope.active, active: false, maximized: true),
    'only the focused window',
  );
  _expect(
    countsForHide(DockHideScope.maximized, active: false, maximized: true) &&
        !countsForHide(DockHideScope.maximized, active: true, maximized: false),
    'only a maximized window',
  );

  // A 1280x800 output at the origin.
  const output = (left: 0.0, top: 0.0, width: 1280.0, height: 800.0);

  // The capsule sits centred on the edge the dock is attached to, inset by the
  // same margin the dock itself uses.
  final bottom = dockRect(
    output: output,
    position: DockPosition.bottom,
    extent: 400,
    thickness: 64,
    inset: 10,
  );
  _expect(bottom.left == 440, 'bottom centred: ${bottom.left}');
  _expect(bottom.top == 800 - 10 - 64, 'bottom top: ${bottom.top}');
  _expect(bottom.width == 400 && bottom.height == 64, 'bottom size');

  final flushBottom = dockRect(
    output: output,
    position: DockPosition.bottom,
    extent: 400,
    thickness: 64,
    inset: 0,
  );
  _expect(flushBottom.bottom == 800, 'zero gap reaches the screen edge');

  final left = dockRect(
    output: output,
    position: DockPosition.left,
    extent: 400,
    thickness: 64,
    inset: 10,
  );
  _expect(left.left == 10, 'left inset: ${left.left}');
  _expect(left.top == 200, 'left centred: ${left.top}');
  _expect(left.width == 64 && left.height == 400, 'left is tall and thin');

  final right = dockRect(
    output: output,
    position: DockPosition.right,
    extent: 400,
    thickness: 64,
    inset: 10,
  );
  _expect(right.right == 1280 - 10, 'right inset: ${right.right}');
  _expect(right.top == 200 && right.width == 64, 'right is tall and thin');

  // An output that does not start at the origin still centres correctly; the
  // old code used Rect.center, so a second monitor must not shift the dock.
  const second = (left: 1280.0, top: 0.0, width: 1920.0, height: 1080.0);
  final secondBottom = dockRect(
    output: second,
    position: DockPosition.bottom,
    extent: 400,
    thickness: 64,
  );
  _expect(secondBottom.left == 1280 + 760, 'second monitor centred');
  _expect(secondBottom.right == 1280 + 1160, 'second monitor inside output');
  _expect(secondBottom.bottom == 1075, 'default bottom gap is 5 pixels');

  // Overlap depth trims the edge the dock is anchored to, so a window that
  // merely touches the screen edge is not a conflict.
  final window = (left: 100.0, top: 700.0, width: 300.0, height: 100.0);
  final trimmedBottom = overlapDepth(window, position: DockPosition.bottom);
  _expect(trimmedBottom.top == 712, 'bottom trims the top edge');
  _expect(trimmedBottom.height == 88, 'bottom keeps the rest');

  final trimmedLeft = overlapDepth(window, position: DockPosition.left);
  _expect(trimmedLeft.left == 112 && trimmedLeft.width == 288, 'left trims');
  final trimmedRight = overlapDepth(window, position: DockPosition.right);
  _expect(trimmedRight.left == 100 && trimmedRight.width == 288, 'right trims');

  // A rectangle thinner than the depth collapses to one pixel instead of
  // producing a negative height.
  final thin = overlapDepth(
    (left: 0.0, top: 0.0, width: 100.0, height: 4.0),
    position: DockPosition.bottom,
    depth: 12,
  );
  _expect(thin.height == 1, 'thin rect clamps: ${thin.height}');

  // Overlap matches Rect.overlaps: edges that only touch do not count.
  const a = (left: 0.0, top: 0.0, width: 10.0, height: 10.0);
  _expect(
    a.overlaps((left: 5.0, top: 5.0, width: 10.0, height: 10.0)),
    'cross',
  );
  _expect(
    !a.overlaps((left: 10.0, top: 0.0, width: 10.0, height: 10.0)),
    'touch',
  );
  _expect(
    !a.overlaps((left: 20.0, top: 0.0, width: 10.0, height: 10.0)),
    'apart',
  );
  _expect(
    !a.overlaps((left: 0.0, top: 10.0, width: 10.0, height: 10.0)),
    'below',
  );
  _expect(
    a.overlaps((left: -5.0, top: -5.0, width: 20.0, height: 20.0)),
    'encloses',
  );
  _expect(a.isEmpty == false, 'ten by ten is not empty');
  _expect(
    (left: 0.0, top: 0.0, width: 0.0, height: 10.0).isEmpty,
    'zero width is empty',
  );

  // A window reporting pixels on a scaled output is divided down; one already
  // in logical coordinates is left alone.
  final pixels = scaledWindowBox(
    geometry: (left: 0.0, top: 0.0, width: 2560.0, height: 1600.0),
    scale: 2.0,
    outputWidth: 1280,
  );
  _expect(pixels.width == 1280 && pixels.height == 800, 'pixels halved');
  final logical = scaledWindowBox(
    geometry: (left: 0.0, top: 0.0, width: 800.0, height: 600.0),
    scale: 2.0,
    outputWidth: 1280,
  );
  _expect(logical.width == 800, 'logical untouched');
  final unknownScale = scaledWindowBox(
    geometry: (left: 0.0, top: 0.0, width: 4000.0, height: 3000.0),
    scale: double.nan,
    outputWidth: 1280,
  );
  _expect(unknownScale.width == 4000, 'non-finite scale ignored');

  // Conflict: only user windows on the same monitor and workspace count.
  const trigger = (left: 400.0, top: 720.0, width: 400.0, height: 80.0);
  const release = (left: 400.0, top: 700.0, width: 400.0, height: 100.0);
  WindowSample sample({
    int monitor = 0,
    int workspace = 1,
    bool minimized = false,
    bool userApp = true,
    Box? box = trigger,
  }) => (
    monitorId: monitor,
    workspaceId: workspace,
    minimized: minimized,
    userApp: userApp,
    box: box,
  );

  bool conflict(
    List<WindowSample> windows, {
    bool previous = false,
    bool desktop = false,
  }) => conflictAt(
    windows: windows,
    trigger: trigger,
    release: release,
    previousConflict: previous,
    monitorId: 0,
    workspaceId: 1,
    desktopVisible: desktop,
  );

  _expect(conflict([sample()]), 'a window over the dock conflicts');
  _expect(!conflict([]), 'no windows');
  _expect(!conflict([sample(monitor: 1)]), 'other monitor');
  _expect(!conflict([sample(workspace: 2)]), 'other workspace');
  _expect(!conflict([sample(minimized: true)]), 'minimized window');
  _expect(!conflict([sample(userApp: false)]), 'system window');
  _expect(!conflict([sample(box: null)]), 'window without geometry');
  _expect(
    !conflict([sample(box: (left: 0, top: 0, width: 0, height: 0))]),
    'empty geometry',
  );
  _expect(!conflict([sample()], desktop: true), 'desktop shown');

  // Hysteresis: a window in the band between the two rectangles holds the
  // current state instead of flipping it.
  const band = (left: 400.0, top: 700.0, width: 400.0, height: 15.0);
  final inBand = [sample(box: band)];
  _expect(!conflict(inBand), 'band does not start a conflict');
  _expect(conflict(inBand, previous: true), 'band does not end one either');
  _expect(
    !conflict([
      sample(box: (left: 400.0, top: 800.0, width: 400.0, height: 10.0)),
    ]),
    'window below the trigger is clear',
  );

  // One covering window is enough, whatever the order of the rest.
  _expect(
    conflict([sample(monitor: 3), sample(minimized: true), sample()]),
    'any covering window conflicts',
  );
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
