import 'package:denial_dock/src/dock_visibility.dart';

void main() {
  bool hides(DockVisibilityMode mode, {required bool conflict}) =>
      DockVisibility.wantsHidden(mode: mode, conflict: conflict);

  _expect(
    hides(DockVisibilityMode.smart, conflict: true),
    'smart hides over a covered strip',
  );
  _expect(
    !hides(DockVisibilityMode.smart, conflict: false),
    'smart stays out when nothing covers it',
  );
  _expect(
    !hides(DockVisibilityMode.always, conflict: true),
    'always never hides',
  );
  _expect(
    hides(DockVisibilityMode.persistent, conflict: false) &&
        hides(DockVisibilityMode.persistent, conflict: true),
    'persistent hides with and without a window',
  );

  // Stored keys round-trip, and unknown values fall back to smart.
  for (final mode in DockVisibilityMode.values) {
    _expect(
      DockVisibilityMode.parse(mode.key) == mode,
      'round-trip ${mode.name}',
    );
  }
  _expect(
    DockVisibilityMode.parse(null) == DockVisibilityMode.smart,
    'missing key defaults to smart',
  );
  _expect(
    DockVisibilityMode.parse('tiling') == DockVisibilityMode.smart,
    'removed mode defaults to smart',
  );
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
