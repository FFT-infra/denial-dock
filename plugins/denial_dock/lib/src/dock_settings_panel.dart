import 'dart:io';
import 'dart:math' as math;

import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dock_extras.dart';
import 'dock_look.dart';
import 'dock_look_style.dart';
import 'dock_metrics.dart';
import 'dock_preferences.dart';
import 'dock_stack_files.dart' show DockStackFiles;
import 'dock_stack_view.dart' show stackFileColor, stackFileIcon;

import 'package:denial_shell_kit/glass_card.dart';
import 'package:denial_shell_kit/kit_motion.dart';
import 'package:denial_shell_kit/kit_settings.dart';
import 'package:denial_shell_kit/kit_style.dart';

const double _rowHeight = 48;
const double _cardRadius = 12;
const double _sheetRadius = 22;
const Duration _quick = Duration(milliseconds: 140);

Duration _motion(BuildContext context, Duration duration) =>
    KitMotion.duration(context, duration);

TextStyle _labelStyle(ShellThemeData theme) => theme.text.cardTitle.copyWith(
  color: theme.colors.textPrimary,
  fontWeight: FontWeight.w500,
);

TextStyle _captionStyle(ShellThemeData theme, [Color? color]) =>
    theme.text.systemBarCaption.copyWith(
      color: color ?? theme.colors.textTertiary,
      height: 1.45,
      letterSpacing: 0.1,
    );

TextStyle _sectionStyle(ShellThemeData theme) =>
    theme.text.systemBarCaption.copyWith(
      color: theme.colors.textTertiary,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.8,
      height: 1.2,
    );

TextStyle _valueStyle(ShellThemeData theme, Color color) =>
    theme.text.systemBarValue.copyWith(color: color, letterSpacing: 0);

/// Denial gives plugins no settings page, so the sheet is a managed shell popup
/// with the scene barrier, focus, Escape and outside-tap dismissal for free.
/// The dock's pages as the shell's settings window lists them, in the order
/// of the panel's own pages.
const List<({String id, String en, String zh, IconData icon})>
dockSettingsPageInfo = [
  (
    id: 'dock.visibility',
    en: 'Dock: Visibility',
    zh: '程序坞：显示与隐藏',
    icon: Icons.visibility_outlined,
  ),
  (
    id: 'dock.clicks',
    en: 'Dock: Clicks and wheel',
    zh: '程序坞：点击与滚轮',
    icon: Icons.mouse_outlined,
  ),
  (
    id: 'dock.appearance',
    en: 'Dock: Appearance',
    zh: '程序坞：外观',
    icon: Icons.palette_outlined,
  ),
  (
    id: 'dock.backplate',
    en: 'Dock: Backplate',
    zh: '程序坞：底板',
    icon: Icons.rounded_corner,
  ),
  (
    id: 'dock.markers',
    en: 'Dock: Markers and badges',
    zh: '程序坞：标记与角标',
    icon: Icons.circle_notifications_outlined,
  ),
  (
    id: 'dock.windows',
    en: 'Dock: Windows and menus',
    zh: '程序坞：窗口与菜单',
    icon: Icons.web_asset_outlined,
  ),
  (
    id: 'dock.layout',
    en: 'Dock: Layout',
    zh: '程序坞：布局',
    icon: Icons.dashboard_customize_outlined,
  ),
  (
    id: 'dock.folders',
    en: 'Dock: Folders',
    zh: '程序坞：文件夹',
    icon: Icons.folder_outlined,
  ),
];

List<KitSettingsPage>? _dockPages;

/// Offers the dock's pages to the shell's settings window, after those of
/// the bar.
void registerDockSettingsPages() {
  final pages = _dockPages ??= [
    for (final (index, info) in dockSettingsPageInfo.indexed)
      KitSettingsPage(
        id: info.id,
        title: (context) =>
            Localizations.maybeLocaleOf(context)?.languageCode == 'zh'
            ? info.zh
            : info.en,
        icon: info.icon,
        colour: const Color(0xff5e6ad2),
        order: 300 + index * 10,
        builder: (context) =>
            DockSettingsPanel(onClose: () {}, embeddedPage: index),
      ),
  ];
  kitSettingsPages.register(pages);
}

class DockSettingsPanel extends ConsumerStatefulWidget {
  const DockSettingsPanel({
    required this.onClose,
    this.initialPage = 0,
    this.embeddedPage,
    super.key,
  });

  final VoidCallback onClose;
  final int initialPage;

  /// When set, the panel is that one page with no sheet around it: the
  /// shell's settings window supplies the list of pages and the title.
  final int? embeddedPage;

  @override
  ConsumerState<DockSettingsPanel> createState() => _DockSettingsPanelState();
}

class _DockSettingsPanelState extends ConsumerState<DockSettingsPanel> {
  String? _browsePath;
  bool _showHidden = false;
  late int _page = widget.initialPage;
  final ScrollController _bodyScroll = ScrollController();
  final ScrollController _browserScroll = ScrollController();

  bool get _zh => Localizations.localeOf(context).languageCode == 'zh';

  DockSettingsController get _controller =>
      ref.read(dockSettingsProvider.notifier);

  @override
  void dispose() {
    _bodyScroll.dispose();
    _browserScroll.dispose();
    super.dispose();
  }

  String _home() {
    final home = Platform.environment['HOME'];
    return home != null && home.startsWith('/') ? home : '/';
  }

