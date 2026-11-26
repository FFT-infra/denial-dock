import 'dart:math' as math;

import 'package:denial_shell_kit/kit_style.dart';
import 'package:flutter/widgets.dart';

/// The two-switch Control Centre mark macOS 27 draws in the menu bar.
///
/// SF Symbols has no exact match, so this reproduces shell27's `cc` path
/// (`MacBar.qml`): a hollow pill with its knob on the left, over a solid pill
/// whose knob is punched out on the right. Drawn at 18 × 18 like the reference
/// and scaled to whatever the caller asks for.
class ControlCentreGlyph extends StatelessWidget {
  const ControlCentreGlyph({
    required this.size,
    required this.color,
    super.key,
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final weight = KitStyle.of(context).look.iconWeight;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _ControlCentrePainter(color, weight),
        isComplex: false,
      ),
    );
  }
}

class _ControlCentrePainter extends CustomPainter {
  const _ControlCentrePainter(this.color, this.weight);

  final Color color;
  final double weight;

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.width / 18;
    canvas.scale(unit);

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3 * weight;
    final fill = Paint()..color = color;

    // Top: outline pill with the knob filled on the left.
    canvas.drawRRect(
      RRect.fromLTRBR(1.55, 1.55, 16.45, 7.05, const Radius.circular(2.75)),
      stroke,
    );
    canvas.drawCircle(const Offset(4.5, 4.3), 1.95, fill);

    // Bottom: solid pill with the knob cut out on the right.
    final lower = RRect.fromLTRBR(
      0.9,
      10.3,
      17.1,
      17.1,
      const Radius.circular(3.4),
    );
    canvas.saveLayer(const Rect.fromLTWH(0, 0, 18, 18), Paint());
    canvas.drawRRect(lower, fill);
    canvas.drawCircle(
      const Offset(13.5, 13.7),
      2.3,
      Paint()..blendMode = BlendMode.clear,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ControlCentrePainter old) =>
      old.color != color || old.weight != weight;
}

/// The Wi-Fi mark at three signal strengths.
///
/// shell27 draws its own `WifiGlyph` because the SF Symbol set has no
/// strength-dependent variant in the icon font. This ports that shape: three
/// arcs over a dot, with the weakest strength dropping the outer arc.
class WifiGlyph extends StatelessWidget {
  const WifiGlyph({
    required this.size,
    required this.color,
    this.strength = 3,
    super.key,
  });

  final double size;
  final Color color;

  /// 0..3 arcs drawn, weakest first.
  final int strength;

  @override
  Widget build(BuildContext context) {
    final weight = KitStyle.of(context).look.iconWeight;
    return SizedBox(
      width: size * 17 / 13,
      height: size,
      child: CustomPaint(
        painter: _WifiPainter(color, strength.clamp(0, 3), weight),
        isComplex: false,
      ),
    );
  }
}

class _WifiPainter extends CustomPainter {
  const _WifiPainter(this.color, this.strength, this.weight);

  final Color color;
  final int strength;
  final double weight;

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.height / 13;
    canvas.scale(unit);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 * weight
      ..strokeCap = StrokeCap.round;
    const centre = Offset(8.5, 11.2);
    // Radii from the innermost arc out, as shell27's `WifiGlyph`.
    const radii = <double>[3.1, 6.0, 8.9];
    for (var index = 0; index < strength && index < radii.length; index++) {
      canvas.drawArc(
        Rect.fromCircle(center: centre, radius: radii[index]),
        math.pi * 1.22,
        math.pi * 0.56,
        false,
        paint,
      );
    }
    canvas.drawCircle(centre, 1.15, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_WifiPainter old) =>
      old.color != color || old.strength != strength || old.weight != weight;
}
