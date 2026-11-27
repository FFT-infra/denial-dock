import 'dart:math' as math;
import 'dart:ui' show PointerDeviceKind;

import 'package:denial_flutter_sdk/models.dart' show PanelEdge;
import 'package:denial_flutter_sdk/settings.dart';
import 'package:denial_flutter_sdk/services.dart';
import 'package:denial_flutter_sdk/theme.dart';
import 'package:denial_shell_kit/kit_dock_link.dart';
import 'package:denial_shell_kit/kit_host.dart';
import 'package:denial_shell_kit/kit_motion.dart';
import 'package:denial_shell_kit/kit_part.dart';
import 'package:denial_shell_kit/kit_settings.dart';
import 'package:denial_shell_kit/kit_style.dart';
import 'package:denial_shell_kit/shell_preset.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bar_icons.dart';
import '../bar_panel.dart';
import '../bar_preferences.dart';
import '../bar_segments.dart';
import '../bar_settings.dart';
import '../bar_tokens.dart';
import '../bar_type.dart';
import '../island/island_options.dart';
import '../tray_names.dart';
import '../l10n.dart';
import 'look_page.dart';
import 'mac_kit.dart';
import 'part_drop.dart';
import 'setting_bits.dart' show SettingSlider;

part 'bar_layout_page.dart';

const double barSettingsWidth = 700;

/// The ids the bar's pages have in the shell's settings window, in the
/// order of the panel's own pages.
const List<String> barSettingsPageIds = <String>[
  'bar.appearance',
  'bar.layout',
  'bar.island',
  'bar.workspaces',
  'bar.items',
  'bar.clock',
];

const List<(String, String, List<String>, int)> _barPageMeta =
    <(String, String, List<String>, int)>[
      (
        'Shell',
        'Choose presets, visual looks, motion speed and auto-hide behaviour.',
        <String>[
          'appearance',
          'look',
          'theme',
          'preset',
          'speed',
          'motion',
          'autohide',
          '外观',
          '预设',
          '主题',
          '动效',
          '自动隐藏',
        ],
        100,
      ),
      (
        'Menu Bar',
        'Pick a shell preset, arrange zones and assign shared Dock parts.',
        <String>[
          'layout',
          'preset',
          'shape',
          'strip',
          'floating',
          'islands',
          'zones',
          'parts',
          'dock',
          '布局',
          '预设',
          '形状',
          '通栏',
          '灵动群岛',
          '部件',
        ],
        110,
      ),
      (
        'Menu Bar',
        'Control Dynamic Island triggers, live activities and multi-tasking gestures.',
        <String>[
          'island',
          'activity',
          'media',
          'timer',
          'notification',
          'charging',
          '灵动岛',
          '实时活动',
          '播放',
          '计时器',
          '充电',
        ],
        120,
      ),
      (
        'Workspaces',
        'Configure the workspace switcher, overview gestures and virtual desktops.',
        <String>[
          'workspace',
          'desktop',
          'overview',
          'dots',
          'numbers',
          'scroll',
          '工作区',
          '桌面',
          '总览',
        ],
        150,
      ),
      (
        'Menu Bar',
        'Choose status icons, tray collection style and per-app tray visibility.',
        <String>[
          'tray',
          'items',
          'status',
          'wifi',
          'bluetooth',
          'volume',
          'battery',
          'clipboard',
          'fold',
          '托盘',
          '收纳',
          '状态',
          '电量',
          '剪贴板',
        ],
        130,
      ),
      (
        'Notifications & Control Centre',
        'Set clock display options and Notification Center behaviour.',
        <String>[
          'clock',
          'date',
          'weekday',
          'notification',
          'widget',
          'control',
          '时钟',
          '日期',
          '通知中心',
          '小组件',
        ],
        140,
      ),
    ];

List<KitSettingsPage>? _barPages;

/// Offers the bar's pages to the shell's settings window. The look, the
/// presets and the layout concern the whole shell, so they come first.
void registerBarSettingsPages(ShellServices services) {
  final pages = _barPages ??= <KitSettingsPage>[
    for (var index = 0; index < barSettingsPageIds.length; index++)
      KitSettingsPage(
        id: barSettingsPageIds[index],
        title: (context) =>
            context.tr(_BarSettingsPanelState._pages[index].$1),
        group: (context) => context.tr(_barPageMeta[index].$1),
        subtitle: (context) => context.tr(_barPageMeta[index].$2),
        keywords: _barPageMeta[index].$3,
        icon: _BarSettingsPanelState._pages[index].$2,
        colour: _BarSettingsPanelState._pages[index].$3,
        order: _barPageMeta[index].$4,
        builder: (context) => BarSettingsPanel(
          services: services,
          embedded: index,
          onClose: () {},
          maxHeight: double.infinity,
        ),
      ),
  ];
  kitSettingsPages.register(pages);
  registerLookPage();
}

typedef _Save = void Function(BarSettings Function(BarSettings) change);

/// The bar's settings: a sidebar of pages on the left, the page on the right.
class BarSettingsPanel extends ConsumerStatefulWidget {
  const BarSettingsPanel({
    required this.onClose,
    required this.maxHeight,
    this.services,
    this.initialPage = 0,
    this.embedded,
    super.key,
  });

  /// When set, the panel is that one page with no window around it: the
  /// shell's settings window supplies the sidebar and the title.
  final int? embedded;

  /// Lists the tray's items when given.
  final ShellServices? services;
  final int initialPage;
  final VoidCallback onClose;
  final double maxHeight;

  @override
  ConsumerState<BarSettingsPanel> createState() => _BarSettingsPanelState();
}

class _BarSettingsPanelState extends ConsumerState<BarSettingsPanel> {
  static const List<(String, IconData, Color)> _pages =
      <(String, IconData, Color)>[
        ('Appearance', BarIcons.paintbrushFill, macBlue),
        ('Layout', BarIcons.rectangle3, Color(0xff30a46c)),
        ('Dynamic Island', BarIcons.capsuleFill, Color(0xff1c1c1e)),
        ('Workspaces', BarIcons.squareGrid, macPurple),
        ('Menu Bar Items', BarIcons.appBadgeFill, Color(0xff8e8e93)),
        ('Clock & Notifications', BarIcons.clock, macRed),
      ];

