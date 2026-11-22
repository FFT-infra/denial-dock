/// Dock visibility policy, kept free of Flutter imports so the decision can be
/// unit-tested next to the layout math.
enum DockVisibilityMode {
  /// Always in reach, even under a window.
  always,

  /// Retract while a window covers the dock's strip; return on edge hover.
  /// Tiles reach the edge like any other window, so a tiling layout retracts
  /// too and comes back from the edge strip.
  smart,

  /// Retract whenever the pointer leaves, whatever is on screen; the edge
  /// strip brings it back.
  persistent;

  String get key => switch (this) {
    DockVisibilityMode.always => 'always',
    DockVisibilityMode.smart => 'smart',
    DockVisibilityMode.persistent => 'persistent',
  };

  static DockVisibilityMode parse(Object? value) => switch (value) {
    'always' => DockVisibilityMode.always,
    'persistent' => DockVisibilityMode.persistent,
    _ => DockVisibilityMode.smart,
  };
}

abstract final class DockVisibility {
  /// Whether the dock retracts right now. Only a pointer in the dock or on the
  /// edge strip keeps it out once this is true.
  static bool wantsHidden({
    required DockVisibilityMode mode,
    required bool conflict,
  }) => switch (mode) {
    DockVisibilityMode.always => false,
    DockVisibilityMode.smart => conflict,
    DockVisibilityMode.persistent => true,
  };
}
