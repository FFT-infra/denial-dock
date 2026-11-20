# Denial Dock

给 [Denial](https://github.com/denialwm/denial) 写的一个 macOS 风格小 Dock。Denial 是跑在 Wayland 上的 Flutter 桌面。Dock 浮在窗口上方贴着屏幕底边，鼠标经过时放大，多窗口应用能弹出预览，窗口压到底部时自动收起。

**这是一个随手 vibe 出来的小玩具。** 不是 Denial 官方插件，没有维护承诺，也不保证稳定。它只在写它的那台机器上跑通过，compositor 升级后可能就坏。开之前想好怎么回退。

## 做了什么

- **波浪放大。** 放大曲线从 NextKDE 的 dock 移植过来，用 smootherstep 衰减。放大是真实布局宽度，邻居会被推开，胶囊跟着变宽，不是互相盖住。
- **固定应用。** 第一次运行写入默认列表，保存在 `~/.config/denial/plugins/denial_dock.json`。没固定的运行中应用排在分隔线后面。
- **窗口预览。** 图标有两个以上窗口时，悬停弹出预览。在某个预览上停 300ms，同显示器的其他窗口淡出；点预览切到那个窗口。单窗口图标点击是激活或最小化。
- **右键菜单。** 打开、新窗口、固定或移出 Dock、最小化。菜单和预览画在 shell overlay 里，位置限制在显示器范围内。
- **拖拽排序。** 横向拖动固定图标可以换位置；拖到胶囊上方超过一个图标高度就移出 Dock。拖动时图标抬起、略微放大、变半透明，邻居 180ms 缓动让位。
- **智能收起。** 当前显示器、当前工作区里有没最小化的窗口碰到 Dock 所在的条带，胶囊滑下去。指针挪到最底边，90ms 后重新拉出；指针离开且窗口还压着，200ms 后收起。窗口正好停在边界上不会来回抖。
- **跟 shell 同一套视觉。** 胶囊用 Denial 的 `ShellTheme`：面板色、背景模糊、发丝边框、圆角，和顶栏一套材质。

## 前提

- Denial 0.6.8，或对应的 Flutter 3.47.5 / Dart 3.13 插件代际。
- 原生 work area 留给顶栏。Denial 0.6.8 只支持在一条边上预留空间，所以这个 Dock 不去抢底边；全屏窗口会盖住它，和 macOS 上全屏盖住 Dock 一样。全屏时 Dock 隐藏，概览或显示桌面时回来。

## 安装

```sh
denial-plugins add https://github.com/FFT-infra/denial-dock.git --path plugins/denial_dock
denial-plugins apply
```

想退回去就 `denial-plugins undo`。

## 设置

文件在 `~/.config/denial/plugins/denial_dock.json`：

```json
{
  "pinnedApplications": [
    {
      "id": "org.gnome.Nautilus.desktop",
      "appId": "org.gnome.Nautilus.desktop",
      "name": "文件"
    }
  ],
  "visibility": "smart"
}
```

- `id` 是启动应用用的 launcher 身份，`appId` 是图标身份，一般就是 desktop 文件名。
- `visibility` 是 `"smart"`（自动收起，默认）或 `"always"`。
- 空列表表示用户把固定项全移除了。

没有设置界面。固定、取消固定、排序时 Dock 会原子地重写这个文件，不认识的键保留。手改之后要重新 apply 插件或者重启 shell 才会读到，因为设置只在插件引擎启动时读一次。

## 已知问题

- 只有一行横排。Dock 比屏幕还宽时没有滚动或折行。
- 每个显示器都会有自己的 Dock，但拖拽和自动收起只在一台显示器上实际验证过。
- Denial 在按下鼠标时会把按钮指针的起点报成场景原点。拖拽靠绝对场景坐标来绕开这个问题，开头几个像素的手感还是不如原生工具包的拖拽。
- 预览用的是 shell 的窗口纹理服务。没有客户端纹理的应用会显示成一块纯色卡片。
- Dock 自己不做窗口状态缓存，应用、窗口、工作区都每帧从 shell 的服务里算。

## 开发

仓库根目录不是 Dart 包，进 `plugins/denial_dock` 工作。把 git 忽略的 `pubspec_overrides.yaml` 指向本机 Denial runtime 的 SDK 包，然后用对应 build kit 里的 Dart SDK 跑检查：

```sh
dart format --output=none --set-exit-if-changed lib test
dart analyze --fatal-infos lib test
dart run test/dock_math_test.dart
dart run test/dock_layout_test.dart
dart run test/dock_drag_test.dart
```

测试就是几个可以直接执行的 Dart 小程序，失败时以非零状态退出并打印原因。

## 许可证

GPL-3.0-or-later。见 [LICENSE](LICENSE)，全文在 [LICENSES/GPL-3.0-only.txt](../../LICENSES/GPL-3.0-only.txt)。

[English](README.md)
