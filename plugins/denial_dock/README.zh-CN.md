# Denial Dock

给 [Denial](https://github.com/denialwm/denial) 写的一个 macOS 风格小 Dock。Denial 是跑在 Wayland 上的 Flutter 桌面。Dock 浮在窗口上方贴着屏幕底边，鼠标经过时放大，多窗口应用能弹出预览，窗口压到底部时自动收起。

**这是一个随手 vibe 出来的小玩具。** 不是 Denial 官方插件，没有维护承诺，也不保证稳定。它只在写它的那台机器上跑通过，compositor 升级后可能就坏。开之前想好怎么回退。

## 做了什么

- **波浪放大。** 放大曲线从 NextKDE 的 dock 移植过来，用 smootherstep 衰减，在图标自己的格宽内保持峰值，再衰减到放大半径。放大是真实布局宽度，邻居会被推开，胶囊跟着变宽，不是互相盖住。
- **macOS 式排布。** 应用排在中间。一条发丝分隔线隔开「已固定」和「运行中但没固定」的应用，第二条分隔线隔开运行区和配件区：文件夹快捷方式在前，回收站固定最后。两侧都非空才画分隔线。启动台不算配件，可以放左端（默认，对应 Launchpad 的位置）、右端，或者不显示。
- **固定应用。** 新装好的 Dock 默认是空的；运行中的应用可以在右键菜单里固定，也可以直接拖进固定区。列表保存在 `~/.config/denial/plugins/denial_dock.json`。
- **启动反馈。** 启动中的图标跳起图标高度的 0.65，用 0.48s 上升、0.13s 落回。窗口一出现就结束，最短 500ms；15s 还没出现就放弃，启动失败立即停。
- **窗口预览。** 图标有两个以上窗口时，悬停弹出预览。在某个预览上停 300ms，同显示器的其他窗口淡出；点预览切到那个窗口。名称标签悬停 250ms 后出现，运行指示点一到三个。
- **点击行为。** 有窗口的应用，点击可以是最小化当前窗口（默认），也可以是按窗口顺序切到下一个，在设置面板里选。没有窗口的应用点击就是启动。
- **右键菜单。** 打开、新窗口、显示所有窗口、固定或移出 Dock、最小化、关闭。Escape 关闭菜单，在同一图标上再右键一次也会收起。菜单和预览画在 shell overlay 里，位置限制在显示器范围内。触摸或手写笔指针长按 550ms 打开同一个菜单。
- **拖拽排序和固定。** 横向拖动固定图标可以换位置；把运行中的图标往左拖过分隔线，会在落点固定；固定图标拖到胶囊上方超过一个图标高度就移出 Dock。只有左键拖动才会开始移动。拖动时图标抬起、略微放大、变半透明，邻居 180ms 缓动让位。
- **智能收起。** 当前显示器、当前工作区里有没最小化的浮动窗口碰到 Dock 所在的条带，胶囊滑下去。指针挪到最底边，90ms 后重新拉出；触摸和手写笔不产生悬停，所以在底边点一下也能拉出，并且保持 4 秒，够手指移动到图标上。指针离开且窗口还压着胶囊，200ms 后收起；窗口退出胶囊本身的范围就立刻回来。窗口正好停在边界上不会来回抖。窗口布局是平铺（dwindle / scrolling）时 Dock 保持常驻：平铺窗口本来就贴着底边，按遮挡收起会让 Dock 一直不出现。
- **文件夹快捷方式和回收站。** 设置面板里用内置目录浏览器添加任意文件夹，点文件夹图标打开，默认用系统程序（`xdg-open`，没有就退回 `gio open`），隐藏目录有开关。回收站打开 `trash:///` 时先用 `gio`，因为 `xdg-open` 会把这个 scheme 当网址丢给浏览器；带数量角标，可以清空，清空要点两次，因为删了回不来。
- **Dock 菜单和设置面板。** 右键胶囊空白处或启动台，先弹出一个照 macOS Dock 菜单做的小菜单：启用/关闭隐藏、开启/关闭放大，然后一条分隔线接「Dock 设置…」。文件夹和回收站的菜单里也有同一个入口。面板是 Denial 的托管 shell popup，自带遮罩、焦点、Escape 和点外面关闭。里面能改：显示方式、点击行为、图标大小、放大开关、启动台和配件区放哪边、回收站开关、文件夹列表。
- **跟 shell 同一套视觉。** 胶囊和设置面板都用 Denial 的 `ShellTheme`：面板色、背景模糊、发丝边框、圆角，和顶栏一套材质。

## 前提

- Denial 0.6.8，或对应的 Flutter 3.47.5 / Dart 3.13 插件代际。
- 原生 work area 留给顶栏。Denial 0.6.8 只支持在一条边上预留空间，所以这个 Dock 不去抢底边；全屏窗口会盖住它，和 macOS 上全屏盖住 Dock 一样。全屏时 Dock 隐藏，概览或显示桌面时回来。平铺窗口同理也会从胶囊下面穿过。平铺时底边留出的空隙来自 Denial 自己的 `maximizePadding` 设置（默认 8），不是这个插件造成的。

## 安装

```sh
denial-plugins add https://github.com/FFT-infra/denial-dock.git --path plugins/denial_dock
denial-plugins apply
```

想退回去就 `denial-plugins undo`。

## 设置

大部分设置都在设置面板里改。同一批值存在 `~/.config/denial/plugins/denial_dock.json`：

```json
{
  "pinnedApplications": [
    {
      "id": "org.gnome.Nautilus.desktop",
      "appId": "org.gnome.Nautilus.desktop",
      "name": "文件"
    }
  ],
  "visibility": "smart",
  "clickAction": "minimize",
  "iconSize": 48,
  "magnification": true,
  "launcherSide": "left",
  "extrasSide": "right",
  "showTrash": true,
  "folders": [{ "path": "/home/me/Documents", "label": "文档" }]
}
```

- `id` 是启动应用用的 launcher 身份，`appId` 是图标身份，一般就是 desktop 文件名。
- `visibility` 是 `"smart"`（浮动窗口遮挡时自动收起，默认）或 `"always"`。
- `clickAction` 是 `"minimize"`（默认）或 `"cycle"`。
- `iconSize` 是逻辑像素，夹在 32–72 之间，步进 4，默认 48。
- `magnification` 默认 `true`，指针经过时图标放大。关掉后所有图标保持 `iconSize`，胶囊也不变宽。
- `launcherSide` 和 `extrasSide` 是 `"left"`、`"right"` 或 `"hidden"`。配件区（文件夹和回收站）默认在右，启动台默认在左。回收站在配件组里永远排最后。
- `showTrash` 单独关掉回收站，不动文件夹列表。
- `folders` 存绝对路径；没写 `label` 就用目录名。重复路径会合并。
- `pinnedApplications` 为空表示固定项都被移除了。

Dock 原子地重写这个文件，按已有内容合并，不认识的键保留。手改之后要重新 apply 插件或者重启 shell 才会读到，因为设置只在插件引擎启动时读一次。读不懂的值退回默认，不抛异常。

## 已知问题

- 只有一行横排。Dock 比屏幕还宽时没有滚动或折行。
- 每个显示器都会有自己的 Dock，但拖拽和自动收起只在一台显示器上实际验证过。
- Denial 在按下鼠标时会把按钮指针的起点报成场景原点。拖拽靠绝对场景坐标来绕开这个问题，开头几个像素的手感还是不如原生工具包的拖拽。
- 预览用的是 shell 的窗口纹理服务。没有客户端纹理的应用会显示成一块纯色卡片。
- Dock 自己不做窗口状态缓存，应用、窗口、工作区都每帧从 shell 的服务里算。
- 回收站数量读的是主目录回收站和 `/proc/self/mounts` 里每个挂载点各自的回收站目录，读不到的条目不计入。
- 文件夹靠 `xdg-open` 打开，没有就退回 `gio open`；回收站先试 `gio`。两个都没有时点击没反应。
- Denial 0.6.8 没有插件设置页接口。这个面板是 Dock 自己开的 shell popup，不会出现在任何系统设置应用里。

## 开发

仓库根目录不是 Dart 包，进 `plugins/denial_dock` 工作。把 git 忽略的 `pubspec_overrides.yaml` 指向本机 Denial runtime 的 SDK 包，然后用对应 build kit 里的 Dart SDK 跑检查：

```sh
dart format --output=none --set-exit-if-changed lib test
dart analyze lib test
for test in test/*_test.dart; do dart run "$test" || exit 1; done
```

测试就是几个可以直接执行的 Dart 小程序，失败时以非零状态退出并打印原因。

## 许可证

GPL-3.0-or-later。见 [LICENSE](LICENSE)，全文在 [LICENSES/GPL-3.0-only.txt](../../LICENSES/GPL-3.0-only.txt)。

[English](README.md)
