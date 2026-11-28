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
  /// mirroring SDK `_glassConfig` (`shell_theme.dart:593-627`) and clamping all
  /// shader parameters to official [ShellGlassConfiguration] bounds so system
  /// refraction, thickness, lighting, and quality changes take effect live with
  /// zero Stagecraft fallbacks.
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
      KitGlassPreset.clear => 1.05,
      KitGlassPreset.tinted => 0.85,
      KitGlassPreset.custom => kitGlassRefraction.value,
    };
    final s = strength.clamp(0.0, 1.0).toDouble();
    final refraction = (g.refraction * s * refractionScale).clamp(
      ShellGlassConfiguration.minimumRefraction,
      ShellGlassConfiguration.maximumRefraction,
    );
    final tintBoost = switch (preset) {
      KitGlassPreset.clear => 0.40,
      KitGlassPreset.tinted => 1.25,
      _ => 1.0,
    };
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
      refraction: refraction,
      dispersion: g.dispersion,
      saturation: kitSaturate.value ? 1 + (g.saturation - 1) * s : 1,
      tint: theme.kitAccent,
      tintStrength: (g.tintStrength * s * tintBoost).clamp(
        ShellGlassConfiguration.minimumTintStrength,
        ShellGlassConfiguration.maximumTintStrength,
      ),
      brightness: g.brightness * s,
      lightAngle: g.lightAngle * math.pi / 180,
      lightIntensity: (g.lightIntensity * s).clamp(
        ShellGlassConfiguration.minimumLightIntensity,
        ShellGlassConfiguration.maximumLightIntensity,
      ),
      edgeStrength: (g.edgeStrength * s).clamp(
        ShellGlassConfiguration.minimumEdgeStrength,
        ShellGlassConfiguration.maximumEdgeStrength,
      ),
      bevelWidthScale: g.bevelWidthScale,
      refractionDepthScale: g.refractionDepthScale,
      rimWidth: g.rimWidth,
      rimFalloff: g.rimFalloff,
      oppositeLightStrength: g.oppositeLightStrength,
    );
  }

  /// Target fill alpha for a [KitSurfaceMode.liquidGlass] surface, derived from
  /// Denial's native `theme.glass.opacity` (`effectivePanelOpacity`) and the
  /// active [KitGlassPreset] so macOS Liquid Glass stays crystal-clear rather
  /// than milky-opaque while still keeping high-minOpacity windows legible.
  static double liquidGlassOpacity(
    ShellThemeData theme, {
    required KitTier tier,
    double minOpacity = 0,
  }) {
    final sysAlpha = theme.glass.opacity.clamp(0.12, 0.72).toDouble();
    final dock = tier == KitTier.dock;
    final preset = kitGlassPreset.value;
    final double target = switch (preset) {
      KitGlassPreset.system => dock ? (sysAlpha * 0.65).clamp(0.10, 0.34) : sysAlpha,
      KitGlassPreset.clear =>
        dock ? (sysAlpha * 0.45).clamp(0.08, 0.22) : (sysAlpha * 0.58).clamp(0.12, 0.30),
      KitGlassPreset.tinted =>
        dock ? (sysAlpha * 1.10).clamp(0.28, 0.48) : (sysAlpha * 1.45).clamp(0.46, 0.68),
      KitGlassPreset.custom =>
        dock ? (kitGlassOpacity.value * 0.65).clamp(0.08, 0.75) : kitGlassOpacity.value,
    };
    return math.max(minOpacity, target);
  }

  /// Shared backdrop resolution used by [KitGlass], `NcPlate`, and
  /// `BarGroundLayer` so all surfaces obey the exact same five-mode material
  /// pipeline, [KitScaleScope] sigma compensation, and Stagecraft fast path.
  static ({KitBlurPlan plan, ImageFilterConfig? directConfig}) resolveBackdrop(
    BuildContext context, {
    required KitMaterial material,
    required double radius,
    required KitTier tier,
    KitSurfaceMode? surfaceMode,
    double blurScale = 1,
  }) {
    final theme = context.shellTheme;
    final style = KitStyle.of(context);
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
    if (!plan.blurs || !plan.direct || plan.mode == KitSurfaceMode.solid) {
      return (plan: plan, directConfig: null);
    }
    final effectiveScale = KitScaleScope.effectiveOf(context);
    final sigma =
        plan.mode == KitSurfaceMode.glass &&
            material.sigma != null &&
            effectiveScale > 1e-3
        ? plan.sigma / effectiveScale
        : plan.sigma;
    final ImageFilterConfig config = switch (plan.mode) {
      KitSurfaceMode.liquidGlass => liquidGlassFilterFor(
        theme,
        sigma: sigma,
        cornerRadius: radius,
        strength: plan.strength,
      ),
      KitSurfaceMode.blur => filterFor(
        theme,
        sigma: sigma,
        saturation: 1.0,
        cornerRadius: radius,
      ),
      _ => filterFor(
        theme,
        sigma: sigma,
        saturation: material.saturation,
        cornerRadius: radius,
      ),
    };
    return (plan: plan, directConfig: config);
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
    // Keep foreground controls out of the backdrop filter's intermediate layer
    // (matching Denial SDK's ShellBackdropBlur.separateChild guidance).
    final separate = this.separate ?? true;
    final resolved = resolveBackdrop(
      context,
      material: material,
      radius: radius,
      tier: tier,
      surfaceMode: surfaceMode,
      blurScale: blurScale,
    );
    final plan = resolved.plan;
    var tone = fill;
    if (tone == null) {
      tone = kitToneColor(material.fill, theme, style);
      if (tone.a < minOpacity) tone = tone.withValues(alpha: minOpacity);
    }
    // Under liquidGlass, align backing fill alpha with Denial's native
    // `theme.glass.opacity` and active Liquid Glass preset (System / Clear /
    // Tinted / Custom) so the Vulkan refractive shader shines through cleanly.
    if (plan.mode == KitSurfaceMode.liquidGlass && blur && minOpacity < 0.85) {
      final preset = kitGlassPreset.value;
      final cap = liquidGlassOpacity(theme, tier: tier, minOpacity: minOpacity);
      if (preset == KitGlassPreset.custom || preset == KitGlassPreset.tinted) {
        tone = tone.withValues(alpha: cap);
      } else if (tone.a > cap) {
        tone = tone.withValues(alpha: cap);
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
    // Liquid Glass draws its own refractive specular rim in the Vulkan shader;
    // suppress duplicate plugin borders unless the user zeroed edgeStrength.
    final suppressRims = filtered && plan.mode == KitSurfaceMode.liquidGlass;
    final pureBlur = filtered && plan.mode == KitSurfaceMode.blur;
    final darkSurface = theme.brightness == Brightness.dark;
    final outer = suppressRims || pureBlur
        ? null
        : _lineOf(material.outer, theme, style);
    final inner = suppressRims
        ? (theme.glass.edgeStrength < 0.1
              ? _lineOf(
                  KitLine(
                    KitTone(KitTone.white, darkSurface ? 0.12 : 0.24),
                    width: 0.75,
                  ),
                  theme,
                  style,
                )
              : null)
        : pureBlur
        ? _lineOf(
            const KitLine(KitTone.of(KitRole.hairline), width: 1),
            theme,
            style,
          )
        : _lineOf(material.inner, theme, style);
    final corners = BorderRadius.circular(radius);
    // Vulkan Liquid Glass renders circular RRect lenses natively via
    // ImageFilterConfig.glass; clipping with ClipRRect instead of a 68-vertex
    // ClipPath matches the shader bevel and avoids Stagecraft split_draws.
    final useContinuous =
        material.continuous && !(filtered && plan.mode == KitSurfaceMode.liquidGlass);
    Widget under = DecoratedBox(
      decoration: ShapeDecoration(
        // Always use a hardware RRect shape for soft blurred drop shadows so
        // Impeller uses its analytical RRect shadow fast path.
        shape: RoundedRectangleBorder(borderRadius: corners),
        shadows: shadows,
      ),
      child: outer == null
          ? null
          : CustomPaint(
              painter: _OuterLinePainter(
                radius: radius,
                continuous: useContinuous,
                line: outer,
              ),
            ),
    );
    if (fade != null) under = FadeTransition(opacity: fade, child: under);

    final Widget surface = CustomPaint(
      painter: _SurfacePainter(
        radius: radius,
        continuous: useContinuous,
        fill: tone,
        line: inner,
      ),
      child: child ?? const SizedBox.expand(),
    );
    Widget plate;
    if (filtered && plan.direct && resolved.directConfig != null) {
      final config = resolved.directConfig!;
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
      if (!useContinuous) {
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
        if (useContinuous)
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
    final line = this.line;
    if (!continuous && line == null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(radius)),
        Paint()..color = fill,
      );
      return;
    }
    final shape = _shape(rect, radius, continuous);
    canvas.drawPath(shape, Paint()..color = fill);
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
