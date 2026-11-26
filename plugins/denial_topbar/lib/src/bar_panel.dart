import 'dart:math' as math;

import 'package:denial_flutter_sdk/panels.dart';
import 'package:denial_shell_kit/kit_layer.dart';
import 'package:denial_shell_kit/kit_style.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'bar_tokens.dart';

export 'package:denial_shell_kit/kit_layer.dart';

/// Where a bar panel sits along the bar.
enum BarPanelAnchor {
  /// A menu under its title.
  dropdown,

  /// A popover centred on its status item.
  centred,

  /// The notification column, at the screen's trailing side.
  clock,

  /// The control centre, at the screen's trailing side with its own inset.
  trailing,
}

/// Opens one bar panel at a time; the open panel's own item closes it.
void showBarPanel({
  required WidgetRef ref,
  required String panelId,
  required GlobalKey anchor,
  required Widget Function(BuildContext context, VoidCallback close) builder,
  PanelEdge side = PanelEdge.top,
  double width = BarTokens.panelMaxWidth,
  bool glass = true,
  BarPanelAnchor placement = BarPanelAnchor.dropdown,
  Color? fill,
  double? radius,
  double barHeight = BarTokens.height,
}) {
  final menu = placement == BarPanelAnchor.dropdown;
  // The control centre is a sheet of round tiles and text, so it grows evenly
  // from the corner under its icon; an uneven start would squash both.
  final sheet = placement == BarPanelAnchor.trailing;
  final bead = kitStyle.value.panelBead;
  showKitPanel(
    ref: ref,
    panelId: panelId,
    debugLabel: 'Top bar $panelId',
    anchor: kitSceneRect(anchor),
    edge: side.kitEdge,
    hostExtent: barHeight,
    gap: menu ? BarTokens.menuDropOffsetY : BarTokens.popoverGap,
    radius: radius ?? (menu ? BarTokens.menuRadius : BarTokens.popoverRadius),
    width: width,
    kind: menu ? KitPanelKind.menu : KitPanelKind.popover,
    align: switch (placement) {
      BarPanelAnchor.dropdown => KitPanelAlign.anchorStart,
      BarPanelAnchor.centred => KitPanelAlign.anchorCenter,
      BarPanelAnchor.clock || BarPanelAnchor.trailing => KitPanelAlign.sceneEnd,
    },
    alignOffset: switch (placement) {
      BarPanelAnchor.dropdown => BarTokens.menuDropOffsetX,
      BarPanelAnchor.centred => 0,
      BarPanelAnchor.clock => 8,
      BarPanelAnchor.trailing => BarTokens.controlCenterInset,
    },
    glass: glass,
    fill: fill,
    bead: sheet
        ? Size.square(math.max(0.94, math.max(bead.width, bead.height)))
        : null,
    cornerOrigin: sheet,
    builder: builder,
  );
}
