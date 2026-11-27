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

/// Shell-wide Control Centre, Notification Centre, and popover layout archetype.
enum KitShellArchetype {
  denial,
  macos,
  cutefish,
  gnome,
  windows,
  plasma,
  material,
  noctalia,
  hyprpanel,
  caelestia,
  axshell,
  omarchy,
  cosmic;

  static KitShellArchetype? tryParse(Object? value) {
    if (value is! String) return null;
    for (final item in values) {
      if (item.name == value) return item;
    }
    return null;
  }

  /// Resolves the default archetype for a look [id] (or its [base] look id).
  static KitShellArchetype forLookId(String id) => switch (id) {
    'mac' || 'macos' => KitShellArchetype.macos,
    'cutefish' => KitShellArchetype.cutefish,
    'gnome' => KitShellArchetype.gnome,
    'windows' => KitShellArchetype.windows,
    'plasma' => KitShellArchetype.plasma,
    'material' => KitShellArchetype.material,
    'noctalia' => KitShellArchetype.noctalia,
    'hyprpanel' => KitShellArchetype.hyprpanel,
    'caelestia' => KitShellArchetype.caelestia,
    'axshell' => KitShellArchetype.axshell,
    'omarchy' || 'terminal' => KitShellArchetype.omarchy,
    'cosmic' => KitShellArchetype.cosmic,
    _ => KitShellArchetype.denial,
  };
}
