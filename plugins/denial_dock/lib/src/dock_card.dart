import 'dart:math' as math;

import 'package:denial_flutter_sdk/effects.dart';
import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/widgets.dart';

import 'dock_corners.dart';

/// The card every dock popup draws on, matching the top bar's: continuous
/// corners, backdrop blur, a hairline and one soft shadow.
class DockCard extends StatelessWidget {
  const DockCard({
    required this.radius,
    required this.child,
    this.elevation = 1,
    this.minOpacity = 0,
    this.blurStrength = 1,
    super.key,
  });

  final double radius;
  final double elevation;

  /// Floor for the fill's opacity. A window of settings sits over other
  /// windows and needs more than a menu does to keep its text readable.
  final double minOpacity;
  final double blurStrength;
  final Widget child;

  static Color fillOf(ShellThemeData theme, {double minOpacity = 0}) {
    final fill = theme.panelColor(theme.colors.panelBackground);
    return fill.a < minOpacity ? fill.withValues(alpha: minOpacity) : fill;
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: ShapeDecoration(
                shape: ContinuousCorners(radius: radius),
                shadows: [
                  BoxShadow(
                    color: theme.colors.shadow.withValues(alpha: 0.30),
                    blurRadius: 36 * elevation,
                    offset: Offset(0, 14 * elevation),
                  ),
                ],
              ),
            ),
          ),
        ),
        ClipPath(
          clipper: ContinuousCornersClipper(radius: radius),
          child: ShellBackdropBlur(
            blur: theme.effectivePanelOpacity < 1,
            strength: blurStrength,
            separateChild: true,
            borderRadius: BorderRadius.circular(radius),
            child: CustomPaint(
              painter: _CardPainter(
                radius: radius,
                fill: fillOf(theme, minOpacity: minOpacity),
                hairline: theme.colors.hairline,
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
    required this.hairline,
  });

  final double radius;
  final Color fill;
  final Color hairline;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawPath(
      continuousRoundedRectPath(rect, radius),
      Paint()..color = fill,
    );
    canvas.drawPath(
      continuousRoundedRectPath(rect.deflate(0.5), math.max(0, radius - 0.5)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = hairline,
    );
  }

  @override
  bool shouldRepaint(_CardPainter old) =>
      old.radius != radius || old.fill != fill || old.hairline != hairline;
}
