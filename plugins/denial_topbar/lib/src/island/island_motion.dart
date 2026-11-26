import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:denial_shell_kit/continuous_corners.dart';
import 'package:denial_shell_kit/kit_control_math.dart';
import 'package:denial_shell_kit/kit_motion.dart';
import 'package:denial_shell_kit/kit_style.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../bar_tokens.dart';
import 'island_shape.dart';
import 'island_skin.dart';

/// Values that stand in for settings the island does not have yet. Each one
/// is read in a single place, so giving it a field later is one edit.
abstract final class IslandDefaults {
  /// A press elsewhere this soon after the panel opened is the press that
  /// opened it.
  static const Duration outsideGuard = Duration(milliseconds: 150);
}

/// How the island moves under one look: the springs of its outline, its
/// content and its bubbles. Every spring runs on the kit's paced clock, so
/// the speed setting and reduced motion reach all of them.
@immutable
class IslandFeel {
  const IslandFeel({
    required this.grow,
    required this.shrink,
    required this.reshape,
    required this.slot,
    required this.content,
    required this.contentOut,
    required this.split,
    required this.merge,
    required this.pop,
    required this.hover,
    required this.veil,
    required this.level,
    required this.press,
    required this.gulp,
    required this.swap,
  });

  /// Denial: a drop with some mass. It passes its size a little on the way
  /// out and comes home without a wobble.
  static const IslandFeel liquid = IslandFeel(
    grow: KitSpringTuning(260, 0.72),
    shrink: KitSpringTuning(340, 1),
    reshape: KitSpringTuning(300, 0.62),
    slot: KitSpringTuning(300, 1),
    content: KitSpringTuning(300, 1),
    contentOut: KitSpringTuning(900, 1),
    split: KitSpringTuning(210, 0.55),
    merge: KitSpringTuning(320, 0.9),
    pop: KitSpringTuning(300, 0.45),
    hover: KitSpringTuning(380, 0.7),
    veil: KitSpringTuning(260, 1),
    level: KitSpringTuning(320, 0.75),
    press: KitSpringTuning(520, 0.42),
    gulp: 1.5,
    swap: 0.62,
  );

  static final Map<KitStyle, IslandFeel> _made = <KitStyle, IslandFeel>{};

  /// The feel of [style]. Only a liquid look may pass a target: every other
  /// look gets the same moves dead-beat, as brisk as the look's own panels.
  static IslandFeel of(KitStyle style) {
    if (style.liquid) return liquid;
    return _made.putIfAbsent(style, () {
      final pace = islandPace(style.panelGrow.stiffness);
      KitSpringTuning still(double stiffness) => KitSpringTuning(
        stiffness * pace,
        islandDamping(0.7, liquid: false),
      );
      return IslandFeel(
        grow: still(440),
        shrink: still(560),
        reshape: still(440),
        slot: still(440),
        content: still(420),
        contentOut: still(1000),
        split: still(400),
        merge: still(500),
        pop: still(460),
        hover: still(460),
        veil: still(300),
        level: still(520),
        press: KitSpringTuning(
          style.pressTuning.stiffness,
          islandDamping(style.pressTuning.dampingRatio, liquid: false),
        ),
        gulp: 0.7,
        swap: islandDamping(liquid.swap, liquid: false),
      );
    });
  }

  /// The outline opening into a card: a slight overshoot where the look
  /// allows one.
  final KitSpringTuning grow;

  /// The outline going back to the pill: critically damped.
  final KitSpringTuning shrink;

  /// The pill changing width for new content.
  final KitSpringTuning reshape;

  /// The room the bar keeps for the pill. Its neighbours move with it, so
  /// it never bounces.
  final KitSpringTuning slot;

  /// The card's content arriving once the outline has opened for it, and
  /// leaving ahead of the outline.
  final KitSpringTuning content;
  final KitSpringTuning contentOut;

  /// A bubble leaving the pill, and returning to it.
  final KitSpringTuning split;
  final KitSpringTuning merge;

  /// The breath the island takes when an item arrives.
  final KitSpringTuning pop;

  /// The pill swelling under a pointer, and fading out of its way.
  final KitSpringTuning hover;
  final KitSpringTuning veil;

  /// A bar, a ring or a dot following its value.
  final KitSpringTuning level;

  /// The pill giving under a press and coming back.
  final KitSpringTuning press;

  /// How hard that breath is drawn: the scale's starting speed, per second.
  final double gulp;

  /// The damping of the curve one piece of content replaces another on;
  /// see [islandSpringCurve].
  final double swap;
}

/// [islandSpringCurve] as a curve for a timed transition.
class IslandSpringCurve extends Curve {
  const IslandSpringCurve(this.damping);

  final double damping;

  @override
  double transformInternal(double t) => islandSpringCurve(t, damping);
}

