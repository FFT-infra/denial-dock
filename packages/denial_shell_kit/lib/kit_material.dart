/// The surfaces the dock and the top bar draw on, as data: how much each one
/// blurs and saturates what is behind it, what it is filled with, its lines
/// and its shadow. A look carries one table of them, so a new look is a new
/// table and no widget changes.
///
/// No Flutter import, so the numbers and the arithmetic run as an ordinary
/// Dart test. `kit_glass.dart` turns a material into paint.
library;

/// What a surface is for. Each has its own material in every look.
enum KitTier { dock, popover, menu, card }

/// A colour the theme or the look decides when the material is drawn.
enum KitRole {
  /// The shell's panel colour at the shell's panel opacity, made solid by a
  /// look that blurs nothing.
  panel,

  /// The theme's surface colour, as the dock has always been filled.
  surface,

  /// The line the look draws around a panel: a hairline, or its accent.
  border,

  /// The theme's hairline, whatever the look.
  hairline,

  /// The theme's shadow colour.
  shadow,
}

/// A colour of a material: fixed, or one of the theme's.
class KitTone {
  /// [rgb] is 0xRRGGBB.
  const KitTone(this.rgb, double this.alpha) : role = null;

  /// The theme's colour for [role]. With [alpha] the colour takes that
  /// opacity in place of its own.
  const KitTone.of(KitRole this.role, {this.alpha}) : rgb = 0;

  static const int black = 0x000000;
  static const int white = 0xffffff;

  final int rgb;
  final double? alpha;
  final KitRole? role;

  bool get fixed => role == null;
}

/// Which sides of a surface a line runs along. On a surface that stands
/// upright (a dock on a side edge) the two swap, so [topBottom] is always
/// the long sides.
enum KitEdges { all, topBottom, ends }

/// A line along a surface's edge.
///
/// A line that is not all the way round fades out along the corners. With a
/// [tail] it also glows inward: [tail] is the opacity of that glow at the
/// line, falling to nothing [reach] further in. That is how a rim that
/// catches light looks: one bright pixel and a soft slope behind it.
class KitLine {
  const KitLine(
    this.tone, {
    this.width,
    this.edges = KitEdges.all,
    this.tail = 0,
    this.reach = 0,
  });

  final KitTone tone;

  /// Null takes the width the look gives its panel lines.
  final double? width;
  final KitEdges edges;
  final double tail;
  final double reach;
}

/// A shadow under a surface.
class KitShadow {
  const KitShadow(
    this.tone, {
    required this.blur,
    required this.dy,
    this.byLook = false,
  });

  final KitTone tone;

  /// The blur radius, as a box shadow counts it.
  final double blur;
  final double dy;

  /// Whether the look's own shadow strength scales it.
  final bool byLook;

  /// The Gaussian's sigma for [blur], by the engine's own rule.
  double get sigma => blur > 0 ? blur * 0.57735 + 0.5 : 0;
}

/// One surface in one appearance.
class KitMaterial {
  const KitMaterial({
    required this.fill,
    this.sigma,
    this.strength = 1,
    this.saturation = 1,
    this.radius,
    this.continuous = true,
    this.outer,
    this.inner,
    this.shadow,
    this.solid = 0.9,
  });

  /// The blur's sigma in logical pixels. Null follows the shell: the blur
  /// level the user chose, at [strength].
  final double? sigma;

  /// The share of the shell's own blur, where [sigma] is null.
  final double strength;

  final KitTone fill;

  /// How much the backdrop's colour is pushed away from its own grey before
  /// the fill goes over it; 1 leaves it alone.
  final double saturation;

  /// The corner radius this surface has when its owner names none.
  final double? radius;

  /// Continuous corners, or plain arcs.
  final bool continuous;

  /// A line just outside the edge, and one just inside.
  final KitLine? outer;
  final KitLine? inner;
  final KitShadow? shadow;

  /// The least the fill covers while the surface is told not to blur, as a
  /// card is while it moves.
  final double solid;

