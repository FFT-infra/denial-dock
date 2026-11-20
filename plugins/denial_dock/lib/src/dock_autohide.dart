import 'dart:ui' show Rect;

import 'package:denial_flutter_sdk/models.dart' show DenialWindow;
import 'package:denial_flutter_sdk/surfaces.dart' show DisplayOutput;

/// Smart-hide collision policy, ported from NextKDE's DockAutoHideMath.mjs.
///
/// A window only hides the dock when it reaches the dock's own rectangle, not
/// the whole bottom edge, and hysteresis keeps a window parked on the boundary
/// from making the dock flap.
abstract final class DockAutoHide {
  /// The fully revealed capsule in scene coordinates.
  static Rect visibleDockRect({
    required Rect output,
    required double width,
    required double height,
    double bottomInset = 10,
  }) => Rect.fromLTWH(
    output.center.dx - width / 2,
    output.bottom - bottomInset - height,
    width,
    height,
  );

  /// A one-pixel touch does not count; the window must reach [depth] into the
  /// dock body before the dock treats it as covered.
  static Rect intentionalOverlap(Rect rect, {double depth = 12}) {
    final inset = depth.clamp(0.0, rect.height - 1);
    return Rect.fromLTWH(
      rect.left,
      rect.top + inset,
      rect.width,
      rect.height - inset,
    );
  }

  /// Wider than [intentionalOverlap]: once hidden, the window has to leave this
  /// rect before the dock counts the space as free again.
  static Rect release(Rect rect) => rect.inflate(16);

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