/// Replaces one piece of content with another, with a sense of direction.
/// What leaves blurs, shrinks and drifts away first; what arrives waits a
/// moment, then comes in from [from] slightly small and settles on the
/// look's spring curve, so it lands the way the outline around it does.
class IslandSwap extends StatelessWidget {
  const IslandSwap({
    required this.child,
    this.from = Offset.zero,
    this.distance = 10,
    this.shrink = 0.1,
    this.alignment = Alignment.center,
    super.key,
  });

  /// Must carry a key that changes with the content.
  final Widget child;

  /// The side the new content comes from, as a unit offset: (1, 0) is the
  /// right, (0, -1) is above. Zero swaps in place.
  final Offset from;
  final double distance;

  /// How much smaller than itself the content is as it comes and goes.
  final double shrink;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    final key = child.key;
    final style = KitStyle.of(context);
    final feel = IslandFeel.of(style);
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
        shrink: shrink,
        damping: feel.swap,
        // A look with no blur behind its panels has none in here either.
        blurs: style.glassy,
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
    required this.shrink,
    required this.damping,
    required this.blurs,
    required this.child,
  }) : super(listenable: animation);

  final bool incoming;
  final Offset from;
  final double shrink;
  final double damping;
  final bool blurs;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final value = (listenable as Animation<double>).value;
    final double opacity;
    final double scale;
    final double blur;
    final Offset offset;
    if (incoming) {
      // It waits out the first quarter, while what it replaces leaves.
      final arrived = islandSpringCurve(kitPhase(value, 0.25, 1), damping);
      final clear = KitMotion.outCubic.transform(kitPhase(value, 0.25, 0.8));
      opacity = clear;
      scale = 1 - shrink * (1 - arrived);
      blur = 6 * (1 - clear);
      offset = from * (1 - arrived);
    } else {
      final gone = KitMotion.inCubic.transform(1 - value);
      opacity = 1 - KitMotion.out.transform(1 - value);
      scale = 1 - shrink * gone;
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
              enabled: blurs && blur > 0.3,
              imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// A bubble beside the pill, as the body's painter needs it.
@immutable
class IslandDrop {
  const IslandDrop(this.box, this.neck);

  final Rect box;

  /// The neck's thickness as a share of the bubble's radius; 0 is none.
  final double neck;

  @override
  bool operator ==(Object other) =>
      other is IslandDrop && other.box == box && other.neck == neck;

  @override
  int get hashCode => Object.hash(box, neck);
}

/// The island's body: the pill, the bubbles on either side of it and the
/// necks that join them while they part, filled as one shape so a join has
/// no seam.
class IslandBlobPainter extends CustomPainter {
  const IslandBlobPainter({
    required this.body,
    required this.radius,
    required this.drops,
    required this.bubbleRadius,
    required this.shadow,
    required this.skin,
  });

  final Rect body;
  final double radius;

  /// The bubbles there are now, on whichever side each stands.
  final List<IslandDrop> drops;
  final double bubbleRadius;

  /// 0 for the pill in the bar, 1 for the open card over the desktop.
  final double shadow;
  final IslandSkin skin;

  @override
  void paint(Canvas canvas, Size size) {
    final bodyPath = continuousRoundedRectPath(body, radius);
    var shape = bodyPath;
    for (final drop in drops) {
      final box = drop.box;
      shape = Path.combine(
        PathOperation.union,
        shape,
        continuousRoundedRectPath(box, bubbleRadius),
      );
      // The neck runs from where the pill's edge is still straight to the
      // bubble's middle. Its two edges are curves whose midpoints sit the
      // neck's thickness from the centre line, so they pinch together as
      // it thins.
      final right = box.center.dx > body.center.dx;
      final from = right
          ? math.max(body.left, body.right - radius)
          : math.min(body.right, body.left + radius);
      final to = box.center.dx;
      if (drop.neck <= 0.03 || (to - from).abs() <= 0.5) continue;
      final half = box.height / 2;
      final middle = box.center.dy;
      final across = (from + to) / 2;
      final pull = 2 * half * drop.neck - half;
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
    final cast = shadow.clamp(0.0, 1.0) * skin.shadow;
    if (cast > 0.01) {
      canvas.drawPath(
        bodyPath.shift(const Offset(0, 12)),
        Paint()
          ..color = Color.fromRGBO(0, 0, 0, 0.36 * cast)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 15),
      );
    }
    canvas.drawPath(shape, Paint()..color = skin.fill);
    if (skin.edgeWidth <= 0) return;
    canvas.drawPath(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = skin.edgeWidth
        ..color = skin.edge,
    );
  }

  @override
  bool shouldRepaint(IslandBlobPainter old) =>
      old.body != body ||
      old.radius != radius ||
      !listEquals(old.drops, drops) ||
      old.bubbleRadius != bubbleRadius ||
      old.shadow != shadow ||
      old.skin != skin;
}
