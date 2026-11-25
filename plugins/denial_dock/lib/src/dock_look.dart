/// What the capsule's fill is mixed from.
enum DockTint {
  /// The theme's own surface colour, light or dark with the appearance.
  theme,

  /// The surface warmed with the accent, which follows the wallpaper.
  accent,

  /// A grey of the user's own depth, from black to white.
  custom,
}

/// Whether the dock floats as a capsule or lies along its edge as a bar.
enum DockShape { floating, bar }

/// What colour the running markers take.
enum DockMarkerColor {
  /// The accent under the application in front, a quiet ink under the rest.
  auto,

  /// Always the accent.
  accent,

  /// Always the text ink, as macOS draws them.
  ink,
}

/// How the dock's capsule is drawn and spaced: one immutable value, so a
/// layout scheme or a theme preset can replace all of it at once.
///
/// Each look of the shell has a preset here. What the user changed is kept as
/// a map of overrides on top of the preset in force, so switching the look
/// moves every value the user left alone and keeps the ones they set.
///
/// No Flutter import, so the rules run as an ordinary Dart test.
class DockLook {
  const DockLook({
    required this.blur,
    required this.opacity,
    required this.tint,
    required this.tintShade,
    required this.radius,
    required this.border,
    required this.borderWidth,
    required this.brightBorder,
    required this.shadow,
    required this.padding,
    required this.gap,
    required this.edgeMargin,
    required this.shape,
    required this.markerColor,
    required this.magnifyRange,
    this.accentBorder = false,
    this.endInset = 5,
    this.blurFull,
  });

  /// Denial's own capsule: the system's blur at full strength and the
  /// system's panel opacity, a hairline, no shadow.
  static const DockLook denial = DockLook(
    blur: 1,
    opacity: null,
    tint: DockTint.theme,
    tintShade: 0.12,
    radius: 20,
    border: true,
    borderWidth: 1,
    brightBorder: false,
    shadow: 0,
    padding: 5,
    gap: 8,
    edgeMargin: 10,
    shape: DockShape.floating,
    markerColor: DockMarkerColor.auto,
    magnifyRange: 140,
  );

  /// The macOS Dock, as measured on macOS: a blur of 1.6 logical pixels
  /// that leaves the wallpaper's shapes readable, corners of 22, no shadow,
  /// 5 from the edge. The fill, the rim and the saturation are the dock
  /// material of the look, one for each appearance; [opacity] here is the
  /// dark one's, which the light appearance replaces with its own until the
  /// user sets one.
  static const DockLook mac = DockLook(
    blur: macBlurSigma / shellBlurSigma,
    blurFull: shellBlurSigma,
    opacity: 0.36,
    tint: DockTint.theme,
    tintShade: 0.12,
    radius: 22,
    border: true,
    borderWidth: 1,
    brightBorder: true,
    shadow: 0,
    padding: 5,
    gap: 8,
    edgeMargin: 5,
    shape: DockShape.floating,
    markerColor: DockMarkerColor.ink,
    magnifyRange: 140,
  );

  /// The blur of the macOS Dock, in logical pixels.
  static const double macBlurSigma = 1.6;

  /// The sigma of the shell's blur at the level it starts with. The macOS
  /// preset counts [blur] against this, so a value kept from when it was a
  /// share of the shell's blur draws what it drew then on every level but
  /// the strongest, and no longer moves when the user changes level.
  static const double shellBlurSigma = 6;

  /// The preset for the shell look called [styleId]; Denial's for any other.
  static DockLook preset(String? styleId) => styleId == 'mac' ? mac : denial;

