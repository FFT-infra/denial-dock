# Denial shell 插件

给 [Denial](https://github.com/denialwm/denial) 写的 macOS 风格 Dock 和菜单栏。仓库是源码容器，每个插件是一个独立的 Dart 包，装一个不会带上另一个。

**这是随手 vibe 出来的小玩具。** 不是 Denial 官方插件，没有维护承诺，也不保证稳定。

| 包 | 路径 | 说明 |
| --- | --- | --- |
| `denial_dock` | [`plugins/denial_dock`](plugins/denial_dock) | Dock：波浪放大、窗口预览、文件夹堆叠、拖拽排序、智能收起。 |
| `denial_topbar` | [`plugins/denial_topbar`](plugins/denial_topbar) | 菜单栏：灵动岛、控制中心、通知中心、工作区、托盘。 |
| `denial_shell_kit` | [`packages/denial_shell_kit`](packages/denial_shell_kit) | 两个插件共用的库。它不是插件，作为依赖一起带上。 |

`plugins.yaml` 是给 Denial 插件管理器看的目录，只列可安装的插件。

## 安装

```sh
denial-plugins add https://github.com/FFT-infra/denial-shell-plugins.git --path plugins/denial_dock
denial-plugins add https://github.com/FFT-infra/denial-shell-plugins.git --path plugins/denial_topbar
denial-plugins apply
```

两行可以只加一行。顶栏要占用原生 work area，apply 之前先关掉 Denial 自带的顶栏：`denial-plugins remove denial_top_bar`。想退回去就 `denial-plugins undo`。

前提、设置和已知问题在各自的 README：Dock
[中文](plugins/denial_dock/README.zh-CN.md) ·
[English](plugins/denial_dock/README.md)，顶栏
[中文](plugins/denial_topbar/README.zh-CN.md) ·
[English](plugins/denial_topbar/README.md)。

## 许可证

GPL-3.0-or-later。见 [LICENSE](LICENSE) 和 [LICENSES/GPL-3.0-only.txt](LICENSES/GPL-3.0-only.txt)。
