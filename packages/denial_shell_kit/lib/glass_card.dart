import 'dart:math' as math;

import 'package:denial_flutter_sdk/effects.dart';
import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/widgets.dart';

import 'continuous_corners.dart';
import 'kit_style.dart';

/// The card every popup of the dock and the top bar draws on: continuous
/// corners, backdrop blur, a hairline and one soft shadow, each as the look
/// in force has them.
class GlassCard extends StatelessWidget {
  const GlassCard({
    required this.radius,
    required this.child,
    this.fill,
    this.elevation = 1,
    this.minOpacity = 0,
    this.blurStrength = 1,
    this.fade,
    this.grouped = false,
    super.key,
  });

  /// The corner radius at the shell's normal roundness; where the look
  /// follows the shell, the card scales it.
  final double radius;

  /// The panel colour unless given.
  final Color? fill;
  final double elevation;

  /// Floor for the fill's opacity. A window of settings sits over other
  /// windows and needs more than a menu does to keep its text readable.
  final double minOpacity;
  final double blurStrength;

  /// Fades the shadow, the backdrop and the content together, for a card
  /// that appears with its layer.
  final Animation<double>? fade;

  /// Shares one backdrop with the other grouped cards under the nearest
  /// [BackdropGroup], for cards that sit side by side and move together.
  /// Every ungrouped card reads the screen back for itself.
  final bool grouped;
  final Widget child;

  static Color fillOf(ShellThemeData theme, {double minOpacity = 0}) {
    final fill = theme.panelColor(theme.colors.panelBackground);
    return fill.a < minOpacity ? fill.withValues(alpha: minOpacity) : fill;
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final style = KitStyle.of(context);
    final radius = style.radius(theme, this.radius);
    final fade = this.fade;
    final fill = style.panelFill(
      this.fill ?? fillOf(theme, minOpacity: minOpacity),
    );
    final Widget shadow = DecoratedBox(
      decoration: ShapeDecoration(
        shape: ContinuousCorners(radius: radius),
        shadows: [
          if (style.shadow > 0)
            BoxShadow(
              color: theme.colors.shadow.withValues(alpha: 0.30 * style.shadow),
              blurRadius: 36 * elevation,
              offset: Offset(0, 14 * elevation),
            ),
        ],
      ),
    );
    return Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: fade == null
                ? shadow
                : FadeTransition(opacity: fade, child: shadow),
          ),
        ),
        ClipPath(
          clipper: ContinuousCornersClipper(radius: radius),
          child: ShellBackdropBlur(
            blur: fill.a < 1,
            grouped: grouped,
            strength: blurStrength,
            // A fading backdrop carries its content through the fade.
            separateChild: fade == null,
            borderRadius: BorderRadius.circular(radius),
            opacity: fade,
            child: CustomPaint(
              painter: _CardPainter(
                radius: radius,
                fill: fill,
                line: style.border(theme),
                lineWidth: style.borderWidth,
              ),
              child: child,
            ),
          ),
        ),
      ],
    );
  }
}

class _CardPainter extends CustomPainter {
  const _CardPainter({
    required this.radius,
    required this.fill,
    required this.line,
    required this.lineWidth,
  });

  final double radius;
  final Color fill;
  final Color line;
  final double lineWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawPath(
      continuousRoundedRectPath(rect, radius),
      Paint()..color = fill,
    );
    if (lineWidth <= 0) return;
    // The line lies wholly inside the card, so the clip does not thin it.
    final half = lineWidth / 2;
    canvas.drawPath(
      continuousRoundedRectPath(rect.deflate(half), math.max(0, radius - half)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = lineWidth
        ..color = line,
    );
  }

  @override
  bool shouldRepaint(_CardPainter old) =>
      old.radius != radius ||
      old.fill != fill ||
      old.line != line ||
      old.lineWidth != lineWidth;
}
