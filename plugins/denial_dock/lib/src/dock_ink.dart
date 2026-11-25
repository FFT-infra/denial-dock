/// Which ink reads on the dock's plate as it actually shows.
///
/// A translucent plate is mostly what lies behind it: the macOS look's
/// light plate is a mid grey at a quarter opacity, so over a dark wallpaper
/// it shows dark whatever the appearance says, and dark ink on it is lost.
/// The ink is therefore chosen against the fill laid over the backdrop at
/// the plate's opacity, and against the fill alone once the plate is solid.
///
/// Channels are sRGB-encoded values from 0 to 1, the space the plate is
/// composited in. No Flutter import, so the rule runs as an ordinary Dart
/// test.
abstract final class DockInk {
  /// At and under this luminance a ground is dark and takes light ink. The
  /// same line the top bar draws for its own ground.
  static const double darkLimit = 0.5;

  /// The luminance of a colour, weighing its channels as the eye does.
  static double luminance(double r, double g, double b) =>
      r * 0.2126 + g * 0.7152 + b * 0.0722;

  /// The luminance the plate shows with: a fill of luminance [fill] laid at
  /// [opacity] over a backdrop of luminance [backdrop].
  static double shown({
    required double fill,
    required double opacity,
    required double backdrop,
  }) {
    final alpha = opacity.isFinite ? opacity.clamp(0.0, 1.0).toDouble() : 1.0;
    return fill * alpha + backdrop * (1 - alpha);
  }

  /// Whether the plate takes light ink.
  ///
  /// [themeDark] settles a plate so close to the line that either ink
  /// reads: it then keeps the ink the appearance already uses, so the ink
  /// does not flip with every small change of the wallpaper.
  static bool lightInk({
    required double fill,
    required double opacity,
    required double backdrop,
    required bool themeDark,
    double band = 0.06,
  }) {
    final luminance = shown(fill: fill, opacity: opacity, backdrop: backdrop);
    // At the line and under it the plate is dark, as the top bar reads its
    // own ground: light ink reads on a mid tone and dark ink does not. Only
    // just above the line does the appearance settle it.
    if (luminance <= darkLimit) return true;
    return luminance - darkLimit <= band && themeDark;
  }
}
