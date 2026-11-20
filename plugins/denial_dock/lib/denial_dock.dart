@Plugin()
library;

import 'package:denial_flutter_sdk/surfaces.dart';
import 'package:denial_sdk/composition.dart';
import 'package:flutter/widgets.dart';

import 'src/dock_container.dart';
import 'src/dock_preferences.dart';

/// Refined macOS-style Dock plugin for Denial.
///
/// Features:
/// - Quintic smootherstep wave magnification & integral push physics (NextKDE).
/// - 60Hz/120Hz/240Hz frame-rate agnostic first-order decay tracking.
/// - Live window preview thumbnails via [ShellWindowServices.buildWindowPreview].
/// - Real-time window peeking emphasis via [ShellWindowServices.emphasizeWindow].
/// - Ballistic launch bounce animation.
/// - Single continuous in-surface name label.
/// - Zero ShellWorkArea conflict, co-existing seamlessly with official Top Bar.
@Provides(ShellSurface)
final class DockPlugin implements ShellSurface {
  const DockPlugin();

  static const _preferences = DockPreferences();
  static final double surfaceHeight =
      _preferences.restingThickness + _preferences.visualHeadroom + 30.0;

  @override
  String get id => 'denial_dock.panel';

  @override
  ShellSurfaceLayer get layer => ShellSurfaceLayer.aboveWindows;

  @override
  ShellSurfacePlacement? place(ShellSurfaceEnvironment environment) {
    if (environment.output.inputOnly) {
      return null;
    }

    final outputRect = environment.output.logicalRect;
    final bounds = Rect.fromLTWH(
      outputRect.left,
      outputRect.bottom - surfaceHeight,
      outputRect.width,
      surfaceHeight,
    );

    return ShellSurfacePlacement(
      bounds: bounds,
      fade: ShellSurfaceFade.automatic,
      occupiesDesktop: false,
      visible:
          !environment.locked &&
          !environment.wallpaperSelectorVisible &&
          (!environment.fullscreen ||
              environment.overview ||
              environment.desktopVisible),
    );
  }

  static final _dockInstances = <int, DockContainer>{};

  @override
  Widget build(BuildContext context, {required ShellSurfaceContext surface}) {
    final monitorId = surface.environment.output.monitorId;
    final existing = _dockInstances[monitorId];
    if (existing != null && identical(existing.services, surface.services)) {
      return existing;
    }

    return _dockInstances[monitorId] = DockContainer(
      monitorId: monitorId,
      services: surface.services,
      preferences: _preferences,
    );
  }
}
