import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:denial_flutter_sdk/effects.dart';
import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/widgets.dart';

import 'continuous_corners.dart';
import 'kit_material.dart';
import 'kit_style.dart';

/// The material of [tier] in the look and the appearance in force.
KitMaterial kitMaterialOf(BuildContext context, KitTier tier) => KitStyle.of(
  context,
).materials.tier(tier).of(dark: context.shellTheme.brightness == Brightness.dark);

/// [tone] as a colour, under [theme] and [style].
Color kitToneColor(KitTone tone, ShellThemeData theme, KitStyle style) {
  final alpha = tone.alpha;
  final Color base;
  switch (tone.role) {
    case null:
      return Color(0xff000000 | tone.rgb).withValues(alpha: alpha ?? 1);
    case KitRole.panel:
      base = style.panelFill(theme.panelColor(theme.colors.panelBackground));
    case KitRole.surface:
      base = theme.panelColor(theme.colors.surfaceContainer);
    case KitRole.border:
      base = style.border(theme);
    case KitRole.hairline:
      base = theme.colors.hairline;
    case KitRole.shadow:
      base = theme.colors.shadow;
  }
  return alpha == null ? base : base.withValues(alpha: alpha);
}

typedef _Line = ({
  Color color,
  double width,
  KitEdges edges,
  double tail,
  double reach,
});

_Line? _lineOf(KitLine? line, ShellThemeData theme, KitStyle style) {
  if (line == null) return null;
  final width = line.width ?? style.borderWidth;
  if (width <= 0) return null;
  return (
    color: kitToneColor(line.tone, theme, style),
    width: width,
    edges: line.edges,
    tail: line.tail,
    reach: line.reach,
  );
}

/// A [KitMaterial] drawn: the shadow and the outer line under it, the clip,
/// the backdrop blurred and saturated, the fill, and the inner line.
///
/// How the backdrop is filtered follows [KitBlurMath.plan]. Where the plan
/// leaves the blur to the shell, this is the shell's own [ShellBackdropBlur]
/// and nothing differs from a surface the shell draws. Where the material
/// names a sigma and the shell is in its blur mode, the same engine filter
/// is built here at that sigma, with the sampling quality of the blur level
/// the user chose, and the saturation is composed into it so the screen is
/// still read back once. With transparency turned off nothing is filtered.
class KitGlass extends StatelessWidget {
  const KitGlass({
    required this.material,
    required this.radius,
    this.child,
    this.fill,
    this.minOpacity = 0,
    this.elevation = 1,
    this.blurScale = 1,
    this.blur = true,
    this.grouped = false,
    this.fade,
    this.separate,
    this.tier = KitTier.popover,
    this.surfaceMode,
    super.key,
  });

  final KitMaterial material;

  /// The corner radius as drawn, already through the look's scale.
  final double radius;
  final Widget? child;

  /// Replaces the material's fill, opacity included.
  final Color? fill;

  /// Floor for the opacity of the material's own fill.
  final double minOpacity;

  /// Scales a shadow that follows the look.
  final double elevation;

  /// A share of the material's blur.
  final double blurScale;

  /// False draws the fill alone, no less solid than the material's
  /// [KitMaterial.solid], for a surface that is moving: nothing reads the
  /// screen back then.
  final bool blur;

  /// Shares one backdrop with the other grouped surfaces under the nearest
  /// [BackdropGroup]. They must not overlap, and must be of one material.
  final bool grouped;

  /// Fades the shadow, the backdrop and the content together.
  final Animation<double>? fade;

  /// Whether the fill and the content are painted after the backdrop, out
  /// of the filter's own layer. Unless said, a steady surface does and a
  /// fading one carries them through the fade inside it.
  final bool? separate;

  /// Surface tier used to scale [KitSurfaceMode.liquidGlass] thickness/blur.
  final KitTier tier;

