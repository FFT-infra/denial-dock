import 'dart:math' as math;

import 'package:denial_flutter_sdk/theme.dart';
import 'package:denial_shell_kit/kit_motion.dart';
import 'package:denial_shell_kit/kit_style.dart';
import 'package:flutter/material.dart';

import '../bar_type.dart';
import 'mac_kit.dart';

/// The pieces a settings page is laid out with, for the pages that live in
/// files of their own: a titled group of rows, a row with a control at its
/// end, a cell with a control under its label, a segmented choice, a small
/// button and a one-line text field. They are drawn as the bar's own
/// settings pages draw theirs.
class SettingGroup extends StatelessWidget {
  const SettingGroup({required this.children, this.title, this.note, super.key});

  final String? title;
  final String? note;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final ink = theme.colors.textPrimary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 7),
              child: Text(
                title!,
                style: BarType.section.copyWith(
                  color: theme.colors.textSecondary,
                ),
              ),
            ),
          Container(
            decoration: BoxDecoration(
              color: ink.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(
                KitStyle.of(context).corner(11),
              ),
              border: Border.all(color: ink.withValues(alpha: 0.07)),
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
                        child: ColoredBox(color: ink.withValues(alpha: 0.07)),
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

class SettingRow extends StatelessWidget {
  const SettingRow({
    required this.label,
    required this.trailing,
    this.enabled = true,
    super.key,
  });

  final String label;
  final Widget trailing;
  final bool enabled;

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
                    child: Text(
                      label,
                      style: BarType.menuRow.copyWith(
                        color: theme.colors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
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

class SettingSwitch extends StatelessWidget {
  const SettingSwitch({
    required this.label,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    super.key,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) => SettingRow(
    label: label,
    enabled: enabled,
    trailing: Transform.scale(
      scale: 0.86,
      alignment: Alignment.centerRight,
      child: MacSwitch(value: value, onChanged: onChanged),
    ),
  );
}

/// A slider under its label, with the value written at the label's end.
///
/// When [commitOnRelease] is true, dragging updates only the displayed value
/// and invokes [onChanged] once the pointer releases, so controls that resize
/// the window itself (such as shell scale) do not shift under the pointer.
class SettingSlider extends StatefulWidget {
  const SettingSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.step = 1,
    this.text,
    this.enabled = true,
    this.commitOnRelease = false,
    this.onReset,
    this.resetLabel,
    super.key,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final double step;
  final ValueChanged<double> onChanged;
  final String Function(double value)? text;
  final bool enabled;
  final bool commitOnRelease;
  final VoidCallback? onReset;
  final String? resetLabel;

  static String number(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');

  @override
  State<SettingSlider> createState() => _SettingSliderState();
}

class _SettingSliderState extends State<SettingSlider> {
  double? _preview;

  @override
  void didUpdateWidget(covariant SettingSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.commitOnRelease || oldWidget.value != widget.value) {
      _preview = null;
    }
  }

  double _snap(double fraction) {
    final raw = widget.min + fraction * (widget.max - widget.min);
    final stepped = (raw / widget.step).round() * widget.step;
    return stepped.clamp(widget.min, widget.max).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final shown = _preview ?? widget.value;
    final span = widget.max - widget.min;
    final norm = span <= 0 ? 0.0 : ((shown - widget.min) / span).clamp(0.0, 1.0);
    return IgnorePointer(
      ignoring: !widget.enabled,
      child: AnimatedOpacity(
        duration: KitMotion.duration(context, KitMotion.fill),
        opacity: widget.enabled ? 1 : 0.4,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 9, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: BarType.menuRow.copyWith(
                        color: theme.colors.textPrimary,
                      ),
                    ),
                  ),
                  if (widget.onReset != null && widget.resetLabel != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: Pressable(
                        onTap: widget.onReset,
                        scale: 0.96,
                        child: Text(
                          widget.resetLabel!,
                          style: BarType.caption.copyWith(
                            color: KitStyle.of(context).accent(theme),
                          ),
                        ),
                      ),
                    ),
                  Text(
                    widget.text?.call(shown) ?? SettingSlider.number(shown),
                    style: BarType.caption.copyWith(
                      color: theme.colors.textTertiary,
                      fontFeatures: const <FontFeature>[
                        FontFeature.tabularFigures(),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              MacSlider(
                // The page scrolls, so the slider yields the wheel and
                // vertical drags to it.
                inList: true,
                value: norm,
                onChanged: (v) {
                  final next = _snap(v);
                  if (widget.commitOnRelease) {
                    if (next != _preview) setState(() => _preview = next);
                  } else if (next != widget.value) {
                    widget.onChanged(next);
                  }
                },
                onChangeEnd: widget.commitOnRelease
                    ? (v) {
                        final next = _snap(v);
                        setState(() => _preview = null);
                        if (next != widget.value) widget.onChanged(next);
                      }
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class Segments<T> extends StatelessWidget {
  const Segments({
    required this.value,
    required this.options,
    required this.onChanged,
    super.key,
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
                constraints: const BoxConstraints(minWidth: 40),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: ink.withValues(alpha: option == value ? 0.20 : 0),
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

/// A button the height of a segmented control. [primary] fills it with the
/// accent, [danger] writes it in red.
class SmallButton extends StatelessWidget {
  const SmallButton({
    required this.label,
    required this.onTap,
    this.primary = false,
    this.danger = false,
    super.key,
  });

  final String label;
  final VoidCallback? onTap;
  final bool primary;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final style = KitStyle.of(context);
    final enabled = onTap != null;
    final ink = danger ? const Color(0xffff453a) : theme.colors.textPrimary;
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Pressable(
        onTap: onTap,
        scale: 0.95,
        builder: (context, hovered, pressed) => Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: primary
                ? style.accent(theme)
                : theme.colors.textPrimary.withValues(
                    alpha: hovered && enabled ? 0.16 : 0.09,
                  ),
            borderRadius: BorderRadius.circular(style.corner(8)),
            border: primary ? null : style.controlLine(theme),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(
                label,
                maxLines: 1,
                style: BarType.caption.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: primary ? style.onAccent(theme) : ink,
                ),
              ),
            ],
          ),
        ),
        child: const SizedBox.shrink(),
      ),
    );
  }
}

/// One line of text to type into.
class NameField extends StatefulWidget {
  const NameField({
    required this.controller,
    required this.hint,
    required this.onSubmitted,
    this.autofocus = true,
    super.key,
  });

  final TextEditingController controller;
  final String hint;
  final VoidCallback onSubmitted;
  final bool autofocus;

  @override
  State<NameField> createState() => _NameFieldState();
}

class _NameFieldState extends State<NameField> {
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_changed);
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _focus
      ..removeListener(_changed)
      ..dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final style = KitStyle.of(context);
    final ink = theme.colors.textPrimary;
    return Container(
      height: 28,
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: ink.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(style.corner(8)),
        border: Border.all(
          color: _focus.hasFocus
              ? style.accent(theme).withValues(alpha: 0.8)
              : ink.withValues(alpha: 0.08),
        ),
      ),
      // A text field draws on a Material, and nothing above a settings page
      // supplies one.
      child: Material(
        type: MaterialType.transparency,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: TextField(
            controller: widget.controller,
            focusNode: _focus,
            maxLength: 40,
            maxLines: 1,
            style: BarType.caption.copyWith(fontSize: 13, color: ink),
            cursorColor: style.accent(theme),
            onSubmitted: (_) => widget.onSubmitted(),
            decoration: InputDecoration(
              isDense: true,
              isCollapsed: true,
              counterText: '',
              border: InputBorder.none,
              hintText: widget.hint,
              hintStyle: BarType.caption.copyWith(
                fontSize: 13,
                color: ink.withValues(alpha: 0.45),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
