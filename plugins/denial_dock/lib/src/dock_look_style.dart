import 'package:denial_shell_kit/kit_style.dart';
import 'package:flutter/widgets.dart';

import 'dock_look.dart';
import 'dock_metrics.dart';
import 'dock_settings.dart';

/// The metrics [style] brings: those of the dock preset it takes after,
/// with what the look itself sets laid over them.
DockMetrics dockMetricsFor(KitStyle style) {
  final look = style.look;
  final base = DockMetrics.preset(look.dockKin);
  return look.dock.isEmpty ? base : DockMetrics.resolve(base, look.dock);
}

/// The capsule's preset under [style], read from the look's own values, so a
/// look added to the kit dresses the dock without the dock knowing its name:
/// the preset it takes after, spaced by the look's density, drawn as the
/// look draws its panels, and then whatever the look sets for the dock
/// alone.
DockLook dockPresetFor(KitStyle style) {
  final look = style.look;
  final metrics = DockMetrics.preset(look.dockKin);
  final styled = DockLook.styled(
    DockLook.fitted(
      DockLook.preset(look.dockKin),
      padding: metrics.padding * look.density,
      gap: metrics.gap * look.density,
      endInset: metrics.endInset,
    ),
    borderWidth: style.borderWidth,
    accentBorder: style.borderFromAccent,
    opaque: style.opaque,
    shadow: style.shadow,
  );
  return look.dock.isEmpty ? styled : DockLook.resolve(styled, look.dock);
}

/// The capsule's look for [settings] under the look of the shell in force.
DockLook dockLookNow(DockSettings settings) => settings.lookFor(
  kitStyle.value.id,
  preset: dockPresetFor(kitStyle.value),
);

/// How application icons are coloured: as the user set it, or, while that is
/// left on full colour, as the look of the shell tints its icons.
DockIconMode dockIconModeNow(DockSettings settings) =>
    settings.iconMode != DockIconMode.color
    ? settings.iconMode
    : switch (kitStyle.value.look.iconTint) {
        KitIconTint.original => DockIconMode.color,
        KitIconTint.mono => DockIconMode.grayscale,
        KitIconTint.accent => DockIconMode.tinted,
      };

extension DockType on TextStyle {
  /// This style in the type of the look in force: its family, and its size
  /// scaled for a family that runs wide. A look that brings no family keeps
  /// the shell's own, and the style comes back untouched.
  TextStyle get inLook {
    final style = kitStyle.value;
    final family = style.fontFamily;
    if (family == null) return this;
    final size = fontSize;
    final weight = fontWeight;
    return copyWith(
      fontFamily: family,
      package: style.fontPackage,
      fontSize: size == null ? null : size * style.fontScale,
      fontWeight: weight == null ? null : style.weight(weight),
    );
  }
}

/// The dock's metrics for [settings] under the look of the shell in force,
/// for a dock of [shape].
DockMetrics dockMetricsNow(DockSettings settings, DockShape shape) =>
    settings.metricsFor(
      kitStyle.value.id,
      shape: shape,
      preset: dockMetricsFor(kitStyle.value),
    );

/// The metrics of the look in force as its preset gives them, for what the
/// settings do not reach: the menus and the label.
DockMetrics get dockLookMetrics => dockMetricsFor(kitStyle.value);
