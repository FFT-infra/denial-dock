# Denial shell plugins

A macOS-style dock and menu bar for [Denial](https://github.com/denialwm/denial).
This repository is a source container. Each plugin is its own Dart package, and
installing one does not enable the other.

**These are casual, vibe-coded toys.** They are not official Denial plugins and
come with no support or stability promise.

| Package | Path | Purpose |
| --- | --- | --- |
| `denial_dock` | [`plugins/denial_dock`](plugins/denial_dock) | Dock with wave magnification, window previews, folder stacks, drag reorder and smart auto-hide. |
| `denial_topbar` | [`plugins/denial_topbar`](plugins/denial_topbar) | Menu bar with a Dynamic Island, control centre, notification centre, workspaces and tray. |
| `denial_shell_kit` | [`packages/denial_shell_kit`](packages/denial_shell_kit) | Library both plugins draw with: the look, the motion clock, popup layers and panel placement. Not a plugin; it comes along as a dependency. |

`plugins.yaml` lists the installable plugins for Denial's Plugin Manager.

## How the pieces fit

Both plugins run inside Denial's shell process and share one library, so a
choice made in one is seen by the other at once.

- The **top bar** is the plugin that reserves the native work area; Denial
  allows one plugin to reserve one edge. The **dock** deliberately reserves
  nothing, so the two can be installed in either order and the bar stays in
  charge of the edge.
- The **look** (Denial or macOS styling) and the **motion speed** are stored in
  `~/.config/denial/plugins/denial_shell_kit.json` and shared. Each plugin's own
  settings stay in its own file: `denial_topbar.json`, `denial_dock.json`.
- Either plugin works alone. Without the top bar there is no reservation, so a
  maximised window covers the dock's strip; without the dock the bar is
  unchanged.

## Install

```sh
denial-plugins add https://github.com/FFT-infra/denial-shell-plugins.git --path plugins/denial_dock
denial-plugins add https://github.com/FFT-infra/denial-shell-plugins.git --path plugins/denial_topbar
denial-plugins apply
```

Add either line or both. The top bar reserves the native work area, so turn
Denial's built-in top bar off before applying it:
`denial-plugins remove denial_top_bar`. `denial-plugins undo` returns to the
previous plugin set.

Requirements, settings and limitations are in each package's README:
dock [English](plugins/denial_dock/README.md) ·
[中文](plugins/denial_dock/README.zh-CN.md), top bar
[English](plugins/denial_topbar/README.md) ·
[中文](plugins/denial_topbar/README.zh-CN.md).

Chinese overview of this repository: [README.zh-CN.md](README.zh-CN.md).

## License

GPL-3.0-or-later. See [LICENSE](LICENSE) and
[LICENSES/GPL-3.0-only.txt](LICENSES/GPL-3.0-only.txt).
