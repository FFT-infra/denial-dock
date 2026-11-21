import 'package:denial_dock/src/dock_visibility.dart';

void main() {
  // Smart mode retracts only while the layout floats.
  _expect(
    DockVisibility.smartHideActive(
      mode: DockVisibilityMode.smart,
      tiling: false,
    ),
    'smart hides over floating windows',
  );
  _expect(
    !DockVisibility.smartHideActive(
      mode: DockVisibilityMode.smart,
      tiling: true,
    ),
    'smart stays resident while tiling',
  );
  _expect(
    !DockVisibility.smartHideActive(
      mode: DockVisibilityMode.always,
      tiling: false,
    ),
    'always never hides',
  );
  _expect(
    !DockVisibility.smartHideActive(
      mode: DockVisibilityMode.always,
      tiling: true,
    ),
    'always never hides while tiling',
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