  KitMaterial copyWith({
    double? sigma,
    KitTone? fill,
    KitLine? Function()? outer,
    KitLine? Function()? inner,
  }) => KitMaterial(
    fill: fill ?? this.fill,
    sigma: sigma ?? this.sigma,
    strength: strength,
    saturation: saturation,
    radius: radius,
    continuous: continuous,
    outer: outer == null ? this.outer : outer(),
    inner: inner == null ? this.inner : inner(),
    shadow: shadow,
    solid: solid,
  );
}

/// A surface in the dark appearance and in the light one.
class KitMaterialPair {
  const KitMaterialPair({required this.dark, required this.light});

  const KitMaterialPair.same(KitMaterial both) : dark = both, light = both;

  final KitMaterial dark;
  final KitMaterial light;

  KitMaterial of({required bool dark}) => dark ? this.dark : light;
}

/// How a column of cards is laid out, which belongs with the card's
/// material: the two were measured together.
class KitCardLayout {
  const KitCardLayout({
    required this.width,
    required this.gap,
    required this.edge,
    required this.peek,
    required this.inset,
    required this.dim,
    required this.dimReach,
  });

  /// A card's width, the space between two, and from the screen's edge.
  final double width;
  final double gap;
  final double edge;

  /// A folded stack: how much of each card behind shows under the one in
  /// front, and how much narrower it is on either side.
  final double peek;
  final double inset;

  /// How dark the wallpaper gets behind the whole column, and how far past
  /// the cards that takes to fade out.
  final double dim;
  final double dimReach;
}

/// A look's materials.
class KitMaterials {
  const KitMaterials({
    required this.dock,
    required this.popover,
    required this.menu,
    required this.card,
    required this.cardLayout,
  });

  final KitMaterialPair dock;
  final KitMaterialPair popover;
  final KitMaterialPair menu;
  final KitMaterialPair card;
  final KitCardLayout cardLayout;

  KitMaterialPair tier(KitTier tier) => switch (tier) {
    KitTier.dock => dock,
    KitTier.popover => popover,
    KitTier.menu => menu,
    KitTier.card => card,
  };

  static const KitMaterial _shellPanel = KitMaterial(
    fill: KitTone.of(KitRole.panel),
    inner: KitLine(KitTone.of(KitRole.border)),
    shadow: KitShadow(
      KitTone.of(KitRole.shadow, alpha: 0.30),
      blur: 36,
      dy: 14,
      byLook: true,
    ),
  );

  /// The shell's own surfaces, which the Denial, Soft and Terminal looks
  /// share. Everything comes from the theme and from the look's few
  /// numbers (how wide its line is, whether it fills solid, how much shadow
  /// it casts), so these are the values those looks have always drawn.
  static const KitMaterials shell = KitMaterials(
    dock: KitMaterialPair.same(
      KitMaterial(
        fill: KitTone.of(KitRole.surface),
        radius: 20,
        continuous: false,
        inner: KitLine(KitTone.of(KitRole.hairline, alpha: 0.7), width: 1),
      ),
    ),
    popover: KitMaterialPair.same(_shellPanel),
    menu: KitMaterialPair.same(_shellPanel),
    card: KitMaterialPair.same(
      KitMaterial(
        fill: KitTone.of(KitRole.panel),
        radius: 22,
        inner: KitLine(KitTone.of(KitRole.hairline), width: 1),
        shadow: KitShadow(
          KitTone.of(KitRole.shadow, alpha: 0.2),
          blur: 13,
          dy: 4,
        ),
      ),
    ),
    cardLayout: KitCardLayout(
      width: 372,
      gap: 10,
      edge: 10,
      peek: 8,
      inset: 12,
      dim: 0.36,
      dimReach: 180,
    ),
  );

