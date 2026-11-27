import 'dart:async';

import 'package:denial_flutter_sdk/models.dart' show DisplayLayout;
import 'package:denial_flutter_sdk/settings.dart'
    show ShellScale, shellSettingsProvider;
import 'package:denial_flutter_sdk/state.dart' show displayLayoutProvider;
import 'package:denial_flutter_sdk/surfaces.dart';
import 'package:denial_shell_kit/kit_host.dart';
import 'package:denial_shell_kit/kit_layer.dart' show KitEdgeOfPanelEdge;
import 'package:denial_shell_kit/kit_panel_place.dart' show KitEdge;
import 'package:denial_shell_kit/kit_style.dart'
    show kitShellScale, resolveKitScale;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'bar_preferences.dart' show barSettingsProvider;

double _lastHostScale = 1.0;
double? _lastBarHeight;

/// Records the live host scale and custom bar height so [TopBarWorkArea.reserve]
/// computes the exact same reservation as [syncBarReservation].
void rememberBarReserveContext({double? hostScale, double? barHeight}) {
  if (hostScale != null && hostScale.isFinite && hostScale > 0) {
    _lastHostScale = hostScale;
  }
  _lastBarHeight = barHeight;
}

/// Computes the current relative scale ratio `(effectiveScale / hostScale)`.
double currentBarScaleRatio({double? hostScale}) {
  final base = (hostScale != null && hostScale.isFinite && hostScale > 0)
      ? hostScale
      : _lastHostScale;
  final effective = resolveKitScale(base, kitShellScale.value);
  return effective / base;
}

/// The room the shell keeps free of windows, decided between the bar and the
/// dock. This plugin holds the shell's one work-area provider, so it answers
/// for both: the bar's strip while the bar draws one, otherwise the edge of
/// a dock that stays on screen, otherwise nothing.
ShellWorkAreaReservation? barReservation(
  ShellLayoutSettings settings, {
  double? scaleRatio,
  double? barHeight,
  bool useStoredBarHeight = true,
}) {
  final side = settings.systemBarSide ?? PanelEdge.top;
  final effectiveBarHeight =
      barHeight ?? (useStoredBarHeight ? _lastBarHeight : null);
  final held = kitResolveReservation(
    barEdge: side == PanelEdge.hidden ? null : side.kitEdge,
    barThickness: effectiveBarHeight ?? settings.systemBarThickness,
  );
  // Whoever asked may be in the middle of a build; the dock rebuilds when
  // this changes.
  scheduleMicrotask(() => kitReservation.value = held);
  if (held == null) return null;
  final rawRatio = scaleRatio ?? currentBarScaleRatio();
  final ratio = rawRatio.isFinite && rawRatio > 0 ? rawRatio : 1.0;
  return ShellWorkAreaReservation(
    edge: switch (held.edge) {
      KitEdge.top => PanelEdge.top,
      KitEdge.bottom => PanelEdge.bottom,
      KitEdge.left => PanelEdge.left,
      KitEdge.right => PanelEdge.right,
    },
    thickness: held.thickness * ratio,
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
  final current = ref.read(displayLayoutProvider);
  final mainId = current?.mainOutput?.monitorId;
  final hostScale = mainId == null ? 1.0 : current!.shellScaleOf(mainId);
  final barHeight = ref.read(barSettingsProvider).value?.barHeight;
  rememberBarReserveContext(hostScale: hostScale, barHeight: barHeight);
  final reservation = barReservation(
    settings,
    scaleRatio: currentBarScaleRatio(hostScale: hostScale),
    barHeight: barHeight,
    useStoredBarHeight: false,
  );
  final side = reservation?.edge ?? PanelEdge.hidden;
  final thickness = reservation?.thickness ?? 0.0;
  if (current != null &&
      current.systemBarSide == side &&
      (side == PanelEdge.hidden || current.systemBarThickness == thickness)) {
    return;
  }
  final scales = ref.read(shellSettingsProvider).appearance.shellScales;
  ref
      .read(displayLayoutProvider.notifier)
      .applyShellConfiguration(
        side: side,
        outputNames: reservation?.outputNames ?? const <String>[],
        systemBarThickness: thickness,
        // The shell decides the padding by its own rules; keep its value.
        maximizePadding: current?.maximizePadding ?? settings.maximizePadding,
        // The call replaces the shell's scale on every output along with the
        // reservation, so the scales go back in as the shell has them.
        shellScales: scales,
        desktopPanels: _desktopPanels(current, scales),
      );
}

/// Whether the desktop shell has the built-in panels, read back from the
/// layout: the shell does not say so anywhere a plugin can ask. Where the
/// mobile shell has them, a built-in panel that would take a scale of its
/// own carries none.
bool _desktopPanels(DisplayLayout? layout, Map<String, double> scales) {
  if (layout == null) return true;
  for (final output in layout.outputs) {
    final name = output.name;
    final builtIn =
        name.startsWith('DSI-') ||
        name.startsWith('eDP-') ||
        name.startsWith('LVDS-');
    if (builtIn &&
        ShellScale.of(output, scales) != 1.0 &&
        layout.shellScaleOf(output.monitorId) == 1.0) {
      return false;
    }
  }
  return true;
}
