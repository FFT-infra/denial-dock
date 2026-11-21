/// Dock visibility policy, kept free of Flutter imports so the decision can be
/// unit-tested next to the layout math.
enum DockVisibilityMode {
  /// Always in reach, even under a window.
  always,

  /// Retract while a floating window covers the dock's strip; return on edge
  /// hover. A tiling layout keeps the dock resident instead: every tile reaches
  /// the bottom edge, so overlap-hiding would hide the dock permanently.
  smart;

  String get key => this == DockVisibilityMode.always ? 'always' : 'smart';

  static DockVisibilityMode parse(Object? value) =>
      value == 'always' ? DockVisibilityMode.always : DockVisibilityMode.smart;
}

abstract final class DockVisibility {
  /// Whether a covered dock retracts. Only [DockVisibilityMode.smart] hides,
  /// and only while the window layout floats.
  static bool smartHideActive({
    required DockVisibilityMode mode,
    required bool tiling,
  }) => mode == DockVisibilityMode.smart && !tiling;
}
