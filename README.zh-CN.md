# Denial dock 插件

给 [Denial](https://github.com/denialwm/denial) 写的 macOS 风格悬浮 Dock。仓库是源码容器，插件本体是 `plugins/denial_dock` 下的 Dart 包。

**这是一个随手 vibe 出来的小玩具。** 不是 Denial 官方插件，没有维护承诺，也不保证稳定。

| 包 | 路径 | 说明 |
| --- | --- | --- |
| `denial_dock` | [`plugins/denial_dock`](plugins/denial_dock) | 底部 Dock：波浪放大、窗口预览、拖拽排序、智能收起。 |

## 安装

```sh
denial-plugins add https://github.com/FFT-infra/denial-dock.git --path plugins/denial_dock
denial-plugins apply
```

想退回去就 `denial-plugins undo`。

前提、设置、已知问题和开发说明在插件 README：
[中文](plugins/denial_dock/README.zh-CN.md) ·
[English](plugins/denial_dock/README.md)。

## 许可证

GPL-3.0-or-later。见 [LICENSE](LICENSE) 和 [LICENSES/GPL-3.0-only.txt](LICENSES/GPL-3.0-only.txt)。