  /// Measured on macOS, from screenshots over a test wallpaper of hard
  /// edges, grey steps and pure colours. Each surface was fitted as
  ///
  ///     out = k * Sat(s) * blur(backdrop, sigma) + t
  ///
  /// on sRGB-encoded values, which is a fill of opacity 1 - k and colour
  /// t / (1 - k) over a blurred, saturated backdrop. Lengths are points,
  /// used here as logical pixels.
  ///
  /// The dark surfaces also lift their mid-tones (a curve near b^0.7). A
  /// colour matrix cannot bend: any gain and offset is only another fill,
  /// and a gain that clips would flatten the wallpaper's highlights. So
  /// mid-greys come out up to 4% darker than measured.
  static const KitMaterials mac = KitMaterials(
    dock: KitMaterialPair(
      dark: KitMaterial(
        sigma: 1.6,
        fill: KitTone(0x222222, 0.36),
        saturation: 2.0,
        radius: 22,
        outer: KitLine(
          KitTone(KitTone.black, 0.4),
          width: 0.5,
          edges: KitEdges.ends,
        ),
        inner: KitLine(
          KitTone(KitTone.white, 0.30),
          width: 1,
          edges: KitEdges.topBottom,
          tail: 0.07,
          reach: 7,
        ),
      ),
      light: KitMaterial(
        sigma: 1.6,
        fill: KitTone(0x979797, 0.25),
        saturation: 1.7,
        radius: 22,
        outer: KitLine(
          KitTone(KitTone.black, 0.4),
          width: 0.5,
          edges: KitEdges.ends,
        ),
        inner: KitLine(
          KitTone(KitTone.white, 0.5),
          width: 1,
          edges: KitEdges.topBottom,
          tail: 0.07,
          reach: 7,
        ),
      ),
    ),
    popover: KitMaterialPair(
      dark: KitMaterial(
        sigma: 10,
        fill: KitTone(0x454545, 0.72),
        saturation: 2.4,
        radius: 16,
        outer: KitLine(KitTone(KitTone.black, 0.76), width: 0.5),
        inner: KitLine(KitTone(KitTone.white, 0.12), width: 1),
        shadow: KitShadow(KitTone(KitTone.black, 0.12), blur: 36, dy: 7),
      ),
      light: KitMaterial(
        sigma: 10,
        fill: KitTone(0xf5f5f5, 0.57),
        saturation: 1.3,
        radius: 16,
        outer: KitLine(KitTone(KitTone.black, 0.28), width: 0.5),
        inner: KitLine(KitTone(KitTone.white, 0.6), width: 1),
        shadow: KitShadow(KitTone(KitTone.black, 0.08), blur: 36, dy: 7),
      ),
    ),
    // A menu's saturation could not be measured (too little colour behind
    // it), so it borrows the popover's.
    menu: KitMaterialPair(
      dark: KitMaterial(
        sigma: 13,
        fill: KitTone(0x494b53, 0.63),
        saturation: 2.4,
        radius: 11,
        outer: KitLine(KitTone(KitTone.black, 0.85), width: 0.5),
        inner: KitLine(KitTone(KitTone.white, 0.2), width: 1),
        shadow: KitShadow(KitTone(KitTone.black, 0.20), blur: 16, dy: 2),
      ),
      light: KitMaterial(
        sigma: 13,
        fill: KitTone(0xf9f9f9, 0.83),
        saturation: 1.3,
        radius: 11,
        outer: KitLine(KitTone(KitTone.black, 0.30), width: 0.5),
        inner: KitLine(KitTone(KitTone.white, 0.6), width: 1),
        shadow: KitShadow(KitTone(KitTone.black, 0.18), blur: 16, dy: 2),
      ),
    ),
    card: KitMaterialPair(
      dark: KitMaterial(
        sigma: 10,
        fill: KitTone(0x474747, 0.52),
        saturation: 1.7,
        radius: 19,
        inner: KitLine(
          KitTone(KitTone.white, 0.15),
          width: 1,
          edges: KitEdges.topBottom,
        ),
        shadow: KitShadow(KitTone(KitTone.black, 0.03), blur: 12, dy: 2),
      ),
      light: KitMaterial(
        sigma: 12,
        fill: KitTone(0xd7d7d7, 0.63),
        saturation: 1.8,
        radius: 19,
        outer: KitLine(KitTone(KitTone.black, 0.11), width: 0.5),
        inner: KitLine(KitTone(KitTone.white, 0.6), width: 1),
        shadow: KitShadow(KitTone(KitTone.black, 0.03), blur: 12, dy: 2),
      ),
    ),
    cardLayout: KitCardLayout(
      width: 344,
      gap: 6,
      edge: 16,
      peek: 8,
      inset: 10,
      dim: 0.20,
      dimReach: 100,
    ),
  );