  @override
  Widget build(BuildContext context) {
    final settings =
        ref.watch(dockSettingsProvider).value ?? DockSettings.defaults;
    final embedded = widget.embeddedPage;
    if (embedded != null) {
      if (_browsePath != null) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ActionRow(
              icon: Icons.arrow_back_rounded,
              label: _zh ? '返回' : 'Back',
              margin: const EdgeInsets.fromLTRB(14, 4, 14, 0),
              radius: 8,
              onTap: () => setState(() => _browsePath = null),
            ),
            Expanded(child: _buildBrowser(context)),
          ],
        );
      }
      final pages = _pages(settings);
      return _pageScroll(
        context,
        pages[embedded.clamp(0, pages.length - 1)].sections,
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.min(
          700.0,
          math.max(280.0, constraints.maxWidth - 32),
        );
        final height = math.min(
          620.0,
          math.max(260.0, constraints.maxHeight - 48),
        );
        return Center(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {},
            child: SizedBox(
              width: width,
              height: height,
              child: _buildShell(context, settings),
            ),
          ),
        );
      },
    );
  }

  Widget _buildShell(BuildContext context, DockSettings settings) {
    final theme = context.shellTheme;
    final browsing = _browsePath != null;
    return GlassCard(
      radius: _sheetRadius,
      minOpacity: 0.9,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(context, browsing),
          SizedBox(height: 1, child: ColoredBox(color: theme.colors.hairline)),
          Expanded(
            child: AnimatedSwitcher(
              duration: _motion(context, const Duration(milliseconds: 240)),
              switchInCurve: Motion.standard,
              switchOutCurve: Motion.standard,
              layoutBuilder: (current, previous) => Stack(
                fit: StackFit.expand,
                children: [...previous, ?current],
              ),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.02, 0),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: browsing
                  ? _buildBrowser(context, key: const ValueKey('browser'))
                  : _buildBody(
                      context,
                      settings,
                      key: const ValueKey('settings'),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, bool browsing) {
    final theme = context.shellTheme;
    final colors = theme.colors;
    final swap = _motion(context, const Duration(milliseconds: 200));
    final titleStyle = theme.text.base.copyWith(
      color: colors.textPrimary,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.1,
      height: 1.2,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 10, 0),
      child: SizedBox(
        height: 56,
        child: Row(
          children: [
            AnimatedSwitcher(
              duration: swap,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.9, end: 1).animate(animation),
                  child: child,
                ),
              ),
              child: browsing
                  ? _IconButton(
                      key: const ValueKey('back'),
                      icon: Icons.arrow_back_rounded,
                      tooltip: _zh ? '返回' : 'Back',
                      onPressed: () => setState(() => _browsePath = null),
                    )
                  : DecoratedBox(
                      key: const ValueKey('badge'),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            theme.kitAccent.withValues(alpha: 0.2),
                            theme.kitAccent.withValues(alpha: 0.1),
                          ],
                        ),
                        borderRadius: theme.borderRadius(8),
                        border: Border.all(
                          color: theme.kitAccent.withValues(alpha: 0.2),
                        ),
                      ),
                      child: SizedBox(
                        width: 30,
                        height: 30,
                        child: Icon(
                          Icons.tune_rounded,
                          size: 16,
                          color: theme.kitAccent,
                        ),
                      ),
                    ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedSwitcher(
                    duration: swap,
                    layoutBuilder: (current, previous) => Stack(
                      alignment: AlignmentDirectional.centerStart,
                      children: [...previous, ?current],
                    ),
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.18),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    ),
                    child: Semantics(
                      header: true,
                      child: Text(
                        browsing
                            ? (_zh ? '选择文件夹' : 'Choose a folder')
                            : (_zh ? 'Dock 设置' : 'Dock settings'),
                        key: ValueKey(browsing),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: titleStyle,
                      ),
                    ),
                  ),
                  if (browsing)
                    Text(
                      _browsePath!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _captionStyle(theme),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            _IconButton(
              icon: Icons.close_rounded,
              tooltip: _zh ? '关闭' : 'Close',
              onPressed: widget.onClose,
            ),
          ],
        ),
      ),
    );
  }

  String _delayText(int ms) =>
      ms == 0 ? (_zh ? '立即' : 'At once') : (_zh ? '$ms 毫秒' : '$ms ms');

  /// The settings, one page per category. A narrow sheet stacks the pages
  /// into the single column it had before.
  List<({String title, IconData icon, List<Widget> sections})> _pages(
    DockSettings settings,
  ) {
    final hides = settings.visibility != DockVisibilityMode.always;
    const gap = SizedBox(height: 22);
    final look = dockLookNow(settings);
    final fit = dockMetricsNow(settings, look.shape);
    final followLabel = _zh ? '跟随外观' : 'Follow the look';
    final floating = look.shape == DockShape.floating;
    String px(double value) => '${value.round()}';
    String percent(double value) => '${(value * 100).round()}%';
    return [
      (
        title: _zh ? '显示与隐藏' : 'Visibility',
        icon: Icons.visibility_outlined,
        sections: [
          _SettingsSection(
            title: _zh ? '显示方式' : 'Visibility',
            footer: _zh
                ? '智能隐藏只在窗口挡住 Dock 时收起；自动隐藏则一直收起，指针碰到屏幕边缘才出现。'
                : 'Smart hide retracts only when a window reaches the '
                      'dock; auto-hide stays away until the pointer '
                      'touches the screen edge.',
            children: [
              _SegmentedField<DockVisibilityMode>(
                value: settings.visibility,
                options: [
                  (
                    DockVisibilityMode.smart,
                    _zh ? '智能隐藏' : 'Smart hide',
                    Icons.visibility_off_outlined,
                  ),
                  (
                    DockVisibilityMode.always,
                    _zh ? '始终显示' : 'Always show',
                    Icons.visibility_outlined,
                  ),
                  (
                    DockVisibilityMode.persistent,
                    _zh ? '自动隐藏' : 'Auto-hide',
                    Icons.vertical_align_bottom,
                  ),
                ],
                onChanged: (value) => _controller.setVisibility(value),
              ),
              _SegmentedField<DockHideScope>(
                label: _zh ? '哪些窗口会让 Dock 收起' : 'Windows that hide the dock',
                value: settings.hideScope,
                options: [
                  (
                    DockHideScope.all,
                    _zh ? '所有窗口' : 'Any window',
                    Icons.select_all,
                  ),
                  (
                    DockHideScope.active,
                    _zh ? '当前窗口' : 'Focused window',
                    Icons.filter_center_focus,
                  ),
                  (
                    DockHideScope.maximized,
                    _zh ? '最大化窗口' : 'Maximized',
                    Icons.crop_square,
                  ),
                ],
                onChanged: (value) => _controller.setHideScope(value),
              ),
              _SliderRow(
                label: _zh ? '出现前等待' : 'Delay before showing',
                value: settings.revealDelayMs.toDouble(),
                min: 0,
                max: DockSettings.maxRevealDelayMs.toDouble(),
                divisions:
                    DockSettings.maxRevealDelayMs ~/ DockSettings.delayStepMs,
                display: _delayText(settings.revealDelayMs),
                describe: (value) => _delayText(value.round()),
                enabled: hides,
                onChanged: (value) =>
                    _controller.setRevealDelayMs(value.round()),
              ),
              _SliderRow(
                label: _zh ? '收起前等待' : 'Delay before hiding',
                value: settings.hideDelayMs.toDouble(),
                min: 0,
                max: DockSettings.maxHideDelayMs.toDouble(),
                divisions:
                    DockSettings.maxHideDelayMs ~/ DockSettings.delayStepMs,
                display: _delayText(settings.hideDelayMs),
                describe: (value) => _delayText(value.round()),
                enabled: hides,
                onChanged: (value) => _controller.setHideDelayMs(value.round()),
              ),
              _ToggleRow(
                label: _zh ? '收起时显示提示条' : 'Show a handle while hidden',
                value: settings.revealIndicator,
                onChanged: (value) =>
                    _controller.setRevealIndicator(show: value),
              ),
            ],
          ),
          gap,
          _SettingsSection(
            title: _zh ? '置于屏幕上的位置' : 'Position on screen',
            footer: _zh
                ? '顶栏或其他面板占用同一条边时，Dock 会让到它的内侧。'
                : 'When a bar holds the same edge, the dock sits inside '
                      'it.',
            children: [
              _SegmentedField<DockPosition>(
                value: settings.position,
                options: [
                  (
                    DockPosition.left,
                    _zh ? '左边' : 'Left',
                    Icons.align_horizontal_left,
                  ),
                  (
                    DockPosition.bottom,
                    _zh ? '底部' : 'Bottom',
                    Icons.vertical_align_bottom,
                  ),
                  (
                    DockPosition.right,
                    _zh ? '右边' : 'Right',
                    Icons.align_horizontal_right,
                  ),
                ],
                onChanged: (value) => _controller.setPosition(value),
              ),
              _ToggleRow(
                label: _zh
                    ? '避开同一边上的顶栏'
                    : 'Keep clear of a bar on the same edge',
                value: settings.avoidReservedEdge,
                onChanged: (value) =>
                    _controller.setAvoidReservedEdge(avoid: value),
              ),
            ],
          ),
        ],
      ),
      (
        title: _zh ? '点击与滚轮' : 'Clicks and wheel',
        icon: Icons.mouse_outlined,
        sections: [
          _SettingsSection(
            title: _zh ? '点击' : 'Clicks',
            footer: _zh
                ? '没有窗口的应用，左键和中键都会启动它。'
                : 'An application with no window starts on either '
                      'button.',
            children: [
              _SegmentedField<DockClickAction>(
                label: _zh ? '点击已打开的应用' : 'Clicking an open application',
                value: settings.clickAction,
                options: [
                  (
                    DockClickAction.minimize,
                    _zh ? '最小化' : 'Minimize',
                    Icons.vertical_align_bottom,
                  ),
                  (
                    DockClickAction.cycle,
                    _zh ? '切换窗口' : 'Cycle windows',
                    Icons.swap_horiz,
                  ),
                  (
                    DockClickAction.previews,
                    _zh ? '窗口预览' : 'Previews',
                    Icons.view_carousel_outlined,
                  ),
                  (
                    DockClickAction.raise,
                    _zh ? '仅前置' : 'Raise only',
                    Icons.flip_to_front,
                  ),
                ],
                onChanged: (value) => _controller.setClickAction(value),
              ),
              _SegmentedField<DockMiddleClickAction>(
                label: _zh
                    ? '中键点击已打开的应用'
                    : 'Middle-clicking an open application',
                value: settings.middleClickAction,
                options: [
                  (
                    DockMiddleClickAction.newWindow,
                    _zh ? '新窗口' : 'New window',
                    Icons.open_in_new,
                  ),
                  (
                    DockMiddleClickAction.close,
                    _zh ? '关闭窗口' : 'Close',
                    Icons.close,
                  ),
                  (
                    DockMiddleClickAction.minimize,
                    _zh ? '最小化' : 'Minimize',
                    Icons.vertical_align_bottom,
                  ),
                  (
                    DockMiddleClickAction.nothing,
                    _zh ? '不操作' : 'Nothing',
                    Icons.block,
                  ),
                ],
                onChanged: (value) => _controller.setMiddleClickAction(value),
              ),
            ],
          ),
          gap,
          _SettingsSection(
            title: _zh ? '滚轮' : 'Wheel',
            children: [
              _SegmentedField<DockScrollAction>(
                label: _zh ? '在 Dock 上滚动滚轮' : 'Scrolling over the dock',
                value: settings.scrollAction,
                options: [
                  (
                    DockScrollAction.nothing,
                    _zh ? '不操作' : 'Do nothing',
                    Icons.block,
                  ),
                  (
                    DockScrollAction.cycleWindows,
                    _zh ? '切换窗口' : 'Cycle windows',
                    Icons.swap_vert,
                  ),
                  (
                    DockScrollAction.switchWorkspace,
                    _zh ? '切换工作区' : 'Switch workspace',
                    Icons.space_dashboard_outlined,
                  ),
                ],
                onChanged: (value) => _controller.setScrollAction(value),
              ),
              _ToggleRow(
                label: _zh ? '反向滚动' : 'Reverse scroll direction',
                value: settings.scrollReversed,
                enabled: settings.scrollAction != DockScrollAction.nothing,
                onChanged: (value) =>
                    _controller.setScrollReversed(reversed: value),
              ),
              _ToggleRow(
                label: _zh
                    ? '滚到尽头时循环到另一端'
                    : 'Wrap around at the last workspace',
                value: settings.scrollWraps,
                enabled:
                    settings.scrollAction == DockScrollAction.switchWorkspace,
                onChanged: (value) => _controller.setScrollWraps(wraps: value),
              ),
            ],
          ),
          gap,
          _SettingsSection(
            title: _zh ? '快捷键' : 'Shortcuts',
            children: [
              _NoteRow(
                text: _zh
                    ? '系统设置的快捷键里有「激活 Dock 第 1–9 个应用」，绑定后相当于点击对应图标。'
                    : 'System shortcuts list "Activate Dock application '
                          '1–9"; a bound one acts as a click on that icon.',
              ),
            ],
          ),
        ],
      ),
      (
        title: _zh ? '外观' : 'Appearance',
        icon: Icons.palette_outlined,
        sections: [
          _SettingsSection(
            title: _zh ? '风格' : 'Style',
            children: [
              _SegmentedField<KitStyle>(
                label: _zh ? '与顶栏共用' : 'Shared with the top bar',
                value: kitStyle.value,
                options: [
                  for (final style in KitStyle.presets)
                    (
                      style,
                      style.label,
                      switch (style.id) {
                        'denial' => Icons.water_drop_outlined,
                        'mac' => Icons.laptop_mac_outlined,
                        'terminal' => Icons.terminal_outlined,
                        _ => Icons.style_outlined,
                      },
                    ),
                ],
                onChanged: kitStyle.choose,
              ),
            ],
          ),
          gap,
          _SettingsSection(
            title: _zh ? '大小' : 'Size',
            children: [
              _SliderRow(
                label: _zh ? '大小' : 'Size',
                value: fit.iconSize,
                min: DockSettings.minIconSize,
                max: DockSettings.maxIconSize,
                divisions:
                    ((DockSettings.maxIconSize - DockSettings.minIconSize) /
                            DockSettings.iconSizeStep)
                        .round(),
                display: '${fit.iconSize.round()}',
                describe: (value) => '${value.round()}',
                onChanged: (value) => _controller.setIconSize(value),
                resetLabel: followLabel,
                onReset: settings.chosen.contains(DockMetrics.iconSizeKey)
                    ? () => _controller.followLook(const [
                        DockMetrics.iconSizeKey,
                      ])
                    : null,
                reserveReset: true,
              ),
              _SegmentedField<int>(
                label: _zh ? '悬停反馈' : 'Under the pointer',
                value: fit.magnify
                    ? 0
                    : fit.highlight
                    ? 1
                    : 2,
                options: [
                  (0, _zh ? '放大' : 'Magnify', Icons.zoom_in),
                  (1, _zh ? '高亮' : 'Highlight', Icons.highlight_alt),
                  (2, _zh ? '无' : 'None', Icons.block),
                ],
                onChanged: (value) => _controller.setHoverFeedback(
                  magnify: value == 0,
                  highlight: value == 1,
                ),
              ),
              _SliderRow(
                label: _zh ? '放大程度' : 'Magnification amount',
                value: fit.magnifyAmount,
                min: DockSettings.minMagnificationAmount,
                max: DockSettings.maxMagnificationAmount,
                divisions:
                    ((DockSettings.maxMagnificationAmount -
                                DockSettings.minMagnificationAmount) /
                            DockSettings.magnificationAmountStep)
                        .round(),
                display: fit.magnifyAmount == 0
                    ? (_zh ? '关闭' : 'Off')
                    : '${(fit.magnifyAmount * 100).round()}%',
                describe: (value) => value == 0
                    ? (_zh ? '关闭' : 'Off')
                    : '${(value * 100).round()}%',
                enabled: fit.magnify,
                onChanged: (value) => _controller.setMagnificationAmount(value),
                resetLabel: followLabel,
                onReset: settings.chosen.contains(DockMetrics.magnifyAmountKey)
                    ? () => _controller.followLook(const [
                        DockMetrics.magnifyAmountKey,
                      ])
                    : null,
                reserveReset: true,
              ),
              _lookSlider(
                settings,
                label: _zh ? '放大范围' : 'Magnification reach',
                keyName: DockLook.magnifyRangeKey,
                value: look.magnifyRange,
                min: DockLook.minMagnifyRange,
                max: DockLook.maxMagnifyRange,
                step: DockLook.magnifyRangeStep,
                text: px,
                enabled: fit.magnify,
              ),
              _ActionRow(
                icon: Icons.style_outlined,
                label: _zh
                    ? '大小与悬停反馈跟随外观'
                    : 'Let size and pointer feedback follow the look',
                onTap: () => _controller.followLook(const [
                  DockMetrics.iconSizeKey,
                  DockMetrics.magnifyKey,
                  DockMetrics.magnifyAmountKey,
                  DockMetrics.highlightKey,
                ]),
              ),
            ],
          ),
          gap,
          _SettingsSection(
            title: _zh ? '图标' : 'Icons',
            children: [
              _SegmentedField<DockAppearance>(
                label: _zh ? '图标样式' : 'Icon style',
                value: settings.appearance,
                options: [
                  (DockAppearance.macos, 'macOS', Icons.grid_view_rounded),
                  (
                    DockAppearance.denial,
                    'Denial',
                    Icons.auto_awesome_mosaic_outlined,
                  ),
                ],
                onChanged: (value) => _controller.setAppearance(value),
              ),
              _SegmentedField<DockIconMode>(
                label: _zh ? '图标' : 'Icons',
                value: settings.iconMode,
                options: [
                  (
                    DockIconMode.color,
                    _zh ? '彩色' : 'Colour',
                    Icons.palette_outlined,
                  ),
                  (
                    DockIconMode.grayscale,
                    _zh ? '灰度' : 'Greyscale',
                    Icons.tonality_outlined,
                  ),
                  (
                    DockIconMode.tinted,
                    _zh ? '着色' : 'Tinted',
                    Icons.colorize_outlined,
                  ),
                ],
                onChanged: (value) => _controller.setIconMode(value),
              ),
              _SliderRow(
                label: _zh ? '图标强度' : 'Icon strength',
                value: settings.iconOpacity,
                min: DockSettings.minIconOpacity,
                max: 1,
                divisions:
                    ((1 - DockSettings.minIconOpacity) /
                            DockSettings.iconOpacityStep)
                        .round(),
                display: '${(settings.iconOpacity * 100).round()}%',
                describe: (value) => '${(value * 100).round()}%',
                enabled: settings.iconMode != DockIconMode.color,
                onChanged: (value) => _controller.setIconOpacity(value),
              ),
              _TintRow(
                label: _zh ? '着色颜色' : 'Tint colour',
                accentLabel: _zh ? '强调色' : 'Accent',
                value: settings.tintColor,
                accent: context.shellTheme.kitAccent,
                enabled: settings.iconMode == DockIconMode.tinted,
                onChanged: (value) => _controller.setTintColor(value),
              ),
              _SegmentedField<DockLaunchFeedback>(
                label: _zh ? '启动时' : 'While an app starts',
                value: settings.launchFeedback,
                options: [
                  (
                    DockLaunchFeedback.hop,
                    _zh ? '跳动' : 'Hop',
                    Icons.vertical_align_top,
                  ),
                  (
                    DockLaunchFeedback.pulse,
                    _zh ? '呼吸' : 'Pulse',
                    Icons.blur_on,
                  ),
                  (DockLaunchFeedback.none, _zh ? '无' : 'None', Icons.block),
                ],
                onChanged: (value) => _controller.setLaunchFeedback(value),
              ),
            ],
          ),
        ],
      ),
      (
        title: _zh ? '底板' : 'Backplate',
        icon: Icons.rounded_corner,
        sections: [
          _SettingsSection(
            title: _zh ? '材质' : 'Material',
            footer: _zh
                ? '未改动的项跟随所选风格的默认值。模糊只在系统开启了透明效果时可见。'
                : 'Anything left alone follows the chosen style. The blur '
                      'shows only while the system has transparency on.',
            children: [
              _SegmentedField<DockShape>(
                label: _zh ? '形状' : 'Shape',
                value: look.shape,
                options: [
                  (
                    DockShape.floating,
                    _zh ? '悬浮圆角' : 'Floating',
                    Icons.crop_7_5,
                  ),
                  (
                    DockShape.bar,
                    _zh ? '贴边通栏' : 'Edge bar',
                    Icons.horizontal_rule,
                  ),
                ],
                onChanged: (value) =>
                    _controller.setLook(DockLook.shapeKey, value.name),
              ),
              _ToggleRow(
                label: _zh
                    ? '通栏上显示窗口标题'
                    : 'Show window titles on an edge bar',
                value: fit.taskTitles,
                enabled: look.shape == DockShape.bar,
                onChanged: (value) =>
                    _controller.setLook(DockMetrics.taskTitlesKey, value),
              ),
              _lookSlider(
                settings,
                label: _zh ? '模糊强度' : 'Blur',
                keyName: DockLook.blurKey,
                value: look.blur,
                min: DockLook.minBlur,
                max: DockLook.maxBlur,
                step: DockLook.blurStep,
                text: percent,
              ),
              _lookSlider(
                settings,
                label: _zh ? '不透明度' : 'Opacity',
                keyName: DockLook.opacityKey,
                value:
                    look.opacity ?? context.shellTheme.effectivePanelOpacity,
                min: DockLook.minOpacity,
                max: DockLook.maxOpacity,
                step: DockLook.opacityStep,
                text: percent,
                display: look.opacity == null
                    ? (_zh ? '跟随系统' : 'System')
                    : null,
              ),
              _SegmentedField<DockTint>(
                label: _zh ? '着色' : 'Tint',
                value: look.tint,
                options: [
                  (
                    DockTint.theme,
                    _zh ? '跟随主题' : 'Theme',
                    Icons.brightness_6_outlined,
                  ),
                  (
                    DockTint.accent,
                    _zh ? '壁纸强调色' : 'Wallpaper accent',
                    Icons.wallpaper_outlined,
                  ),
                  (DockTint.custom, _zh ? '自定深浅' : 'Custom', Icons.tonality),
                ],
                onChanged: (value) =>
                    _controller.setLook(DockLook.tintKey, value.name),
              ),
              _lookSlider(
                settings,
                label: _zh ? '深浅' : 'Shade',
                keyName: DockLook.tintShadeKey,
                value: look.tintShade,
                min: DockLook.minShade,
                max: DockLook.maxShade,
                step: DockLook.shadeStep,
                text: percent,
                enabled: look.tint == DockTint.custom,
              ),
            ],
          ),
          gap,
          _SettingsSection(
            title: _zh ? '轮廓' : 'Outline',
            children: [
              _lookSlider(
                settings,
                label: _zh ? '圆角' : 'Corner radius',
                keyName: DockLook.radiusKey,
                value: look.radius,
                min: DockLook.minRadius,
                max: DockLook.maxRadius,
                step: DockLook.radiusStep,
                text: px,
                enabled: floating,
              ),
              _ToggleRow(
                label: _zh ? '描边' : 'Border',
                value: look.border,
                onChanged: (value) =>
                    _controller.setLook(DockLook.borderKey, value),
              ),
              _lookSlider(
                settings,
                label: _zh ? '描边粗细' : 'Border width',
                keyName: DockLook.borderWidthKey,
                value: look.borderWidth,
                min: DockLook.minBorderWidth,
                max: DockLook.maxBorderWidth,
                step: DockLook.borderWidthStep,
                text: (value) => value.toStringAsFixed(1),
                enabled: look.border,
              ),
              _lookSlider(
                settings,
                label: _zh ? '阴影' : 'Shadow',
                keyName: DockLook.shadowKey,
                value: look.shadow,
                min: DockLook.minShadow,
                max: DockLook.maxShadow,
                step: DockLook.shadowStep,
                text: (value) =>
                    value == 0 ? (_zh ? '关闭' : 'Off') : percent(value),
              ),
            ],
          ),
          gap,
          _SettingsSection(
            title: _zh ? '间距' : 'Spacing',
            children: [
              _lookSlider(
                settings,
                label: _zh ? '底板内边距' : 'Padding',
                keyName: DockLook.paddingKey,
                value: look.padding,
                min: DockLook.minPadding,
                max: DockLook.maxPadding,
                step: DockLook.paddingStep,
                text: px,
              ),
              _lookSlider(
                settings,
                label: _zh ? '图标间距' : 'Icon spacing',
                keyName: DockLook.gapKey,
                value: look.gap,
                min: DockLook.minGap,
                max: DockLook.maxGap,
                step: DockLook.gapStep,
                text: px,
              ),
              _lookSlider(
                settings,
                label: _zh ? '离屏幕边缘' : 'Distance from the edge',
                keyName: DockLook.edgeMarginKey,
                value: look.edgeMargin,
                min: DockLook.minEdgeMargin,
                max: DockLook.maxEdgeMargin,
                step: DockLook.edgeMarginStep,
                text: px,
                enabled: floating,
              ),
              _ActionRow(
                icon: Icons.restart_alt,
                label: _zh ? '全部恢复默认' : 'Restore all defaults',
                onTap: () => _controller.resetLook(),
              ),
            ],
          ),
        ],
      ),
      (
        title: _zh ? '标记与角标' : 'Markers and badges',
        icon: Icons.circle_notifications_outlined,
        sections: [
          _SettingsSection(
            title: _zh ? '运行状态' : 'Running state',
            children: [
              _SegmentedField<DockIndicatorStyle>(
                label: _zh ? '运行标记' : 'Running marker',
                value: fit.indicator,
                options: [
                  (
                    DockIndicatorStyle.dot,
                    _zh ? '圆点' : 'Dots',
                    Icons.fiber_manual_record_outlined,
                  ),
                  (
                    DockIndicatorStyle.line,
                    _zh ? '横条' : 'Line',
                    Icons.horizontal_rule,
                  ),
                  (
                    DockIndicatorStyle.pill,
                    _zh ? '胶囊' : 'Pill',
                    Icons.remove,
                  ),
                  (
                    DockIndicatorStyle.dashes,
                    _zh ? '短线' : 'Dashes',
                    Icons.more_horiz,
                  ),
                  (
                    DockIndicatorStyle.segments,
                    _zh ? '分段' : 'Segments',
                    Icons.power_input,
                  ),
                  (DockIndicatorStyle.none, _zh ? '无' : 'None', Icons.block),
                ],
                onChanged: (value) => _controller.setIndicatorStyle(value),
              ),
              if (settings.chosen.contains(DockMetrics.indicatorKey))
                _ActionRow(
                  icon: Icons.style_outlined,
                  label: _zh
                      ? '运行标记跟随外观'
                      : 'Let the running marker follow the look',
                  onTap: () => _controller.followLook(const [
                    DockMetrics.indicatorKey,
                  ]),
                ),
              _SegmentedField<DockMarkerColor>(
                label: _zh ? '标记颜色' : 'Marker colour',
                value: look.markerColor,
                options: [
                  (
                    DockMarkerColor.auto,
                    _zh ? '自动' : 'Automatic',
                    Icons.auto_awesome_outlined,
                  ),
                  (
                    DockMarkerColor.accent,
                    _zh ? '强调色' : 'Accent',
                    Icons.palette_outlined,
                  ),
                  (
                    DockMarkerColor.ink,
                    _zh ? '文字色' : 'Text colour',
                    Icons.contrast,
                  ),
                ],
                onChanged: (value) =>
                    _controller.setLook(DockLook.markerColorKey, value.name),
              ),
              _ToggleRow(
                label: _zh
                    ? '没打开时淡出固定的 App'
                    : 'Fade pinned apps that are not running',
                value: settings.dimInactivePinned,
                onChanged: (value) =>
                    _controller.setDimInactivePinned(dim: value),
              ),
            ],
          ),
          gap,
          _SettingsSection(
            title: _zh ? '应用发布的状态' : 'What applications report',
            footer: _zh
                ? '进度和提醒来自应用自己发布的 Unity LauncherEntry 信号，不发布的应用不会显示。声音标记需要每隔几秒查询一次混音器。'
                : 'Progress and attention come from the Unity '
                      'LauncherEntry signals an application sends itself. '
                      'The sound marker asks the mixer every few seconds.',
            children: [
              _ToggleRow(
                label: _zh ? '显示通知角标' : 'Show notification badges',
                value: settings.showBadges,
                onChanged: (value) => _controller.setShowBadges(show: value),
              ),
              _ToggleRow(
                label: _zh ? '在图标上显示进度条' : 'Show progress on icons',
                value: settings.showProgress,
                onChanged: (value) => _controller.setShowProgress(show: value),
              ),
              _ToggleRow(
                label: _zh
                    ? '应用请求注意时跳动'
                    : 'Hop when an application wants attention',
                value: settings.showAttention,
                onChanged: (value) => _controller.setShowAttention(show: value),
              ),
              _ToggleRow(
                label: _zh
                    ? '正在发声的应用显示喇叭'
                    : 'Mark applications that play sound',
                value: settings.showAudioIndicator,
                onChanged: (value) =>
                    _controller.setShowAudioIndicator(show: value),
              ),
            ],
          ),
        ],
      ),
      (
        title: _zh ? '窗口与菜单' : 'Windows and menus',
        icon: Icons.web_asset_outlined,
        sections: [
          _SettingsSection(
            title: _zh ? '窗口预览' : 'Window previews',
            children: [
              _SegmentedField<DockPreviewStyle>(
                label: _zh ? '窗口预览' : 'Window previews',
                value: settings.previewStyle,
                options: [
                  (
                    DockPreviewStyle.cards,
                    _zh ? '横排卡片' : 'Card row',
                    Icons.view_carousel_outlined,
                  ),
                  (
                    DockPreviewStyle.stack,
                    _zh ? '竖排列表' : 'Stacked list',
                    Icons.view_agenda_outlined,
                  ),
                ],
                onChanged: (value) => _controller.setPreviewStyle(value),
              ),
              _SliderRow(
                label: _zh ? '停留多久后弹出预览' : 'Delay before previews',
                value: settings.previewDelayMs.toDouble(),
                min: 0,
                max: DockSettings.maxPreviewDelayMs.toDouble(),
                divisions:
                    DockSettings.maxPreviewDelayMs ~/
                    DockSettings.previewDelayStepMs,
                display: _delayText(settings.previewDelayMs),
                describe: (value) => _delayText(value.round()),
                onChanged: (value) =>
                    _controller.setPreviewDelayMs(value.round()),
              ),
              _SegmentedField<DockPreviewHover>(
                label: _zh ? '指针停在预览上' : 'Resting on a preview',
                value: settings.previewHover,
                options: [
                  (
                    DockPreviewHover.highlight,
                    _zh ? '突出显示' : 'Highlight',
                    Icons.visibility_outlined,
                  ),
                  (
                    DockPreviewHover.focus,
                    _zh ? '切换窗口' : 'Switch',
                    Icons.flip_to_front,
                  ),
                  (
                    DockPreviewHover.nothing,
                    _zh ? '不操作' : 'Nothing',
                    Icons.block,
                  ),
                ],
                onChanged: (value) => _controller.setPreviewHover(value),
              ),
              _ToggleRow(
                label: _zh ? '中键点预览关闭窗口' : 'Middle-click a preview to close it',
                value: settings.previewMiddleClose,
                onChanged: (value) =>
                    _controller.setPreviewMiddleClose(close: value),
              ),
            ],
          ),
          gap,
          _SettingsSection(
            title: _zh ? '窗口与菜单' : 'Windows and menus',
            children: [
              _ToggleRow(
                label: _zh ? '只显示当前工作区的窗口' : 'Only windows on this workspace',
                value: settings.currentWorkspaceOnly,
                onChanged: (value) =>
                    _controller.setCurrentWorkspaceOnly(only: value),
              ),
              _ToggleRow(
                label: _zh
                    ? '图标菜单里显示应用的快捷操作'
                    : 'List application actions in the menu',
                value: settings.showDesktopActions,
                onChanged: (value) =>
                    _controller.setShowDesktopActions(show: value),
              ),
            ],
          ),
        ],
      ),
      (
        title: _zh ? '布局' : 'Layout',
        icon: Icons.dashboard_customize_outlined,
        sections: [
          _SettingsSection(
            title: _zh ? '布局' : 'Layout',
            footer: _zh
                ? '锁定后不能拖动图标排序、拖出移除，也不能拖分隔线改大小。'
                : 'A locked dock ignores drags: no reordering, no removing, '
                      'no resizing by the divider.',
            children: [
              _SegmentedField<DockSide>(
                label: _zh ? '启动台' : 'Launcher',
                value: settings.launcherSide,
                options: [
                  (
                    DockSide.left,
                    _zh ? '左侧' : 'Left',
                    Icons.align_horizontal_left,
                  ),
                  (
                    DockSide.right,
                    _zh ? '右侧' : 'Right',
                    Icons.align_horizontal_right,
                  ),
                  (
                    DockSide.hidden,
                    _zh ? '隐藏' : 'Hidden',
                    Icons.visibility_off,
                  ),
                ],
                onChanged: (value) => _controller.setLauncherSide(value),
              ),
              _SegmentedField<DockSide>(
                label: _zh ? '文件夹与回收站' : 'Folders and Trash',
                value: settings.extrasSide,
                options: [
                  (
                    DockSide.left,
                    _zh ? '左侧' : 'Left',
                    Icons.align_horizontal_left,
                  ),
                  (
                    DockSide.right,
                    _zh ? '右侧' : 'Right',
                    Icons.align_horizontal_right,
                  ),
                  (
                    DockSide.hidden,
                    _zh ? '隐藏' : 'Hidden',
                    Icons.visibility_off,
                  ),
                ],
                onChanged: (value) => _controller.setExtrasSide(value),
              ),
              _ToggleRow(
                label: _zh ? '显示回收站' : 'Show Trash',
                value: settings.showTrash,
                onChanged: (value) => _controller.setShowTrash(show: value),
              ),
              // Only an edge bar has room to spread its ends apart.
              if (!floating)
                _SegmentedField<DockAlign>(
                label: _zh ? '贴边通栏里的应用' : 'Applications on an edge bar',
                value: settings.align,
                options: [
                  (
                    DockAlign.packed,
                    _zh ? '整体居中' : 'One group',
                    Icons.align_horizontal_center,
                  ),
                  (
                    DockAlign.center,
                    _zh ? '两端分开，居中' : 'Ends apart, centred',
                    Icons.format_align_center,
                  ),
                  (
                    DockAlign.start,
                    _zh ? '两端分开，靠起始' : 'Ends apart, at the start',
                    Icons.format_align_left,
                  ),
                ],
                onChanged: (value) =>
                    _controller.applyLayout({'align': value.key}),
              ),
              _ToggleRow(
                label: _zh ? '锁定 Dock 内容' : 'Lock the dock',
                value: settings.lockItems,
                onChanged: (value) => _controller.setLockItems(locked: value),
              ),
            ],
          ),
          gap,
          _SettingsSection(
            title: _zh ? '建议与最近使用' : 'Suggestions and recents',
            children: [
              _ToggleRow(
                label: _zh
                    ? '显示建议 App 和最近使用的 App'
                    : 'Show suggested and recent apps',
                value: settings.showSuggestions,
                onChanged: (value) =>
                    _controller.setShowSuggestions(show: value),
              ),
              _SliderRow(
                label: _zh ? '最近 App 数量' : 'Recent app count',
                value: settings.recentCount.toDouble(),
                min: DockSettings.minRecentCount.toDouble(),
                max: DockSettings.maxRecentCount.toDouble(),
                divisions:
                    DockSettings.maxRecentCount - DockSettings.minRecentCount,
                display: '${settings.recentCount}',
                describe: (value) => '${value.round()}',
                enabled: settings.showSuggestions,
                onChanged: (value) => _controller.setRecentCount(value.round()),
              ),
            ],
          ),
        ],
      ),
      (
        title: _zh ? '文件夹' : 'Folders',
        icon: Icons.folder_outlined,
        sections: [
          _SettingsSection(
            title: _zh ? '文件夹快捷方式' : 'Folder shortcuts',
            footer: _zh
                ? '点文件夹图标会展开它的内容；要打开文件夹本身，用图标菜单里的「打开」。'
                : 'A click fans a folder out; open the folder itself from '
                      'its menu.',
            children: [
              if (settings.folders.isEmpty && settings.files.isEmpty)
                _NoteRow(text: _zh ? '还没有添加文件夹或文件。' : 'Nothing added yet.'),
              for (final folder in settings.folders)
                _FolderRow(
                  folder: folder,
                  removeTooltip: _zh ? '移除' : 'Remove',
                  onRemove: () => _controller.removeFolder(folder.path),
                ),
              for (final file in settings.files)
                _FileRow(
                  file: file,
                  removeTooltip: _zh ? '移除' : 'Remove',
                  onRemove: () => _controller.removeFile(file.path),
                ),
              _ActionRow(
                icon: Icons.create_new_folder_outlined,
                label: _zh ? '添加文件夹或文件…' : 'Add folder or file…',
                onTap: () => setState(() {
                  _browsePath = _home();
                  _showHidden = false;
                }),
              ),
            ],
          ),
        ],
      ),
    ];
  }

  /// A slider for one number of the capsule's look. Its reset button shows
  /// once the user has moved it off the style's own value.
  Widget _lookSlider(
    DockSettings settings, {
    required String label,
    required String keyName,
    required double value,
    required double min,
    required double max,
    required double step,
    required String Function(double value) text,
    String? display,
    bool enabled = true,
  }) => _SliderRow(
    label: label,
    value: value,
    min: min,
    max: max,
    divisions: ((max - min) / step).round(),
    display: display ?? text(value),
    describe: text,
    enabled: enabled,
    onChanged: (next) => _controller.setLook(keyName, next),
    resetLabel: _zh ? '恢复默认' : 'Restore default',
    onReset: settings.look.containsKey(keyName)
        ? () => _controller.setLook(keyName, null)
        : null,
    reserveReset: true,
  );

  Widget _pageScroll(BuildContext context, List<Widget> children) {
    final theme = context.shellTheme;
    return _ScrollEdgeFade(
      controller: _bodyScroll,
      child: RawScrollbar(
        controller: _bodyScroll,
        thumbColor: theme.colors.textPrimary.withValues(alpha: 0.22),
        thickness: 5,
        radius: const Radius.circular(3),
        crossAxisMargin: 2,
        minThumbLength: 36,
        child: SingleChildScrollView(
          controller: _bodyScroll,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, DockSettings settings, {Key? key}) {
    final theme = context.shellTheme;
    final pages = _pages(settings);
    return LayoutBuilder(
      key: key,
      builder: (context, constraints) {
        if (constraints.maxWidth < _twoPaneWidth) {
          return _pageScroll(context, [
            for (final (index, page) in pages.indexed) ...[
              if (index > 0) const SizedBox(height: 22),
              ...page.sections,
            ],
          ]);
        }
        final selected = _page.clamp(0, pages.length - 1);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 204,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (index, page) in pages.indexed)
                      _CategoryItem(
                        icon: page.icon,
                        label: page.title,
                        selected: index == selected,
                        onTap: () {
                          if (index == selected) return;
                          setState(() => _page = index);
                          if (_bodyScroll.hasClients) _bodyScroll.jumpTo(0);
                        },
                      ),
                  ],
                ),
              ),
            ),
            SizedBox(width: 1, child: ColoredBox(color: theme.colors.hairline)),
            Expanded(child: _pageScroll(context, pages[selected].sections)),
          ],
        );
      },
    );
  }

  Widget _buildBrowser(BuildContext context, {Key? key}) {
    final theme = context.shellTheme;
    final colors = theme.colors;
    final path = _browsePath ?? _home();
    final directories = DockExtras.listDirectories(path);
    final visible = [
      for (final directory in directories)
        if (_showHidden || !_basename(directory).startsWith('.')) directory,
    ];
    // Files are pinnable too, so the same browser lists them below the
    // folders: the dock lets one file sit beside the stacks.
    final files = DockExtras.listFiles(path, hidden: _showHidden);
    final parent = _parentOf(path);
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _ScrollEdgeFade(
            controller: _browserScroll,
            child: RawScrollbar(
              controller: _browserScroll,
              thumbColor: colors.textPrimary.withValues(alpha: 0.22),
              thickness: 5,
              radius: const Radius.circular(3),
              crossAxisMargin: 2,
              minThumbLength: 36,
              child: ListView(
                controller: _browserScroll,
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                children: [
                  _ToggleRow(
                    label: _zh ? '显示隐藏项' : 'Show hidden items',
                    value: _showHidden,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    radius: 8,
                    onChanged: (value) => setState(() => _showHidden = value),
                  ),
                  if (parent != null)
                    _ActionRow(
                      icon: Icons.drive_file_move_outline,
                      label: '..',
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      radius: 8,
                      onTap: () => setState(() => _browsePath = parent),
                    ),
                  for (final directory in visible)
                    _ActionRow(
                      icon: Icons.folder_outlined,
                      label: _basename(directory),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      radius: 8,
                      onTap: () => setState(() => _browsePath = directory),
                    ),
                  for (final file in files)
                    _ActionRow(
                      icon: Icons.insert_drive_file_outlined,
                      label: _basename(file),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      radius: 8,
                      onTap: () {
                        _controller.addFile(
                          DockFile(path: file, label: _basename(file)),
                        );
                        setState(() => _browsePath = null);
                      },
                    ),
                  if (visible.isEmpty && files.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 40,
                      ),
                      child: Column(
                        children: [
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: colors.textPrimary.withValues(alpha: 0.05),
                              shape: BoxShape.circle,
                            ),
                            child: SizedBox(
                              width: 46,
                              height: 46,
                              child: Icon(
                                Icons.folder_off_outlined,
                                size: 22,
                                color: colors.textTertiary,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _zh
                                ? '这里没有可添加的子文件夹或文件。'
                                : 'No folders or files here.',
                            textAlign: TextAlign.center,
                            style: _captionStyle(theme),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        SizedBox(height: 1, child: ColoredBox(color: colors.hairline)),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _captionStyle(theme),
                ),
              ),
              const SizedBox(width: 10),
              _PillButton(
                label: _zh ? '添加此文件夹' : 'Add this folder',
                primary: true,
                onTap: () {
                  final label = folderLabel(
                    path,
                    home: _home(),
                    homeLabel: _zh ? '主目录' : 'Home',
                  );
                  _controller.addFolder(DockFolder(path: path, label: label));
                  setState(() => _browsePath = null);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _basename(String path) {
    final trimmed = path.length > 1 && path.endsWith('/')
        ? path.substring(0, path.length - 1)
        : path;
    final index = trimmed.lastIndexOf('/');
    if (index < 0) return trimmed;
    final name = trimmed.substring(index + 1);
    return name.isEmpty ? '/' : name;
  }

  static String? _parentOf(String path) {
    if (path == '/' || path.isEmpty) return null;
    final trimmed = path.length > 1 && path.endsWith('/')
        ? path.substring(0, path.length - 1)
        : path;
    final index = trimmed.lastIndexOf('/');
    if (index <= 0) return '/';
    return trimmed.substring(0, index);
  }
}

class _ScrollEdgeFade extends StatefulWidget {
  const _ScrollEdgeFade({required this.controller, required this.child});

  final ScrollController controller;
  final Widget child;

  @override
  State<_ScrollEdgeFade> createState() => _ScrollEdgeFadeState();
}

class _ScrollEdgeFadeState extends State<_ScrollEdgeFade> {
  static const double _extent = 18;
  double _top = 0;
  double _bottom = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_sync);
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void didUpdateWidget(covariant _ScrollEdgeFade oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_sync);
    widget.controller.addListener(_sync);
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void dispose() {
    widget.controller.removeListener(_sync);
    super.dispose();
  }

  void _sync() {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
      return;
    }
    final controller = widget.controller;
    var top = 0.0;
    var bottom = 0.0;
    if (controller.hasClients) {
      final position = controller.position;
      top = (position.pixels / 24).clamp(0.0, 1.0);
      bottom = ((position.maxScrollExtent - position.pixels) / 24).clamp(
        0.0,
        1.0,
      );
    }
    if ((top - _top).abs() < 0.01 && (bottom - _bottom).abs() < 0.01) return;
    setState(() {
      _top = top;
      _bottom = bottom;
    });
  }

  /// The shell delivers wheel events as pointer signals, but the scroll view
  /// does not always claim them. Driving the controller here keeps the sheet
  /// scrolling with the wheel; an inner scrollable still wins the resolver.
  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || event.scrollDelta.dy == 0) return;
    final controller = widget.controller;
    if (!controller.hasClients) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      final position = controller.position;
      final target = (position.pixels + event.scrollDelta.dy).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if (target == position.pixels) return;
      controller.jumpTo(target);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: _handlePointerSignal,
      child: NotificationListener<ScrollMetricsNotification>(
        onNotification: (_) {
          _sync();
          return false;
        },
        child: ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (rect) {
            final start = (_extent / math.max(1, rect.height)).clamp(0.0, 0.5);
            return LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.white.withValues(alpha: 1 - _top),
                Colors.white,
                Colors.white,
                Colors.white.withValues(alpha: 1 - _bottom),
              ],
              stops: [0, start, 1 - start, 1],
            ).createShader(rect);
          },
          child: widget.child,
        ),
      ),
    );
  }
}

