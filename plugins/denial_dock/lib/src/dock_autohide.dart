import 'dart:ui' show Rect;

import 'package:denial_flutter_sdk/models.dart' show DenialWindow;
import 'package:denial_flutter_sdk/surfaces.dart' show DisplayOutput;

import 'dock_autohide_math.dart' as math;
import 'dock_settings.dart' show DockHideScope, DockPosition;

export 'dock_autohide_math.dart' show Box, WindowSample;

/// Adapts the dock's scene types to [math], which holds the policy.
///
/// The arithmetic lives in `dock_autohide_math.dart` so it can be unit-tested
/// without `dart:ui`; this file only converts [Rect], [DenialWindow] and
/// [DisplayOutput] into plain boxes.
abstract final class DockAutoHide {
  /// The fully revealed capsule in scene coordinates.
  static Rect visibleDockRect({
    required Rect output,
    required DockPosition position,
    required double extent,
    required double thickness,
    double inset = 10,
  }) => _toRect(
    math.dockRect(
      output: _toBox(output),
      position: position,
      extent: extent,
      thickness: thickness,
      inset: inset,
    ),
  );

  /// A one-pixel touch does not count; the window must reach [depth] into the
  /// dock body before the dock treats it as covered. The depth is measured from
  /// the screen edge the dock is attached to.
  static Rect intentionalOverlap(
    Rect rect, {
    DockPosition position = DockPosition.bottom,
    double depth = 12,
  }) => _toRect(
    math.overlapDepth(_toBox(rect), position: position, depth: depth),
  );

  static Rect windowRect(DenialWindow window, DisplayOutput output) {
    final geometry = window.geometry;
    if (geometry == null) return Rect.zero;
    return _toRect(
      math.scaledWindowBox(
        geometry: _toBox(geometry),
        scale: output.scale,
        outputWidth: output.logicalRect.width,
      ),
    );
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
    DockHideScope scope = DockHideScope.all,
    Set<int> activeIds = const {},
  }) => math.conflictAt(
    windows: [
      for (final window in windows)
        if (math.countsForHide(
          scope,
          active: activeIds.contains(window.objectId),
          maximized: window.maximized || window.fullscreen,
        ))
          _sample(window, output),
    ],
    trigger: _toBox(trigger),
    release: _toBox(release),
    previousConflict: previousConflict,
    monitorId: monitorId,
    workspaceId: workspaceId,
    desktopVisible: desktopVisible,
  );

  /// How far the dock sits in from its edge because a bar reserves it.
  static double reservedEdge({
    required Rect output,
    required Rect workArea,
    required DockPosition position,
  }) => math.reservedEdge(
    output: _toBox(output),
    workArea: _toBox(workArea),
    position: position,
  );

  static math.WindowSample _sample(DenialWindow window, DisplayOutput output) {
    final geometry = window.geometry;
    return (
      monitorId: window.monitorId,
      workspaceId: window.workspaceId,
      minimized: window.minimized,
      userApp: window.isUserApp,
      box: geometry == null
          ? null
          : math.scaledWindowBox(
              geometry: _toBox(geometry),
              scale: output.scale,
              outputWidth: output.logicalRect.width,
            ),
    );
  }

  static math.Box _toBox(Rect rect) =>
      (left: rect.left, top: rect.top, width: rect.width, height: rect.height);

  static Rect _toRect(math.Box box) =>
      Rect.fromLTWH(box.left, box.top, box.width, box.height);
}
