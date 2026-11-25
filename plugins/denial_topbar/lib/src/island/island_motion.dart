import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:denial_shell_kit/continuous_corners.dart';
import 'package:denial_shell_kit/kit_control_math.dart';
import 'package:denial_shell_kit/kit_motion.dart';
import 'package:denial_shell_kit/kit_style.dart';
import 'package:flutter/widgets.dart';

import '../bar_tokens.dart';
import 'island_engine.dart';

/// Values that stand in for settings the island does not have yet. Each one
/// is read in a single place, so giving it a field later is one edit.
abstract final class IslandDefaults {
  /// How long the pointer rests on the compact island before it fades away,
  /// where fading under the pointer is on. Long enough to arrive and click.
  static const Duration fadeDwell = Duration(milliseconds: 600);

  /// How long a press is held before it opens the panel.
  static const Duration longPress = Duration(milliseconds: 280);

  /// A press elsewhere this soon after the panel opened is the press that
  /// opened it.
  static const Duration outsideGuard = Duration(milliseconds: 150);
}

/// How the island moves under one look: the springs of its outline, its
/// content and its bubble.
@immutable
class IslandFeel {
  const IslandFeel({
    required this.grow,
    required this.shrink,
    required this.reshape,
    required this.content,
    required this.split,
    required this.merge,
    required this.pop,
    required this.gulp,
  });

  /// Denial: a drop with some mass. It passes its size a little on the way
  /// out and comes home without a wobble.
  static const IslandFeel liquid = IslandFeel(
    grow: KitSpringTuning(260, 0.72),
    shrink: KitSpringTuning(340, 1),
    reshape: KitSpringTuning(300, 0.62),
    content: KitSpringTuning(420, 1),
    split: KitSpringTuning(210, 0.55),
    merge: KitSpringTuning(320, 0.9),
    pop: KitSpringTuning(300, 0.45),
    gulp: 1.5,
  );

  /// The other look: the same moves, settled almost without overshoot.
  static const IslandFeel crisp = IslandFeel(
    grow: KitSpringTuning(420, 0.9),
    shrink: KitSpringTuning(520, 1),
    reshape: KitSpringTuning(420, 0.85),
    content: KitSpringTuning(520, 1),
    split: KitSpringTuning(380, 0.8),
    merge: KitSpringTuning(480, 1),
    pop: KitSpringTuning(420, 0.7),
    gulp: 0.8,
  );

  static IslandFeel of(KitStyle style) => style.liquid ? liquid : crisp;

  /// The outline opening into a card: a slight overshoot.
  final KitSpringTuning grow;

  /// The outline going back to the pill: critically damped.
  final KitSpringTuning shrink;

  /// The pill changing width for new content.
  final KitSpringTuning reshape;

  /// The cross-over between the pill's face and the card's content.
  final KitSpringTuning content;

  /// The bubble leaving the pill, and returning to it.
  final KitSpringTuning split;
  final KitSpringTuning merge;

  /// The breath the island takes when an item arrives.
  final KitSpringTuning pop;

  /// How hard that breath is drawn: the scale's starting speed, per second.
  final double gulp;
}

/// What the island is made of: its colours, and every corner it draws.
abstract final class IslandLook {
  static const Color fill = Color(BarTokens.islandFill);
  static const Color ink = Color(0xffffffff);
  static const Color dim = Color(0x99ffffff);
  static const Color edge = Color(0x1fffffff);

  /// The one place a corner of the island comes from. [natural] is the
  /// radius the design asks for and [extent] the shorter side it rounds; a
  /// look with squarer corners scales the result here and every outline, the
  /// pill included, follows.
  static double corner(KitStyle style, double natural, double extent) =>
      math.min(natural, extent / 2);

  /// The resting pill and the bubble: as round as their height allows.
  static double pill(KitStyle style, double height) =>
      corner(style, double.infinity, height);

  static double card(KitStyle style, IslandKind kind, Size size) => corner(
    style,
    kind == IslandKind.media || kind == IslandKind.track ? 36 : 30,
    size.shortestSide,
  );

  /// Something set inside an outline of [outer], [inset] from its edge.
  static double nested(KitStyle style, double outer, double inset) =>
      math.max(4, outer - inset);
}

/// Replaces one piece of content with another, with a sense of direction.
/// What leaves blurs, shrinks and drifts away first; what arrives waits a
/// moment, then comes in from [from] slightly small and grows into place.
class IslandSwap extends StatelessWidget {
  const IslandSwap({
    required this.child,
    this.from = Offset.zero,
    this.distance = 10,
    this.alignment = Alignment.center,
    super.key,
  });