  /// Optional per-surface override; null reads the active [KitStyle.surfaceMode].
  final KitSurfaceMode? surfaceMode;

  /// The filter for a Liquid Glass surface driven by Denial's `theme.glass`,
  /// mirroring SDK `_glassConfig` so system refraction/thickness/lighting/quality
  /// changes take effect live with zero Stagecraft fallbacks.
  static ImageFilterConfig liquidGlassFilterFor(
    ShellThemeData theme, {
    required double sigma,
    required double cornerRadius,
    double strength = 1.0,
  }) {
    final g = theme.glass;
    final preset = kitGlassPreset.value;
    final refractionScale = switch (preset) {
      KitGlassPreset.system => 1.0,
      KitGlassPreset.clear => 1.18,
      KitGlassPreset.tinted => 0.88,
      KitGlassPreset.custom => kitGlassRefraction.value,
    };
    final s = (strength * refractionScale).clamp(0.0, 1.5).toDouble();
    final dark = theme.brightness == Brightness.dark;
    final tintColor = preset == KitGlassPreset.clear
        ? (dark ? const Color(0xff1e1e26) : const Color(0xffffffff))
        : theme.kitAccent;
    final tintBoost = switch (preset) {
      KitGlassPreset.clear => 0.30,
      KitGlassPreset.tinted => 1.30,
      _ => 1.0,
    };
    final dispersion = preset == KitGlassPreset.clear
        ? math.max(g.dispersion, 0.22)
        : g.dispersion;
    final corner = cornerRadius > 0
        ? Radius.circular(cornerRadius)
        : Radius.zero;
    return ImageFilterConfig.glass(
      sigmaX: sigma,
      sigmaY: sigma,
      topLeft: corner,
      topRight: corner,
      bottomRight: corner,
      bottomLeft: corner,
      downsampleScale: g.quality,
      thickness: g.thickness,
      refraction: g.refraction * s,
      dispersion: dispersion,
      saturation: kitSaturate.value ? 1 + (g.saturation - 1) * strength : 1,
      tint: tintColor,
      tintStrength: (g.tintStrength * strength * tintBoost).clamp(0.0, 1.0),
      brightness: g.brightness * strength,
      lightAngle: g.lightAngle * math.pi / 180,
      lightIntensity:
          (g.lightIntensity *
                  strength *
                  (preset == KitGlassPreset.clear ? 1.18 : 1.0))
              .clamp(0.0, 2.0),
      edgeStrength:
          (g.edgeStrength *
                  strength *
                  (preset == KitGlassPreset.clear ? 1.12 : 1.0))
              .clamp(0.0, 2.0),
      bevelWidthScale: g.bevelWidthScale,
      refractionDepthScale: g.refractionDepthScale,
      rimWidth: g.rimWidth,
      rimFalloff: g.rimFalloff,
      oppositeLightStrength: g.oppositeLightStrength,
    );
  }

