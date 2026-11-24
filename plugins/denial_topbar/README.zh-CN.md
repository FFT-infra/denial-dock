# Denial 顶栏

给 [Denial](https://github.com/denialwm/denial) 写的 macOS 风格菜单栏，中间带一个灵动岛。

**这是一个随手 vibe 出来的小玩具。** 不是 Denial 官方插件，没有维护承诺，也不保证稳定。它只在写它的那台机器上跑通过。

## 做了什么

- **菜单栏。** 系统菜单、当前应用名、工作区、托盘、状态项和时钟。可以贴边也可以悬浮。
- **灵动岛。** 正在播放、音量和亮度、充电、通知、屏幕录制、计时器，以及应用通过 Unity `LauncherEntry` 信号发出的进度。可以同时显示两个活动，左右轻扫换主次。
- **控制中心。** Wi-Fi、蓝牙、专注模式、外观、护眼、屏幕录制、亮度、音量和正在播放。控件可以增删、排序、换尺寸。
- **通知中心**，带日历、世界时钟、电池和处理器小组件。
- **托盘。** 每个托盘项目可以设成显示、收在箭头后面，或者永不显示。
- **指示。** 录屏时出现红色停止键，有应用在用麦克风时出现橙点。

设置入口：右键菜单栏，选「菜单栏设置…」。配置保存在 `~/.config/denial/plugins/denial_topbar.json`。

## 前提

- Denial 的 Flutter 3.47.5 / Dart 3.13 插件代际。
- 顶栏提供 `ShellWorkArea`，这个契约只能有一个插件提供。先关掉自带的顶栏：`denial-plugins remove denial_top_bar`。
- 麦克风指示需要 `pactl`，剪贴板历史需要 `wl-paste`。没有的话这两项是空的。

## 安装

```sh
denial-plugins add https://github.com/FFT-infra/denial-shell-plugins.git --path plugins/denial_topbar
denial-plugins apply
```

## 已知问题

- 切换护眼时整个界面会闪一下。护眼用的是桌面 LUT，Denial 在加载或清除 LUT 时会重启界面。
- 通知会在灵动岛和 Denial 自带的横幅各出现一次。插件关不掉横幅，可以关掉灵动岛的通知活动。
- 应用名后面没有应用菜单。Denial 不提供窗口对应的总线连接，没有菜单可显示。
- 没有天气、日历事件和蓝牙设备电量。

## 许可证

GPL-3.0-or-later。内置的 Inter 字体使用 SIL Open Font License，见 `assets/Inter-OFL.txt`。