  /// Must carry a key that changes with the content.
  final Widget child;

  /// The side the new content comes from, as a unit offset: (1, 0) is the
  /// right, (0, -1) is above. Zero swaps in place.
  final Offset from;
  final double distance;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    final key = child.key;
    return AnimatedSwitcher(
      duration: KitMotion.duration(context, BarTokens.islandContentIn),
      reverseDuration: KitMotion.duration(context, BarTokens.islandContentOut),
      layoutBuilder: (current, previous) => Stack(
        alignment: alignment,
        clipBehavior: Clip.none,
        children: <Widget>[...previous, ?current],
      ),
      transitionBuilder: (child, animation) => _SwapMotion(
        animation: animation,
        incoming: child.key == key,
        from: from * distance,
        child: child,
      ),
      child: child,
    );
  }
}

class _SwapMotion extends AnimatedWidget {
  const _SwapMotion({
    required Animation<double> animation,
    required this.incoming,
    required this.from,
    required this.child,
  }) : super(listenable: animation);

  final bool incoming;
  final Offset from;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final value = (listenable as Animation<double>).value;
    final double opacity;
    final double scale;
    final double blur;
    final Offset offset;
    if (incoming) {
      final arrived = KitMotion.outCubic.transform(kitPhase(value, 0.3, 1));
      opacity = kitPhase(value, 0.3, 0.8);
      scale = 0.9 + 0.1 * arrived;
      blur = 6 * (1 - arrived);
      offset = from * (1 - arrived);
    } else {
      final gone = 1 - value;
      opacity = value;
      scale = 1 - 0.1 * gone;
      blur = 8 * gone;
      offset = from * (-0.8 * gone);
    }
    return IgnorePointer(
      ignoring: !incoming,
      child: Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: offset,
          child: Transform.scale(
            scale: scale,
            child: ImageFiltered(
              enabled: blur > 0.3,
              imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// The island's body: the pill, the bubble beside it and the neck that
/// joins them while they part, filled as one shape so the join has no seam.
class IslandBlobPainter extends CustomPainter {
  const IslandBlobPainter({
    required this.body,
    required this.radius,
    required this.bubble,
    required this.bubbleRadius,
    required this.neck,
    required this.shadow,
  });

  final Rect body;
  final double radius;

  /// The bubble's box, or null while there is none.
  final Rect? bubble;
  final double bubbleRadius;

  /// The neck's thickness as a share of the bubble's radius; 0 is none.
  final double neck;

  /// 0 for the pill in the bar, 1 for the open card over the desktop.
  final double shadow;

  @override
  void paint(Canvas canvas, Size size) {
    final bodyPath = continuousRoundedRectPath(body, radius);
    var shape = bodyPath;
    final drop = bubble;
    if (drop != null) {
      shape = Path.combine(
        PathOperation.union,
        shape,
        continuousRoundedRectPath(drop, bubbleRadius),
      );
      // The neck runs from where the pill's top edge is still straight to
      // the bubble's middle. Its two edges are curves whose midpoints sit
      // the neck's thickness from the centre line, so they pinch together
      // as it thins.
      final from = math.max(body.left, body.right - radius);
      final to = drop.center.dx;
      if (neck > 0.03 && to > from + 0.5) {
        final half = drop.height / 2;
        final middle = drop.center.dy;
        final across = (from + to) / 2;
        final pull = 2 * half * neck - half;
        shape = Path.combine(
          PathOperation.union,
          shape,
          Path()
            ..moveTo(from, middle - half)
            ..quadraticBezierTo(across, middle - pull, to, middle - half)
            ..lineTo(to, middle + half)
            ..quadraticBezierTo(across, middle + pull, from, middle + half)
            ..close(),
        );
      }
    }
    if (shadow > 0.01) {
      canvas.drawPath(
        bodyPath.shift(const Offset(0, 12)),
        Paint()
          ..color = Color.fromRGBO(0, 0, 0, 0.36 * shadow.clamp(0.0, 1.0))
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 15),
      );
    }
    canvas.drawPath(shape, Paint()..color = IslandLook.fill);
    canvas.drawPath(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.6
        ..color = IslandLook.edge,
    );
  }

  @override
  bool shouldRepaint(IslandBlobPainter old) =>
      old.body != body ||
      old.radius != radius ||
      old.bubble != bubble ||
      old.bubbleRadius != bubbleRadius ||
      old.neck != neck ||
      old.shadow != shadow;
}
