import 'dart:math' as math;

import 'package:denial_flutter_sdk/effects.dart';
import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bar_icons.dart';
import '../bar_preferences.dart';
import '../bar_settings.dart';
import '../bar_tokens.dart';
import '../bar_type.dart';

/// The dock's settings sheet geometry, copied so the two panels read as one
/// product: 48-high rows inside 12-radius cards, an 18-radius sheet, and a
/// 140 ms quick transition.
const double _rowHeight = 48;
const double _cardRadius = 12;
const double _sheetRadius = 18;
const Duration _quick = Duration(milliseconds: 140);

Duration _motion(BuildContext context, Duration duration) =>
    MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;

TextStyle _labelStyle(ShellThemeData theme) => BarType.value.copyWith(
  color: theme.colors.textPrimary,
  fontWeight: FontWeight.w500,
);

TextStyle _captionStyle(ShellThemeData theme, [Color? color]) =>
  BarType.caption.copyWith(
    color: color ?? theme.colors.textTertiary,
    height: 1.45,
    letterSpacing: 0.1,
  );

TextStyle _sectionStyle(ShellThemeData theme) => BarType.caption.copyWith(
  color: theme.colors.textTertiary,
  fontWeight: FontWeight.w700,
  letterSpacing: 0.8,
  height: 1.2,
);

/// The bar's settings.
///
/// Denial gives plugins no settings page, so this is a managed shell popup, the
/// same shape the dock's sheet takes: a header with a badge, a title and a
/// close button, a hairline, then a scrolling column of grouped cards. Each
/// card is an uppercase section label over a rounded, hairline-separated list,
/// with an optional footer explaining the choice.
class BarSettingsPanel extends ConsumerStatefulWidget {
  const BarSettingsPanel({
    required this.onClose,
    required this.width,
    required this.maxHeight,
    super.key,
  });

  final VoidCallback onClose;
  final double width;
  final double maxHeight;

  @override
  ConsumerState<BarSettingsPanel> createState() => _BarSettingsPanelState();
}

class _BarSettingsPanelState extends ConsumerState<BarSettingsPanel> {
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final stored = ref.watch(barSettingsProvider).value;
    final settings = stored ?? BarSettings.defaults;
    final controller = ref.read(barSettingsProvider.notifier);
    final radius = theme.borderRadius(_sheetRadius);
    final enabled = stored != null;

    void save(BarSettings Function(BarSettings current) change) {
      if (enabled) controller.save(change);
    }

