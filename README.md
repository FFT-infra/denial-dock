# Denial dock plugin

A macOS-style floating dock for [Denial](https://github.com/denialwm/denial).
This repository is a source container; the plugin is the Dart package under
`plugins/denial_dock`.

**This is a casual, vibe-coded toy.** It is not an official Denial plugin and
comes with no support or stability promise.

| Package | Path | Purpose |
| --- | --- | --- |
| `denial_dock` | [`plugins/denial_dock`](plugins/denial_dock) | Bottom dock with wave magnification, window previews, drag reorder and smart auto-hide. |

## Install

```sh
denial-plugins add https://github.com/FFT-infra/denial-dock.git --path plugins/denial_dock
denial-plugins apply
```

`denial-plugins undo` returns to the previous plugin set.

Requirements, settings, limitations and development notes are in the package
README: [English](plugins/denial_dock/README.md) ·
[中文](plugins/denial_dock/README.zh-CN.md).

Chinese overview of this repository: [README.zh-CN.md](README.zh-CN.md).

## License

GPL-3.0-or-later. See [LICENSE](LICENSE) and
[LICENSES/GPL-3.0-only.txt](LICENSES/GPL-3.0-only.txt).
