@Plugin()
library;

import 'package:denial_flutter_sdk/surfaces.dart';
import 'package:denial_sdk/composition.dart';
import 'package:flutter/widgets.dart';

import 'src/bar_surface.dart';
import 'src/island/island.dart' show islandReach;

/// A macOS 27 menu bar with an optional Dynamic Island.
///
/// The bar is the sole work-area provider, so the built-in `denial_top_bar`
/// must be disabled before this plugin is activated.
@Provides(ShellSurface)
final class TopBarPlugin implements ShellSurface {
  const TopBarPlugin();

  @override
  String get id => 'denial_topbar.panel';

  @override
  ShellSurfaceLayer get layer => ShellSurfaceLayer.aboveWindows;

  @override
  ShellSurfacePlacement? place(ShellSurfaceEnvironment environment) {
    final layout = environment.settings.layout;
    final side = layout.systemBarSide ?? PanelEdge.top;
    if (side == PanelEdge.hidden ||
        !environment.outputSelected(layout.systemBarOutputNames)) {
      return null;
    }
    return ShellSurfacePlacement(
      bounds: ShellSurfacePlacement.edgeBounds(
        environment.output.logicalRect,
        side,
        layout.systemBarThickness +
            barShadowExtent +
            (side == PanelEdge.top ? islandReach : 0),
      ),
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
    return TopBarSurface(
      key: ValueKey(surface.environment.output.monitorId),
      monitorId: surface.environment.output.monitorId,
      environment: surface.environment,
      services: surface.services,
    );
  }
}

@Provides(ShellWorkArea)
final class TopBarWorkArea implements ShellWorkArea {
  const TopBarWorkArea();

  @override
  ShellWorkAreaReservation? reserve(ShellLayoutSettings settings) {
    final side = settings.systemBarSide ?? PanelEdge.top;
    if (side == PanelEdge.hidden) return null;
    return ShellWorkAreaReservation(
      edge: side,
      thickness: settings.systemBarThickness,
      outputNames: settings.systemBarOutputNames,
    );
  }
}