    return SizedBox(
      width: widget.width,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: widget.maxHeight),
        child: ShellBackdropBlur(
          blur: theme.effectivePanelOpacity < 1,
          separateChild: true,
          borderRadius: radius,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: theme.panelColor(theme.colors.surfaceContainer),
              borderRadius: radius,
              border: Border.all(color: theme.colors.hairline),
            ),
            child: ClipRRect(
              borderRadius: radius,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _Header(onClose: widget.onClose),
                  SizedBox(
                    height: 1,
                    child: ColoredBox(color: theme.colors.hairline),
                  ),
                  Flexible(
                    child: ListView(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                      children: <Widget>[
                        _SettingsSection(
                          title: 'Layout',
                          footer:
                              'Attached spans the screen edge to edge; '
                              'floating is the inset capsule.',
                          children: <Widget>[
                            _SegmentedRow<BarLayout>(
                              value: settings.layout,
                              options: const <(BarLayout, String, IconData)>[
                                (
                                  BarLayout.attached,
                                  'Attached',
                                  Icons.horizontal_rule,
                                ),
                                (
                                  BarLayout.floating,
                                  'Floating',
                                  Icons.crop_16_9,
                                ),
                              ],
                              onChanged: (value) =>
                                  save((s) => s.copyWith(layout: value)),
                            ),
                            _SegmentedRow<BarGround>(
                              label: 'Ground',
                              value: settings.ground,
                              options: const <(BarGround, String, IconData)>[
                                (BarGround.none, 'None', Icons.block),
                                (
                                  BarGround.plate,
                                  'Plate',
                                  Icons.rectangle_outlined,
                                ),
                                (
                                  BarGround.glass,
                                  'Glass',
                                  Icons.blur_on,
                                ),
                              ],
                              onChanged: (value) =>
                                  save((s) => s.copyWith(ground: value)),
                            ),
                            _SliderRow(
                              label: 'Ground opacity',
                              value: settings.groundOpacity,
                              min: BarTokens.plateOpacityMin,
                              max: BarTokens.plateOpacityMax,
                              enabled: settings.ground != BarGround.none,
                              onChanged: (value) =>
                                  save((s) => s.copyWith(groundOpacity: value)),
                            ),
                            _ToggleRow(
                              label: 'Hairline',
                              value: settings.hairline,
                              onChanged: (value) =>
                                  save((s) => s.copyWith(hairline: value)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 22),
                        _SettingsSection(
                          title: 'Island',
                          footer: settings.islandEnabled
                              ? 'The capsule sits in the middle of the bar and '
                                    'expands for a notice or a track change.'
                              : null,
                          children: <Widget>[
                            _ToggleRow(
                              label: 'Show island',
                              value: settings.islandEnabled,
                              onChanged: (value) =>
                                  save((s) => s.copyWith(islandEnabled: value)),
                            ),
                            _ToggleRow(
                              label: 'Clock in island',
                              value: settings.islandShowsClock,
                              enabled: settings.islandEnabled,
                              onChanged: (value) => save(
                                (s) => s.copyWith(islandShowsClock: value),
                              ),
                            ),
                            _ToggleRow(
                              label: 'Hover to peek',
                              value: settings.islandHoverPeek,
                              enabled: settings.islandEnabled,
                              onChanged: (value) => save(
                                (s) => s.copyWith(islandHoverPeek: value),
                              ),
                            ),
                            _ToggleRow(
                              label: 'Media activity',
                              value: settings.activityMedia,
                              enabled: settings.islandEnabled,
                              onChanged: (value) =>
                                  save((s) => s.copyWith(activityMedia: value)),
                            ),
                            _ToggleRow(
                              label: 'Charging activity',
                              value: settings.activityCharging,
                              enabled: settings.islandEnabled,
                              onChanged: (value) => save(
                                (s) => s.copyWith(activityCharging: value),
                              ),
                            ),
                            _ToggleRow(
                              label: 'Notification activity',
                              value: settings.activityNotifications,
                              enabled: settings.islandEnabled,
                              onChanged: (value) => save(
                                (s) => s.copyWith(activityNotifications: value),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 22),
                        _SettingsSection(
                          title: 'Workspaces',
                          footer:
                              'macOS has no workspace switcher, so this is an '
                              'addition; the island keeps the bar\'s edges '
                              'clear.',
                          children: <Widget>[
                            _SegmentedRow<BarWorkspacePlacement>(
                              value: settings.workspacePlacement,
                              options: const <
                                (BarWorkspacePlacement, String, IconData)
                              >[
                                (
                                  BarWorkspacePlacement.island,
                                  'Island',
                                  Icons.radio_button_checked,
                                ),
                                (
                                  BarWorkspacePlacement.leading,
                                  'Left',
                                  Icons.align_horizontal_left,
                                ),
                                (
                                  BarWorkspacePlacement.trailing,
                                  'Right',
                                  Icons.align_horizontal_right,
                                ),
                                (
                                  BarWorkspacePlacement.hidden,
                                  'Hidden',
                                  Icons.block,
                                ),
                              ],
                              onChanged: (value) => save(
                                (s) => s.copyWith(workspacePlacement: value),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 22),
                        _SettingsSection(
                          title: 'Menu bar items',
                          children: <Widget>[
                            _ToggleRow(
                              label: 'Application menus',
                              value: settings.showAppMenu,
                              onChanged: (value) =>
                                  save((s) => s.copyWith(showAppMenu: value)),
                            ),
                            _ToggleRow(
                              label: 'Window title',
                              value: settings.showWindowTitle,
                              enabled: settings.showAppMenu,
                              onChanged: (value) => save(
                                (s) => s.copyWith(showWindowTitle: value),
                              ),
                            ),
                            _ToggleRow(
                              label: 'Date beside the clock',
                              value: settings.showClockDate,
                              onChanged: (value) =>
                                  save((s) => s.copyWith(showClockDate: value)),
                            ),
                            _ToggleRow(
                              label: 'System tray',
                              value: settings.showTray,
                              onChanged: (value) =>
                                  save((s) => s.copyWith(showTray: value)),
                            ),
                            _ToggleRow(
                              label: 'Wi-Fi',
                              value: settings.showWifi,
                              onChanged: (value) =>
                                  save((s) => s.copyWith(showWifi: value)),
                            ),
                            _ToggleRow(
                              label: 'Sound',
                              value: settings.showVolume,
                              onChanged: (value) =>
                                  save((s) => s.copyWith(showVolume: value)),
                            ),
                            _ToggleRow(
                              label: 'Battery',
                              value: settings.showBattery,
                              onChanged: (value) =>
                                  save((s) => s.copyWith(showBattery: value)),
                            ),
                            _ToggleRow(
                              label: 'Battery percentage',
                              value: settings.showBatteryPercent,
                              enabled: settings.showBattery,
                              onChanged: (value) => save(
                                (s) => s.copyWith(showBatteryPercent: value),
                              ),
                            ),
                            _ToggleRow(
                              label: 'Notifications',
                              value: settings.showNotifications,
                              onChanged: (value) => save(
                                (s) => s.copyWith(showNotifications: value),
                              ),
                            ),
                            _ToggleRow(
                              label: 'Control Centre',
                              value: settings.showControlCenter,
                              onChanged: (value) => save(
                                (s) => s.copyWith(showControlCenter: value),
                              ),
                            ),
                            _ToggleRow(
                              label: 'Settings button',
                              value: settings.showSettingsButton,
                              onChanged: (value) => save(
                                (s) => s.copyWith(showSettingsButton: value),
                              ),
                            ),
                          ],
                        ),
                      ],
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

/// The sheet header: a small bar badge, the title, and a close button, on the
/// dock sheet's 56 pt header.
class _Header extends StatelessWidget {
  const _Header({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = theme.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 10, 0),
      child: SizedBox(
        height: 56,
        child: Row(
          children: <Widget>[
            DecoratedBox(
              decoration: BoxDecoration(
                color: theme.accent.withValues(alpha: 0.18),
                borderRadius: theme.borderRadius(8),
                border: Border.all(
                  color: theme.accent.withValues(alpha: 0.26),
                ),
              ),
              child: SizedBox(
                width: 30,
                height: 30,
                child: Center(
                  child: BarGlyph(
                    BarIcons.sliderHorizontal3,
                    size: 17,
                    color: theme.accent,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Menu Bar',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: BarType.title.copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.1,
                  color: colors.textPrimary,
                ),
              ),
            ),
            _IconButton(
              icon: Icons.close_rounded,
              tooltip: 'Close',
              onPressed: onClose,
            ),
          ],
        ),
      ),
    );
  }
}

class _IconButton extends StatefulWidget {
  const _IconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  State<_IconButton> createState() => _IconButtonState();
}

class _IconButtonState extends State<_IconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: _motion(context, _quick),
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: theme.colors.textPrimary.withValues(
                alpha: _hovered ? 0.10 : 0,
              ),
              borderRadius: theme.borderRadius(7),
            ),
            child: Icon(
              widget.icon,
              size: 16,
              color: theme.colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// One group: an uppercase label, a hairline-separated card, and an optional
/// footer note. Copied from the dock sheet's `_SettingsSection`.
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
      children: <Widget>[
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
              colors: <Color>[
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
              children: <Widget>[
                for (var index = 0; index < children.length; index++) ...<Widget>[
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

/// A row with a hover wash, which every interactive row in the sheet uses.
class _HoverSurface extends StatefulWidget {
  const _HoverSurface({
    required this.height,
    required this.onTap,
    required this.child,
    this.enabled = true,
  });

  final double height;
  final VoidCallback? onTap;
  final Widget child;
  final bool enabled;

  @override
  State<_HoverSurface> createState() => _HoverSurfaceState();
}

class _HoverSurfaceState extends State<_HoverSurface> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    return MouseRegion(
      cursor: widget.enabled && widget.onTap != null
          ? SystemMouseCursors.click
          : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: _motion(context, _quick),
          height: widget.height,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: _hovered && widget.enabled
                ? theme.colors.textPrimary.withValues(alpha: 0.045)
                : const Color(0x00000000),
          ),
          child: widget.child,
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
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  /// A row whose setting only matters under another choice stays visible but
  /// inert, so the panel does not reflow as options change.
  final bool enabled;

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
            enabled: enabled,
            onTap: toggle,
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _labelStyle(theme),
                  ),
                ),
                const SizedBox(width: 12),
                _Switch(value: value),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The dock sheet's switch: a 44 × 26 track that lerps to the accent and a
/// thumb that springs across.
class _Switch extends StatefulWidget {
  const _Switch({required this.value});

  final bool value;

  @override
  State<_Switch> createState() => _SwitchState();
}

class _SwitchState extends State<_Switch> with SingleTickerProviderStateMixin {
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
      duration: const Duration(milliseconds: 260),
      value: widget.value ? 1 : 0,
    );
  }

  @override
  void dispose() {
    _slide.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _Switch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value == widget.value) return;
    final target = widget.value ? 1.0 : 0.0;
    if (MediaQuery.disableAnimationsOf(context)) {
      _slide.value = target;
    } else {
      _slide.animateTo(
        target,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
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
              theme.accent,
              t,
            )!;
            final border = Color.lerp(colors.hairlineSoft, theme.accent, t)!;
            final thumbLeft = _inset + (_width - _inset * 2 - _thumb) * t;
            final scale = _pressed ? 1.12 : (_hovered ? 1.05 : 1.0);
            return SizedBox(
              width: _width,
              height: _height,
              child: Stack(
                children: <Widget>[
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
                        boxShadow: <BoxShadow>[
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
                      curve: Curves.easeOut,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: colors.sliderThumb,
                          border: Border.all(
                            color: colors.textPrimary.withValues(alpha: 0.08),
                          ),
                          boxShadow: <BoxShadow>[
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

/// A label over the dock sheet's sliding segmented control.
class _SegmentedRow<T> extends StatelessWidget {
  const _SegmentedRow({
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
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (label != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(1, 0, 1, 9),
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
    with SingleTickerProviderStateMixin {
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
    _slide = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
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
    _slide.animateTo(
      _target,
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutBack,
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
    return LayoutBuilder(
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
              children: <Widget>[
                Positioned.fill(
                  child: AnimatedScale(
                    scale: _pressedIndex >= 0 ? 0.985 : 1,
                    duration: _motion(context, _quick),
                    curve: Curves.easeOut,
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
                            colors: <Color>[
                              Color.alphaBlend(
                                theme.accent.withValues(alpha: 0.24),
                                colors.surfaceContainerHigh,
                              ),
                              Color.alphaBlend(
                                theme.accent.withValues(alpha: 0.14),
                                colors.surfaceContainerHigh,
                              ),
                            ],
                          ),
                          borderRadius: theme.borderRadius(8),
                          border: Border.all(
                            color: theme.accent.withValues(alpha: 0.28),
                          ),
                          boxShadow: <BoxShadow>[
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
                    children: <Widget>[
                      for (var index = 0; index < count; index++)
                        Expanded(
                          child: _Segment(
                            label: widget.options[index].$2,
                            icon: widget.options[index].$3,
                            selected: index == _selectedIndex,
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
    );
  }
}

class _Segment extends StatefulWidget {
  const _Segment({
    required this.label,
    required this.icon,
    required this.selected,
    required this.showIcon,
    required this.onSelect,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final bool showIcon;
  final VoidCallback onSelect;

  @override
  State<_Segment> createState() => _SegmentState();
}

class _SegmentState extends State<_Segment> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final color = widget.selected
        ? theme.colors.textPrimary
        : theme.colors.textSecondary;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onSelect,
        child: AnimatedContainer(
          duration: _motion(context, _quick),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: !widget.selected && _hovered
                ? theme.colors.textPrimary.withValues(alpha: 0.06)
                : const Color(0x00000000),
            borderRadius: theme.borderRadius(8),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              if (widget.showIcon) ...<Widget>[
                Icon(widget.icon, size: 14, color: color),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: BarType.value.copyWith(
                    color: color,
                    fontWeight: widget.selected
                        ? FontWeight.w600
                        : FontWeight.w400,
                    fontSize: 12,
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

/// A labelled slider row. The dock sheet's `_SliderRow` is the same shape.
class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.enabled = true,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final t = max > min ? ((value - min) / (max - min)).clamp(0.0, 1.0) : 0.0;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _labelStyle(theme),
                  ),
                ),
                Text(
                  '${(t * 100).round()}%',
                  style: BarType.caption.copyWith(
                    color: theme.colors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _Slider(
              value: t,
              enabled: enabled,
              onChanged: (next) => onChanged(min + next * (max - min)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Slider extends StatefulWidget {
  const _Slider({
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final double value;
  final ValueChanged<double> onChanged;
  final bool enabled;

  @override
  State<_Slider> createState() => _SliderState();
}

class _SliderState extends State<_Slider> {
  bool _hovered = false;
  bool _dragging = false;

  void _update(Offset position, double width) {
    if (!widget.enabled || width <= 0) return;
    widget.onChanged((position.dx / width).clamp(0.0, 1.0).toDouble());
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = theme.colors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final t = widget.value.clamp(0.0, 1.0);
        return MouseRegion(
          cursor: widget.enabled
              ? SystemMouseCursors.click
              : MouseCursor.defer,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) => _update(details.localPosition, width),
            onHorizontalDragStart: (details) {
              setState(() => _dragging = true);
              _update(details.localPosition, width);
            },
            onHorizontalDragUpdate: (details) =>
                _update(details.localPosition, width),
            onHorizontalDragEnd: (_) => setState(() => _dragging = false),
            onHorizontalDragCancel: () =>
                setState(() => _dragging = false),
            child: SizedBox(
              height: 20,
              child: Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: Container(
                        height: 4,
                        decoration: BoxDecoration(
                          color: colors.textPrimary.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    width: width * t,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: Container(
                        height: 4,
                        decoration: BoxDecoration(
                          color: theme.accent,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: (width * t - 9).clamp(-9.0, width - 9),
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: AnimatedScale(
                        scale: _dragging ? 1.15 : (_hovered ? 1.06 : 1.0),
                        duration: _motion(context, _quick),
                        child: Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: colors.sliderThumb,
                            border: Border.all(
                              color: colors.textPrimary.withValues(alpha: 0.08),
                            ),
                            boxShadow: <BoxShadow>[
                              BoxShadow(
                                color: colors.shadow,
                                blurRadius: 4,
                                offset: const Offset(0, 1.5),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
