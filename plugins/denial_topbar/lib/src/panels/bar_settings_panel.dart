import 'package:denial_flutter_sdk/effects.dart';
import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bar_preferences.dart';
import '../bar_settings.dart';
import '../bar_tokens.dart';
import '../bar_type.dart';

const double _rowHeight = 44;
const double _cardRadius = 12;
const double _sheetRadius = 18;
const Duration _quick = Duration(milliseconds: 140);

Duration _motion(BuildContext context, Duration duration) =>
    MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;

/// Denial gives plugins no settings page, so the sheet is a managed shell
/// popup, the same shape the dock's settings sheet takes.
class BarSettingsPanel extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
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
      width: width,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
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
                  _Header(onClose: onClose),
                  SizedBox(
                    height: 1,
                    child: ColoredBox(color: theme.colors.hairline),
                  ),
                  Flexible(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
                      children: <Widget>[
                        _Section(
                          title: 'Layout',
                          children: <Widget>[
                            _ChoiceRow<BarLayout>(
                              label: 'Bar',
                              value: settings.layout,
                              choices: const <BarLayout>[
                                BarLayout.attached,
                                BarLayout.floating,
                              ],
                              labelOf: (value) => switch (value) {
                                BarLayout.attached => 'Attached',
                                BarLayout.floating => 'Floating',
                              },
                              onChanged: (value) =>
                                  save((s) => s.copyWith(layout: value)),
                            ),
                            _ChoiceRow<BarGround>(
                              label: 'Ground',
                              value: settings.ground,
                              choices: const <BarGround>[
                                BarGround.none,
                                BarGround.plate,
                                BarGround.glass,
                              ],
                              labelOf: (value) => switch (value) {
                                BarGround.none => 'None',
                                BarGround.plate => 'Plate',
                                BarGround.glass => 'Glass',
                              },
                              onChanged: (value) =>
                                  save((s) => s.copyWith(ground: value)),
                            ),
                            _SliderRow(
                              label: 'Ground opacity',
                              value: settings.groundOpacity,
                              min: BarTokens.plateOpacityMin,
                              max: BarTokens.plateOpacityMax,
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
                        const SizedBox(height: 10),
                        _Section(
                          title: 'Island',
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
                        const SizedBox(height: 10),
                        _Section(
                          title: 'Workspaces',
                          children: <Widget>[
                            _ChoiceRow<BarWorkspacePlacement>(
                              label: 'Switcher',
                              value: settings.workspacePlacement,
                              choices: const <BarWorkspacePlacement>[
                                BarWorkspacePlacement.island,
                                BarWorkspacePlacement.leading,
                                BarWorkspacePlacement.trailing,
                                BarWorkspacePlacement.hidden,
                              ],
                              labelOf: (value) => switch (value) {
                                BarWorkspacePlacement.island => 'Island',
                                BarWorkspacePlacement.leading => 'Left',
                                BarWorkspacePlacement.trailing => 'Right',
                                BarWorkspacePlacement.hidden => 'Hidden',
                              },
                              onChanged: (value) => save(
                                (s) => s.copyWith(workspacePlacement: value),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _Section(
                          title: 'Cells',
                          children: <Widget>[
                            _ToggleRow(
                              label: 'Window title',
                              value: settings.showWindowTitle,
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

class _Header extends StatelessWidget {
  const _Header({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    return SizedBox(
      height: 48,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 8, 0),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                'Menu Bar',
                style: BarType.title.copyWith(
                  fontSize: 14,
                  color: theme.colors.textPrimary,
                ),
              ),
            ),
            _IconButton(onTap: onClose),
          ],
        ),
      ),
    );
  }
}

class _IconButton extends StatefulWidget {
  const _IconButton({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_IconButton> createState() => _IconButtonState();
}

class _IconButtonState extends State<_IconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.shellTheme.colors;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: _hovered
                ? colors.textPrimary.withValues(alpha: 0.08)
                : const Color(0x00000000),
            shape: BoxShape.circle,
          ),
          child: CustomPaint(painter: _CrossPainter(colors.textSecondary)),
        ),
      ),
    );
  }
}

class _CrossPainter extends CustomPainter {
  const _CrossPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    final centre = size.center(Offset.zero);
    const arm = 4.5;
    canvas.drawLine(
      centre - const Offset(arm, arm),
      centre + const Offset(arm, arm),
      paint,
    );
    canvas.drawLine(
      centre + const Offset(arm, -arm),
      centre - const Offset(arm, -arm),
      paint,
    );
  }

  @override
  bool shouldRepaint(_CrossPainter oldDelegate) => oldDelegate.color != color;
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
          child: Text(
            title.toUpperCase(),
            style: BarType.cellLabel.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: theme.colors.textTertiary,
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colors.surfaceContainer.withValues(alpha: 0.55),
            borderRadius: theme.borderRadius(_cardRadius),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}

class _RowSurface extends StatefulWidget {
  const _RowSurface({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  State<_RowSurface> createState() => _RowSurfaceState();
}

class _RowSurfaceState extends State<_RowSurface> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.shellTheme.colors;
    return MouseRegion(
      cursor: widget.onTap == null
          ? MouseCursor.defer
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: _motion(context, Motion.tile),
          height: _rowHeight,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: _hovered
                ? colors.textPrimary.withValues(alpha: 0.055)
                : const Color(0x00000000),
            borderRadius: BorderRadius.circular(_cardRadius),
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
          child: _RowSurface(
            onTap: toggle,
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: BarType.item.copyWith(
                      color: theme.colors.textPrimary,
                    ),
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

/// The same switch the dock's settings sheet draws: 44 × 26, 3 inset, a 20
/// thumb, accent track, 260 ms spring.
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
      springTo(_slide, target, spring: Motion.snappy);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = theme.colors;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedBuilder(
        animation: _slide,
        builder: (context, _) {
          final t = _slide.value.clamp(0.0, 1.0);
          final track = Color.lerp(
            colors.textPrimary.withValues(alpha: 0.16),
            theme.accent,
            t,
          )!;
          final thumbLeft = _inset + (_width - _inset * 2 - _thumb) * t;
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
                      border: Border.all(
                        color: Color.lerp(
                          colors.hairlineSoft,
                          theme.accent,
                          t,
                        )!,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: thumbLeft,
                  top: _inset,
                  width: _thumb,
                  height: _thumb,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colors.sliderThumb,
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
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ChoiceRow<T> extends StatelessWidget {
  const _ChoiceRow({
    required this.label,
    required this.value,
    required this.choices,
    required this.labelOf,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<T> choices;
  final String Function(T value) labelOf;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    return SizedBox(
      height: _rowHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: BarType.item.copyWith(color: theme.colors.textPrimary),
              ),
            ),
            const SizedBox(width: 10),
            DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colors.textPrimary.withValues(alpha: 0.07),
                borderRadius: theme.borderRadius(8),
              ),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    for (final choice in choices)
                      _ChoiceChip(
                        label: labelOf(choice),
                        selected: choice == value,
                        onTap: () => onChanged(choice),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChoiceChip extends StatefulWidget {
  const _ChoiceChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_ChoiceChip> createState() => _ChoiceChipState();
}

class _ChoiceChipState extends State<_ChoiceChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: _motion(context, _quick),
          curve: Motion.standard,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: widget.selected
                ? theme.accent.withValues(alpha: 0.9)
                : _hovered
                ? theme.colors.textPrimary.withValues(alpha: 0.07)
                : const Color(0x00000000),
            borderRadius: theme.borderRadius(6),
          ),
          child: Text(
            widget.label,
            style: BarType.cellLabel.copyWith(
              fontWeight: widget.selected ? FontWeight.w600 : FontWeight.w500,
              color: widget.selected
                  ? const Color(0xffffffff)
                  : theme.colors.textSecondary,
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
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    return SizedBox(
      height: _rowHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: BarType.item.copyWith(color: theme.colors.textPrimary),
              ),
            ),
            SizedBox(
              width: 130,
              child: SliderTheme(
                data: SliderThemeData(
                  trackHeight: 4,
                  activeTrackColor: theme.colors.textPrimary,
                  inactiveTrackColor: theme.colors.textPrimary.withValues(
                    alpha: 0.16,
                  ),
                  thumbColor: theme.colors.sliderThumb,
                  overlayShape: SliderComponentShape.noOverlay,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 7,
                  ),
                ),
                child: Slider(
                  value: value.clamp(min, max),
                  min: min,
                  max: max,
                  onChanged: onChanged,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