  /// The filter for a blur or measured glass the kit carries out itself.
  static ImageFilterConfig filterFor(
    ShellThemeData theme, {
    required double sigma,
    required double saturation,
    double cornerRadius = 0,
  }) {
    if (saturation == 1 || !kitSaturate.value) {
      return ImageFilterConfig.blur(
        sigmaX: sigma,
        sigmaY: sigma,
        tileMode: ui.TileMode.clamp,
        downsampleScale: theme.backdropBlurDownsampleScale,
      );
    }
    final corner = cornerRadius > 0
        ? Radius.circular(cornerRadius)
        : Radius.zero;
    return ImageFilterConfig.glass(
      sigmaX: sigma,
      sigmaY: sigma,
      topLeft: corner,
      topRight: corner,
      bottomRight: corner,
      bottomLeft: corner,
      downsampleScale: theme.backdropBlurDownsampleScale,
      thickness: 0,
      refraction: 0,
      dispersion: 0,
      saturation: saturation,
      tint: const Color(0x00000000),
      tintStrength: 0,
      brightness: 0,
      lightAngle: 0,
      lightIntensity: 0,
      edgeStrength: 0,
      bevelWidthScale: 1,
      refractionDepthScale: 1,
      rimWidth: 0,
      rimFalloff: 1,
      oppositeLightStrength: 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final style = KitStyle.of(context);
    final material = this.material;
    final fade = this.fade;
    final separate = this.separate ?? fade == null;
    final glassMode = theme.transparencyMode == ShellTransparencyMode.glass;
    final requestedMode = surfaceMode ?? style.surfaceMode;
    final systemEnabled =
        theme.backdropBlurEnabled &&
        theme.transparencyMode != ShellTransparencyMode.off;
    final plan = KitBlurMath.plan(
      material,
      enabled: systemEnabled,
      glass: glassMode,
      base: requestedMode == KitSurfaceMode.liquidGlass || glassMode
          ? theme.glass.blurSigma
          : theme.backdropBlurSigma,
      scale: blurScale,
      mode: requestedMode,
      tier: tier,
    );
    var tone = fill;
    if (tone == null) {
      tone = kitToneColor(material.fill, theme, style);
      if (tone.a < minOpacity) tone = tone.withValues(alpha: minOpacity);
    }
    // Under liquidGlass, keep a clean translucent tint that never washes out
    // text on busy wallpapers while honouring Clear / Tinted / Custom presets.
    if (plan.mode == KitSurfaceMode.liquidGlass && blur && minOpacity < 0.85) {
      final preset = kitGlassPreset.value;
      final dark = theme.brightness == Brightness.dark;
      final dock = tier == KitTier.dock;
      final double targetCap = switch (preset) {
        KitGlassPreset.system => dock ? 0.28 : (dark ? 0.54 : 0.52),
        KitGlassPreset.clear => dock ? 0.20 : (dark ? 0.36 : 0.34),
        KitGlassPreset.tinted => dock ? 0.44 : (dark ? 0.68 : 0.66),
        KitGlassPreset.custom =>
          dock ? (kitGlassOpacity.value * 0.65).clamp(0.08, 0.80) : kitGlassOpacity.value,
      };
      final cap = math.max(minOpacity, targetCap);
      if (preset == KitGlassPreset.custom || preset == KitGlassPreset.tinted) {
        tone = tone.withValues(alpha: cap);
      } else if (tone.a > cap) {
        tone = tone.withValues(alpha: cap);
      } else if (!dock && preset == KitGlassPreset.system && tone.a < cap * 0.72) {
        // Keep floating panels legible over busy desktop widgets while
        // preserving full Liquid Glass refraction.
        tone = tone.withValues(alpha: cap * 0.85);
      }
    }
    final filtered =
        blur && plan.blurs && tone.a < 1 && plan.mode != KitSurfaceMode.solid;
    // Solid mode is fully opaque so sharp text behind the surface never bleeds
    // through; a moving/unblurred glass surface still raises fill to solid floor.
    if (plan.mode == KitSurfaceMode.solid) {
      tone = tone.withValues(alpha: 1);
    } else if (!filtered &&
        (!blur || (fill == null && material.fill.fixed)) &&
        tone.a < material.solid) {
      tone = tone.withValues(alpha: material.solid);
    }

    final cast = material.shadow;
    final lift = cast == null || !cast.byLook ? 1.0 : elevation;
    final strength = cast == null || !cast.byLook ? 1.0 : style.shadow;
    final shadowTone = cast == null ? null : kitToneColor(cast.tone, theme, style);
    final shadows = <BoxShadow>[
      if (cast != null && shadowTone != null && strength > 0)
        BoxShadow(
          color: shadowTone.withValues(alpha: shadowTone.a * strength),
          blurRadius: cast.blur * lift,
          offset: Offset(0, cast.dy * lift),
        ),
    ];
    // Liquid Glass draws its own refractive specular rim in the shader; add a
    // subtle crisp specular inner edge so floating modules separate cleanly
    // over light and dark wallpapers without double heavy strokes.
    final suppressRims = filtered && plan.mode == KitSurfaceMode.liquidGlass;
    final pureBlur = filtered && plan.mode == KitSurfaceMode.blur;
    final darkSurface = theme.brightness == Brightness.dark;
    final outer = suppressRims || pureBlur
        ? null
        : _lineOf(material.outer, theme, style);
    final inner = suppressRims
        ? _lineOf(
            KitLine(
              KitTone(KitTone.white, darkSurface ? 0.18 : 0.52),
              width: 0.75,
            ),
            theme,
            style,
          )
        : pureBlur
        ? _lineOf(
            const KitLine(KitTone.of(KitRole.hairline), width: 1),
            theme,
            style,
          )
        : _lineOf(material.inner, theme, style);
    Widget under = DecoratedBox(
      decoration: ShapeDecoration(
        shape: material.continuous
            ? ContinuousCorners(radius: radius)
            : RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(radius),
              ),
        shadows: shadows,
      ),
      child: outer == null
          ? null
          : CustomPaint(
              painter: _OuterLinePainter(
                radius: radius,
                continuous: material.continuous,
                line: outer,
              ),
            ),
    );
    if (fade != null) under = FadeTransition(opacity: fade, child: under);

    final Widget surface = CustomPaint(
      painter: _SurfacePainter(
        radius: radius,
        continuous: material.continuous,
        fill: tone,
        line: inner,
      ),
      child: child ?? const SizedBox.expand(),
    );
    final corners = BorderRadius.circular(radius);
    Widget plate;
    if (filtered && plan.direct) {
      final effectiveScale = KitScaleScope.effectiveOf(context);
      final sigma = plan.mode == KitSurfaceMode.glass &&
              material.sigma != null &&
              effectiveScale > 1e-3
          ? plan.sigma / effectiveScale
          : plan.sigma;
      final ImageFilterConfig config;
      if (plan.mode == KitSurfaceMode.liquidGlass) {
        config = liquidGlassFilterFor(
          theme,
          sigma: sigma,
          cornerRadius: radius,
          strength: plan.strength,
        );
      } else {
        config = filterFor(
          theme,
          sigma: sigma,
          saturation:
              plan.mode == KitSurfaceMode.blur ? 1.0 : material.saturation,
          cornerRadius: radius,
        );
      }
      // Laid out as the shell's own backdrop is: a steady one replaces what
      // is behind it, a fading one blends over it.
      final inside = separate ? const SizedBox.expand() : surface;
      final mode = fade == null ? ui.BlendMode.src : ui.BlendMode.srcOver;
      final Widget backdrop = grouped
          ? BackdropFilter.grouped(
              filterConfig: config,
              blendMode: mode,
              child: inside,
            )
          : BackdropFilter(filterConfig: config, blendMode: mode, child: inside);
      Widget faded(Widget value) =>
          fade == null ? value : FadeTransition(opacity: fade, child: value);
      plate = separate
          ? Stack(
              fit: StackFit.passthrough,
              children: [
                Positioned.fill(child: faded(backdrop)),
                faded(surface),
              ],
            )
          : faded(backdrop);
      if (!material.continuous) {
        plate = ClipRRect(
          borderRadius: corners,
          clipBehavior: Clip.antiAlias,
          child: plate,
        );
      }
    } else {
      plate = ShellBackdropBlur(
        blur: filtered,
        grouped: grouped,
        strength: plan.strength.clamp(0.0, 1.0).toDouble(),
        separateChild: separate,
        borderRadius: corners,
        opacity: fade,
        child: surface,
      );
    }
    return Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(child: IgnorePointer(child: under)),
        if (material.continuous)
          ClipPath(
            clipper: ContinuousCornersClipper(radius: radius),
            child: plate,
          )
        else
          plate,
      ],
    );
  }
}

