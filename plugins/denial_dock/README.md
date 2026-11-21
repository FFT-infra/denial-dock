# Dock for Denial

A small macOS-style dock for [Denial](https://github.com/denialwm/denial), the
Flutter-native Wayland compositor. It floats above windows on the bottom, left
or right edge, magnifies under the pointer, shows live window previews, and
slides away when a window reaches it.

**This is a casual, vibe-coded toy.** It is not an official Denial plugin and
comes with no support or stability promise. It works on the machine it was
written on; compositor updates may break it. Keep the undo path in mind before
turning it on.

## What it does

- **Wave magnification.** Icons grow with a smootherstep falloff ported from
  NextKDE's dock, holding the peak across the icon's own slot and then decaying
  to the magnification radius. The growth is real layout width, so neighbours
  are pushed aside and the capsule widens with the row instead of overlapping.
- **macOS arrangement.** Applications sit in the middle. A hairline divider
  separates them from running-but-unpinned applications, and a second divider
  separates the running group from the accessories: folder shortcuts, then the
  trash can last. A divider only appears when both of its sides are non-empty.
  The launcher is not an accessory; it can sit on the left end (default, like
  Launchpad), the right end, or not at all.
- **Pinned applications.** A fresh install starts with an empty dock; pin a
  running application from its context menu or by dragging it into the pinned
  section. The list is kept in `~/.config/denial/plugins/denial_dock.json`.
- **Launch feedback.** A launching icon hops 0.65 of its height over 0.48 s and
  glides back down in 0.13 s. The hop stops as soon as a window appears, and
  after 500 ms at the earliest; it gives up after 15 s, or immediately if the
  launch fails.
- **Window previews.** Hover an icon with two or more windows to open its tray.
  Hover one card for 300 ms to fade the other windows on that monitor; click a
  card to focus that window. The icon's name label appears after a 250 ms
  dwell above the magnified icon, on a pill with a tail pointing down at it,
  and the running indicator shows one to three dots.
- **Click behaviour.** Clicking an icon with windows either minimizes the
  active window (default) or cycles to the next one; the choice is in the
  settings sheet. Clicking an application with no windows launches it.
- **Context menu.** Right-click an icon for open / new window, show all
  windows, pin or unpin, minimize, and close. Escape closes the menu, and
  right-clicking the same icon again toggles it. The menu and trays are drawn
  in the shell overlay, clamped to the monitor. On a touch or pen pointer, a
  550 ms press opens the same menu.
- **Drag to reorder and pin.** Drag a pinned icon sideways to move it; drag a
  running icon left across the divider to pin it at the drop position; drag a
  pinned icon more than one icon height above the capsule to remove it. Only
  primary-button drags start a move. The icon lifts, grows slightly and turns
  translucent while held, and neighbours ease into place.
- **Smart auto-hide.** When a non-minimized floating window on the same output
  and workspace reaches the dock's strip, the capsule slides down. Moving the
  pointer to the bottom edge brings it back after 90 ms, and tapping that edge
  does the same for touch and pen, which produce no hover; a tap holds the dock
  out for four seconds so the finger can reach an icon. It retracts 200 ms
  after the pointer leaves while a window still reaches the capsule, and comes
  back as soon as that window clears the capsule itself. A window parked
  exactly on the boundary does not make it flap. Tiles reach the edge like any
  other window, so a tiling layout retracts too.
- **Folder shortcuts and Trash.** Add any folder from the settings sheet
  through a built-in directory browser, with hidden entries behind a toggle.
  Clicking a shortcut opens the folder with the system handler (`xdg-open`,
  falling back to `gio open`). The trash can opens `trash:///` through `gio`
  first, because `xdg-open` treats the scheme as a web address, shows a count
  badge, and offers *Empty Trash*; emptying needs a second press, because it
  cannot be undone.
- **Dock menu and settings sheet.** Right-clicking the capsule background or the
  launcher opens a small dock menu, modelled on the macOS Dock menu: turn hiding
  on or off, turn magnification on or off, then *Position on Screen* with a
  checkmark on the current edge, then *Dock settings…*. Folder and trash icons
  offer the same entry in their own menus. The sheet is a managed shell popup,
  so it gets the scene barrier, focus, Escape and outside-tap dismissal. It
  covers visibility, click behaviour, edge, icon size, magnification amount,
  launch bounce, running indicators, suggested applications, which end the
  launcher and the accessories sit on, the trash toggle and the folder list.
- **Shell-native looks.** The capsule and the settings sheet use Denial's
  `ShellTheme` panel colour, backdrop blur, hairline border and corner radii,
  so they match the top bar.

## Requirements

- Denial 0.6.8, or the matching Flutter 3.47.5 / Dart 3.13 plugin generation.
- The top bar stays in charge of the native work area. Denial 0.6.8 supports
  reserving space on one edge only, so this dock deliberately does not claim the
  bottom edge; fullscreen windows cover it, the same way they cover the Dock on
  macOS. In fullscreen the dock hides and comes back in overview or show
  desktop. Tiled windows run under the capsule while it is out. The gap you may
  see at the bottom comes from `maximizePadding` in Denial's own settings
  (default 8), not from this plugin.

## Install

```sh
denial-plugins add https://github.com/FFT-infra/denial-dock.git --path plugins/denial_dock
denial-plugins apply
```

`denial-plugins undo` returns to the plugin set that ran before.

## Settings

Most settings live in the settings sheet. The same values are stored in
`~/.config/denial/plugins/denial_dock.json`:

```json
{
  "pinnedApplications": [
    {
      "id": "org.gnome.Nautilus.desktop",
      "appId": "org.gnome.Nautilus.desktop",
      "name": "Files"
    }
  ],
  "visibility": "smart",
  "clickAction": "minimize",
  "iconSize": 48,
  "magnification": true,
  "magnificationAmount": 0.6,
  "position": "bottom",
  "bounceOnLaunch": true,
  "showIndicators": true,
  "showSuggestions": true,
  "iconMode": "color",
  "revealIndicator": true,
  "launcherSide": "left",
  "extrasSide": "right",
  "showTrash": true,
  "folders": [{ "path": "/home/me/Documents", "label": "Documents" }]
}
```

- `id` is the launcher identity used to start an application; `appId` is the
  icon identity, normally the desktop file name.
- `visibility` is `"smart"` (auto-hide while windows float, default) or
  `"always"`.
- `clickAction` is `"minimize"` (default) or `"cycle"`.
- `iconSize` is in logical pixels, clamped to 32–72 in steps of 4; the default
  is 48.
- `magnification` (default `true`) makes icons grow under the pointer. Off keeps
  every icon at `iconSize` and the capsule at its resting width.
- `magnificationAmount` is the share of the 1.6x peak reached under the
  pointer, clamped to 0–1; the default is 0.6.
- `position` is `"bottom"` (default), `"left"` or `"right"`. The capsule turns
  with the edge: magnification runs along the row, labels and menus open away
  from the edge, and indicators sit on the inner side.
- `bounceOnLaunch` (default `true`) plays the hop while an application starts.
- `showIndicators` (default `true`) draws the running dots.
- `showSuggestions` (default `true`) appends recently used applications that
  are not pinned, after a divider.
- `iconMode` is `"color"` (default), `"grayscale"` or `"tinted"`; tinted
  multiplies the icon through the theme accent.
- `revealIndicator` (default `true`) draws a short bar on the screen edge while
  the dock is retracted.
- `launcherSide` and `extrasSide` are `"left"`, `"right"` or `"hidden"`.
  Accessories (folders and trash) default to the right; the launcher defaults
  to the left. Trash stays the last item inside the accessory group.
- `showTrash` turns the trash can off without touching the folder list.
- `folders` holds absolute paths; a missing `label` falls back to the
  directory's basename. Duplicate paths are collapsed.
- An empty `pinnedApplications` list means you removed every pin.

The dock rewrites this file atomically, merging over the existing keys so
unknown keys survive. Hand edits are read when the plugin engine starts, so
apply the plugin again (or restart the shell) after changing the file by hand.
Values the dock cannot parse fall back to the defaults rather than throwing.

## Known limitations

- A dock longer than the edge it sits on has no scrolling or overflow mode.
- Every output gets its own dock, but drag and auto-hide were only exercised on
  a single monitor.
- No quit, hide or per-application autostart. `ShellWindowServices` exposes
  activate, minimize and close only, so a menu entry for them would be dead.
- No notification badges. `desktopNotificationsProvider` carries a
  `desktopEntry` per notification that does not reliably match a launcher id.
- Windows cannot be dropped onto an icon. The shell forwards no external drag.
- Denial starts button pointers at the scene origin. The drag code works from
  absolute scene positions to compensate; the first few pixels of a drag can
  still feel less precise than a native toolkit drag.
- Previews use the shell's window texture service. Applications without a
  client texture fall back to a plain theme card.
- The dock stores no per-window state. Everything is derived from the shell's
  application, window and workspace services each frame.
- The trash count reads the home trash and the per-mount trash directories of
  every mount in `/proc/self/mounts`. Items in a trash directory the dock cannot
  read are not counted.
- Folder shortcuts open through `xdg-open` with a `gio open` fallback; the
  trash tries `gio` first. Without either, clicking them does nothing.
- The plugin has no settings-page contract in Denial 0.6.8. The sheet is a
  shell popup owned by the dock, so it is not listed in any system settings
  application.

## Development

The repository root is not a Dart package. Work inside
`plugins/denial_dock`. Point a git-ignored `pubspec_overrides.yaml` at your
Denial runtime's SDK packages, then run the checks with the Dart SDK from the
matching build kit:

```sh
dart format --output=none --set-exit-if-changed lib test
dart analyze lib test
for test in test/*_test.dart; do dart run "$test" || exit 1; done
```

The tests are small executable Dart programs. They exit non-zero with a message
on failure.

## License

GPL-3.0-or-later. See [LICENSE](LICENSE); the full text is in
[LICENSES/GPL-3.0-only.txt](../../LICENSES/GPL-3.0-only.txt).

[中文说明](README.zh-CN.md)
