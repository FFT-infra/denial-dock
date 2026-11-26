@Plugin()
library;

import 'package:denial_flutter_sdk/surfaces.dart';
import 'package:denial_sdk/composition.dart';
import 'package:denial_shell_kit/kit_style.dart';
import 'package:flutter/widgets.dart';

import 'src/bar_reserve.dart';
import 'src/bar_surface.dart';
import 'src/island/island.dart' show islandReach;

/// A macOS 27 menu bar with an optional Dynamic Island.
///
/// The bar is the sole work-area provider, so the built-in `denial_top_bar`
/// must be disabled before this plugin is activated.
///
/// The surface stays placed while the bar draws only its island or nothing
/// at all: it is what offers the bar's parts to other hosts and keeps the
/// shell's reservation in step.
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
    return KitThemed(
      key: ValueKey(surface.environment.output.monitorId),
      child: TopBarSurface(
        monitorId: surface.environment.output.monitorId,
        environment: surface.environment,
        services: surface.services,
      ),
    );
  }
}

@Provides(ShellWorkArea)
final class TopBarWorkArea implements ShellWorkArea {
  const TopBarWorkArea();

  @override
  ShellWorkAreaReservation? reserve(ShellLayoutSettings settings) =>
      barReservation(settings);
}