  late int _page = (widget.embedded ?? widget.initialPage).clamp(
    0,
    _pages.length - 1,
  );

  void _namesChanged() => setState(() {});

  /// Puts the bar back as it came. The look and the preset live outside the
  /// bar's own settings, and go back with them.
  void _restore() {
    // Forgotten after the switch: switching remembers the preset it leaves.
    applyShellPreset(ref, ShellPreset.denial, fresh: true);
    forgetShellPresets();
    kitSpeed.value = 1;
    kitShellScale.value = null;
    ref
        .read(barSettingsProvider.notifier)
        .save((s) => BarSettings(recentsClearedAt: s.recentsClearedAt));
  }

  @override
  void initState() {
    super.initState();
    trayNames.addListener(_namesChanged);
    kitShellScale.addListener(_namesChanged);
  }

  @override
  void dispose() {
    trayNames.removeListener(_namesChanged);
    kitShellScale.removeListener(_namesChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final settings =
        ref.watch(barSettingsProvider).value ?? BarSettings.defaults;
    void save(BarSettings Function(BarSettings) change) =>
        ref.read(barSettingsProvider.notifier).save(change);

    final body = switch (_page) {
      0 => _appearance(context, settings, save),
      1 => <Widget>[_LayoutPage(settings: settings, save: save)],
      2 => _island(context, settings, save),
      3 => _workspaces(context, settings, save),
      4 => _items(context, settings, save),
      _ => _clock(context, settings, save),
    };

    if (widget.embedded != null) {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            ...body,
            // The window's own sidebar has no room for it, so the reset
            // sits at the foot of the first page.
            if (_page == 0)
              _Group(
                children: <Widget>[
                  _Row(
                    label: context.tr('Menu Bar'),
                    trailing: SizedBox(
                      width: 132,
                      child: _TextButton(
                        label: context.tr('Restore Defaults'),
                        onTap: _restore,
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      );
    }

    return SizedBox(
      width: barSettingsWidth,
      height: math.min(560, widget.maxHeight),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            width: 204,
            color: theme.colors.textPrimary.withValues(alpha: 0.04),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                KitWindowHandle(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 18, 12, 12),
                    child: Text(
                      context.tr('Menu Bar'),
                      style: BarType.title.copyWith(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: theme.colors.textPrimary,
                      ),
                    ),
                  ),
                ),
                for (var i = 0; i < _pages.length; i++)
                  _SidebarItem(
                    label: context.tr(_pages[i].$1),
                    icon: _pages[i].$2,
                    colour: _pages[i].$3,
                    selected: i == _page,
                    onTap: () => setState(() => _page = i),
                  ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: _TextButton(
                    label: context.tr('Restore Defaults'),
                    onTap: _restore,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: 1, child: ColoredBox(color: theme.colors.hairline)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                KitWindowHandle(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(22, 14, 12, 8),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            context.tr(_pages[_page].$1),
                            style: BarType.title.copyWith(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: theme.colors.textPrimary,
                            ),
                          ),
                        ),
                        Pressable(
                          onTap: widget.onClose,
                          scale: 0.85,
                          child: Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              borderRadius: KitStyle.of(context).disc(26),
                              color: theme.colors.textPrimary.withValues(
                                alpha: 0.10,
                              ),
                            ),
                            child: BarGlyph(
                              BarIcons.xmark,
                              size: 11,
                              color: theme.colors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: KitMotion.duration(context, KitMotion.turn),
                    layoutBuilder: (current, previous) => Stack(
                      alignment: Alignment.topCenter,
                      children: <Widget>[...previous, ?current],
                    ),
                    child: SingleChildScrollView(
                      key: ValueKey<int>(_page),
                      padding: const EdgeInsets.fromLTRB(20, 6, 20, 22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: body,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _appearance(BuildContext context, BarSettings s, _Save save) {
    final theme = context.shellTheme;
    final activeStyle = KitStyle.of(context);
    final currentPreset = ShellPreset.byId(kitPreset.value);
    final looks = <KitStyle>[...KitStyle.builtins, ...KitStyle.user];
    return <Widget>[
      // A preset saved, updated or deleted, or the dock rearranged, changes
      // which card is in force without touching the bar's own settings.
      ListenableBuilder(
        listenable: Listenable.merge(<Listenable>[
          kitPreset,
          kitPresets,
          kitDock,
          kitBarMode,
        ]),
        builder: (context, _) => _PresetShelf(settings: s),
      ),
      _Group(
        title: context.tr('Look only'),
        resetLabel: context.tr('Edit Look…'),
        onReset: () => openKitSettingsPage('bar.look'),
        note: context.tr(
          'A look changes colours, glass, corners, type and motion and leaves the layout where it is. The preset above chose “{}”.',
          context.tr(KitStyle.byId(currentPreset.look).label),
        ),
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    for (final style in looks)
                      _LookCard(
                        look: style,
                        label: style.custom ? style.label : context.tr(style.label),
                        selected: style.id == activeStyle.id,
                        onTap: () => kitStyle.choose(style),
                      ),
                  ],
                ),
              ],
            ),
          ),
          _Row(
            label: context.tr('Motion speed'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (kitSpeed.value != 1)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Pressable(
                      onTap: () => kitSpeed.value = 1,
                      scale: 0.96,
                      child: Text(
                        context.tr('Reset'),
                        style: BarType.caption.copyWith(
                          color: activeStyle.accent(theme),
                        ),
                      ),
                    ),
                  ),
                _Segments<double>(
                  value: kitSpeed.value,
                  options: const <(double, String)>[
                    (0.5, '0.5×'),
                    (0.75, '0.75×'),
                    (1, '1×'),
                    (1.5, '1.5×'),
                    (2, '2×'),
                  ],
                  onChanged: (speed) => kitSpeed.value = speed,
                ),
              ],
            ),
          ),
          _Row(
            label: context.tr('Shell scale'),
            trailing: _Segments<double?>(
              value: kitShellScale.value,
              options: <(double?, String)>[
                (null, context.tr('Follow system')),
                (0.85, '85%'),
                (1.0, '100%'),
                (1.10, '110%'),
                (1.25, '125%'),
              ],
              onChanged: (scale) => kitShellScale.value = scale,
            ),
          ),
          if (kitShellScale.value != null)
            SettingSlider(
              label: context.tr('Custom shell scale'),
              value: kitShellScale.value!,
              min: 0.75,
              max: 1.50,
              step: 0.05,
              text: (v) => '${(v * 100).round()}%',
              onChanged: (v) => kitShellScale.value = v,
            ),
        ],
      ),
      _Group(
        title: context.tr('Auto-hide'),
        resetLabel: s.autoHide ? context.tr('Reset') : null,
        onReset: s.autoHide
            ? () => save(
                (s) => s.copyWith(
                  autoHide: false,
                  autoHideDelayMs: barAutoHideDelayDefault,
                ),
              )
            : null,
        note: context.tr(
          'The bar slides away and returns when the pointer or a finger touches its strip at the screen edge. Windows keep that strip free.',
        ),
        children: <Widget>[
          _Switch(
            label: context.tr('Automatically hide and show the menu bar'),
            value: s.autoHide,
            onChanged: (v) => save((s) => s.copyWith(autoHide: v)),
          ),
          _Row(
            label: context.tr('Reveal delay'),
            enabled: s.autoHide,
            note: s.autoHide
                ? null
                : context.tr(
                    'Turn on “Automatically hide and show the menu bar” to set a reveal delay.',
                  ),
            trailing: _Segments<int>(
              value: s.autoHideDelayMs <= 60
                  ? 0
                  : (s.autoHideDelayMs <= 250 ? 120 : 400),
              options: <(int, String)>[
                (0, context.tr('None')),
                (120, context.tr('Short')),
                (400, context.tr('Long')),
              ],
              onChanged: (v) => save((s) => s.copyWith(autoHideDelayMs: v)),
            ),
          ),
        ],
      ),
    ];
  }

  /// Why an island option is out of reach, in words.
  String _why(BuildContext context, IslandWhy why) => context.tr(switch (why) {
    IslandWhy.barHidden => 'The bar is hidden.',
    IslandWhy.barNotOnTop =>
      'The island needs the bar at the top of the screen.',
    IslandWhy.islandOff => 'Turn on the Dynamic Island first.',
    IslandWhy.islandOnly =>
      'Always shown while the bar is reduced to its island.',
    IslandWhy.needsFade => 'Only while the island fades under the pointer.',
    IslandWhy.needsNotifications => 'Only while notifications show here.',
    IslandWhy.needsTwoLive =>
      'Needs two of Now Playing, Timer, Screen recording and Downloads.',
    IslandWhy.needsPages =>
      'Needs two activities to turn between, or one and the home panel.',
    IslandWhy.needsPanel => 'Needs an activity that opens a panel.',
  });

  List<Widget> _island(BuildContext context, BarSettings s, _Save save) {
    final side = ref.watch(
      shellSettingsProvider.select((v) => v.layout.systemBarSide),
    );
    // Every dependency between these switches is decided in one place.
    final options = IslandOptions(
      s,
      mode: kitBarModeInForce,
      top: side == PanelEdge.top || side == PanelEdge.hidden,
    );
    // The reason the whole page is out of reach is said once, above it;
    // a row says only what is particular to it.
    final absent = options.present ? null : options[IslandOption.media].why;
    String? note(IslandOption option) {
      final why = options[option].why;
      return why == null || why == absent ? null : _why(context, why);
    }

    _Switch toggle(IslandOption option, String label) {
      final state = options[option];
      return _Switch(
        label: context.tr(label),
        value: state.on,
        enabled: state.enabled,
        note: note(option),
        onChanged: (v) =>
            save((s) => IslandOptions(s, mode: options.mode, top: true)
                .set(option, v)),
      );
    }

    return <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
        child: Text(
          absent != null
              ? _why(context, absent)
              : options.workspacesLost
              ? context.tr(
                  'The workspace switcher is set to ride in the island, so it shows nowhere while the island is off.',
                )
              : context.tr(
                  'Pressing and holding opens it too; click outside or press Esc to close it.',
                ),
          style: BarType.caption.copyWith(
            height: 1.35,
            color: context.shellTheme.colors.textSecondary,
          ),
        ),
      ),
      _Group(
        note: context.tr(
          'The island sits in the middle of a bar at the top of the screen. Click or tap it to open the activity; drag down to pull it open.',
        ),
        children: <Widget>[
          toggle(IslandOption.shown, 'Show Dynamic Island'),
          toggle(IslandOption.hoverPeek, 'Open when the pointer rests on it'),
          toggle(IslandOption.hoverFade, 'Fade away under the pointer'),
          _Pair(
            _timing(
              context,
              label: context.tr('Fade after the pointer rests for'),
              value: s.islandFadeDelayMs,
              min: BarMetric.islandFadeDelayMsMin,
              max: BarMetric.islandFadeDelayMsMax,
              step: 50,
              enabled: options[IslandOption.fadeDelay].enabled,
              onChanged: (v) => save((s) => s.copyWith(islandFadeDelayMs: v)),
            ),
            _timing(
              context,
              label: context.tr('Press and hold to open after'),
              value: s.islandLongPressMs,
              min: BarMetric.islandLongPressMsMin,
              max: BarMetric.islandLongPressMsMax,
              step: 10,
              enabled: options[IslandOption.longPress].enabled,
              onChanged: (v) => save((s) => s.copyWith(islandLongPressMs: v)),
            ),
          ),
          _Cell(
            label: context.tr('Width at rest'),
            detail: s.islandWidth == BarMetric.islandWidth
                ? context.tr('As the look has it')
                : '${s.islandWidth}%',
            enabled: options[IslandOption.shown].on,
            child: MacSlider(
              inList: true,
              value:
                  (s.islandWidth - BarMetric.islandWidthMin) /
                  (BarMetric.islandWidthMax - BarMetric.islandWidthMin),
              onChanged: (v) {
                final next =
                    ((BarMetric.islandWidthMin +
                                    v *
                                        (BarMetric.islandWidthMax -
                                            BarMetric.islandWidthMin)) /
                                10)
                            .round() *
                        10;
                if (next != s.islandWidth) {
                  save((s) => s.copyWith(islandWidth: next));
                }
              },
            ),
          ),
        ],
      ),
      _Group(
        title: context.tr('Live Activities'),
        note: context.tr(
          'Denial still shows its own volume and brightness display: a plugin cannot replace it.',
        ),
        children: <Widget>[
          toggle(IslandOption.media, 'Now Playing'),
          toggle(IslandOption.notifications, 'Notifications'),
          toggle(IslandOption.charging, 'Charging and low battery'),
          toggle(IslandOption.hud, 'Volume and brightness'),
          toggle(IslandOption.recording, 'Screen recording'),
          toggle(IslandOption.timer, 'Timer'),
          toggle(IslandOption.progress, 'Downloads and file copies'),
          toggle(IslandOption.status, 'Bluetooth, Wi-Fi and Focus changes'),
          _Row(
            label: context.tr('Keep a notification for'),
            enabled: options[IslandOption.noticeHold].enabled,
            note: note(IslandOption.noticeHold),
            trailing: _Segments<int>(
              value: s.islandNoticeSeconds <= 3
                  ? 3
                  : (s.islandNoticeSeconds <= 5 ? 5 : 8),
              options: <(int, String)>[
                for (final n in const <int>[3, 5, 8])
                  (n, context.tr('{} s', n)),
              ],
              onChanged: (v) =>
                  save((s) => s.copyWith(islandNoticeSeconds: v)),
            ),
          ),
        ],
      ),
      _Group(
        title: context.tr('Several Activities'),
        note: context.tr(
          'Downloads and file copies come from applications that report progress to docks. Timers start from the Timer control in Control Centre or from the home card.',
        ),
        children: <Widget>[
          toggle(IslandOption.split, 'Show other activities beside the island'),
          toggle(IslandOption.swipe, 'Swipe sideways to switch activities'),
          toggle(IslandOption.home, 'Open a home card from the resting island'),
          _Row(
            label: context.tr('Timers on the home card'),
            enabled:
                options[IslandOption.home].on &&
                options[IslandOption.timer].on,
            note:
                options[IslandOption.home].on && options[IslandOption.timer].on
                ? null
                : context.tr('Needs the home card and the Timer activity.'),
            trailing: _Segments<int>(
              value: s.islandTimerSet,
              options: <(int, String)>[
                for (var i = 0; i < BarMetric.islandTimerSets.length; i++)
                  (i, BarMetric.islandTimerSets[i].join(' · ')),
              ],
              onChanged: (v) => save((s) => s.copyWith(islandTimerSet: v)),
            ),
          ),
        ],
      ),
    ];
  }

  List<Widget> _workspaces(BuildContext context, BarSettings s, _Save save) {
    final layout = ref.watch(shellSettingsProvider.select((v) => v.layout));
    final shell = ref.read(shellSettingsProvider.notifier);
    final placement = s.workspacesShownIn;
    final shown = placement != BarWorkspacePlacement.hidden;
    return <Widget>[
      _Group(
        children: <Widget>[
          _Row(
            label: context.tr('Show in'),
            // No option is lit while the layout page holds the switcher in
            // the centre.
            trailing: _Segments<BarWorkspacePlacement?>(
              value: placement,
              options: <(BarWorkspacePlacement?, String)>[
                (BarWorkspacePlacement.island, context.tr('Island')),
                (BarWorkspacePlacement.leading, context.tr('Left')),
                (BarWorkspacePlacement.trailing, context.tr('Right')),
                (BarWorkspacePlacement.hidden, context.tr('Hidden')),
              ],
              onChanged: (v) {
                if (v != null) save((s) => s.withWorkspacePlacement(v));
              },
            ),
          ),
          _Row(
            label: context.tr('Style'),
            enabled: shown,
            trailing: _Segments<BarWorkspaceStyle>(
              value: s.workspaceStyle,
              options: <(BarWorkspaceStyle, String)>[
                (BarWorkspaceStyle.dots, context.tr('Dots')),
                (BarWorkspaceStyle.numbers, context.tr('Numbers')),
              ],
              onChanged: (v) => save((s) => s.copyWith(workspaceStyle: v)),
            ),
          ),
        ],
      ),
      _Group(
        note: context.tr(
          'In the overview, tap a desktop to go there, or drag a window onto another desktop to move it. Hold or right-click the indicator to open it at any time.',
        ),
        children: <Widget>[
          _Switch(
            label: context.tr('Scroll or swipe on the indicator to switch'),
            value: s.workspaceScroll,
            enabled: shown,
            onChanged: (v) => save((s) => s.copyWith(workspaceScroll: v)),
          ),
          _Switch(
            label: context.tr('Show the overview when the pointer rests'),
            value: s.workspacePreview,
            enabled: shown,
            note: shown
                ? null
                : context.tr(
                    'Choose where to show the workspace switcher above first.',
                  ),
            onChanged: (v) => save((s) => s.copyWith(workspacePreview: v)),
          ),
        ],
      ),
      _Group(
        title: context.tr('Overview'),
        resetLabel:
            !s.overviewShowMinimised ||
                    !s.overviewMiddleClickCloses ||
                    !s.overviewLiveOtherWorkspaces ||
                    s.overviewLiveLimit != 6
                ? context.tr('Reset')
                : null,
        onReset: () => save(
          (s) => s.copyWith(
            overviewShowMinimised: true,
            overviewMiddleClickCloses: true,
            overviewLiveOtherWorkspaces: true,
            overviewLiveLimit: 6,
          ),
        ),
        children: <Widget>[
          _Switch(
            label: context.tr('Show minimised windows'),
            value: s.overviewShowMinimised,
            onChanged: (v) =>
                save((s) => s.copyWith(overviewShowMinimised: v)),
          ),
          _Switch(
            label: context.tr('Live thumbnails on other desktops'),
            value: s.overviewLiveOtherWorkspaces,
            onChanged: (v) =>
                save((s) => s.copyWith(overviewLiveOtherWorkspaces: v)),
          ),
          _Switch(
            label: context.tr('Middle-click a thumbnail to close window'),
            value: s.overviewMiddleClickCloses,
            onChanged: (v) =>
                save((s) => s.copyWith(overviewMiddleClickCloses: v)),
          ),
          _Row(
            label: context.tr('Live thumbnails per desktop'),
            trailing: _Stepper(
              value: s.overviewLiveLimit,
              min: 1,
              max: 12,
              onChanged: (v) => save((s) => s.copyWith(overviewLiveLimit: v)),
            ),
          ),
        ],
      ),
      _Group(
        title: context.tr('System'),
        children: <Widget>[
          _Switch(
            label: context.tr('Use workspaces'),
            value: layout.workspacesEnabled,
            onChanged: shell.setWorkspacesEnabled,
          ),
          _Row(
            label: context.tr('Number of desktops'),
            enabled: layout.workspacesEnabled,
            trailing: _Stepper(
              value: layout.workspaceCount,
              min: minimumWorkspaceCount,
              max: maximumWorkspaceCount,
              onChanged: (v) => shell.setWorkspaceCount(v.toDouble()),
            ),
          ),
        ],
      ),
    ];
  }

  static const Map<String, (String, IconData)> _statusItems =
      <String, (String, IconData)>{
        'tray': ('System tray', BarIcons.squareGrid),
        'wifi': ('Wi-Fi', BarIcons.wifi),
        'bluetooth': ('Bluetooth', BarIcons.bluetooth),
        'volume': ('Sound', BarIcons.speaker3Fill),
        'battery': ('Battery', BarIcons.batteryFull),
        'keyboard': ('Keyboard layout', BarIcons.globe),
        'search': ('Search', BarIcons.search),
        'clipboard': ('Clipboard History', BarIcons.clipboard),
        'notifications': ('Notifications', BarIcons.bellFill),
        'controlcenter': ('Control Centre', BarIcons.sliderHorizontal3),
        'settings': ('Menu Bar Settings', BarIcons.gear),
      };

  static bool _shown(BarSettings s, String id) => switch (id) {
    'tray' => s.showTray,
    'wifi' => s.showWifi,
    'bluetooth' => s.showBluetooth,
    'volume' => s.showVolume,
    'battery' => s.showBattery,
    'keyboard' => s.showKeyboard,
    'search' => s.showSearch,
    'clipboard' => s.showClipboard,
    'notifications' => s.showNotifications,
    'controlcenter' => s.showControlCenter,
    _ => s.showSettingsButton,
  };

  static BarSettings _show(BarSettings s, String id, bool v) => switch (id) {
    'tray' => s.copyWith(showTray: v),
    'wifi' => s.copyWith(showWifi: v),
    'bluetooth' => s.copyWith(showBluetooth: v),
    'volume' => s.copyWith(showVolume: v),
    'battery' => s.copyWith(showBattery: v),
    'keyboard' => s.copyWith(showKeyboard: v),
    'search' => s.copyWith(showSearch: v),
    'clipboard' => s.copyWith(showClipboard: v),
    'notifications' => s.copyWith(showNotifications: v),
    'controlcenter' => s.copyWith(showControlCenter: v),
    _ => s.copyWith(showSettingsButton: v),
  };

  List<Widget> _items(BuildContext context, BarSettings s, _Save save) {
    final services = widget.services;
    final trayIds = services == null
        ? const <String>[]
        : ref.watch(services.trayItemIds);
    trayNames.resolve(trayIds);
    bool listed(List<String> keys, String id) =>
        keys.contains(trayNames.of(id).key) || keys.contains(id);
    void place(String id, int section) {
      final key = trayNames.of(id).key;
      bool other(String entry) => entry != key && entry != id;
      save(
        (s) => s.copyWith(
          trayHidden: <String>[
            ...s.trayHidden.where(other),
            if (section == 1) key,
          ],
          trayNever: <String>[
            ...s.trayNever.where(other),
            if (section == 2) key,
          ],
        ),
      );
    }

    final order = <String>[
      ...<String>{...s.statusOrder, ..._statusItems.keys},
    ].where(_statusItems.containsKey).toList();
    return <Widget>[
      _Group(
        title: context.tr('Left side'),
        children: <Widget>[
          _Switch(
            label: context.tr('System menu'),
            value: s.hasPart(BarPart.system),
            onChanged: (v) => save((s) => s.withPart(BarPart.system, v)),
          ),
          _Switch(
            label: context.tr('Application name'),
            value: s.hasPart(BarPart.app),
            onChanged: (v) => save((s) => s.withPart(BarPart.app, v)),
          ),
        ],
      ),
      _Group(
        title: context.tr('Right side'),
        note: context.tr(
          'Drag the handle to change the order in the menu bar.',
        ),
        children: <Widget>[
          _OrderList(
            ids: order,
            onReorder: (ids) => save((s) => s.copyWith(statusOrder: ids)),
            rowBuilder: (id) => (
              icon: _statusItems[id]!.$2,
              label: context.tr(_statusItems[id]!.$1),
              value: _shown(s, id),
              onChanged: (v) => save((s) => _show(s, id, v)),
            ),
          ),
        ],
      ),
      _Group(
        children: <Widget>[
          _Switch(
            label: context.tr('Show a stop button while recording the screen'),
            value: s.showRecording,
            onChanged: (v) => save((s) => s.copyWith(showRecording: v)),
          ),
          _Switch(
            label: context.tr('Show a dot while the microphone is in use'),
            value: s.showMic,
            onChanged: (v) => save((s) => s.copyWith(showMic: v)),
          ),
          _Switch(
            label: context.tr('Show places and servers in Recent Items'),
            value: s.recentPlaces,
            onChanged: (v) => save((s) => s.copyWith(recentPlaces: v)),
          ),
          _Switch(
            label: context.tr('Show names when the pointer rests on an item'),
            value: s.tooltips,
            onChanged: (v) => save((s) => s.copyWith(tooltips: v)),
          ),
        ],
      ),
      _Group(
        title: context.tr('System tray'),
        // The per-item choices below are the user's own list and are not
        // part of what this group puts back.
        resetLabel: s.collapseItems ||
                s.trayFold != BarTrayFold.inline ||
                s.collapseAutoSeconds != 15
            ? context.tr('Reset')
            : null,
        onReset: () => save(
          (s) => s.copyWith(
            collapseItems: false,
            trayFold: BarTrayFold.inline,
            collapseAutoSeconds: 15,
          ),
        ),
        children: <Widget>[
          _Switch(
            label: context.tr('Icons in colour'),
            value: s.trayColour,
            enabled: s.showTray,
            note: s.showTray
                ? null
                : context.tr('Enable System tray above to change icon appearance.'),
            onChanged: (v) => save((s) => s.copyWith(trayColour: v)),
          ),
          _Switch(
            label: context.tr('Collect tray icons'),
            value: s.collapseItems,
            enabled: s.showTray,
            note: !s.showTray
                ? context.tr('System tray is turned off.')
                : s.trayHidden.isNotEmpty
                ? context.tr(
                    'Items marked Hidden below are collected either way; this adds every other icon.',
                  )
                : null,
            onChanged: (v) => save((s) => s.copyWith(collapseItems: v)),
          ),
          _Row(
            label: context.tr('Collection style'),
            enabled: s.showTray && (s.collapseItems || s.trayHidden.isNotEmpty),
            note: !s.showTray
                ? context.tr('System tray is turned off.')
                : !(s.collapseItems || s.trayHidden.isNotEmpty)
                ? context.tr(
                    'Turn on folding or set an item below to Hidden first.',
                  )
                : s.trayFold == BarTrayFold.controlCenter &&
                      !s.showControlCenter
                ? context.tr(
                    'Control Centre is off in the menu bar, so the icons open in a grid instead.',
                  )
                : null,
            trailing: _Segments<BarTrayFold>(
              value: s.trayFold,
              options: <(BarTrayFold, String)>[
                (BarTrayFold.inline, context.tr('Arrow')),
                (BarTrayFold.hover, context.tr('Hover')),
                (BarTrayFold.floatingBar, context.tr('Floating bar')),
                (BarTrayFold.popover, context.tr('Grid')),
                (BarTrayFold.controlCenter, context.tr('Control Centre')),
              ],
              onChanged: (v) => save((s) => s.copyWith(trayFold: v)),
            ),
          ),
          _Row(
            label: context.tr('Fold again after'),
            enabled:
                s.showTray &&
                (s.collapseItems || s.trayHidden.isNotEmpty) &&
                s.trayFold != BarTrayFold.controlCenter,
            note: !s.showTray
                ? context.tr('System tray is turned off.')
                : !(s.collapseItems || s.trayHidden.isNotEmpty)
                ? context.tr(
                    'Turn on folding or set an item below to Hidden first.',
                  )
                : s.trayFold == BarTrayFold.controlCenter
                ? context.tr(
                    'Not used while icons sit inside Control Centre.',
                  )
                : null,
            trailing: _Segments<int>(
              value: const <int>[0, 5, 15, 30].contains(s.collapseAutoSeconds)
                  ? s.collapseAutoSeconds
                  : 15,
              options: <(int, String)>[
                for (final n in const <int>[5, 15, 30])
                  (n, context.tr('{} s', n)),
                (0, context.tr('Never')),
              ],
              onChanged: (v) => save((s) => s.copyWith(collapseAutoSeconds: v)),
            ),
          ),
        ],
      ),
      if (trayIds.isNotEmpty)
        _Group(
          title: context.tr('Tray items'),
          note: context.tr(
            'Hidden items wait behind the arrow; items set to Never are not drawn at all. The list shows what is in the tray right now.',
          ),
          children: <Widget>[
            for (final id in trayIds)
              _Row(
                label: trayNames.of(id).title,
                enabled: s.showTray,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    IgnorePointer(
                      child: services!.buildSystemTray(
                        context,
                        horizontal: true,
                        itemIds: <String>[id],
                      ),
                    ),
                    const SizedBox(width: 10),
                    _Segments<int>(
                      value: listed(s.trayNever, id)
                          ? 2
                          : (listed(s.trayHidden, id) ? 1 : 0),
                      options: <(int, String)>[
                        (0, context.tr('Shown')),
                        (1, context.tr('Hidden')),
                        (2, context.tr('Never')),
                      ],
                      onChanged: (v) => place(id, v),
                    ),
                  ],
                ),
              ),
          ],
        ),
      _Group(
        title: context.tr('Battery'),
        children: <Widget>[
          _Switch(
            label: context.tr('Show percentage'),
            value: s.showBatteryPercent,
            enabled: s.showBattery,
            onChanged: (v) => save((s) => s.copyWith(showBatteryPercent: v)),
          ),
        ],
      ),
    ];
  }

  List<Widget> _clock(
    BuildContext context,
    BarSettings s,
    _Save save,
  ) => <Widget>[
    _Group(
      title: context.tr('Clock'),
      children: <Widget>[
        _Switch(
          label: context.tr('Show the date'),
          value: s.showClockDate,
          onChanged: (v) => save((s) => s.copyWith(showClockDate: v)),
        ),
        _Switch(
          label: context.tr('Show the day of the week'),
          value: s.clockWeekday,
          enabled: s.showClockDate,
          onChanged: (v) => save((s) => s.copyWith(clockWeekday: v)),
        ),
      ],
    ),
    _Group(
      title: context.tr('Notification Center'),
      note: context.tr(
        'Widgets are arranged from the Edit Widgets button at the bottom of the column; Control Centre has its own Edit Controls button.',
      ),
      children: <Widget>[
        _Switch(
          label: context.tr('Open notifications and widgets from the clock'),
          value: s.mergedNotificationCenter,
          onChanged: (v) =>
              save((s) => s.copyWith(mergedNotificationCenter: v)),
        ),
      ],
    ),
  ];
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.label,
    required this.icon,
    required this.colour,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color colour;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
      child: Pressable(
        onTap: onTap,
        scale: 0.98,
        child: const SizedBox.shrink(),
        builder: (context, hovered, _) => AnimatedContainer(
          duration: KitMotion.duration(context, KitMotion.fade),
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: selected
                ? KitStyle.of(context).accent(context.shellTheme)
                : theme.colors.textPrimary.withValues(
                    alpha: hovered ? 0.07 : 0,
                  ),
            borderRadius: BorderRadius.circular(KitStyle.of(context).corner(8)),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: colour,
                  borderRadius: BorderRadius.circular(
                    KitStyle.of(context).corner(6),
                  ),
                  border: Border.all(
                    color: const Color(0x33ffffff),
                    width: 0.5,
                  ),
                ),
                child: BarGlyph(icon, size: 13, color: const Color(0xffffffff)),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: BarType.menuRow.copyWith(
                    color: selected
                        ? const Color(0xffffffff)
                        : theme.colors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A length of time in milliseconds, set with a slider.
Widget _timing(
  BuildContext context, {
  required String label,
  required int value,
  required int min,
  required int max,
  required int step,
  required bool enabled,
  required ValueChanged<int> onChanged,
}) => _Cell(
  label: label,
  detail: context.tr('{} ms', value),
  enabled: enabled,
  child: MacSlider(
    inList: true,
    value: ((value - min) / (max - min)).clamp(0.0, 1.0),
    onChanged: (v) {
      final next = (((min + v * (max - min)) / step).round() * step).clamp(
        min,
        max,
      );
      if (next != value) onChanged(next);
    },
  ),
);

class _Group extends StatelessWidget {
  const _Group({
    required this.children,
    this.title,
    this.note,
    this.onReset,
    this.resetLabel,
  });

  final String? title;
  final String? note;
  final VoidCallback? onReset;
  final String? resetLabel;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (title != null || onReset != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 7),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: title != null
                        ? Text(
                            title!,
                            style: BarType.section.copyWith(
                              color: theme.colors.textSecondary,
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                  if (onReset != null && resetLabel != null)
                    Pressable(
                      onTap: onReset,
                      scale: 0.96,
                      child: Text(
                        resetLabel!,
                        style: BarType.caption.copyWith(
                          color: KitStyle.of(context).accent(theme),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          Container(
            decoration: BoxDecoration(
              color: theme.colors.textPrimary.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(
                KitStyle.of(context).corner(11),
              ),
              border: Border.all(
                color: theme.colors.textPrimary.withValues(alpha: 0.07),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (var i = 0; i < children.length; i++) ...<Widget>[
                  if (i > 0)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: SizedBox(
                        height: 1,
                        child: ColoredBox(
                          color: theme.colors.textPrimary.withValues(
                            alpha: 0.07,
                          ),
                        ),
                      ),
                    ),
                  children[i],
                ],
              ],
            ),
          ),
          if (note != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 7, 4, 0),
              child: Text(
                note!,
                style: BarType.caption.copyWith(
                  height: 1.35,
                  color: theme.colors.textTertiary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One look as a small sample of itself: a panel in the look's own fill,
/// corners, line and type, with a control in its accent.
class _LookCard extends StatelessWidget {
  const _LookCard({
    required this.look,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final KitStyle look;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  static const double width = 104;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final style = KitStyle.of(context);
    final own = look.themed(theme);
    final ink = own.colors.textPrimary;
    final accent = look.accent(own);
    final corner = look.corner(9).clamp(0.0, 14.0);
    return Pressable(
      onTap: onTap,
      scale: 0.97,
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            AnimatedContainer(
              duration: KitMotion.duration(context, KitMotion.fade),
              height: 52,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(style.corner(11)),
                border: Border.all(
                  width: 2,
                  color: selected
                      ? style.accent(theme)
                      : theme.colors.textPrimary.withValues(alpha: 0),
                ),
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: own.colors.panelBackground.withValues(
                    alpha: look.opaque ? 1 : 0.72,
                  ),
                  borderRadius: BorderRadius.circular(corner),
                  border: Border.all(
                    width: look.borderWidth.clamp(0.5, 2.0),
                    color: look.border(own),
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    Text(
                      'Aa',
                      style: TextStyle(
                        fontFamily: look.fontFamily,
                        package: look.fontPackage,
                        fontSize: 15,
                        fontWeight: look.weight(FontWeight.w600),
                        color: ink,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      width: 24,
                      height: 12,
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: BorderRadius.circular(look.pill(12)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: BarType.caption.copyWith(
                fontSize: 11.5,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: theme.colors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.trailing,
    this.enabled = true,
    this.note,
  });

  final String label;
  final Widget trailing;
  final bool enabled;

  /// Why the row cannot be changed, said under its label.
  final String? note;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    return IgnorePointer(
      ignoring: !enabled,
      child: AnimatedOpacity(
        duration: KitMotion.duration(context, KitMotion.fill),
        opacity: enabled ? 1 : 0.4,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 42),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: LayoutBuilder(
              builder: (context, constraints) => Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          label,
                          style: BarType.menuRow.copyWith(
                            color: theme.colors.textPrimary,
                          ),
                        ),
                        if (note != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              note!,
                              style: BarType.caption.copyWith(
                                height: 1.3,
                                color: theme.colors.textSecondary,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // A wider face makes a wider control: it shrinks before it
                  // runs out of the row.
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: math.max(0, constraints.maxWidth - 12 - 96),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: trailing,
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

class _Switch extends StatelessWidget {
  const _Switch({
    required this.label,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.note,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;
  final String? note;

  @override
  Widget build(BuildContext context) {
    return _Row(
      label: label,
      enabled: enabled,
      note: note,
      trailing: Transform.scale(
        scale: 0.86,
        alignment: Alignment.centerRight,
        child: MacSwitch(value: value, onChanged: onChanged),
      ),
    );
  }
}

class _Segments<T> extends StatelessWidget {
  const _Segments({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final ink = theme.colors.textPrimary;
    return Container(
      height: 28,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: ink.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(KitStyle.of(context).corner(8)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final (option, label) in options)
            Pressable(
              onTap: option == value ? null : () => onChanged(option),
              scale: 0.95,
              child: AnimatedContainer(
                duration: KitMotion.duration(context, KitMotion.turn),
                curve: KitMotion.outCubic,
                height: 24,
                constraints: const BoxConstraints(minWidth: 46),
                padding: const EdgeInsets.symmetric(horizontal: 11),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: option == value
                      ? ink.withValues(alpha: 0.20)
                      : ink.withValues(alpha: 0),
                  borderRadius: BorderRadius.circular(
                    KitStyle.of(context).corner(6),
                  ),
                ),
                child: Text(
                  label,
                  style: BarType.caption.copyWith(
                    fontSize: 12,
                    fontWeight: option == value
                        ? FontWeight.w600
                        : FontWeight.w400,
                    color: ink,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final ink = theme.colors.textPrimary;
    Widget button(IconData icon, int next) {
      final enabled = next >= min && next <= max;
      return Pressable(
        onTap: enabled ? () => onChanged(next) : null,
        scale: 0.85,
        child: SizedBox(
          width: 30,
          height: 24,
          child: BarGlyph(
            icon,
            size: 11,
            color: ink.withValues(alpha: enabled ? 1 : 0.3),
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          '$value',
          style: BarType.menuRow.copyWith(
            color: ink,
            fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(width: 10),
        Container(
          height: 28,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: ink.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(KitStyle.of(context).corner(8)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              button(BarIcons.minus, value - 1),
              SizedBox(
                width: 1,
                height: 14,
                child: ColoredBox(color: ink.withValues(alpha: 0.15)),
              ),
              button(BarIcons.plus, value + 1),
            ],
          ),
        ),
      ],
    );
  }
}

class _TextButton extends StatelessWidget {
  const _TextButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    return Pressable(
      onTap: onTap,
      scale: 0.96,
      child: Container(
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: theme.colors.textPrimary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(KitStyle.of(context).corner(8)),
        ),
        // A wider face still fits the button.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            maxLines: 1,
            style: BarType.caption.copyWith(
              fontSize: 12,
              color: theme.colors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

typedef _OrderRow = ({
  IconData icon,
  String label,
  bool value,
  ValueChanged<bool> onChanged,
});

/// Rows that are reordered by dragging the handle at their end.
class _OrderList extends StatefulWidget {
  const _OrderList({
    required this.ids,
    required this.onReorder,
    required this.rowBuilder,
  });

  final List<String> ids;
  final ValueChanged<List<String>> onReorder;
  final _OrderRow Function(String id) rowBuilder;

  @override
  State<_OrderList> createState() => _OrderListState();
}

class _OrderListState extends State<_OrderList> {
  static const double _h = 42;
  List<String>? _order;
  String? _dragId;
  double _dragTop = 0;

  void _move(double dy) {
    final order = _order!;
    _dragTop = (_dragTop + dy).clamp(0.0, (order.length - 1) * _h);
    final from = order.indexOf(_dragId!);
    final to = ((_dragTop + _h / 2) / _h).floor().clamp(0, order.length - 1);
    if (to != from) {
      order
        ..removeAt(from)
        ..insert(to, _dragId!);
    }
    setState(() {});
  }

  void _end() {
    final order = _order;
    setState(() {
      _order = null;
      _dragId = null;
    });
    if (order != null) widget.onReorder(order);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final ink = theme.colors.textPrimary;
    final order = _order ?? widget.ids;

    Widget row(String id) {
      final data = widget.rowBuilder(id);
      final dragging = id == _dragId;
      return AnimatedPositioned(
        key: ValueKey<String>(id),
        duration: dragging
            ? Duration.zero
            : KitMotion.duration(context, KitMotion.enterLarge),
        curve: KitMotion.outCubic,
        left: 0,
        right: 0,
        top: dragging ? _dragTop : order.indexOf(id) * _h,
        height: _h,
        child: AnimatedContainer(
          duration: KitMotion.duration(context, KitMotion.ease),
          decoration: BoxDecoration(
            color: dragging
                ? Color.alphaBlend(
                    ink.withValues(alpha: 0.12),
                    theme.colors.surfaceContainer,
                  )
                : ink.withValues(alpha: 0),
            borderRadius: BorderRadius.circular(KitStyle.of(context).corner(9)),
            boxShadow: dragging
                ? KitStyle.of(context).cast(const <BoxShadow>[
                    BoxShadow(color: Color(0x44000000), blurRadius: 12),
                  ])
                : null,
          ),
          padding: const EdgeInsets.only(left: 12, right: 4),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 20,
                child: BarGlyph(data.icon, size: 14, color: ink),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  data.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: BarType.menuRow.copyWith(color: ink),
                ),
              ),
              Transform.scale(
                scale: 0.86,
                alignment: Alignment.centerRight,
                child: MacSwitch(value: data.value, onChanged: data.onChanged),
              ),
              MouseRegion(
                cursor: SystemMouseCursors.grab,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragStart: (_) => setState(() {
                    _order = List<String>.of(widget.ids);
                    _dragId = id;
                    _dragTop = widget.ids.indexOf(id) * _h;
                  }),
                  onVerticalDragUpdate: (d) => _move(d.delta.dy),
                  onVerticalDragEnd: (_) => _end(),
                  onVerticalDragCancel: _end,
                  child: SizedBox(
                    width: 36,
                    height: _h,
                    child: BarGlyph(
                      BarIcons.lineHorizontal3,
                      size: 14,
                      color: theme.colors.textTertiary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SizedBox(
      height: order.length * _h,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          for (final id in order)
            if (id != _dragId) row(id),
          if (_dragId != null) row(_dragId!),
        ],
      ),
    );
  }
}
