import 'package:denial_shell_kit/kit_panel_place.dart';
import 'package:denial_shell_kit/kit_reserve.dart';

void _expect(bool ok, String what) {
  if (!ok) throw StateError(what);
}

void main() {
  const pinned = KitHostState(edge: KitEdge.bottom, thickness: 68, pinned: true);
  const hiding = KitHostState(
    edge: KitEdge.bottom,
    thickness: 68,
    pinned: false,
  );

  // A bar that draws its strip reserves it, whatever the dock says.
  for (final dock in <KitHostState?>[null, pinned, hiding]) {
    final result = resolveKitReservation(
      barMode: KitBarMode.shown,
      barEdge: KitEdge.top,
      barThickness: 33,
      dock: dock,
    );
    _expect(
      result ==
          const KitReservation(
            owner: KitReserver.bar,
            edge: KitEdge.top,
            thickness: 33,
          ),
      'the bar comes first with dock $dock: $result',
    );
  }

  // No strip: a dock that stays reserves its own edge and thickness.
  for (final mode in <KitBarMode>[KitBarMode.islandOnly, KitBarMode.hidden]) {
    final result = resolveKitReservation(
      barMode: mode,
      barEdge: KitEdge.top,
      barThickness: 33,
      dock: pinned,
    );
    _expect(
      result ==
          const KitReservation(
            owner: KitReserver.dock,
            edge: KitEdge.bottom,
            thickness: 68,
          ),
      '${mode.name}: the pinned dock reserves: $result',
    );
    _expect(
      resolveKitReservation(
            barMode: mode,
            barEdge: KitEdge.top,
            barThickness: 33,
            dock: hiding,
          ) ==
          null,
      '${mode.name}: a dock that hides reserves nothing',
    );
    _expect(
      resolveKitReservation(
            barMode: mode,
            barEdge: KitEdge.top,
            barThickness: 33,
            dock: null,
          ) ==
          null,
      '${mode.name}: no dock, nothing reserved',
    );
  }

  // A side dock reserves its side.
  final side = resolveKitReservation(
    barMode: KitBarMode.hidden,
    barEdge: KitEdge.top,
    barThickness: 33,
    dock: const KitHostState(edge: KitEdge.left, thickness: 72, pinned: true),
  );
  _expect(
    side?.edge == KitEdge.left && side?.thickness == 72,
    'a side dock reserves its side',
  );

  // The system's settings hide the bar: the dock may take over.
  _expect(
    resolveKitReservation(
          barMode: KitBarMode.shown,
          barEdge: null,
          barThickness: 33,
          dock: pinned,
        )?.owner ==
        KitReserver.dock,
    'a bar the system hides leaves the edge to the dock',
  );
  _expect(
    resolveKitReservation(
          barMode: KitBarMode.shown,
          barEdge: null,
          barThickness: 33,
          dock: null,
        ) ==
        null,
    'nothing shown, nothing reserved',
  );

  // Sizes that cannot be reserved are no reservation.
  _expect(
    resolveKitReservation(
          barMode: KitBarMode.shown,
          barEdge: KitEdge.top,
          barThickness: 0,
          dock: null,
        ) ==
        null,
    'a bar of no thickness reserves nothing',
  );
  _expect(
    resolveKitReservation(
          barMode: KitBarMode.hidden,
          barEdge: KitEdge.top,
          barThickness: 33,
          dock: const KitHostState(
            edge: KitEdge.bottom,
            thickness: double.nan,
            pinned: true,
          ),
        ) ==
        null,
    'a dock of no thickness reserves nothing',
  );

  // The mode's stored form round-trips, and anything else is the bar shown.
  for (final mode in KitBarMode.values) {
    _expect(KitBarMode.parse(mode.key) == mode, '${mode.name} round-trips');
  }
  _expect(KitBarMode.parse(null) == KitBarMode.shown, 'missing is shown');
  _expect(KitBarMode.parse('nope') == KitBarMode.shown, 'unknown is shown');
}
