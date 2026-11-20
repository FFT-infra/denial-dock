@Plugin()
library;

import 'package:denial_flutter_sdk/surfaces.dart';
import 'package:denial_sdk/composition.dart';
import 'package:flutter/widgets.dart';

import 'src/dock_container.dart';
import 'src/dock_preferences.dart';

/// A floating, macOS-style dock for Denial.
///
/// The compositor reserves only the top bar, so the dock sits above windows and
/// retracts while a window covers its strip. Magnification uses the NextKDE
/// smootherstep wave with real layout growth.
@Provides(ShellSurface)
final class DockPlugin implements ShellSurface {
  const DockPlugin();

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
      outputRect.bottom - dockSurfaceHeight,
      outputRect.width,
      dockSurfaceHeight,
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

  @override
  Widget build(BuildContext context, {required ShellSurfaceContext surface}) {
    return DockContainer(
      key: ValueKey(surface.environment.output.monitorId),
      monitorId: surface.environment.output.monitorId,
      services: surface.services,
      environment: surface.environment,
    );
  }
}