  /// Every table, for a test to walk.
  static const List<KitMaterials> all = <KitMaterials>[shell, mac];
}

/// How a material's blur is carried out under the shell's settings.
class KitBlurPlan {
  const KitBlurPlan({
    required this.direct,
    required this.strength,
    required this.sigma,
    this.capped = false,
  });

  static const KitBlurPlan none = KitBlurPlan(
    direct: false,
    strength: 0,
    sigma: 0,
  );

  /// Whether the filter is built here at [sigma], or left to the shell's own
  /// backdrop at [strength].
  final bool direct;
  final double strength;

  /// The sigma that reaches the screen.
  final double sigma;

  /// The shell could not blur as far as the material asked.
  final bool capped;

  /// A glass with no frost of its own still bends and lights the backdrop.
  bool get blurs => direct ? sigma > 0 : strength > 0;
}

/// The arithmetic between a sigma in pixels and the shell's blur.
///
/// The shell knows a blur only as a share of the level the user chose:
/// `sigma = base * strength`, with the strength snapped to one of 32 steps
/// and never above 1. So a material that names a sigma can reach it through
/// the shell only up to that base (6 on three of the four levels, 14 on the
/// best). In the shell's blur mode the kit therefore builds the same engine
/// filter itself, at the material's own sigma and the level's own sampling
/// quality, and nothing is capped. In glass mode the shell's filter is a
/// lens with refraction and lighting the user tuned, which the kit must not
/// replace: there the sigma becomes a share of the glass's own, capped at
/// it. With transparency off nothing blurs, whatever the material says.
abstract final class KitBlurMath {
  /// The steps the shell snaps a strength to.
  static const int steps = 32;

  /// The share of [base] that gives [sigma], as the shell will take it.
  static double strengthFor(double sigma, double base) =>
      base > 0 && sigma > 0 ? (sigma / base).clamp(0.0, 1.0).toDouble() : 0;

  /// The sigma the shell draws for [strength] of [base].
  static double sigmaAt(double strength, double base) {
    if (strength <= 0) return 0;
    final step = (strength.clamp(0.0, 1.0) * steps).round().clamp(1, steps);
    return base * step / steps;
  }

  /// [enabled] is false when the user turned transparency off; [glass] is
  /// the shell's glass mode; [base] is the sigma of the shell's own blur in
  /// the mode in force. [scale] is a caller's share of the material's blur.
  static KitBlurPlan plan(
    KitMaterial material, {
    required bool enabled,
    required bool glass,
    required double base,
    double scale = 1,
  }) {
    if (!enabled || scale <= 0 || (base <= 0 && !glass)) {
      return KitBlurPlan.none;
    }
    final target = material.sigma;
    if (target == null) {
      final strength = (material.strength * scale).clamp(0.0, 1.0).toDouble();
      return strength <= 0
          ? KitBlurPlan.none
          : KitBlurPlan(
              direct: false,
              strength: strength,
              sigma: sigmaAt(strength, base),
            );
    }
    final sigma = target * scale;
    if (sigma <= 0) return KitBlurPlan.none;
    if (!glass) {
      return KitBlurPlan(direct: true, strength: 1, sigma: sigma);
    }
    final strength = base > 0 ? strengthFor(sigma, base) : 1.0;
    return strength <= 0
        ? KitBlurPlan.none
        : KitBlurPlan(
            direct: false,
            strength: strength,
            sigma: sigmaAt(strength, base),
            capped: sigma > base,
          );
  }
}

/// The 5 by 4 colour matrix, row by row, that multiplies a colour's distance
/// from its own grey by [saturation]. Greys stay as they are; the weights
/// are Rec. 709 luma, applied to encoded values as the measurements were.
List<double> kitSaturationMatrix(double saturation) {
  const weights = <double>[0.2126, 0.7152, 0.0722];
  final rest = 1 - saturation;
  return <double>[
    for (var row = 0; row < 3; row++) ...[
      for (var column = 0; column < 3; column++)
        rest * weights[column] + (row == column ? saturation : 0),
      0,
      0,
    ],
    0,
    0,
    0,
    1,
    0,
  ];
}
