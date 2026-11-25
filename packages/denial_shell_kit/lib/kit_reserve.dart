/// Who keeps windows off a screen edge. The compositor reserves one edge for
/// the whole shell, so the bar and the dock cannot each ask for their own:
/// one rule decides between them. Plain data, so it runs as an ordinary test.
library;

import 'kit_panel_place.dart';

/// How much of itself the top bar draws.
enum KitBarMode {
  /// The bar as it has always been.
  shown,

  /// No strip: only the island floats at the top of the screen, and windows
  /// may reach under it.
  islandOnly,

  /// Nothing at all. The bar's parts can still be placed in another host.
  hidden;

  String get key => switch (this) {
    KitBarMode.shown => 'shown',
    KitBarMode.islandOnly => 'islandOnly',
    KitBarMode.hidden => 'hidden',
  };

  static KitBarMode parse(Object? value) => switch (value) {
    'islandOnly' => KitBarMode.islandOnly,
    'hidden' => KitBarMode.hidden,
    _ => KitBarMode.shown,
  };
}

/// What a host other than the bar says about itself.
class KitHostState {
  const KitHostState({
    required this.edge,
    required this.thickness,
    required this.pinned,
  });

  final KitEdge edge;

  /// From the screen edge to the host's inner face.
  final double thickness;

  /// Whether the host stays on screen whatever the windows do. A host that
  /// hides itself reserves nothing.
  final bool pinned;

  @override
  bool operator ==(Object other) =>
      other is KitHostState &&
      other.edge == edge &&
      other.thickness == thickness &&
      other.pinned == pinned;

  @override
  int get hashCode => Object.hash(edge, thickness, pinned);

  @override
  String toString() => 'KitHostState($edge, $thickness, pinned: $pinned)';
}

enum KitReserver { bar, dock }

/// The one edge the shell reserves, and for whom.
class KitReservation {
  const KitReservation({
    required this.owner,
    required this.edge,
    required this.thickness,
  });

  final KitReserver owner;
  final KitEdge edge;
  final double thickness;

  @override
  bool operator ==(Object other) =>
      other is KitReservation &&
      other.owner == owner &&
      other.edge == edge &&
      other.thickness == thickness;

  @override
  int get hashCode => Object.hash(owner, edge, thickness);

  @override
  String toString() => 'KitReservation(${owner.name}, $edge, $thickness)';
}

/// Decides the reservation. A bar that draws its strip comes first; with no
/// strip, a dock that stays on screen reserves its own edge; otherwise
/// nothing is reserved and windows take the whole output.
///
/// [barEdge] is null when the system's settings hide the bar. [dock] is null
/// when no dock runs or it is switched off.
KitReservation? resolveKitReservation({
  required KitBarMode barMode,
  required KitEdge? barEdge,
  required double barThickness,
  required KitHostState? dock,
}) {
  if (barMode == KitBarMode.shown &&
      barEdge != null &&
      barThickness.isFinite &&
      barThickness > 0) {
    return KitReservation(
      owner: KitReserver.bar,
      edge: barEdge,
      thickness: barThickness,
    );
  }
  if (dock != null &&
      dock.pinned &&
      dock.thickness.isFinite &&
      dock.thickness > 0) {
    return KitReservation(
      owner: KitReserver.dock,
      edge: dock.edge,
      thickness: dock.thickness,
    );
  }
  return null;
}
