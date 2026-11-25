# Denial Dock

给 [Denial](https://github.com/denialwm/denial) 写的一个 macOS 风格小 Dock。Denial 是跑在 Wayland 上的 Flutter 桌面。Dock 浮在窗口上方贴着底边、左边或右边，鼠标经过时放大，多窗口应用能弹出预览，窗口压上来时自动收起。

**这是一个随手 vibe 出来的小玩具。** 不是 Denial 官方插件，没有维护承诺，也不保证稳定。它只在写它的那台机器上跑通过，compositor 升级后可能就坏。开之前想好怎么回退。

## 做了什么

- **波浪放大。** 放大曲线从 NextKDE 的 dock 移植过来，用 smootherstep 衰减，在图标自己的格宽内保持峰值，再衰减到放大半径。放大是真实布局宽度，邻居会被推开，胶囊跟着变宽，不是互相盖住。
- **macOS 式排布。** 应用排在中间。一条发丝分隔线隔开「已固定」和「运行中但没固定」的应用，第二条分隔线隔开运行区和配件区：文件夹快捷方式在前，回收站固定最后。两侧都非空才画分隔线。启动台不算配件，可以放左端（默认，对应 Launchpad 的位置）、右端，或者不显示。
- **固定应用。** 新装好的 Dock 默认是空的；运行中的应用可以在右键菜单里固定，也可以直接拖进固定区。列表保存在 `~/.config/denial/plugins/denial_dock.json`。
- **启动反馈。** 启动中的图标跳起图标高度的 0.65，用 0.48s 上升、0.13s 落回；也可以选成透明度在 1 和 0.7 之间呼吸，或者不动。窗口一出现就结束，最短 500ms；5s 还没出现就放弃，启动失败立即停。
- **窗口预览。** 两种排布。横排卡片默认等 600ms，可在设置里调（0–1500ms）；竖排列表用同一个等待，单个窗口也弹，每行带关闭按钮；竖排会跟着指针走，移到相邻的运行图标上直接换过去，不用重新等。在某个预览上停 300ms，同显示器的其他窗口淡出；点预览切到那个窗口。名称标签悬停 250ms 后出现在放大后的图标上方，胶囊形状带一个指向下方的小尾巴。运行标记可以是一个窗口一个点（最多三个）、一条横条，或者不画。
- **通知角标。** 有未读通知的图标右上角带一个红色计数，超过 99 显示 `99+`，通知中心标为已读后消失。
- **点击行为。** 有窗口的应用，点击可以是最小化当前窗口（默认）、按窗口顺序切到下一个、打开窗口预览，或者只前置。中键可以是新开窗口（默认）、关闭窗口、最小化或不操作。没有窗口的应用点击就是启动。
- **应用发布的状态。** 应用通过 Unity `LauncherEntry` D-Bus 信号发出的进度、计数和提醒，会显示成图标上的进度条、角标和跳动。图标菜单里列出应用 desktop 文件自带的快捷操作。正在发声的应用可以显示喇叭，默认关闭。
- **快捷键。** 插件提供九个动作「激活 Dock 第 1–9 个应用」，在 Denial 的快捷键设置里绑定。
- **右键菜单。** 先按标题列出这个应用的窗口，然后「选项」子菜单（保留或移出 Dock、最小化、关闭），最后才是打开或新窗口，和 macOS 的顺序一致。Escape 关闭菜单，在同一图标上再右键一次也会收起。菜单和预览画在 shell overlay 里，位置限制在显示器范围内。触摸或手写笔指针长按 550ms 打开同一个菜单。
- **拖拽排序和固定。** 横向拖动固定图标可以换位置；把运行中的图标往左拖过分隔线，会在落点固定；固定图标拖到胶囊上方超过一个图标高度就移出 Dock。只有左键拖动才会开始移动。触摸和手写笔要先按住 550ms 才开始拖，横向滑动留给滚动。拖动时图标抬起、略微放大、变半透明，邻居按外壳的动效速度缓动让位；系统的减弱动效打开时，位置和尺寸直接到位，启动的跳动改成脉冲，提醒变成图标变暗。
- **拖分隔线改大小。** 光标停在分隔线上会变成缩放光标，拖动它图标、胶囊和放大范围都跟着指针走，松手保存。按整像素步进，拖动不会每个事件都重建全部图标纹理。
- **智能收起。** 当前显示器、当前工作区里有没最小化的浮动窗口碰到 Dock 所在的条带，胶囊滑下去。指针挪到最底边，90ms 后重新拉出；触摸和手写笔不产生悬停，所以在底边点一下也能拉出，并且保持 4 秒，够手指移动到图标上。指针离开且窗口还压着胶囊，200ms 后收起；窗口退出胶囊本身的范围就立刻回来。窗口正好停在边界上不会来回抖。平铺窗口一样会碰到边，所以平铺时也收起。另外两种是「始终显示」和「自动隐藏」，后者指针一离开就收起，靠同一条边上的感应条拉回。
- **文件夹堆叠、单个文件和回收站。** 设置面板里用内置目录浏览器添加任意文件夹或单个文件，隐藏项有开关。点文件夹图标，内容按堆叠从图标里散开，再点一次收回。堆叠可以排成扇状、网格或列表，按名称、添加日期、修改日期、种类或拖出来的自定顺序排序，打开期间会重新读取文件夹，新落进去的文件会冒出来。点某一行打开对应的文件或文件夹；在堆叠里拖动一行会存成自定顺序，把一行拖到回收站图标上就移进回收站。文件夹自己的菜单里能用系统程序打开它（`xdg-open`，没有就退回 `gio open`），也放着排序、显示方式和视图的选项。固定的文件用系统里对应的程序打开，菜单里有「在文件管理器中显示」和「从 Dock 中移除」。回收站打开 `trash:///` 时先用 `gio`，因为 `xdg-open` 会把这个 scheme 当网址丢给浏览器；带数量角标，可以清空，清空要点两次，因为删了回不来。
- **Dock 菜单和设置面板。** 右键胶囊空白处或启动台，先弹出一个照 macOS Dock 菜单做的小菜单：启用/关闭隐藏、开启/关闭放大，然后一条分隔线接「置于屏幕上的位置」子菜单（当前那条边打勾），再接「Dock 设置…」。文件夹和回收站的菜单里也有同一个入口。面板是 Denial 的托管 shell popup，自带遮罩、焦点、Escape 和点外面关闭。里面能改：显示方式、点击行为、停靠边、图标大小、放大程度、图标模式、强度和着色、启动弹跳、运行指示点、通知角标、推荐应用和它的数量、启动台和配件区放哪边、回收站开关、文件夹列表。
- **跟 shell 同一套视觉。** 胶囊和设置面板都用 Denial 的 `ShellTheme`：面板色、背景模糊、发丝边框、圆角，和顶栏一套材质。面板里的「图标样式」可以在 Denial 强调色卡片和 macOS 圆角方块之间切换启动台、文件夹和回收站的图块，固定文件则直接画成文件本身的缩略图。

## 前提

- Denial 0.6.8，或对应的 Flutter 3.47.5 / Dart 3.13 插件代际。
- 原生 work area 留给顶栏。Denial 0.6.8 只支持在一条边上预留空间，所以这个 Dock 不去抢底边；全屏窗口会盖住它，和 macOS 上全屏盖住 Dock 一样。全屏时 Dock 隐藏，概览或显示桌面时回来。平铺窗口会从胶囊下面穿过。底边留出的空隙来自 Denial 自己的 `maximizePadding` 设置（默认 8），不是这个插件造成的。

## 安装

```sh
denial-plugins add https://github.com/FFT-infra/denial-shell-plugins.git --path plugins/denial_dock
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
  "magnificationAmount": 0.6,
  "position": "bottom",
  "launchFeedback": "hop",
  "indicatorStyle": "dot",
  "previewStyle": "cards",
  "previewHover": "highlight",
  "dimInactivePinned": false,
  "showBadges": true,
  "showSuggestions": true,
  "scrollAction": "nothing",
  "scrollReversed": false,
  "scrollWraps": false,
  "iconMode": "color",
  "iconOpacity": 1,
  "tintColor": "#a855f7",
  "appearance": "macos",
  "revealIndicator": true,
  "launcherSide": "left",
  "extrasSide": "right",
  "showTrash": true,
  "folders": [
    {
      "path": "/home/me/Documents",
      "label": "文档",
      "view": "auto",
      "sort": "added"
    }
  ],
  "files": [{ "path": "/home/me/report.pdf", "label": "report.pdf" }]
}
```

- `id` 是启动应用用的 launcher 身份，`appId` 是图标身份，一般就是 desktop 文件名。
- `visibility` 是 `"smart"`（浮动窗口遮挡时自动收起，默认）、`"always"`（不收起）或 `"persistent"`（指针一离开就收起，不管屏幕上有什么）。
- `clickAction` 是 `"minimize"`（默认）、`"cycle"`、`"previews"` 或 `"raise"`。切窗口时先走没最小化的窗口，最小化的排在最后。
- `middleClickAction` 是 `"new-window"`（默认）、`"close"`、`"minimize"` 或 `"nothing"`。
- `hideScope` 决定智能隐藏时哪些窗口会让 Dock 收起：`"all"`（默认）、`"active"` 或 `"maximized"`。`revealDelayMs`（默认 90）和 `hideDelayMs`（默认 200）是出现和收起前的等待。
- `avoidReservedEdge` 默认 `true`，同一条边上有顶栏时 Dock 让到它内侧。
- `showProgress`、`showAttention`、`showDesktopActions` 默认 `true`；`showAudioIndicator`、`lockItems`、`currentWorkspaceOnly`、`previewMiddleClose` 默认 `false`。
- `iconSize` 是逻辑像素，夹在 32–72 之间，步进 4，默认 48。
- `magnification` 默认 `true`，指针经过时图标放大。关掉后所有图标保持 `iconSize`，胶囊也不变宽。
- `magnificationAmount` 是峰值 1.6 倍里用到多少，夹在 0–1，默认 0.6。
- `position` 是 `"bottom"`（默认）、`"left"` 或 `"right"`。胶囊跟着转：放大沿行方向走，标签和菜单朝屏幕里开，指示点在内侧。
- `launchFeedback` 是 `"hop"`（默认，跳一下）、`"pulse"`（呼吸）或 `"none"`。旧的 `bounceOnLaunch` 布尔值仍然能读，对应 `"hop"` 和 `"none"`。
- `indicatorStyle` 是 `"dot"`（默认，每个窗口一个点，最多三个）、`"line"`（一条横条）、`"dashes"`（短线）、`"segments"`（横条按窗口分段）或 `"none"`。旧的 `showIndicators` 布尔值仍然能读。
- `previewStyle` 是 `"cards"`（默认，Dock 上方一排缩略图卡片）或 `"stack"`（贴着图标的竖排列表，单窗口也弹，每行带关闭按钮）。
- `previewHover` 决定指针停在预览上做什么：`"highlight"`（默认）淡化其他窗口、不改焦点，`"focus"` 直接切到那个窗口，`"nothing"` 只标出指针所在的预览。旧的 `hoverFocusPreview` 布尔值仍然能读。
- `dimInactivePinned` 默认 `false`，打开后没在运行的固定 App 淡化到 62%。
- `showBadges` 默认 `true`，在图标上显示未读通知数。通知用 `desktop-entry` 提示对到图标身份上，没带提示的发送方按应用名匹配。
- `showSuggestions` 默认 `true`，在分隔线后面加一段没固定的应用。它是一份成员表，旧的在前：app 开始运行时加入，退出后留在原位，只有新开一个超过 `recentCount` 才挤掉最旧的已关闭成员。运行中的永不挤掉，所以开着的 app 多时这一段会比设定的数量长。
- `recentCount` 是这一段保留几个成员，0–8，默认 3。
- `dismissedSuggestions` 记着被拖出这一段的 app，下次运行之前不会自动回来。
- `recentsOrder` 和 `parkedRecents` 是这一段本身和被挤出去的 id。调小 `recentCount` 或关掉这一段之后还能还原。
- `scrollAction` 是 `"nothing"`（默认）、`"cycle-windows"` 或 `"switch-workspace"`。向上滚在应用窗口里倒退或切到上一个工作区，向下滚前进。一格滚轮算一步，两步之间至少隔 200ms；触控板要划满更长的距离才算一格。到第一个或最后一个工作区就停住，不绕回。
- `scrollReversed` 默认 `false`，反转滚轮方向。
- `scrollWraps` 默认 `false`，打开后最后一个工作区会绕回第一个。
- `iconMode` 是 `"color"`（默认）、`"grayscale"` 或 `"tinted"`，着色模式用主题强调色乘上图标。
- `iconOpacity` 是灰度/着色模式的强度，0.1–1，默认 1。彩色图标始终不透明。
- `tintColor` 是着色模式的 `#rrggbb` 颜色，不写就用主题强调色。
- `appearance` 是 `"macos"`（默认，圆角图块，固定文件画成文件本身的缩略图）或 `"denial"`（强调色卡片里放类型图标）。
- `revealIndicator` 默认 `true`，Dock 收起时在屏幕边缘留一条短提示条。
- `launcherSide` 和 `extrasSide` 是 `"left"`、`"right"` 或 `"hidden"`。配件区（文件夹和回收站）默认在右，启动台默认在左。回收站在配件组里永远排最后。
- `showTrash` 单独关掉回收站，不动文件夹列表。
- `folders` 存绝对路径；没写 `label` 就用目录名。重复路径会合并。每一项还可以带 `view`（`"auto"`、`"fan"`、`"grid"` 或 `"list"`）、`sort`（`"added"`、`"modified"`、`"name"`、`"kind"` 或 `"manual"`）、`stacked`（`false` 画成普通文件夹，不画文件堆）和 `order`（自定顺序里的文件名）。
- `files` 用同样的方式存固定的单个文件。它们排在文件夹之后、回收站之前，点开用系统程序，在堆叠里和文件夹共用卡片大小，互相可以盖住。
- `pinnedApplications` 为空表示固定项都被移除了。

Dock 原子地重写这个文件，按已有内容合并，不认识的键保留。手改之后要重新 apply 插件或者重启 shell 才会读到，因为设置只在插件引擎启动时读一次。读不懂的值退回默认，不抛异常。

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
