# Denial Top Bar

A macOS-style menu bar for [Denial](https://github.com/denialwm/denial), with a
Dynamic Island in the middle.

**This is a casual, vibe-coded toy.** It is not an official Denial plugin and
comes with no support or stability promise. It has only run on the machine it
was written on.

## What it does

- **Menu bar.** A system menu, the focused application's name, workspaces,
  tray, status items and the clock. The bar can be attached to the edge or
  float.
- **Dynamic Island.** Now playing, volume and brightness, charging,
  notifications, screen recording, a timer, and the progress applications
  publish through the Unity `LauncherEntry` signal. Two activities can show at
  once; swipe sideways to change which is in front.
- **Control centre.** Wi-Fi, Bluetooth, focus, appearance, night light, screen
  recording, brightness, volume and now playing. The controls can be added,
  removed, reordered and resized.
- **Notification centre** with a calendar, world clock, battery and processor
  widgets.
- **Tray.** Each tray item can be shown, hidden behind a chevron, or never
  shown.
- **Indicators.** A red stop button while the screen is recorded and an orange
  dot while an application records from a microphone.

- **Motion.** Every transition the bar draws runs on one clock with a speed
  setting (0.5× to 2×) in Menu Bar Settings, under Appearance. The system's
  reduced-motion flag still turns transitions into instant changes; a
  repeating animation keeps its rhythm at whatever speed is set.

Settings: right-click the bar and choose Menu Bar Settings… They are saved in
`~/.config/denial/plugins/denial_topbar.json`. The speed and the look's
choice live in `denial_shell_kit.json` beside it, shared with the dock.

## Requirements

- The Flutter 3.47.5 / Dart 3.13 plugin generation of Denial.
- The bar provides `ShellWorkArea`, which only one plugin may do. Turn the
  built-in top bar off first: `denial-plugins remove denial_top_bar`.
- `pactl` for the microphone indicator and `wl-paste` for the clipboard
  history. Without them those two features stay empty.

## Install

```sh
denial-plugins add https://github.com/FFT-infra/denial-shell-plugins.git --path plugins/denial_topbar
denial-plugins apply
```

## Known limitations

- Switching night light makes the whole interface blink. Night light is a
  desktop LUT, and Denial restarts its interface when one is loaded or cleared.
- A notification shows both in the island and as Denial's own banner. The
  plugin cannot turn the banner off; turn the island's notification activity
  off instead.
- There is no application menu after the application's name. Denial does not
  say which bus connection a window belongs to, so there is no menu to show.
- No weather, no calendar events, and no battery level for Bluetooth devices.

## License

GPL-3.0-or-later. The vendored Inter font is under the SIL Open Font License,
see `assets/Inter-OFL.txt`. The vendored CupertinoIcons glyphs are under the
MIT license, see `assets/CupertinoIcons-LICENSE.txt`.
