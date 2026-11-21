import 'dart:ui' show Rect;

import 'package:denial_flutter_sdk/models.dart' show DenialWindow;
import 'package:denial_flutter_sdk/surfaces.dart' show DisplayOutput;

import 'dock_settings.dart' show DockPosition;

/// Smart-hide collision policy, ported from NextKDE's DockAutoHideMath.mjs.
///
/// A window only hides the dock when it reaches the dock's own rectangle, not
/// the whole screen edge, and hysteresis keeps a window parked on the boundary
/// from making the dock flap.
abstract final class DockAutoHide {
  /// The fully revealed capsule in scene coordinates.
  static Rect visibleDockRect({
    required Rect output,
    required DockPosition position,
    required double extent,
    required double thickness,
    double inset = 10,
  }) => switch (position) {
    DockPosition.bottom => Rect.fromLTWH(
      output.center.dx - extent / 2,
      output.bottom - inset - thickness,
      extent,
      thickness,
    ),
    DockPosition.left => Rect.fromLTWH(
      output.left + inset,
      output.center.dy - extent / 2,
      thickness,
      extent,
    ),
    DockPosition.right => Rect.fromLTWH(
      output.right - inset - thickness,
      output.center.dy - extent / 2,
      thickness,
      extent,
    ),
  };

  /// A one-pixel touch does not count; the window must reach [depth] into the
  /// dock body before the dock treats it as covered. The depth is measured from
  /// the screen edge the dock is attached to.
  static Rect intentionalOverlap(
    Rect rect, {
    DockPosition position = DockPosition.bottom,
    double depth = 12,
  }) => switch (position) {
    DockPosition.bottom => () {
      final d = depth.clamp(0.0, rect.height - 1);
      return Rect.fromLTWH(
        rect.left,
        rect.top + d,
        rect.width,
        rect.height - d,
      );
    }(),
    DockPosition.left => () {
      final d = depth.clamp(0.0, rect.width - 1);
      return Rect.fromLTWH(
        rect.left + d,
        rect.top,
        rect.width - d,
        rect.height,
      );
    }(),
    DockPosition.right => () {
      final d = depth.clamp(0.0, rect.width - 1);
      return Rect.fromLTWH(rect.left, rect.top, rect.width - d, rect.height);
    }(),
  };

  static Rect windowRect(DenialWindow window, DisplayOutput output) {
    final geometry = window.geometry;
    if (geometry == null) return Rect.zero;
    final scale = output.scale;
    if (scale > 1.0 &&
        scale.isFinite &&
        output.logicalRect.width > 0 &&
        geometry.width > output.logicalRect.width * 1.2) {
      return Rect.fromLTWH(
        geometry.left / scale,
        geometry.top / scale,
        geometry.width / scale,
        geometry.height / scale,
      );
    }
    return geometry;
  }

  static bool hasConflict({
    required Iterable<DenialWindow> windows,
    required Rect trigger,
    required Rect release,
    required bool previousConflict,
    required int monitorId,
    required int workspaceId,
    required DisplayOutput output,
    required bool desktopVisible,
  }) {
    if (desktopVisible) return false;
    final active = previousConflict ? release : trigger;
    for (final window in windows) {
      if (window.monitorId != monitorId) continue;
      if (window.workspaceId != workspaceId) continue;
      if (window.minimized || !window.isUserApp) continue;
      final rect = windowRect(window, output);
      if (rect.isEmpty) continue;
      if (rect.overlaps(active)) return true;
    }
    return false;
  }
}
