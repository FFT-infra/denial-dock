import 'dart:async';

import 'package:denial_flutter_sdk/state.dart' show displayLayoutProvider;
import 'package:denial_flutter_sdk/surfaces.dart';
import 'package:denial_shell_kit/kit_host.dart';
import 'package:denial_shell_kit/kit_layer.dart' show KitEdgeOfPanelEdge;
import 'package:denial_shell_kit/kit_panel_place.dart' show KitEdge;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The room the shell keeps free of windows, decided between the bar and the
/// dock. This plugin holds the shell's one work-area provider, so it answers
/// for both: the bar's strip while the bar draws one, otherwise the edge of
/// a dock that stays on screen, otherwise nothing.
ShellWorkAreaReservation? barReservation(ShellLayoutSettings settings) {
  final side = settings.systemBarSide ?? PanelEdge.top;
  final held = kitResolveReservation(
    barEdge: side == PanelEdge.hidden ? null : side.kitEdge,
    barThickness: settings.systemBarThickness,
  );
  // Whoever asked may be in the middle of a build; the dock rebuilds when
  // this changes.
  scheduleMicrotask(() => kitReservation.value = held);
  if (held == null) return null;
  return ShellWorkAreaReservation(
    edge: switch (held.edge) {
      KitEdge.top => PanelEdge.top,
      KitEdge.bottom => PanelEdge.bottom,
      KitEdge.left => PanelEdge.left,
      KitEdge.right => PanelEdge.right,
    },
    thickness: held.thickness,
    outputNames: settings.systemBarOutputNames,
  );
}

/// Has the shell take up the reservation as it stands now.
///
/// The shell asks [barReservation] only when its own layout settings change.
/// The bar's mode, the dock's switch and what the dock reports are not among
/// them, so after one of those changes the answer is handed over here, with
/// the same call the shell makes itself.
void syncBarReservation(WidgetRef ref, ShellLayoutSettings settings) {
  final reservation = barReservation(settings);
  final side = reservation?.edge ?? PanelEdge.hidden;
  final thickness = reservation?.thickness ?? 0.0;
  final current = ref.read(displayLayoutProvider);
  if (current != null &&
      current.systemBarSide == side &&
      (side == PanelEdge.hidden || current.systemBarThickness == thickness)) {
    return;
  }
  ref
      .read(displayLayoutProvider.notifier)
      .applyShellConfiguration(
        side: side,
        outputNames: reservation?.outputNames ?? const <String>[],
        systemBarThickness: thickness,
        // The shell decides the padding by its own rules; keep its value.
        maximizePadding: current?.maximizePadding ?? settings.maximizePadding,
      );
}
