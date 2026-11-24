import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/rendering.dart';

/// Continuous corners, the way macOS and iOS draw them.
///
/// A `BorderRadius.circular` corner is a quarter circle, so where it meets a
/// straight edge the curvature jumps from 0 to 1/r at once and the eye reads
/// the join as a crease. Apple's corners are superellipse arcs: curvature
/// grows from zero at the edge and peaks at the corner, which is what makes a
/// macOS panel look soft rather than stamped. macOS 27's expanded island is
/// 32 pt of exactly this [S27].
///
/// The corner is `|x/r|^n + |y/r|^n = 1`, sampled into a path. `n = 3` is
/// NextKDE `AppearanceTokens.qml`'s `cornerExponent`: 2.0 is a plain circular
/// arc, 2.5-4 is the useful range, and 3 overhangs the arc by 12% along the
/// diagonal, which is what reads as Apple's fuller corner. Sampling rather than
/// approximating with a few beziers keeps the curve exact at every radius; 16
/// segments per corner is under a pixel of error at the sizes this bar draws.
Path continuousRoundedRectPath(
  Rect rect,
  double radius, {
  double exponent = 3,
  int segments = 16,
}) {
  final r = math.max(
    0.0,
    math.min(radius, math.min(rect.width, rect.height) / 2),
  );
  final path = Path();
  if (r <= 0.001) {
    return path..addRect(rect);
  }

  // `cos(t)^(2/n)` runs 1 → 0 and `sin(t)^(2/n)` runs 0 → 1; together they
  // walk one corner from its horizontal edge to its vertical edge.
  final power = 2 / exponent;
  double along(double t) => math.pow(math.cos(t), power).toDouble();
  double across(double t) => math.pow(math.sin(t), power).toDouble();

  final left = rect.left, top = rect.top;
  final right = rect.right, bottom = rect.bottom;

  path.moveTo(left + r, top);
  path.lineTo(right - r, top);
  for (var index = 0; index <= segments; index++) {
    final t = index / segments * math.pi / 2;
    path.lineTo(right - r + r * across(t), top + r - r * along(t));
  }
  path.lineTo(right, bottom - r);
  for (var index = 0; index <= segments; index++) {
    final t = index / segments * math.pi / 2;
    path.lineTo(right - r + r * along(t), bottom - r + r * across(t));
  }
  path.lineTo(left + r, bottom);
  for (var index = 0; index <= segments; index++) {
    final t = index / segments * math.pi / 2;
    path.lineTo(left + r - r * across(t), bottom - r + r * along(t));
  }
  path.lineTo(left, top + r);
  for (var index = 0; index <= segments; index++) {
    final t = index / segments * math.pi / 2;
    path.lineTo(left + r - r * along(t), top + r - r * across(t));
  }
  return path..close();
}

/// The shape itself, for `ShapeDecoration` and `ClipPath`.
class ContinuousCorners extends ShapeBorder {
  const ContinuousCorners({
    required this.radius,
    this.exponent = 3,
    this.side = BorderSide.none,
  });

  final double radius;
  final double exponent;
  final BorderSide side;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      continuousRoundedRectPath(rect, radius, exponent: exponent);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      continuousRoundedRectPath(
        rect.deflate(side.width),
        math.max(0, radius - side.width),
        exponent: exponent,
      );

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none || side.width <= 0) return;
    canvas.drawPath(
      getOuterPath(rect, textDirection: textDirection),
      side.toPaint(),
    );
  }

  @override
  ShapeBorder scale(double t) => ContinuousCorners(
    radius: radius * t,
    exponent: exponent,
    side: side.scale(t),
  );

  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) {
    if (a is ContinuousCorners) {
      return ContinuousCorners(
        radius: lerpDouble(a.radius, radius, t) ?? radius,
        exponent: lerpDouble(a.exponent, exponent, t) ?? exponent,
        side: BorderSide.lerp(a.side, side, t),
      );
    }
    return super.lerpFrom(a, t);
  }

  @override
  ShapeBorder? lerpTo(ShapeBorder? b, double t) {
    if (b is ContinuousCorners) {
      return ContinuousCorners(
        radius: lerpDouble(radius, b.radius, t) ?? radius,
        exponent: lerpDouble(exponent, b.exponent, t) ?? exponent,
        side: BorderSide.lerp(side, b.side, t),
      );
    }
    return super.lerpTo(b, t);
  }

  @override
  bool operator ==(Object other) =>
      other is ContinuousCorners &&
      other.radius == radius &&
      other.exponent == exponent &&
      other.side == side;

  @override
  int get hashCode => Object.hash(radius, exponent, side);
}

/// A clipper with the same shape, so content never spills past the curve.
class ContinuousCornersClipper extends CustomClipper<Path> {
  const ContinuousCornersClipper({required this.radius, this.exponent = 3});

  final double radius;
  final double exponent;

  @override
  Path getClip(Size size) =>
      continuousRoundedRectPath(Offset.zero & size, radius, exponent: exponent);

  @override
  bool shouldReclip(ContinuousCornersClipper oldClipper) =>
      oldClipper.radius != radius || oldClipper.exponent != exponent;
}
