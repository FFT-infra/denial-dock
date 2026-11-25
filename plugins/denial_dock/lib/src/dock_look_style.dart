import 'package:denial_shell_kit/kit_style.dart';
import 'package:flutter/widgets.dart';

import 'dock_look.dart';
import 'dock_metrics.dart';
import 'dock_settings.dart';

/// The capsule's preset under [style], read from the look's own values, so a
/// look added to the kit dresses the dock without the dock knowing its name.
DockLook dockPresetFor(KitStyle style) => DockLook.styled(
  DockLook.fitted(
    DockLook.preset(style.id),
    padding: DockMetrics.preset(style.id).padding,
    gap: DockMetrics.preset(style.id).gap,
    endInset: DockMetrics.preset(style.id).endInset,
  ),
  borderWidth: style.borderWidth,
  accentBorder: style.borderFromAccent,
  opaque: style.opaque,
  shadow: style.shadow,
);

/// The capsule's look for [settings] under the look of the shell in force.
DockLook dockLookNow(DockSettings settings) => settings.lookFor(
  kitStyle.value.id,
  preset: dockPresetFor(kitStyle.value),
);

extension DockType on TextStyle {
  /// This style in the type of the look in force: its family, and its size
  /// scaled for a family that runs wide. A look that brings no family keeps
  /// the shell's own, and the style comes back untouched.
  TextStyle get inLook {
    final style = kitStyle.value;
    final family = style.fontFamily;
    if (family == null) return this;
    final size = fontSize;
    return copyWith(
      fontFamily: family,
      package: style.fontPackage,
      fontSize: size == null ? null : size * style.fontScale,
    );
  }
}

/// The dock's metrics for [settings] under the look of the shell in force,
/// for a dock of [shape].
DockMetrics dockMetricsNow(DockSettings settings, DockShape shape) =>
    settings.metricsFor(kitStyle.value.id, shape: shape);

/// The metrics of the look in force as its preset gives them, for what the
/// settings do not reach: the menus and the label.
DockMetrics get dockLookMetrics => DockMetrics.preset(kitStyle.value.id);
