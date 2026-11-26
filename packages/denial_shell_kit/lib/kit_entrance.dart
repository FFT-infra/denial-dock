import 'package:flutter/widgets.dart';

import 'kit_control_math.dart';
import 'kit_motion.dart';

/// Lets the [KitEntranceItem]s below arrive one after another when the
/// surface first appears: each rises a few pixels into place and fades in,
/// rows in turn. It plays once, follows the shell's speed, and is skipped
/// under reduced motion.
class KitEntrance extends StatefulWidget {
  const KitEntrance({required this.child, super.key});

  final Widget child;

  @override
  State<KitEntrance> createState() => _KitEntranceState();
}

class _KitEntranceState extends State<KitEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _arrive = AnimationController(
    vsync: this,
    duration: KitMotion.timedNow.duration(KitMotion.fillSlow),
  );

  @override
  void initState() {
    super.initState();
    if (_arrive.duration == Duration.zero) {
      _arrive.value = 1;
    } else {
      _arrive.forward();
    }
  }

  @override
  void dispose() {
    _arrive.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _KitEntranceScope(arrive: _arrive, child: widget.child);
}

class _KitEntranceScope extends InheritedWidget {
  const _KitEntranceScope({required this.arrive, required super.child});

  final Animation<double> arrive;

  @override
  bool updateShouldNotify(_KitEntranceScope old) => arrive != old.arrive;
}

/// One block of a [KitEntrance], placed by its [row] and [col] in the
/// surface. Outside a [KitEntrance] it is just its child.
class KitEntranceItem extends StatelessWidget {
  const KitEntranceItem({
    required this.row,
    required this.child,
    this.col = 0,
    this.rise = 10,
    super.key,
  });

  final int row;
  final int col;

  /// How far below its place the block starts, in pixels.
  final double rise;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_KitEntranceScope>();
    if (scope == null) return child;
    final delay = staggerDelay(row, col);
    // Denial lets a block pass its place by a hair; the other look lands
    // without any overshoot.
    final curve = KitMotion.settleCurve(context);
    return AnimatedBuilder(
      animation: scope.arrive,
      builder: (context, child) {
        final v = scope.arrive.value;
        final moved = curve.transform(kitPhase(v, delay, delay + 0.64));
        return Opacity(
          opacity: kitPhase(v, delay, delay + 0.4),
          child: Transform.translate(
            offset: Offset(0, (1 - moved) * rise),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}
