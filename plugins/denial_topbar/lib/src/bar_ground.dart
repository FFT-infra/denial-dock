import 'package:denial_flutter_sdk/effects.dart';
import 'package:denial_flutter_sdk/theme.dart';
import 'package:denial_shell_kit/kit_style.dart';
import 'package:flutter/widgets.dart';

import 'bar_segments.dart';
import 'bar_settings.dart';
import 'bar_tokens.dart';

/// The strip behind the bar content.
///
/// macOS 27 draws no background by default: titles and status items sit
/// straight on the wallpaper, and the system picks black or white ink from
/// what is behind them [S30][S29]. Turning the background on adds a veil
/// tinted to the appearance, never to the wallpaper, which is what shell27's
/// `#1E1E1E` / `#F5F5F7` pair does. `glass` is the compositor's backdrop blur
/// for people who want the Tahoe look back.
///
/// With no veil at all the type can still land on a busy wallpaper, so a
/// short gradient feather sits under the strip exactly like shell27's
/// `barFeather`: 30% at the top edge fading to nothing 14 below.
class BarGroundLayer extends StatelessWidget {
  const BarGroundLayer({
    required this.settings,
    required this.borderRadius,
    required this.backdrop,
    required this.child,
    this.edges,
    this.fill,
    super.key,
  });

  final BarSettings settings;
  final BorderRadius borderRadius;

  /// Dominant wallpaper colour, used to pick the plate and the ink.
  final Color backdrop;

  /// Cuts the plate's two sides into points instead of rounding its corners.
  final BarSegmentEdges? edges;

  /// The plate's colour when it is not the bar's own, without its opacity.
  final Color? fill;
  final Widget child;

  static double luminanceOf(Color color) =>
      color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722;

  static bool isDark(Color color) =>
      luminanceOf(color) <= BarTokens.plateLuminanceThreshold;

  /// The veil matches the wallpaper's own lightness: a dark wallpaper gets
  /// the dark neutral, a light one the light neutral. shell27 `content`.
  static Color plateFor(Color backdrop) => isDark(backdrop)
      ? const Color(BarTokens.plateDark)
      : const Color(BarTokens.plateLight);

  /// The plate's colour before its opacity, from where the settings say it
  /// comes.
  static Color baseFor(
    Color backdrop,
    BarSettings settings,
    ShellThemeData theme,
  ) => switch (settings.groundTint) {
    BarGroundTint.wallpaper => plateFor(backdrop),
    BarGroundTint.panel => theme.colors.panelBackground.withValues(alpha: 1),
    BarGroundTint.accent =>
      Color.lerp(plateFor(backdrop), theme.kitAccent, 0.22) ??
          plateFor(backdrop),
  };

  /// The second colour of a bar whose segments alternate.
  static Color alternateFor(Color base, ShellThemeData theme) =>
      Color.lerp(base, theme.kitAccent, 0.62) ?? base;

  /// Black or white, whichever reads on [ground].
  static Color inkOn(Color ground) =>
      isDark(ground) ? const Color(0xffffffff) : const Color(0xff000000);

  /// The ink the type is drawn in.
  ///
  /// macOS flips black/white against what sits under the bar, so this reads
  /// the backdrop when there is no veil and the veil's own lightness when
  /// there is one.
  static Color inkFor(
    Color backdrop,
    BarSettings settings,
    ShellThemeData theme,
  ) => inkOn(
    settings.ground == BarGround.none
        ? backdrop
        : baseFor(backdrop, settings, theme),
  );

  @override
  Widget build(BuildContext context) {
    final ground = settings.ground;
    if (ground == BarGround.none) return child;
    final theme = context.shellTheme;
    final base = fill ?? baseFor(backdrop, settings, theme);
    final colour = base.withValues(alpha: settings.groundOpacity);
    final dark = isDark(base);
    final line = settings.borderColour == BarBorderColour.accent
        ? theme.kitAccent
        : dark
        ? const Color(0xffffffff).withValues(alpha: 0.12)
        : const Color(0xff000000).withValues(alpha: 0.08);

    final edges = this.edges;
    if (edges != null) {
      final Widget plate = CustomPaint(
        painter: _SegmentPainter(
          edges: edges,
          fill: colour,
          line: line,
          lineWidth: settings.borderWidth,
        ),
        child: child,
      );
      if (ground != BarGround.glass) return plate;
      return ClipPath(
        clipper: _SegmentClipper(edges),
        child: ShellBackdropBlur(blendMode: BlendMode.srcOver, child: plate),
      );
    }

    final Widget plate = DecoratedBox(
      decoration: BoxDecoration(
        color: colour,
        borderRadius: borderRadius,
        border: settings.borderWidth > 0
            ? Border.all(color: line, width: settings.borderWidth)
            : null,
      ),
      child: child,
    );
    if (ground != BarGround.glass) return plate;
    return ShellBackdropBlur(
      borderRadius: borderRadius,
      blendMode: BlendMode.srcOver,
      child: plate,
    );
  }
}

Path _segmentPath(Size size, BarSegmentEdges edges) {
  final points = barSegmentOutline(
    width: size.width,
    height: size.height,
    depth: barArrowDepth(size.height),
    left: edges.left,
    right: edges.right,
  );
  final path = Path()..moveTo(points.first.x, points.first.y);
  for (final point in points.skip(1)) {
    path.lineTo(point.x, point.y);
  }
  return path..close();
}

class _SegmentPainter extends CustomPainter {
  const _SegmentPainter({
    required this.edges,
    required this.fill,
    required this.line,
    required this.lineWidth,
  });

  final BarSegmentEdges edges;
  final Color fill;
  final Color line;
  final double lineWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final path = _segmentPath(size, edges);
    canvas.drawPath(path, Paint()..color = fill);
    if (lineWidth <= 0) return;
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = lineWidth
        ..strokeJoin = StrokeJoin.round
        ..color = line,
    );
  }

  @override
  bool shouldRepaint(_SegmentPainter old) =>
      old.edges != edges ||
      old.fill != fill ||
      old.line != line ||
      old.lineWidth != lineWidth;
}

class _SegmentClipper extends CustomClipper<Path> {
  const _SegmentClipper(this.edges);

  final BarSegmentEdges edges;

  @override
  Path getClip(Size size) => _segmentPath(size, edges);

  @override
  bool shouldReclip(_SegmentClipper oldClipper) => oldClipper.edges != edges;
}

/// The soft fade shell27 paints when the bar is completely clear.
///
/// The tint is the veil colour, not the ink: a white wash sits under black
/// type and a black wash under white type, which is what shell27's `barFeather`
/// does. It is skipped whenever a veil already does that job.
class BarFeather extends StatelessWidget {
  const BarFeather({
    required this.tint,
    required this.height,
    required this.visible,
    super.key,
  });

  final Color tint;
  final double height;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    return IgnorePointer(
      child: SizedBox(
        height: height + 14,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                tint.withValues(alpha: 0.30),
                tint.withValues(alpha: 0.20),
                tint.withValues(alpha: 0.08),
                tint.withValues(alpha: 0.02),
                tint.withValues(alpha: 0),
              ],
              stops: const <double>[0.0, 0.35, 0.65, 0.85, 1.0],
            ),
          ),
        ),
      ),
    );
  }
}
