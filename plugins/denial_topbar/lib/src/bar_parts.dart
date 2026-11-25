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

/// What draws a part where there is no bar, set by the bar's own library:
/// the content needs its panels and anchors, which live there.
Widget Function(String id, KitPartContext part)? _outside;

/// The parts another plugin's host may place too. The rest only make sense
/// in a bar: the application's name, the island, and the bar's own spacing.
const Set<String> _anywhere = <String>{
  BarPart.system,
  BarPart.workspaces,
  BarPart.clock,
  BarPart.status,
};

bool _placedAnywhere(String id) =>
    _anywhere.contains(id) || BarPart.statusItemOf(id) != null;

final List<KitPart> _barParts = <KitPart>[
  for (final id in BarPart.all)
    KitPart(
      id: id,
      single: !BarPart.repeats(id),
      hosts: _placedAnywhere(id)
          ? const <KitHostKind>{KitHostKind.bar, KitHostKind.dock}
          : const <KitHostKind>{KitHostKind.bar},
      densities: id == BarPart.clock
          ? const <KitDensity>{KitDensity.bar, KitDensity.tile}
          : const <KitDensity>{KitDensity.bar},
      // In a bar the content comes from that bar's state of this frame;
      // anywhere else the part hosts itself.
      build: (context, part) =>
          BarHost.maybeOf(context)?.builders[id]?.call(part) ??
          (_placedAnywhere(id) ? _outside?.call(id, part) : null) ??
          const SizedBox.shrink(),
    ),
];

/// Offers the bar's content as parts. Safe to call from every bar.
/// [outside] draws a part in a host that is not a bar.
void registerBarParts({
  Widget Function(String id, KitPartContext part)? outside,
}) {
  _outside = outside ?? _outside;
  kitParts.register(_barParts);
}
