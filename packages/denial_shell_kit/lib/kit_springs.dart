import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'kit_style.dart';

/// A damped spring stepped by the frame clock, after the recipe in Denial's
/// `docs/LIQUID_MOTION.md`: a new target keeps the velocity, so quick changes
/// blend into one motion. Values are free to overshoot.
class KitSpring {
  KitSpring(this.value, KitSpringTuning tuning)
    : target = value,
      stiffness = tuning.stiffness,
      dampingRatio = tuning.dampingRatio;

  double value;
  double target;
  double velocity = 0;
  double stiffness;
  double dampingRatio;

  void tune(KitSpringTuning tuning) {
    stiffness = tuning.stiffness;
    dampingRatio = tuning.dampingRatio;
  }

  /// Sub-steps of at most 1/480 s keep a stiff spring stable at any refresh
  /// rate.
  void step(double dt) {
    final damping = 2 * dampingRatio * math.sqrt(stiffness);
    var left = dt;
    while (left > 0) {
      final h = math.min(left, 1 / 480);
      velocity += (-stiffness * (value - target) - damping * velocity) * h;
      value += velocity * h;
      left -= h;
    }
  }

  bool resting(double tolerance) =>
      (value - target).abs() < tolerance && velocity.abs() < tolerance * 10;

  void settle() {
    value = target;
    velocity = 0;
  }
}

/// Several springs on one ticker. The ticker starts on [kick] and stops
/// itself once every spring rests, so nothing runs while nothing moves.
class KitSprings extends ChangeNotifier {
  KitSprings(TickerProvider vsync, this.springs, {this.tolerance = 0.001}) {
    _ticker = vsync.createTicker(_tick);
  }

  final List<KitSpring> springs;
  final double tolerance;
  late final Ticker _ticker;
  Duration? _last;

  /// Runs before the springs step, for targets that follow other springs.
  void Function(double dt)? before;

  /// Runs once when everything has come to rest.
  VoidCallback? onRest;

  bool get moving => _ticker.isActive;

  void kick({bool reduceMotion = false}) {
    if (reduceMotion) {
      for (final spring in springs) {
        spring.settle();
      }
      notifyListeners();
      onRest?.call();
      return;
    }
    if (!_ticker.isActive) {
      _last = null;
      _ticker.start();
    }
  }

  void _tick(Duration elapsed) {
    final last = _last;
    _last = elapsed;
    final dt = last == null
        ? 1 / 120
        : ((elapsed - last).inMicroseconds / 1e6).clamp(0.0, 1 / 30);
    before?.call(dt);
    var resting = true;
    for (final spring in springs) {
      spring.step(dt);
      resting = resting && spring.resting(tolerance);
    }
    if (resting) {
      for (final spring in springs) {
        spring.settle();
      }
      _ticker.stop();
    }
    notifyListeners();
    if (resting) onRest?.call();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }
}

/// Follows [target] with a spring and rebuilds [builder] with its value.
class Sprung extends StatefulWidget {
  const Sprung({
    required this.target,
    required this.tuning,
    required this.builder,
    this.tolerance = 0.001,
    this.child,
    super.key,
  });

  final double target;
  final KitSpringTuning tuning;

  /// How close to its target counts as arrived: a value in pixels wants
  /// about a twentieth, a share of one wants a thousandth.
  final double tolerance;
  final Widget Function(BuildContext context, double value, Widget? child)
  builder;
  final Widget? child;

  @override
  State<Sprung> createState() => _SprungState();
}

class _SprungState extends State<Sprung> with SingleTickerProviderStateMixin {
  late final KitSpring _spring = KitSpring(widget.target, widget.tuning);
  late final KitSprings _springs = KitSprings(this, <KitSpring>[
    _spring,
  ], tolerance: widget.tolerance);

  @override
  void didUpdateWidget(Sprung old) {
    super.didUpdateWidget(old);
    _spring.tune(widget.tuning);
    if (widget.target != _spring.target) {
      _spring.target = widget.target;
      _springs.kick(reduceMotion: MediaQuery.disableAnimationsOf(context));
    }
  }

  @override
  void dispose() {
    _springs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _springs,
      builder: (context, child) =>
          widget.builder(context, _spring.value, child),
      child: widget.child,
    );
  }
}

/// A shape that fills with [color] like a liquid: the level pours to
/// [level], its surface bulges while it moves, rings a little and settles
/// flat. Where the look is not liquid the level simply eases.
class LiquidFill extends StatefulWidget {
  const LiquidFill({
    required this.level,
    required this.color,
    required this.base,
    required this.radius,
    this.sideways = false,
    this.child,
    super.key,
  });

