import 'package:denial_dock/src/dock_visibility.dart';

void main() {
  _expect(
    DockVisibility.smartHideActive(mode: DockVisibilityMode.smart),
    'smart hides over a covered strip',
  );
  _expect(
    !DockVisibility.smartHideActive(mode: DockVisibilityMode.always),
    'always never hides',
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
