/// Dock visibility policy, kept free of Flutter imports so the decision can be
/// unit-tested next to the layout math.
enum DockVisibilityMode {
  /// Always in reach, even under a window.
  always,

  /// Retract while a window covers the dock's strip; return on edge hover.
  /// Tiles reach the edge like any other window, so a tiling layout retracts
  /// too and comes back from the edge strip.
  smart;

  String get key => this == DockVisibilityMode.always ? 'always' : 'smart';

  static DockVisibilityMode parse(Object? value) =>
      value == 'always' ? DockVisibilityMode.always : DockVisibilityMode.smart;
}

abstract final class DockVisibility {
  /// Whether a covered dock retracts.
  static bool smartHideActive({required DockVisibilityMode mode}) =>
      mode == DockVisibilityMode.smart;
}
