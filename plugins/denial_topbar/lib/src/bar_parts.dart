import 'package:denial_shell_kit/kit_part.dart';
import 'package:flutter/widgets.dart';

import 'bar_zones.dart';

typedef BarPartBuilder = Widget Function(KitPartContext part);

/// The bar a part is being drawn in. The parts are registered once for the
/// whole program, while their content belongs to one bar on one output, so a
/// part finds its bar here and draws what that bar gives it.
class BarHost extends InheritedWidget {
  const BarHost({required this.builders, required super.child, super.key});

  final Map<String, BarPartBuilder> builders;

  static BarHost? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BarHost>();

  // The builders close over the bar's state of this frame.
  @override
  bool updateShouldNotify(BarHost oldWidget) => true;
}

final List<KitPart> _barParts = <KitPart>[
  for (final id in BarPart.all)
    KitPart(
      id: id,
      single: !BarPart.repeats(id),
      // Outside a bar there is nothing to draw yet: the content still comes
      // from the bar's own state.
      build: (context, part) =>
          BarHost.maybeOf(context)?.builders[id]?.call(part) ??
          const SizedBox.shrink(),
    ),
];

/// Offers the bar's content as parts. Safe to call from every bar.
void registerBarParts() => kitParts.register(_barParts);
