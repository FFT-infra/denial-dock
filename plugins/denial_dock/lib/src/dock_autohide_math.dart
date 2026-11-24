import 'dock_settings.dart' show DockHideScope, DockPosition;

/// Smart-hide collision policy, kept free of `dart:ui` and SDK imports so it
/// runs under plain `dart run`. Ported from NextKDE's DockAutoHideMath.mjs.
///
/// A window only hides the dock when it reaches the dock's own rectangle, not
/// the whole screen edge, and hysteresis keeps a window parked on the boundary
/// from making the dock flap.
typedef Box = ({double left, double top, double width, double height});

/// The fields a window contributes to the collision test.
typedef WindowSample = ({
  int monitorId,
  int workspaceId,
  bool minimized,
  bool userApp,
  Box? box,
});

extension BoxGeometry on Box {
  double get right => left + width;
  double get bottom => top + height;
  bool get isEmpty => width <= 0 || height <= 0;

  /// Matches `Rect.overlaps`: touching edges do not count.
  bool overlaps(Box other) {
    if (right <= other.left || other.right <= left) return false;
    if (bottom <= other.top || other.bottom <= top) return false;
    return true;
  }
}

/// The fully revealed capsule in scene coordinates.
Box dockRect({
  required Box output,
  required DockPosition position,
  required double extent,
  required double thickness,
  double inset = 10,
}) {
  final centerX = output.left + output.width / 2;
  final centerY = output.top + output.height / 2;
  return switch (position) {
    DockPosition.bottom => (
      left: centerX - extent / 2,
      top: output.bottom - inset - thickness,
      width: extent,
      height: thickness,
    ),
    DockPosition.left => (
      left: output.left + inset,
      top: centerY - extent / 2,
      width: thickness,
      height: extent,
    ),
    DockPosition.right => (
      left: output.right - inset - thickness,
      top: centerY - extent / 2,
      width: thickness,
      height: extent,
    ),
  };
}

/// A one-pixel touch does not count; the window must reach [depth] into the
/// dock body before the dock treats it as covered. The depth is measured from
/// the screen edge the dock is attached to.
Box overlapDepth(
  Box rect, {
  required DockPosition position,
  double depth = 12,
}) => switch (position) {
  DockPosition.bottom => () {
    final d = depth.clamp(0.0, rect.height - 1);
    return (
      left: rect.left,
      top: rect.top + d,
      width: rect.width,
      height: rect.height - d,
    );
  }(),
  DockPosition.left => () {
    final d = depth.clamp(0.0, rect.width - 1);
    return (
      left: rect.left + d,
      top: rect.top,
      width: rect.width - d,
      height: rect.height,
    );
  }(),
  DockPosition.right => () {
    final d = depth.clamp(0.0, rect.width - 1);
    return (
      left: rect.left,
      top: rect.top,
      width: rect.width - d,
      height: rect.height,
    );
  }(),
};

/// Window geometry in logical scene coordinates. A window whose pixel width
/// exceeds the output's logical width is reporting pixels, so divide by scale.
Box scaledWindowBox({
  required Box geometry,
  required double scale,
  required double outputWidth,
}) {
  if (scale > 1.0 &&
      scale.isFinite &&
      outputWidth > 0 &&
      geometry.width > outputWidth * 1.2) {
    return (
      left: geometry.left / scale,
      top: geometry.top / scale,
      width: geometry.width / scale,
      height: geometry.height / scale,
    );
  }
  return geometry;
}

/// Whether a window is one a smart-hiding dock reacts to under [scope].
bool countsForHide(
  DockHideScope scope, {
  required bool active,
  required bool maximized,
}) => switch (scope) {
  DockHideScope.all => true,
  DockHideScope.active => active,
  DockHideScope.maximized => maximized,
};

/// The distance a dock moves inward because something reserves its edge:
/// the gap between the output and the work area on that side, never negative.
double reservedEdge({
  required Box output,
  required Box workArea,
  required DockPosition position,
}) {
  if (workArea.isEmpty) return 0;
  final gap = switch (position) {
    DockPosition.bottom => output.bottom - workArea.bottom,
    DockPosition.left => workArea.left - output.left,
    DockPosition.right => output.right - workArea.right,
  };
  if (!gap.isFinite || gap <= 0) return 0;
  final limit =
      (position == DockPosition.bottom ? output.height : output.width) / 2;
  return gap > limit ? 0 : gap;
}

/// Whether any window on this monitor and workspace covers the dock.
///
/// [trigger] is the deeper rectangle that starts a conflict; [release] is the
/// full capsule that ends it. Using the smaller one to enter and the larger to
/// leave is the hysteresis that stops a window parked on the boundary from
/// making the dock flap.
bool conflictAt({
  required List<WindowSample> windows,
  required Box trigger,
  required Box release,
  required bool previousConflict,
  required int monitorId,
  required int workspaceId,
  required bool desktopVisible,
}) {
  if (desktopVisible) return false;
  final active = previousConflict ? release : trigger;
  for (final window in windows) {
    if (window.monitorId != monitorId) continue;
    if (window.workspaceId != workspaceId) continue;
    if (window.minimized || !window.userApp) continue;
    final box = window.box;
    if (box == null || box.isEmpty) continue;
    if (box.overlaps(active)) return true;
  }
  return false;
}
