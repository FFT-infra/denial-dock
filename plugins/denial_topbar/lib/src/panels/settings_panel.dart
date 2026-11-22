import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../top_bar_preferences.dart';

class TopBarSettingsPanel extends ConsumerWidget {
  const TopBarSettingsPanel({required this.onClose, super.key});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(topBarSettingsProvider).value;
    if (settings == null) {
      return const SizedBox(
        height: 120,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final theme = context.shellTheme;
    void save(TopBarSettings Function(TopBarSettings) change) {
      ref.read(topBarSettingsProvider.notifier).save(change);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                'Top bar',
                style: theme.text.systemBarValue.copyWith(
                  color: theme.colors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              _TextButton(label: 'Done', onTap: onClose),
            ],
          ),
          _Section(
            title: 'Appearance',
            children: <Widget>[
              _ChoiceRow<TopBarAppearance>(
                label: 'Layout',
                value: settings.appearance,
                options: const <TopBarAppearance>[
                  TopBarAppearance.attached,
                  TopBarAppearance.floating,
                  TopBarAppearance.segmented,
                ],
                labelOf: (value) => switch (value) {
                  TopBarAppearance.attached => 'Edge',
                  TopBarAppearance.floating => 'Capsule',
                  TopBarAppearance.segmented => 'Segments',
                },
                onChanged: (value) =>
                    save((current) => current.copyWith(appearance: value)),
              ),
              _SwitchRow(
                label: 'Show background',
                value: settings.showBackground,
                onChanged: (value) =>
                    save((current) => current.copyWith(showBackground: value)),
              ),
              _SwitchRow(
                label: 'Hairline border',
                value: settings.hairline,
                onChanged: (value) =>
                    save((current) => current.copyWith(hairline: value)),
              ),
            ],
          ),
          _Section(
            title: 'Island',
            children: <Widget>[
              _SwitchRow(
                label: 'Enable island',
                value: settings.islandEnabled,
                onChanged: (value) =>
                    save((current) => current.copyWith(islandEnabled: value)),
              ),
              _ChoiceRow<TopBarIslandStyle>(
                label: 'Style',
                value: settings.islandStyle,
                options: const <TopBarIslandStyle>[
                  TopBarIslandStyle.black,
                  TopBarIslandStyle.theme,
                ],
                labelOf: (value) =>
                    value == TopBarIslandStyle.black ? 'Black' : 'Theme',
                onChanged: (value) =>
                    save((current) => current.copyWith(islandStyle: value)),
              ),
              _SwitchRow(
                label: 'Peek on hover',
                value: settings.islandHoverPeek,
                onChanged: (value) =>
                    save((current) => current.copyWith(islandHoverPeek: value)),
              ),
              _SwitchRow(
                label: 'Media activity',
                value: settings.activityMedia,
                onChanged: (value) =>
                    save((current) => current.copyWith(activityMedia: value)),
              ),
              _SwitchRow(
                label: 'Charging activity',
                value: settings.activityCharging,
                onChanged: (value) => save(
                  (current) => current.copyWith(activityCharging: value),
                ),
              ),
              _SwitchRow(
                label: 'Notification activity',
                value: settings.activityNotifications,
                onChanged: (value) => save(
                  (current) => current.copyWith(activityNotifications: value),
                ),
              ),
              _SwitchRow(
                label: 'Workspace activity',
                value: settings.activityWorkspaces,
                onChanged: (value) => save(
                  (current) => current.copyWith(activityWorkspaces: value),
                ),
              ),
              _SliderRow(
                label: 'Auto collapse',
                value: settings.islandAutoCollapseSeconds.toDouble(),
                min: topBarMinAutoCollapse,
                max: topBarMaxAutoCollapse,
                divisions:
                    topBarMaxAutoCollapse.toInt() -
                    topBarMinAutoCollapse.toInt(),
                suffix: 's',
                onChanged: (value) => save(
                  (current) => current.copyWith(
                    islandAutoCollapseSeconds: value.round(),
                  ),
                ),
              ),
            ],
          ),
          _Section(
            title: 'Clock',
            children: <Widget>[
              _ChoiceRow<TopBarSlot>(
                label: 'Position',
                value: settings.clockPlacement,
                options: const <TopBarSlot>[
                  TopBarSlot.island,
                  TopBarSlot.leading,
                  TopBarSlot.trailing,
                  TopBarSlot.hidden,
                ],
                labelOf: _slotLabel,
                onChanged: (value) =>
                    save((current) => current.copyWith(clockPlacement: value)),
              ),
              _SwitchRow(
                label: 'Show date',
                value: settings.clockShowsDate,
                onChanged: (value) =>
                    save((current) => current.copyWith(clockShowsDate: value)),
              ),
            ],
          ),
          _Section(
            title: 'Media',
            children: <Widget>[
              _ChoiceRow<TopBarSlot>(
                label: 'Position',
                value: settings.mediaPlacement,
                options: const <TopBarSlot>[
                  TopBarSlot.island,
                  TopBarSlot.trailing,
                  TopBarSlot.hidden,
                ],
                labelOf: _slotLabel,
                onChanged: (value) =>
                    save((current) => current.copyWith(mediaPlacement: value)),
              ),
            ],
          ),
          _Section(
            title: 'Notifications',
            children: <Widget>[
              _ChoiceRow<TopBarSlot>(
                label: 'Position',
                value: settings.notificationPlacement,
                options: const <TopBarSlot>[
                  TopBarSlot.trailing,
                  TopBarSlot.hidden,
                ],
                labelOf: _slotLabel,
                onChanged: (value) => save(
                  (current) => current.copyWith(notificationPlacement: value),
                ),
              ),
              _SwitchRow(
                label: 'Unread badge',
                value: settings.notificationBadge,
                onChanged: (value) => save(
                  (current) => current.copyWith(notificationBadge: value),
                ),
              ),
            ],
          ),
          _Section(
            title: 'Bar',
            children: <Widget>[
              _SwitchRow(
                label: 'System tray',
                value: settings.showTray,
                onChanged: (value) =>
                    save((current) => current.copyWith(showTray: value)),
              ),
              _SwitchRow(
                label: 'Battery',
                value: settings.showBattery,
                onChanged: (value) =>
                    save((current) => current.copyWith(showBattery: value)),
              ),
              _SwitchRow(
                label: 'Battery percentage',
                value: settings.showBatteryPercent,
                onChanged: (value) => save(
                  (current) => current.copyWith(showBatteryPercent: value),
                ),
              ),
              _SwitchRow(
                label: 'Active window title',
                value: settings.showWindowTitle,
                onChanged: (value) =>
                    save((current) => current.copyWith(showWindowTitle: value)),
              ),
              _SwitchRow(
                label: 'Settings button',
                value: settings.showSettingsButton,
                onChanged: (value) => save(
                  (current) => current.copyWith(showSettingsButton: value),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _slotLabel(TopBarSlot slot) => switch (slot) {
  TopBarSlot.island => 'Island',
  TopBarSlot.leading => 'Leading',
  TopBarSlot.trailing => 'Trailing',
  TopBarSlot.hidden => 'Hidden',
};

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 6),
            child: Text(
              title.toUpperCase(),
              style: theme.text.systemBarCaption.copyWith(
                color: theme.colors.textTertiary,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colors.textPrimary.withValues(alpha: 0.035),
              borderRadius: theme.borderRadius(12),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              child: Column(children: children),
            ),
          ),
        ],
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    return SizedBox(
      height: 40,
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: theme.text.systemBarCaption.copyWith(
                color: theme.colors.textPrimary,
              ),
            ),
          ),
          _Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _Switch extends StatelessWidget {
  const _Switch({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => onChanged(!value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 36,
          height: 20,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: value
                ? theme.accent
                : theme.colors.textPrimary.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(10),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOutCubic,
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 16,
              height: 16,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChoiceRow<T> extends StatelessWidget {
  const _ChoiceRow({
    required this.label,
    required this.value,
    required this.options,
    required this.labelOf,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<T> options;
  final String Function(T value) labelOf;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: theme.text.systemBarCaption.copyWith(
              color: theme.colors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              for (final option in options)
                _Chip(
                  label: labelOf(option),
                  selected: option == value,
                  onTap: () => onChanged(option),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: selected
                ? theme.accent.withValues(alpha: 0.18)
                : theme.colors.textPrimary.withValues(alpha: 0.06),
            borderRadius: theme.borderRadius(8),
          ),
          child: Text(
            label,
            style: theme.text.systemBarCaption.copyWith(
              color: selected ? theme.accent : theme.colors.textSecondary,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _SliderRow extends StatefulWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.suffix,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String suffix;
  final ValueChanged<double> onChanged;

  @override
  State<_SliderRow> createState() => _SliderRowState();
}

class _SliderRowState extends State<_SliderRow> {
  late double _value = widget.value;

  @override
  void didUpdateWidget(covariant _SliderRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) _value = widget.value;
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: 6),
        Row(
          children: <Widget>[
            Text(
              widget.label,
              style: theme.text.systemBarCaption.copyWith(
                color: theme.colors.textPrimary,
              ),
            ),
            const Spacer(),
            Text(
              '${_value.round()}${widget.suffix}',
              style: theme.text.systemBarCaption.copyWith(
                color: theme.colors.textTertiary,
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
          ),
          child: Slider(
            value: _value.clamp(widget.min, widget.max).toDouble(),
            min: widget.min,
            max: widget.max,
            divisions: widget.divisions,
            onChanged: (value) => setState(() => _value = value),
            onChangeEnd: widget.onChanged,
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
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: theme.accent.withValues(alpha: 0.16),
            borderRadius: theme.borderRadius(8),
          ),
          child: Text(
            label,
            style: theme.text.systemBarCaption.copyWith(
              color: theme.accent,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