/// Below this the sheet has no room for a category list beside the page.
const double _twoPaneWidth = 600;

class _CategoryItem extends StatefulWidget {
  const _CategoryItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_CategoryItem> createState() => _CategoryItemState();
}

class _CategoryItemState extends State<_CategoryItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = theme.colors;
    final selected = widget.selected;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Semantics(
          button: true,
          selected: selected,
          label: widget.label,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: _motion(context, const Duration(milliseconds: 140)),
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                borderRadius: theme.borderRadius(9),
                color: selected
                    ? theme.kitAccent.withValues(alpha: 0.18)
                    : colors.textPrimary.withValues(alpha: _hovered ? 0.06 : 0),
              ),
              child: Row(
                children: [
                  Icon(
                    widget.icon,
                    size: 16,
                    color: selected ? theme.kitAccent : colors.textSecondary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ExcludeSemantics(
                      child: Text(
                        widget.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _labelStyle(theme).copyWith(
                          color: colors.textPrimary,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.title,
    required this.children,
    this.footer,
  });

  final String title;
  final List<Widget> children;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = theme.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Semantics(
            header: true,
            child: Text(title.toUpperCase(), style: _sectionStyle(theme)),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                colors.textPrimary.withValues(alpha: 0.055),
                colors.textPrimary.withValues(alpha: 0.035),
              ],
            ),
            borderRadius: theme.borderRadius(_cardRadius),
            border: Border.all(color: colors.hairlineSoft),
          ),
          child: ClipRRect(
            borderRadius: theme.borderRadius(_cardRadius),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var index = 0; index < children.length; index++) ...[
                  if (index > 0)
                    Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: SizedBox(
                        height: 1,
                        child: ColoredBox(color: colors.hairlineSoft),
                      ),
                    ),
                  children[index],
                ],
              ],
            ),
          ),
        ),
        if (footer != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
            child: Text(footer!, style: _captionStyle(theme)),
          ),
      ],
    );
  }
}

