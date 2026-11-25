import 'package:flutter/widgets.dart';

import 'kit_panel_place.dart';

/// What a host tells a part about the place it is drawn in.
@immutable
class KitPartContext {
  const KitPartContext({
    required this.edge,
    required this.axis,
    required this.crossExtent,
    required this.ink,
    this.options = const <String, Object?>{},
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
}

/// One piece of content a host can place: a clock, a status item, the
/// workspace switcher. The plugin that owns the content registers it; a host
/// asks for it by [id] and never learns who drew it.
@immutable
class KitPart {
  const KitPart({required this.id, required this.build, this.single = true});

  final String id;

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
