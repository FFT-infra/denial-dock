import 'package:flutter/foundation.dart';

import 'kit_panel_place.dart';
import 'kit_reserve.dart';
import 'kit_store.dart';
import 'kit_style.dart';

export 'kit_reserve.dart';

/// How much of itself the top bar draws, kept in `denial_shell_kit.json`.
/// The bar's work-area provider is asked before any widget is built, so the
/// value has to be readable at once, which the kit's store is.
final KitBarModeNotifier kitBarMode = KitBarModeNotifier._();

class KitBarModeNotifier extends ValueNotifier<KitBarMode> {
  KitBarModeNotifier._() : super(KitBarMode.parse(kitStore.read()['bar']));

  @override
  set value(KitBarMode next) {
    if (next == super.value) return;
    super.value = next;
    kitStore.put('bar', next.key);
  }
}

/// What the hosts other than the bar report about themselves. The bar's
/// plugin holds the shell's one work-area provider, so a dock that wants its
/// edge kept free says so here and the bar's plugin asks for it.
final KitHosts kitHosts = KitHosts._();

class KitHosts extends ChangeNotifier {
  KitHosts._();

  static const String dock = 'dock';

  final Map<String, KitHostState> _states = <String, KitHostState>{};

  KitHostState? operator [](String id) => _states[id];

  /// Sets what host [id] says, or forgets the host when [state] is null.
  /// Never call it while widgets are being built: listeners rebuild.
  void report(String id, KitHostState? state) {
    if (_states[id] == state) return;
    if (state == null) {
      _states.remove(id);
    } else {
      _states[id] = state;
    }
    notifyListeners();
  }
}

/// The reservation in force, as last decided. A host reads it to learn
/// whether the room kept free on its edge is its own, in which case it must
/// not move inwards to avoid it.
final ValueNotifier<KitReservation?> kitReservation =
    ValueNotifier<KitReservation?>(null);

/// The reservation the shell should hold now, for a bar on [barEdge] that is
/// [barThickness] thick.
KitReservation? kitResolveReservation({
  required KitEdge? barEdge,
  required double barThickness,
}) => resolveKitReservation(
  barMode: kitBarMode.value,
  barEdge: barEdge,
  barThickness: barThickness,
  dock: kitDockEnabled.value ? kitHosts[KitHosts.dock] : null,
);