  /// 0 empty, 1 full.
  final double level;
  final Color color;

  /// The empty vessel's colour.
  final Color base;
  final BorderRadius radius;

  /// Fills from the left rather than from the bottom.
  final bool sideways;
  final Widget? child;

  @override
  State<LiquidFill> createState() => _LiquidFillState();
}

class _LiquidFillState extends State<LiquidFill>
    with SingleTickerProviderStateMixin {
  static const KitSpringTuning _pour = KitSpringTuning(300, 0.8);
  static const KitSpringTuning _slosh = KitSpringTuning(340, 0.2);
  static const KitSpringTuning _plain = KitSpringTuning(520, 1);

  late final KitSpring _level = KitSpring(widget.level, _pour);
  late final KitSpring _surface = KitSpring(0, _slosh);
  late final KitSprings _springs = KitSprings(this, <KitSpring>[
    _level,
    _surface,
  ]);
  double _extent = 1;
  double _time = 0;
  bool _liquid = true;

  @override
  void initState() {
    super.initState();
    _springs.before = (dt) {
      _time += dt;
      // The surface leans with the level's speed; rising, its middle leads.
      final reach = math.min(14.0, _extent * 0.22);
      _surface.target = _liquid
          ? (_level.velocity * _extent * 0.05).clamp(-reach, reach)
          : 0;
    };
  }

  @override
  void didUpdateWidget(LiquidFill old) {
    super.didUpdateWidget(old);
    if (widget.level != _level.target) {
      _level.target = widget.level;
      _springs.kick(reduceMotion: MediaQuery.disableAnimationsOf(context));
    }
  }

  @override
  void dispose() {
    _springs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _liquid = KitStyle.of(context).liquid;
    _level.tune(_liquid ? _pour : _plain);
    return CustomPaint(
      painter: _LiquidPainter(
        springs: _springs,
        level: _level,
        surface: _surface,
        color: widget.color,
        base: widget.base,
        radius: widget.radius,
        sideways: widget.sideways,
        extent: (value) => _extent = value,
        time: () => _time,
      ),
      child: widget.child,
    );
  }
}

class _LiquidPainter extends CustomPainter {
  _LiquidPainter({
    required this.springs,
    required this.level,
    required this.surface,
    required this.color,
    required this.base,
    required this.radius,
    required this.sideways,
    required this.extent,
    required this.time,
  }) : super(repaint: springs);

  final KitSprings springs;
  final KitSpring level;
  final KitSpring surface;
  final Color color;
  final Color base;
  final BorderRadius radius;
  final bool sideways;
  final ValueChanged<double> extent;
  final double Function() time;

  @override
  void paint(Canvas canvas, Size size) {
    final vessel = radius.toRRect(Offset.zero & size);
    canvas.drawRRect(vessel, Paint()..color = base);
    final along = sideways ? size.width : size.height;
    final across = sideways ? size.height : size.width;
    extent(along);
    final filled = level.value;
    if (filled <= 0.001 && surface.value.abs() < 0.05) return;
    final paint = Paint()..color = color;
    if (filled >= 0.999 && surface.value.abs() < 0.05) {
      canvas.drawRRect(vessel, paint);
      return;
    }
    final bulge = surface.value;
    final ripple = bulge.abs() * 0.4 * math.sin(time() * 26);
    final edge = along * filled.clamp(-0.2, 1.2);
    // Drawn as a column filling upward, then turned for a sideways vessel.
    final y = along - edge;
    final body = Path()
      ..moveTo(0, y + ripple)
      ..cubicTo(
        across * 0.3,
        y - bulge,
        across * 0.7,
        y - bulge,
        across,
        y - ripple,
      )
      ..lineTo(across, along + 1)
      ..lineTo(0, along + 1)
      ..close();
    canvas.save();
    canvas.clipRRect(vessel);
    if (sideways) {
      // Column space (x across, y along, filling upward) onto the vessel:
      // the bottom of the column is the vessel's left end.
      canvas.transform(
        (Matrix4.identity()
              ..setEntry(0, 0, 0)
              ..setEntry(0, 1, -1)
              ..setEntry(0, 3, along)
              ..setEntry(1, 0, 1)
              ..setEntry(1, 1, 0))
            .storage,
      );
    }
    canvas.drawPath(body, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LiquidPainter old) =>
      old.color != color ||
      old.base != base ||
      old.radius != radius ||
      old.sideways != sideways;
}
