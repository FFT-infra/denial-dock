import 'package:flutter/foundation.dart';

/// The dock's arrangement as other plugins see it. The plugins may not
/// import one another, so the dock publishes what it draws here and takes
/// changes from here: a preset and the layout editor of the shell's settings
/// both reach the dock this way and never touch its preferences file.
///
/// The map holds the dock's layout keys: `leading` and `trailing` (lists of
/// part ids), `shape`, `align`, `magnification` and `visibility`.
final KitDockLink kitDock = KitDockLink._();

class KitDockLink extends ChangeNotifier {
  KitDockLink._();

  Map<String, Object?>? _layout;
  void Function(Map<String, Object?> changes)? _apply;
  Map<String, Object?>? _pending;

  /// What the dock draws now, or null while no dock runs.
  Map<String, Object?>? get layout => _layout;

  bool get attached => _apply != null;

  /// The dock says what it draws. Never call it during a build.
  void publish(Map<String, Object?> layout) {
    if (_same(_layout, layout)) return;
    _layout = Map<String, Object?>.unmodifiable(layout);
    notifyListeners();
  }

  /// The dock starts taking changes. Changes asked for before it was ready
  /// are handed over now.
  void attach(void Function(Map<String, Object?> changes) apply) {
    _apply = apply;
    final pending = _pending;
    _pending = null;
    if (pending != null) apply(pending);
  }

  void detach(void Function(Map<String, Object?> changes) apply) {
    if (_apply != apply) return;
    _apply = null;
    _layout = null;
    notifyListeners();
  }

  /// Lays [changes] over the dock's layout. Keys it does not name stay.
  void apply(Map<String, Object?> changes) {
    final apply = _apply;
    if (apply == null) {
      _pending = <String, Object?>{...?_pending, ...changes};
      return;
    }
    apply(changes);
  }

  static bool _same(Object? a, Object? b) {
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final key in a.keys) {
        if (!b.containsKey(key) || !_same(a[key], b[key])) return false;
      }
      return true;
    }
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var index = 0; index < a.length; index++) {
        if (!_same(a[index], b[index])) return false;
      }
      return true;
    }
    return a == b;
  }
}