Path _shape(Rect rect, double radius, bool continuous) => continuous
    ? continuousRoundedRectPath(rect, radius)
    : (Path()..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius))));

/// Strokes [line] along the edge of [rect]: outside it, or wholly inside so
/// a clip to the shape does not thin it. A line on some sides only fades out
/// across the corners.
void _strokeLine(
  Canvas canvas,
  Rect rect,
  double radius,
  bool continuous,
  _Line line, {
  required bool outside,
}) {
  final half = line.width / 2;
  final paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = line.width;
  if (line.edges == KitEdges.all) {
    paint.color = line.color;
  } else {
    final wide = rect.width >= rect.height;
    final length = wide ? rect.width : rect.height;
    if (length <= 0) return;
    final corner = (math.max(radius, 1) / length).clamp(0.0, 0.5).toDouble();
    final clear = line.color.withValues(alpha: 0);
    final atEnd = line.edges == KitEdges.ends ? line.color : clear;
    final between = line.edges == KitEdges.ends ? clear : line.color;
    paint.shader = ui.Gradient.linear(
      wide ? rect.centerLeft : rect.topCenter,
      wide ? rect.centerRight : rect.bottomCenter,
      <Color>[atEnd, between, between, atEnd],
      <double>[0, corner, 1 - corner, 1],
    );
  }
  canvas.drawPath(
    _shape(
      outside ? rect.inflate(half) : rect.deflate(half),
      math.max(0, outside ? radius + half : radius - half),
      continuous,
    ),
    paint,
  );
}

