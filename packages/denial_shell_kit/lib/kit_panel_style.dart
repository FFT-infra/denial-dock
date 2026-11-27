/// Panel layout archetypes and widget card styling shared across presets.
///
/// Pure Dart (no Flutter import) so preset/style serialization and tests run
/// directly under `dart`.
library;

/// How Control Centre and shell flyout panels are framed and positioned.
enum KitPanelStyle {
  /// Independent floating glass modules with no outer slab (macOS 26 Tahoe).
  floating,

  /// Single framed panel slab housing the full grid (Denial / Plasma / Cutefish).
  framed,

  /// Compact quick-settings flyout anchored to the trigger (GNOME / Win11 / Omarchy / COSMIC).
  anchored,

  /// Edge-fused / concave-attached drawer panel (Noctalia / Ax-Shell / Caelestia).
  attached;

  static KitPanelStyle? tryParse(Object? value) {
    if (value is! String) return null;
    for (final style in values) {
      if (style.name == value) return style;
    }
    return null;
  }
}

/// Visual card treatment for Notification Centre / desktop widgets.
enum KitWidgetStyle {
  /// Unified translucent glass cards following the active [KitSurfaceMode].
  glass,

  /// Distinct per-widget signature colour/artwork plates (paper calendar, night clock).
  color;

  static KitWidgetStyle? tryParse(Object? value) {
    if (value is! String) return null;
    for (final style in values) {
      if (style.name == value) return style;
    }
    return null;
  }
}
