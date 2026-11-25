import 'package:denial_dock/src/dock_ink.dart';

void main() {
  _expect(
    (DockInk.luminance(1, 1, 1) - 1).abs() < 1e-9 &&
        DockInk.luminance(0, 0, 0) == 0,
    'white is one, black is nought',
  );
  _expect(
    DockInk.luminance(0, 1, 0) > DockInk.luminance(1, 0, 0) &&
        DockInk.luminance(1, 0, 0) > DockInk.luminance(0, 0, 1),
    'green weighs most, blue least',
  );

  // The macOS look's light plate: a mid grey at a quarter opacity. Over a
  // dark wallpaper it shows dark, so it takes light ink in a light
  // appearance too.
  const grey = 151 / 255;
  _expect(
    DockInk.shown(fill: grey, opacity: 0.25, backdrop: 0.1) < 0.3,
    'a thin light plate over a dark wallpaper is dark',
  );
  _expect(
    DockInk.lightInk(
      fill: grey,
      opacity: 0.25,
      backdrop: 0.1,
      themeDark: false,
    ),
    'light ink on it, whatever the appearance',
  );
  // The same plate over a bright wallpaper keeps dark ink, in a dark
  // appearance too.
  _expect(
    !DockInk.lightInk(
      fill: grey,
      opacity: 0.25,
      backdrop: 0.9,
      themeDark: true,
    ),
    'dark ink over a bright wallpaper',
  );

  // A solid plate is judged by its fill alone.
  for (final backdrop in const [0.0, 0.5, 1.0]) {
    _expect(
      DockInk.lightInk(
            fill: 0.12,
            opacity: 1,
            backdrop: backdrop,
            themeDark: false,
          ) &&
          !DockInk.lightInk(
            fill: 0.95,
            opacity: 1,
            backdrop: backdrop,
            themeDark: true,
          ),
      'an opaque plate ignores the wallpaper ($backdrop)',
    );
  }
  // A clear plate is judged by the wallpaper alone.
  _expect(
    DockInk.lightInk(fill: 1, opacity: 0, backdrop: 0.1, themeDark: false) &&
        !DockInk.lightInk(fill: 0, opacity: 0, backdrop: 0.9, themeDark: true),
    'a clear plate is the wallpaper',
  );

  // Close to the line either ink reads, and the appearance's own stays.
  _expect(
    DockInk.lightInk(fill: 0.52, opacity: 1, backdrop: 0, themeDark: true) &&
        !DockInk.lightInk(
          fill: 0.52,
          opacity: 1,
          backdrop: 0,
          themeDark: false,
        ) &&
        DockInk.lightInk(fill: 0.47, opacity: 1, backdrop: 0, themeDark: true) &&
        DockInk.lightInk(
          fill: 0.47,
          opacity: 1,
          backdrop: 0,
          themeDark: false,
        ),
    'just above the line the appearance decides, under it the ink is light',
  );
  _expect(
    DockInk.lightInk(fill: 0.40, opacity: 1, backdrop: 0, themeDark: false) &&
        !DockInk.lightInk(fill: 0.60, opacity: 1, backdrop: 0, themeDark: true),
    'past the band the plate decides',
  );

  // Opacity out of range, or not a number, is clamped or read as solid.
  _expect(
    DockInk.shown(fill: 0.2, opacity: 7, backdrop: 0.9) == 0.2 &&
        DockInk.shown(fill: 0.2, opacity: -3, backdrop: 0.9) == 0.9 &&
        DockInk.shown(fill: 0.2, opacity: double.nan, backdrop: 0.9) == 0.2,
    'opacity is clamped',
  );
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
