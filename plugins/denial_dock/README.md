# Dock for Denial

A small macOS-style dock for [Denial](https://github.com/denialwm/denial), the
Flutter-native Wayland compositor. It floats above windows along the bottom
edge, magnifies under the pointer, shows live window previews, and slides away
when a window reaches it.

**This is a casual, vibe-coded toy.** It is not an official Denial plugin and
comes with no support or stability promise. It works on the machine it was
written on; compositor updates may break it. Keep the undo path in mind before
turning it on.

## What it does

- **Wave magnification.** Icons grow with a smootherstep falloff ported from
  NextKDE's dock; the growth is real layout width, so neighbours are pushed
  aside and the capsule widens with the row instead of overlapping.
- **Pinned applications.** The default set is written on first run and kept in
  `~/.config/denial/plugins/denial_dock.json`. Running applications that are not
  pinned appear after a divider.
- **Window previews.** Hover an icon with two or more windows to open its tray.
  Hover one card for 300 ms to fade the other windows on that monitor; click a
  card to focus that window. Clicking a single-window icon activates or
  minimizes it.
- **Context menu.** Right-click an icon for open / new window, pin or unpin,
  and minimize. The menu and trays are drawn in the shell overlay, clamped to
  the monitor.
- **Drag to reorder.** Drag a pinned icon sideways to move it; drag it more than
  one icon height above the capsule to remove it from the dock. The icon lifts,
  grows slightly and turns translucent while held, and neighbours ease into
  place.
- **Smart auto-hide.** When a non-minimized window on the same output and
  workspace reaches the dock's strip, the capsule slides down. Moving the
  pointer to the bottom edge brings it back after 90 ms; it retracts 200 ms
  after the pointer leaves while the window still overlaps. A window parked
  exactly on the boundary does not make it flap.
- **Shell-native looks.** The capsule uses Denial's `ShellTheme` panel colour,
  backdrop blur, hairline border and corner radii, so it matches the top bar.

## Requirements

- Denial 0.6.8, or the matching Flutter 3.47.5 / Dart 3.13 plugin generation.
- The top bar stays in charge of the native work area. Denial 0.6.8 supports
  reserving space on one edge only, so this dock deliberately does not claim the
  bottom edge; fullscreen windows cover it, the same way they cover the Dock on
  macOS. In fullscreen the dock hides and comes back in overview or show
  desktop.

## Install

```sh
denial-plugins add https://github.com/FFT-infra/denial-dock.git --path plugins/denial_dock
denial-plugins apply
```

`denial-plugins undo` returns to the plugin set that ran before.

## Settings

The file is `~/.config/denial/plugins/denial_dock.json`:

```json
{
  "pinnedApplications": [
    {
      "id": "org.gnome.Nautilus.desktop",
      "appId": "org.gnome.Nautilus.desktop",
      "name": "Files"
    }
  ],
  "visibility": "smart"
}
```

- `id` is the launcher identity used to start an application; `appId` is the
  icon identity, normally the desktop file name.
- `visibility` is `"smart"` (auto-hide, default) or `"always"`.
- An empty list means you removed every pin.

There is no settings UI. The dock rewrites this file atomically when you pin,
unpin or reorder, and leaves unknown keys alone. Hand edits are read when the
plugin engine starts, so apply the plugin again (or restart the shell) after
changing the file.

## Known limitations

- One horizontal row. A dock wider than the screen has no scrolling or overflow
  mode.
- Every output gets its own dock, but drag and auto-hide were only exercised on
  a single monitor.
- Denial starts button pointers at the scene origin. The drag code works from
  absolute scene positions to compensate; the first few pixels of a drag can
  still feel less precise than a native toolkit drag.
- Previews use the shell's window texture service. Applications without a
  client texture fall back to a plain theme card.
- The dock stores no per-window state. Everything is derived from the shell's
  application, window and workspace services each frame.

## Development

The repository root is not a Dart package. Work inside
`plugins/denial_dock`. Point a git-ignored `pubspec_overrides.yaml` at your
Denial runtime's SDK packages, then run the checks with the Dart SDK from the
matching build kit:

```sh
dart format --output=none --set-exit-if-changed lib test
dart analyze --fatal-infos lib test
dart run test/dock_math_test.dart
dart run test/dock_layout_test.dart
dart run test/dock_drag_test.dart
```

The tests are small executable Dart programs. They exit non-zero with a message
on failure.

## License

GPL-3.0-or-later. See [LICENSE](LICENSE); the full text is in
[LICENSES/GPL-3.0-only.txt](../../LICENSES/GPL-3.0-only.txt).

[中文说明](README.zh-CN.md)