class _OuterLinePainter extends CustomPainter {
  const _OuterLinePainter({
    required this.radius,
    required this.continuous,
    required this.line,
  });

  final double radius;
  final bool continuous;
  final _Line line;

  @override
  void paint(Canvas canvas, Size size) =>
      _strokeLine(canvas, Offset.zero & size, radius, continuous, line, outside: true);

  @override
  bool shouldRepaint(_OuterLinePainter old) =>
      old.radius != radius || old.continuous != continuous || old.line != line;
}

class _SurfacePainter extends CustomPainter {
  const _SurfacePainter({
    required this.radius,
    required this.continuous,
    required this.fill,
    required this.line,
  });

  final double radius;
  final bool continuous;
  final Color fill;
  final _Line? line;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final shape = _shape(rect, radius, continuous);
    canvas.drawPath(shape, Paint()..color = fill);
    final line = this.line;
    if (line == null) return;
    if (line.tail > 0 && line.reach > 0 && line.edges == KitEdges.topBottom) {
      // The glow behind a rim: from each long side inward.
      final wide = rect.width >= rect.height;
      final glow = line.color.withValues(alpha: line.tail);
      final clear = line.color.withValues(alpha: 0);
      canvas
        ..save()
        ..clipPath(shape);
      for (final far in const <bool>[false, true]) {
        final Rect band;
        final Offset from, to;
        if (wide) {
          final top = far ? rect.bottom - line.reach : rect.top;
          band = Rect.fromLTWH(rect.left, top, rect.width, line.reach);
          from = far ? band.bottomCenter : band.topCenter;
          to = far ? band.topCenter : band.bottomCenter;
        } else {
          final left = far ? rect.right - line.reach : rect.left;
          band = Rect.fromLTWH(left, rect.top, line.reach, rect.height);
          from = far ? band.centerRight : band.centerLeft;
          to = far ? band.centerLeft : band.centerRight;
        }
        canvas.drawRect(
          band,
          Paint()
            ..shader = ui.Gradient.linear(from, to, <Color>[glow, clear]),
        );
      }
      canvas.restore();
    }
    _strokeLine(canvas, rect, radius, continuous, line, outside: false);
  }

  @override
  bool shouldRepaint(_SurfacePainter old) =>
      old.radius != radius ||
      old.continuous != continuous ||
      old.fill != fill ||
      old.line != line;
}
