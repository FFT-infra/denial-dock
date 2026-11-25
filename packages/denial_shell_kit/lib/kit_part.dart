import 'package:denial_flutter_sdk/services.dart' show ShellServices;
import 'package:denial_flutter_sdk/surfaces.dart' show ShellSurfaceEnvironment;
import 'package:flutter/widgets.dart';

import 'kit_panel_place.dart';

/// How much room a host gives one part.
enum KitDensity {
  /// A row about 28 high, as in a bar.
  bar,

  /// A cell as tall as a dock's icons.
  tile,
}

/// The kinds of host a part can be placed in.
enum KitHostKind { bar, dock }

/// What a host tells a part about the place it is drawn in.
@immutable
class KitPartContext {
  const KitPartContext({
    required this.edge,
    required this.axis,
    required this.crossExtent,
    required this.ink,
    this.options = const <String, Object?>{},
    this.density = KitDensity.bar,
    this.host = KitHostKind.bar,
    this.hostExtent,
    this.siblings = const <String>[],
    this.monitorId,
    this.services,
    this.environment,
  });

  /// The screen edge the host sits on.
  final KitEdge edge;

  /// The direction the host lays its parts out in.
  final Axis axis;

  /// The room across the host: a bar's height, a side bar's width.
  final double crossExtent;

  /// The colour type and glyphs are drawn in on this spot of the host.
  final Color ink;

  /// Settings of this one placement.
  final Map<String, Object?> options;

  final KitDensity density;
  final KitHostKind host;

  /// How far the host reaches in from its screen edge. A panel a part opens
  /// starts beyond it and grows away from [edge], so it never covers the host
  /// it belongs to. Null means [crossExtent].
  final double? hostExtent;

  /// Every part placed in the same host, so a part that stands for a group
  /// can leave out the members placed on their own.
  final List<String> siblings;

  /// The output the host is on, and what the shell gave the host's plugin.
  /// A part drawn outside its own plugin's host needs them to reach the
  /// system; a host that leaves them out gets parts that draw nothing.
  final int? monitorId;
  final ShellServices? services;
  final ShellSurfaceEnvironment? environment;

  /// The reach of the host from its edge, for placing a panel.
  double get panelExtent => hostExtent ?? crossExtent;
}

/// One piece of content a host can place: a clock, a status item, the
/// workspace switcher. The plugin that owns the content registers it; a host
/// asks for it by [id] and never learns who drew it.
@immutable
class KitPart {
  const KitPart({
    required this.id,
    required this.build,
    this.single = true,
    this.hosts = const <KitHostKind>{KitHostKind.bar},
    this.densities = const <KitDensity>{KitDensity.bar},
    this.label,
  });

  final String id;

  /// The hosts that can place it.
  final Set<KitHostKind> hosts;

  /// The densities it draws itself in. A host gives a part that lacks the
  /// host's own density a plain shell: centred, in the host's ink.
  final Set<KitDensity> densities;

  /// Its name in a layout editor, in English; the editor translates it.
  final String? label;

  /// Whether one host may show it only once. A spacer may repeat; a clock
  /// may not, because its popup hangs from one place.
  final bool single;

  final Widget Function(BuildContext context, KitPartContext part) build;
}

/// Every part the running plugins offer. A host listens, so the order in
/// which plugins start does not matter.
final KitParts kitParts = KitParts._();

class KitParts extends ChangeNotifier {
  KitParts._();

  final Map<String, KitPart> _parts = <String, KitPart>{};

  KitPart? operator [](String id) => _parts[id];

  Iterable<String> get ids => _parts.keys;

  /// The ids a host of [kind] can place, in the order they were registered.
  List<String> idsFor(KitHostKind kind) => <String>[
    for (final part in _parts.values)
      if (part.hosts.contains(kind)) part.id,
  ];

  /// Adds [parts], replacing any registered under the same id.
  void register(Iterable<KitPart> parts) {
    var changed = false;
    for (final part in parts) {
      if (identical(_parts[part.id], part)) continue;
      _parts[part.id] = part;
      changed = true;
    }
    if (changed) notifyListeners();
  }
}

/// Draws the part registered as [id], and nothing while no plugin offers it.
class KitPartView extends StatelessWidget {
  const KitPartView({required this.id, required this.part, super.key});

  final String id;
  final KitPartContext part;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: kitParts,
    builder: (context, _) =>
        kitParts[id]?.build(context, part) ?? const SizedBox.shrink(),
  );
}