  /// [base] as a look of the shell draws its panels: the line around the
  /// capsule as thick as the look's and in the accent when the look says
  /// so, a solid fill with nothing blurred behind it for a look of opaque
  /// panels, and as much of the shadow as the look casts. A look that
  /// changes none of this gets [base] itself, so Denial and macOS keep
  /// their presets value for value.
  static DockLook styled(
    DockLook base, {
    double borderWidth = 1,
    bool accentBorder = false,
    bool opaque = false,
    double shadow = 1,
  }) {
    if (borderWidth == 1 && !accentBorder && !opaque && shadow == 1) {
      return base;
    }
    return DockLook(
      blur: opaque ? 0 : base.blur,
      opacity: opaque ? 1 : base.opacity,
      tint: base.tint,
      tintShade: base.tintShade,
      radius: base.radius,
      border: base.border,
      borderWidth: (base.borderWidth * borderWidth)
          .clamp(minBorderWidth, maxBorderWidth)
          .toDouble(),
      brightBorder: base.brightBorder && !accentBorder,
      // An opaque plate with no blur needs something to lift it off the
      // windows; a look that casts shadows gives the capsule a soft one.
      shadow: ((opaque && base.shadow == 0 ? 0.3 : base.shadow) * shadow)
          .clamp(minShadow, maxShadow)
          .toDouble(),
      padding: base.padding,
      gap: base.gap,
      edgeMargin: base.edgeMargin,
      shape: base.shape,
      markerColor: base.markerColor,
      magnifyRange: base.magnifyRange,
      accentBorder: accentBorder,
      endInset: base.endInset,
      blurFull: base.blurFull,
    );
  }

  /// [base] spaced as a look's metrics ask: the room around the icons,
  /// between them and at the two ends of the row. Everything the capsule is
  /// drawn with stays, and a spacing that changes nothing gets [base]
  /// itself.
  static DockLook fitted(
    DockLook base, {
    required double padding,
    required double gap,
    required double endInset,
  }) {
    if (padding == base.padding &&
        gap == base.gap &&
        endInset == base.endInset) {
      return base;
    }
    return DockLook(
      blur: base.blur,
      opacity: base.opacity,
      tint: base.tint,
      tintShade: base.tintShade,
      radius: base.radius,
      border: base.border,
      borderWidth: base.borderWidth,
      brightBorder: base.brightBorder,
      shadow: base.shadow,
      padding: padding.clamp(minPadding, maxPadding).toDouble(),
      gap: gap.clamp(minGap, maxGap).toDouble(),
      edgeMargin: base.edgeMargin,
      shape: base.shape,
      markerColor: base.markerColor,
      magnifyRange: base.magnifyRange,
      accentBorder: base.accentBorder,
      endInset: endInset,
      blurFull: base.blurFull,
    );
  }

  // The ranges the settings offer. A value from a file is clamped into them.
  static const double minBlur = 0, maxBlur = 1, blurStep = 0.05;
  static const double minOpacity = 0, maxOpacity = 1, opacityStep = 0.05;
  static const double minShade = 0, maxShade = 1, shadeStep = 0.05;
  static const double minRadius = 0, maxRadius = 40, radiusStep = 1;
  static const double minBorderWidth = 0.5,
      maxBorderWidth = 3,
      borderWidthStep = 0.5;
  static const double minShadow = 0, maxShadow = 1, shadowStep = 0.05;
  static const double minPadding = 2, maxPadding = 20, paddingStep = 1;
  static const double minGap = 0, maxGap = 20, gapStep = 1;
  static const double minEdgeMargin = 0, maxEdgeMargin = 40, edgeMarginStep = 1;
  static const double minMagnifyRange = 80,
      maxMagnifyRange = 240,
      magnifyRangeStep = 10;

  /// The keys the overrides are stored under.
  static const String blurKey = 'blur';
  static const String opacityKey = 'opacity';
  static const String tintKey = 'tint';
  static const String tintShadeKey = 'tintShade';
  static const String radiusKey = 'radius';
  static const String borderKey = 'border';
  static const String borderWidthKey = 'borderWidth';
  static const String shadowKey = 'shadow';
  static const String paddingKey = 'padding';
  static const String gapKey = 'gap';
  static const String edgeMarginKey = 'edgeMargin';
  static const String shapeKey = 'shape';
  static const String markerColorKey = 'markerColor';
  static const String magnifyRangeKey = 'magnifyRange';

  /// Strength of the backdrop blur: a share of [blurFull], or of the
  /// system's own blur where that is null.
  final double blur;

  /// The sigma, in logical pixels, that a [blur] of 1 stands for. Null
  /// follows the system's blur, whatever level the user chose. Part of the
  /// preset; the settings do not offer it.
  final double? blurFull;

  /// The blur in logical pixels, for a preset that counts in them.
  double? get blurSigma {
    final full = blurFull;
    return full == null ? null : blur * full;
  }

  /// Opacity of the fill. Null follows the system's panel opacity, so the
  /// dock is as clear or as solid as every other panel.
  final double? opacity;

  final DockTint tint;

  /// The grey a [DockTint.custom] fill uses: 0 black, 1 white.
  final double tintShade;