class _SegmentedField<T> extends StatelessWidget {
  const _SegmentedField({
    required this.value,
    required this.options,
    required this.onChanged,
    this.label,
  });

  final T value;
  final List<(T, String, IconData)> options;
  final ValueChanged<T> onChanged;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (label != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(3, 0, 3, 9),
              child: Text(
                label!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _labelStyle(theme),
              ),
            ),
          _SlidingSegments<T>(
            value: value,
            options: options,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _SlidingSegments<T> extends StatefulWidget {
  const _SlidingSegments({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final T value;
  final List<(T, String, IconData)> options;
  final ValueChanged<T> onChanged;

  @override
  State<_SlidingSegments<T>> createState() => _SlidingSegmentsState<T>();
}

class _SlidingSegmentsState<T> extends State<_SlidingSegments<T>>
    with SingleTickerProviderStateMixin<_SlidingSegments<T>> {
  static const double _inset = 3;

  late final AnimationController _slide;
  int _pressedIndex = -1;

  double get _target => _positionFor(_selectedIndex);

  int get _selectedIndex {
    final index = widget.options.indexWhere(
      (option) => option.$1 == widget.value,
    );
    return index < 0 ? 0 : index;
  }

  double _positionFor(int index) {
    final count = widget.options.length;
    return count < 2 ? 0 : index / (count - 1);
  }

  @override
  void initState() {
    super.initState();
    // initState may not read MediaQuery, so the pace comes from the platform
    // value the kit falls back to.
    _slide = AnimationController(
      vsync: this,
      duration: KitMotion.now.duration(const Duration(milliseconds: 360)),
      value: _target,
    );
  }

  @override
  void dispose() {
    _slide.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _SlidingSegments<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A speed change inside the sheet reaches the running controls too.
    final duration = KitMotion.now.duration(const Duration(milliseconds: 360));
    if (_slide.duration != duration) _slide.duration = duration;
    if (oldWidget.options.length != widget.options.length) {
      _slide.value = _target;
      return;
    }
    if (oldWidget.value != widget.value) _settle();
  }

  void _settle() {
    if (MediaQuery.disableAnimationsOf(context)) {
      _slide.value = _target;
      return;
    }
    springTo(
      _slide,
      _target,
      spring: Motion.bouncy,
      telemetryLabel: 'dock.settings.segments',
    );
  }

  int _indexAt(double dx, double width) {
    final count = widget.options.length;
    final inner = math.max(1.0, width - _inset * 2);
    final t = ((dx - _inset) / inner).clamp(0.0, 1.0);
    return (t * count).floor().clamp(0, count - 1);
  }

  void _select(int index) {
    if (index < 0 || index >= widget.options.length) return;
    final next = widget.options[index].$1;
    if (next == widget.value) return;
    widget.onChanged(next);
  }

  void _clearPress() {
    if (_pressedIndex < 0) return;
    setState(() => _pressedIndex = -1);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = theme.colors;
    final count = widget.options.length;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            dragStartBehavior: DragStartBehavior.down,
            onTapDown: (details) => setState(
              () => _pressedIndex = _indexAt(details.localPosition.dx, width),
            ),
            onTapUp: (details) {
              _select(_indexAt(details.localPosition.dx, width));
              _clearPress();
            },
            onTapCancel: _clearPress,
            onHorizontalDragStart: (details) =>
                _select(_indexAt(details.localPosition.dx, width)),
            onHorizontalDragUpdate: (details) =>
                _select(_indexAt(details.localPosition.dx, width)),
            onHorizontalDragEnd: (_) => _clearPress(),
            onHorizontalDragCancel: _clearPress,
            child: Container(
              height: 36,
              padding: const EdgeInsets.all(_inset),
              decoration: BoxDecoration(
                color: colors.textPrimary.withValues(alpha: 0.05),
                borderRadius: theme.borderRadius(11),
                border: Border.all(color: colors.hairlineSoft),
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: AnimatedScale(
                      scale: _pressedIndex >= 0 ? 0.985 : 1,
                      duration: _motion(context, _quick),
                      curve: Motion.standard,
                      child: AnimatedBuilder(
                        animation: _slide,
                        builder: (context, child) => Align(
                          alignment: Alignment(
                            -1 + 2 * _slide.value.clamp(0.0, 1.0),
                            0,
                          ),
                          child: FractionallySizedBox(
                            widthFactor: 1 / count,
                            heightFactor: 1,
                            child: child,
                          ),
                        ),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Color.alphaBlend(
                                  theme.kitAccent.withValues(alpha: 0.24),
                                  colors.surfaceContainerHigh,
                                ),
                                Color.alphaBlend(
                                  theme.kitAccent.withValues(alpha: 0.14),
                                  colors.surfaceContainerHigh,
                                ),
                              ],
                            ),
                            borderRadius: theme.borderRadius(8),
                            border: Border.all(
                              color: theme.kitAccent.withValues(alpha: 0.28),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: colors.shadow,
                                blurRadius: 6,
                                offset: const Offset(0, 1.5),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var index = 0; index < count; index++)
                          Expanded(
                            child: _Segment(
                              label: widget.options[index].$2,
                              icon: widget.options[index].$3,
                              selected: index == _selectedIndex,
                              pressed: index == _pressedIndex,
                              showIcon: width >= 300,
                              onSelect: () => _select(index),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Segment extends StatefulWidget {
  const _Segment({
    required this.label,
    required this.icon,
    required this.selected,
    required this.pressed,
    required this.onSelect,
    required this.showIcon,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final bool pressed;
  final VoidCallback onSelect;
  final bool showIcon;

  @override
  State<_Segment> createState() => _SegmentState();
}

class _SegmentState extends State<_Segment> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = theme.colors;
    final foreground = widget.selected
        ? theme.kitAccent
        : _hovered
        ? colors.textPrimary
        : colors.textSecondary;
    final quick = _motion(context, _quick);
    return Semantics(
      button: true,
      selected: widget.selected,
      inMutuallyExclusiveGroup: true,
      label: widget.label,
      onTap: widget.onSelect,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedContainer(
          duration: quick,
          curve: Motion.standard,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            color: _hovered && !widget.selected
                ? colors.textPrimary.withValues(alpha: 0.05)
                : Colors.transparent,
            borderRadius: theme.borderRadius(8),
          ),
          child: AnimatedScale(
            scale: widget.pressed ? 0.96 : 1,
            duration: quick,
            curve: Motion.standard,
            child: AnimatedOpacity(
              opacity: widget.pressed && !widget.selected ? 0.5 : 1,
              duration: quick,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (widget.showIcon) ...[
                    TweenAnimationBuilder<Color?>(
                      tween: ColorTween(end: foreground),
                      duration: quick,
                      curve: Motion.standard,
                      builder: (context, color, _) => AnimatedScale(
                        scale: widget.selected ? 1.06 : 1,
                        duration: quick,
                        curve: Motion.standard,
                        child: Icon(
                          widget.icon,
                          size: 14,
                          color: color ?? foreground,
                        ),
                      ),
                    ),
                    const SizedBox(width: 5),
                  ],
                  Flexible(
                    child: AnimatedDefaultTextStyle(
                      duration: quick,
                      curve: Motion.standard,
                      style: theme.text.systemBarCaption.copyWith(
                        color: foreground,
                        height: 1.2,
                        letterSpacing: 0.1,
                        fontWeight: widget.selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                      child: Text(
                        widget.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.label,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.margin = EdgeInsets.zero,
    this.radius = 0,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  /// A row whose setting only matters under another choice stays visible but
  /// inert, so the panel does not reflow as options change.
  final bool enabled;
  final EdgeInsetsGeometry margin;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    void toggle() {
      if (enabled) onChanged(!value);
    }

    return Semantics(
      container: true,
      button: true,
      toggled: value,
      enabled: enabled,
      label: label,
      onTap: toggle,
      child: ExcludeSemantics(
        child: Opacity(
          opacity: enabled ? 1 : 0.45,
          child: _HoverSurface(
            height: _rowHeight,
            margin: margin,
            radius: radius,
            onTap: toggle,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _labelStyle(theme),
                  ),
                ),
                const SizedBox(width: 12),
                _DockSwitch(value: value),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DockSwitch extends StatefulWidget {
  const _DockSwitch({required this.value});

  final bool value;

  @override
  State<_DockSwitch> createState() => _DockSwitchState();
}

class _DockSwitchState extends State<_DockSwitch>
    with SingleTickerProviderStateMixin {
  static const double _width = 44;
  static const double _height = 26;
  static const double _inset = 3;
  static const double _thumb = _height - _inset * 2;

  late final AnimationController _slide;
  bool _hovered = false;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _slide = AnimationController(
      vsync: this,
      duration: KitMotion.now.duration(const Duration(milliseconds: 260)),
      value: widget.value ? 1 : 0,
    );
  }

  @override
  void dispose() {
    _slide.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _DockSwitch oldWidget) {
    super.didUpdateWidget(oldWidget);
    final duration = KitMotion.now.duration(const Duration(milliseconds: 260));
    if (_slide.duration != duration) _slide.duration = duration;
    if (oldWidget.value == widget.value) return;
    final target = widget.value ? 1.0 : 0.0;
    if (MediaQuery.disableAnimationsOf(context)) {
      _slide.value = target;
    } else {
      springTo(
        _slide,
        target,
        spring: Motion.snappy,
        telemetryLabel: 'dock.settings.switch',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = theme.colors;
    final quick = _motion(context, _quick);
    return Listener(
      onPointerDown: (_) => setState(() => _pressed = true),
      onPointerUp: (_) => setState(() => _pressed = false),
      onPointerCancel: (_) => setState(() => _pressed = false),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() {
          _hovered = false;
          _pressed = false;
        }),
        child: AnimatedBuilder(
          animation: _slide,
          builder: (context, _) {
            final t = _slide.value.clamp(0.0, 1.0);
            final track = Color.lerp(
              colors.textPrimary.withValues(alpha: 0.16),
              theme.kitAccent,
              t,
            )!;
            final border = Color.lerp(colors.hairlineSoft, theme.kitAccent, t)!;
            final thumbLeft = _inset + (_width - _inset * 2 - _thumb) * t;
            final scale = _pressed ? 1.12 : (_hovered ? 1.05 : 1.0);
            return SizedBox(
              width: _width,
              height: _height,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Color.alphaBlend(
                          colors.textPrimary.withValues(
                            alpha: _hovered ? 0.04 : 0,
                          ),
                          track,
                        ),
                        borderRadius: BorderRadius.circular(_height / 2),
                        border: Border.all(color: border),
                        boxShadow: [
                          BoxShadow(
                            color: colors.shadow,
                            blurRadius: 2,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: thumbLeft,
                    top: _inset,
                    width: _thumb,
                    height: _thumb,
                    child: AnimatedScale(
                      scale: scale,
                      duration: quick,
                      curve: Motion.standard,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: colors.sliderThumb,
                          border: Border.all(
                            color: colors.textPrimary.withValues(alpha: 0.08),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: colors.shadow,
                              blurRadius: 3,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Picks the tinted-mode colour from a short swatch row. The first swatch is
/// the shell accent, so a fresh install follows the theme without storing a
/// colour.
class _TintRow extends StatelessWidget {
  const _TintRow({
    required this.label,
    required this.accentLabel,
    required this.value,
    required this.accent,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final String accentLabel;
  final String? value;
  final Color accent;
  final bool enabled;
  final ValueChanged<String?> onChanged;

  static const List<String> _swatches = [
    '#a855f7',
    '#3b82f6',
    '#10b981',
    '#f59e0b',
    '#ef4444',
    '#ec4899',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = theme.colors;
    final selected = value?.toLowerCase();
    return AnimatedOpacity(
      duration: _motion(context, _quick),
      opacity: enabled ? 1 : 0.5,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: SizedBox(
          height: 52,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _labelStyle(theme).copyWith(
                    color: enabled ? colors.textPrimary : colors.textSecondary,
                  ),
                ),
              ),
              for (final (index, swatch) in _swatches.indexed) ...[
                if (index > 0) const SizedBox(width: 8),
                _Swatch(
                  color: Color(
                    0xFF000000 | int.parse(swatch.substring(1), radix: 16),
                  ),
                  selected: selected == swatch,
                  enabled: enabled,
                  onTap: () => onChanged(swatch),
                ),
              ],
              const SizedBox(width: 8),
              _Swatch(
                color: accent,
                selected: selected == null,
                enabled: enabled,
                onTap: () => onChanged(null),
                semanticLabel: accentLabel,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.selected,
    required this.enabled,
    required this.onTap,
    this.semanticLabel,
  });

  final Color color;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        child: SizedBox(
          width: 22,
          height: 22,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected
                    ? theme.colors.textPrimary
                    : theme.colors.hairline,
                width: selected ? 2 : 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.display,
    required this.describe,
    required this.onChanged,
    this.enabled = true,
    this.onReset,
    this.resetLabel = '',
    this.reserveReset = false,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String display;
  final String Function(double value) describe;
  final ValueChanged<double> onChanged;
  final bool enabled;

  /// Puts the value back on its default; null while it is already there.
  final VoidCallback? onReset;
  final String resetLabel;

  /// Keeps room for the reset button, so the row does not shift when the
  /// button comes and goes.
  final bool reserveReset;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = theme.colors;
    final labelStyle = _labelStyle(theme)
        .copyWith(color: enabled ? colors.textPrimary : colors.textSecondary);
    final valueStyle = _valueStyle(
      theme,
      enabled ? colors.textSecondary : colors.textTertiary,
    );
    return AnimatedOpacity(
      duration: _motion(context, _quick),
      opacity: enabled ? 1 : 0.5,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final slider = _DockSlider(
            semanticLabel: label,
            semanticValue: display,
            describe: describe,
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            enabled: enabled,
            onChanged: onChanged,
          );
          final readout = Text(
            display,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: valueStyle,
          );
          final reset = !reserveReset
              ? null
              : SizedBox.square(
                  dimension: 26,
                  child: onReset == null
                      ? null
                      : _IconButton(
                          icon: Icons.restart_alt,
                          tooltip: resetLabel,
                          onPressed: onReset!,
                          size: 26,
                          iconSize: 15,
                        ),
                );
          if (constraints.maxWidth < 360) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: labelStyle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(width: 52, child: readout),
                      ?reset,
                    ],
                  ),
                  const SizedBox(height: 1),
                  slider,
                ],
              ),
            );
          }
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SizedBox(
              height: 52,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: labelStyle,
                    ),
                  ),
                  const SizedBox(width: 14),
                  SizedBox(
                    width: (constraints.maxWidth * 0.48).clamp(120.0, 210.0),
                    child: slider,
                  ),
                  const SizedBox(width: 12),
                  SizedBox(width: 52, child: readout),
                  ?reset,
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DockSlider extends StatefulWidget {
  const _DockSlider({
    required this.semanticLabel,
    required this.semanticValue,
    required this.describe,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.enabled,
    required this.onChanged,
  });

  final String semanticLabel;
  final String semanticValue;
  final String Function(double value) describe;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final bool enabled;
  final ValueChanged<double> onChanged;

  @override
  State<_DockSlider> createState() => _DockSliderState();
}

class _DockSliderState extends State<_DockSlider> {
  static const double _thumbSize = 18;
  static const double _trackHeight = 4;
  static const double _height = 32;

  bool _hovered = false;
  bool _pressed = false;

  double get _fraction {
    if (widget.max <= widget.min) return 0;
    return ((widget.value - widget.min) / (widget.max - widget.min)).clamp(
      0.0,
      1.0,
    );
  }

  void _seek(double dx, double width) {
    if (!widget.enabled || width <= 0) return;
    final travel = math.max(1.0, width - _thumbSize);
    final t = ((dx - _thumbSize / 2) / travel).clamp(0.0, 1.0);
    var next = widget.min + (widget.max - widget.min) * t;
    if (widget.divisions > 0) {
      final step = (widget.max - widget.min) / widget.divisions;
      next = widget.min + ((next - widget.min) / step).round() * step;
    }
    widget.onChanged(next.clamp(widget.min, widget.max).toDouble());
  }

  String _preview(int direction) {
    final step = widget.divisions > 0
        ? (widget.max - widget.min) / widget.divisions
        : (widget.max - widget.min) / 20;
    return widget.describe(
      (widget.value + step * direction)
          .clamp(widget.min, widget.max)
          .toDouble(),
    );
  }

  void _step(int direction) {
    if (!widget.enabled) return;
    final step = widget.divisions > 0
        ? (widget.max - widget.min) / widget.divisions
        : (widget.max - widget.min) / 20;
    widget.onChanged(
      (widget.value + step * direction)
          .clamp(widget.min, widget.max)
          .toDouble(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = theme.colors;
    final t = _fraction;
    final active = widget.enabled;
    final quick = _motion(context, _quick);
    return Semantics(
      slider: true,
      enabled: active,
      label: widget.semanticLabel,
      value: widget.semanticValue,
      increasedValue: _preview(1),
      decreasedValue: _preview(-1),
      onIncrease: active ? () => _step(1) : null,
      onDecrease: active ? () => _step(-1) : null,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final travel = math.max(0.0, width - _thumbSize);
          final center = _thumbSize / 2 + travel * t;
          return MouseRegion(
            cursor: active ? SystemMouseCursors.click : MouseCursor.defer,
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() {
              _hovered = false;
              _pressed = false;
            }),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              dragStartBehavior: DragStartBehavior.down,
              onTapDown: active
                  ? (details) {
                      setState(() => _pressed = true);
                      _seek(details.localPosition.dx, width);
                    }
                  : null,
              onTapUp: active ? (_) => setState(() => _pressed = false) : null,
              onTapCancel: active
                  ? () => setState(() => _pressed = false)
                  : null,
              onHorizontalDragStart: active
                  ? (details) {
                      setState(() => _pressed = true);
                      _seek(details.localPosition.dx, width);
                    }
                  : null,
              onHorizontalDragUpdate: active
                  ? (details) => _seek(details.localPosition.dx, width)
                  : null,
              onHorizontalDragEnd: active
                  ? (_) => setState(() => _pressed = false)
                  : null,
              onHorizontalDragCancel: active
                  ? () => setState(() => _pressed = false)
                  : null,
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(
                  end: _hovered || _pressed ? 6.0 : _trackHeight,
                ),
                duration: quick,
                curve: Motion.standard,
                builder: (context, trackHeight, _) {
                  return SizedBox(
                    height: _height,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned(
                          left: 0,
                          right: 0,
                          top: (_height - trackHeight) / 2,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: colors.textPrimary.withValues(
                                alpha: active ? 0.15 : 0.07,
                              ),
                              borderRadius: BorderRadius.circular(
                                trackHeight / 2,
                              ),
                            ),
                            child: SizedBox(height: trackHeight),
                          ),
                        ),
                        Positioned(
                          left: 0,
                          top: (_height - trackHeight) / 2,
                          width: center,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  theme.kitAccent.withValues(
                                    alpha: active ? 0.85 : 0.35,
                                  ),
                                  theme.kitAccent.withValues(
                                    alpha: active ? 1 : 0.4,
                                  ),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(
                                trackHeight / 2,
                              ),
                            ),
                            child: SizedBox(height: trackHeight),
                          ),
                        ),
                        Positioned(
                          left: center - 16,
                          top: (_height - 32) / 2,
                          width: 32,
                          height: 32,
                          child: IgnorePointer(
                            child: AnimatedOpacity(
                              duration: quick,
                              opacity: _hovered || _pressed ? 1 : 0,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: theme.kitAccent.withValues(
                                    alpha: _pressed ? 0.2 : 0.14,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: center - _thumbSize / 2,
                          top: (_height - _thumbSize) / 2,
                          width: _thumbSize,
                          height: _thumbSize,
                          child: IgnorePointer(
                            child: AnimatedScale(
                              scale: _pressed ? 1.12 : (_hovered ? 1.06 : 1),
                              duration: quick,
                              curve: Motion.standard,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: active
                                      ? colors.sliderThumb
                                      : colors.surfaceContainerHigh,
                                  border: Border.all(
                                    color: colors.textPrimary.withValues(
                                      alpha: 0.08,
                                    ),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: colors.shadow,
                                      blurRadius: 4,
                                      offset: const Offset(0, 1),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.margin = EdgeInsets.zero,
    this.radius = 0,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final EdgeInsetsGeometry margin;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = theme.colors;
    return Semantics(
      container: true,
      button: true,
      label: label,
      onTap: onTap,
      child: ExcludeSemantics(
        child: _HoverSurface(
          height: _rowHeight,
          margin: margin,
          radius: radius,
          onTap: onTap,
          child: Row(
            children: [
              _Glyph(icon: icon),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _labelStyle(theme),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color: colors.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Glyph extends StatelessWidget {
  const _Glyph({required this.icon, this.tint});

  final IconData icon;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = theme.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.textPrimary.withValues(alpha: 0.06),
        borderRadius: theme.borderRadius(7),
      ),
      child: SizedBox(
        width: 26,
        height: 26,
        child: Icon(icon, size: 15, color: tint ?? colors.textSecondary),
      ),
    );
  }
}

class _NoteRow extends StatelessWidget {
  const _NoteRow({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Text(text, style: _captionStyle(theme)),
    );
  }
}

class _FolderRow extends StatelessWidget {
  const _FolderRow({
    required this.folder,
    required this.removeTooltip,
    required this.onRemove,
  });

  final DockFolder folder;
  final String removeTooltip;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = theme.colors;
    return Semantics(
      label: '${folder.label}, ${folder.path}',
      child: _HoverSurface(
        height: _rowHeight,
        padding: const EdgeInsets.fromLTRB(12, 0, 6, 0),
        child: Row(
          children: [
            _Glyph(icon: Icons.folder_rounded, tint: theme.kitAccent),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    folder.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.text.cardTitle.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    folder.path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _captionStyle(theme),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            _IconButton(
              icon: Icons.remove_circle_outline,
              tooltip: removeTooltip,
              size: 28,
              iconSize: 16,
              onPressed: onRemove,
            ),
          ],
        ),
      ),
    );
  }
}

/// A pinned single file, listed under the folder shortcuts.
class _FileRow extends StatelessWidget {
  const _FileRow({
    required this.file,
    required this.removeTooltip,
    required this.onRemove,
  });

  final DockFile file;
  final String removeTooltip;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = theme.colors;
    return Semantics(
      label: '${file.label}, ${file.path}',
      child: _HoverSurface(
        height: _rowHeight,
        padding: const EdgeInsets.fromLTRB(12, 0, 6, 0),
        child: Row(
          children: [
            _Glyph(
              icon: stackFileIcon(DockStackFiles.extensionOf(file.path)),
              tint: stackFileColor(DockStackFiles.extensionOf(file.path)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.text.cardTitle.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    file.path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _captionStyle(theme),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            _IconButton(
              icon: Icons.remove_circle_outline,
              tooltip: removeTooltip,
              size: 28,
              iconSize: 16,
              onPressed: onRemove,
            ),
          ],
        ),
      ),
    );
  }
}

class _HoverSurface extends StatefulWidget {
  const _HoverSurface({
    required this.child,
    this.onTap,
    this.height = _rowHeight,
    this.width,
    this.margin = EdgeInsets.zero,
    this.radius = 0,
    this.padding = const EdgeInsets.symmetric(horizontal: 12),
    this.alignment = AlignmentDirectional.centerStart,
    this.scaleOnPress = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double height;
  final double? width;
  final EdgeInsetsGeometry margin;
  final double radius;
  final EdgeInsetsGeometry padding;
  final AlignmentGeometry alignment;
  final bool scaleOnPress;

  @override
  State<_HoverSurface> createState() => _HoverSurfaceState();
}

class _HoverSurfaceState extends State<_HoverSurface> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.shellTheme.colors;
    final enabled = widget.onTap != null;
    final fill = _pressed
        ? colors.textPrimary.withValues(alpha: 0.09)
        : _hovered
        ? colors.textPrimary.withValues(alpha: 0.055)
        : Colors.transparent;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: widget.scaleOnPress && _pressed ? 0.97 : 1,
          duration: _motion(context, _quick),
          curve: Motion.standard,
          child: AnimatedContainer(
            duration: _motion(context, Motion.tile),
            curve: Motion.standard,
            height: widget.height,
            width: widget.width,
            margin: widget.margin,
            padding: widget.padding,
            alignment: widget.alignment,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(widget.radius),
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

class _IconButton extends StatelessWidget {
  const _IconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.size = 30,
    this.iconSize = 17,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final colors = context.shellTheme.colors;
    return Semantics(
      button: true,
      label: tooltip,
      onTap: onPressed,
      child: _HoverSurface(
        width: size,
        height: size,
        radius: 8,
        padding: EdgeInsets.zero,
        alignment: Alignment.center,
        scaleOnPress: true,
        onTap: onPressed,
        child: Icon(icon, size: iconSize, color: colors.textSecondary),
      ),
    );
  }
}

class _PillButton extends StatefulWidget {
  const _PillButton({
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  State<_PillButton> createState() => _PillButtonState();
}

class _PillButtonState extends State<_PillButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = theme.colors;
    final accent = theme.kitAccent;
    final fill = widget.primary
        ? (_pressed
              ? Color.alphaBlend(
                  colors.background.withValues(alpha: 0.16),
                  accent,
                )
              : _hovered
              ? Color.alphaBlend(
                  colors.background.withValues(alpha: 0.08),
                  accent,
                )
              : accent)
        : colors.textPrimary.withValues(
            alpha: _pressed
                ? 0.14
                : _hovered
                ? 0.11
                : 0.08,
          );
    final foreground = widget.primary ? colors.background : colors.textPrimary;
    return Semantics(
      button: true,
      label: widget.label,
      onTap: widget.onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() {
          _hovered = false;
          _pressed = false;
        }),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: _pressed ? 0.97 : 1,
            duration: _motion(context, const Duration(milliseconds: 110)),
            curve: Motion.standard,
            child: AnimatedContainer(
              duration: _motion(context, _quick),
              curve: Motion.standard,
              height: 30,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(15),
                border: widget.primary
                    ? null
                    : Border.all(color: colors.hairlineSoft),
              ),
              child: Text(
                widget.label,
                maxLines: 1,
                style: theme.text.systemBarCaption.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