  /// Corner radius of a floating capsule, before the look's corner scale.
  final double radius;

  final bool border;
  final double borderWidth;

  /// A rim of white rather than the theme's hairline. Part of the preset; the
  /// settings do not offer it on its own.
  final bool brightBorder;

  /// A rim in the accent, as a look that outlines its panels draws them.
  /// Part of the preset, like [brightBorder].
  final bool accentBorder;

  /// How strong the shadow under the capsule is; zero draws none.
  final double shadow;

  /// Space between the capsule's long edges and the icons.
  final double padding;

  /// Space between two icons.
  final double gap;

  /// Distance from the screen edge to a floating capsule.
  final double edgeMargin;

  final DockShape shape;
  final DockMarkerColor markerColor;

  /// How far along the row the pointer's magnification reaches.
  final double magnifyRange;

  /// How much looser the two ends of the row are than [padding]. Part of
  /// the preset; the settings do not offer it on its own.
  final double endInset;

  /// Space at the two ends of the row.
  double get endPadding => padding + endInset;

  /// A bar lies on the edge it belongs to.
  double get effectiveEdgeMargin => shape == DockShape.bar ? 0 : edgeMargin;

  /// A bar has square corners.
  double get effectiveRadius => shape == DockShape.bar ? 0 : radius;

  /// [base] with the overrides a settings file holds. A missing key, or a
  /// value of the wrong kind, keeps the preset's; a number is clamped into
  /// its range. Keys this build does not know are ignored here and kept by
  /// [cleaned].
  static DockLook resolve(DockLook base, Map<String, Object?> overrides) {
    double number(String key, double fallback, double min, double max) {
      final value = overrides[key];
      return value is num && value.isFinite
          ? value.toDouble().clamp(min, max).toDouble()
          : fallback;
    }

    T named<T extends Enum>(String key, List<T> values, T fallback) {
      final value = overrides[key];
      for (final candidate in values) {
        if (candidate.name == value) return candidate;
      }
      return fallback;
    }

    final opacity = overrides[opacityKey];
    final border = overrides[borderKey];
    return DockLook(
      blur: number(blurKey, base.blur, minBlur, maxBlur),
      opacity: opacity is num && opacity.isFinite
          ? opacity.toDouble().clamp(minOpacity, maxOpacity).toDouble()
          : base.opacity,
      tint: named(tintKey, DockTint.values, base.tint),
      tintShade: number(tintShadeKey, base.tintShade, minShade, maxShade),
      radius: number(radiusKey, base.radius, minRadius, maxRadius),
      border: border is bool ? border : base.border,
      borderWidth: number(
        borderWidthKey,
        base.borderWidth,
        minBorderWidth,
        maxBorderWidth,
      ),
      brightBorder: base.brightBorder,
      accentBorder: base.accentBorder,
      endInset: base.endInset,
      blurFull: base.blurFull,
      shadow: number(shadowKey, base.shadow, minShadow, maxShadow),
      padding: number(paddingKey, base.padding, minPadding, maxPadding),
      gap: number(gapKey, base.gap, minGap, maxGap),
      edgeMargin: number(
        edgeMarginKey,
        base.edgeMargin,
        minEdgeMargin,
        maxEdgeMargin,
      ),
      shape: named(shapeKey, DockShape.values, base.shape),
      markerColor: named(
        markerColorKey,
        DockMarkerColor.values,
        base.markerColor,
      ),
      magnifyRange: number(
        magnifyRangeKey,
        base.magnifyRange,
        minMagnifyRange,
        maxMagnifyRange,
      ),
    );
  }

  /// The overrides a settings file holds, as this build keeps them: a map
  /// with string keys, every entry left as it was written. Anything else
  /// reads as no overrides.
  static Map<String, Object?> cleaned(Object? stored) {
    if (stored is! Map) return const {};
    return Map.unmodifiable({
      for (final entry in stored.entries)
        if (entry.key is String) entry.key as String: entry.value,
    });
  }

  /// [overrides] with [key] set to [value], or without it when [value] is
  /// null, which is how one setting goes back to its preset.
  static Map<String, Object?> withOverride(
    Map<String, Object?> overrides,
    String key,
    Object? value,
  ) {
    final next = {...overrides};
    if (value == null) {
      next.remove(key);
    } else {
      next[key] = value;
    }
    return Map.unmodifiable(next);
  }
}
