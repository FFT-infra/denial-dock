import 'dart:math' as math;

import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/material.dart';

import '../bar_icons.dart';
import '../bar_tokens.dart';
import '../bar_type.dart';

/// Text styles for the bar's popovers.
///
/// shell27 `MacBar.qml` draws popover copy at four sizes: 15 DemiBold for a
/// header title, 13 regular for a body row, 12 for a detail line and 11
/// DemiBold for a section label. They are grouped here so every panel agrees.
abstract final class PanelText {
  static TextStyle _base(double size, FontWeight weight) =>
      BarType.menuRow.copyWith(fontSize: size, fontWeight: weight, height: 1.25);

  static TextStyle title(ShellThemeData theme) =>
      _base(15, FontWeight.w600).copyWith(color: theme.colors.textPrimary);

  static TextStyle body(ShellThemeData theme) =>
      _base(13, FontWeight.w400).copyWith(color: theme.colors.textPrimary);

  static TextStyle bodyBold(ShellThemeData theme) =>
      _base(13, FontWeight.w600).copyWith(color: theme.colors.textPrimary);

  static TextStyle detail(ShellThemeData theme) =>
      _base(12, FontWeight.w400).copyWith(color: theme.colors.textSecondary);

  static TextStyle section(ShellThemeData theme) =>
      _base(11, FontWeight.w600).copyWith(color: theme.colors.textSecondary);
}

/// A popover header: an optional back chevron, the title, and an optional
/// trailing control. shell27 gives every one of them `height: 32`, the title at
/// `x: 6` (`x: 30` beside a back arrow) and the switch at `rightMargin: 4`.
class PanelHeader extends StatelessWidget {
  const PanelHeader({
    required this.title,
    this.showBack = false,
    this.onBack,
    this.trailing,
    super.key,
  });

  final String title;
  final bool showBack;
  final VoidCallback? onBack;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    return SizedBox(
      height: 32,
      child: Row(
        children: <Widget>[
          if (showBack)
            SizedBox(
              width: 30,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onBack,
                  child: Center(
                    child: BarGlyph(
                      BarIcons.chevronLeft,
                      size: 12,
                      color: theme.colors.textPrimary,
                    ),
                  ),
                ),
              ),
            ),
          Padding(
            padding: EdgeInsets.only(left: showBack ? 0 : 6),
            child: Text(title, style: PanelText.title(theme)),
          ),
          const Spacer(),
          if (trailing != null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: trailing,
            ),
        ],
      ),
    );
  }
}

/// The popover's own switch: shell27 `PSwitch`.
///
/// A 38 × 22 track that fills with the accent, a 18 pt thumb inset 2, and a
/// 150 ms colour animation. It is smaller than the dock's settings switch
/// because a popover header is only 32 pt tall.
class PanelSwitch extends StatefulWidget {
  const PanelSwitch({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  State<PanelSwitch> createState() => _PanelSwitchState();
}

class _PanelSwitchState extends State<PanelSwitch> {
  static const double _width = 38;
  static const double _height = 22;
  static const double _inset = 2;
  static const double _thumb = _height - _inset * 2;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final enabled = widget.onChanged != null;
    final t = widget.value ? 1.0 : 0.0;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? () => widget.onChanged!(!widget.value) : null,
          child: SizedBox(
            width: _width,
            height: _height,
            child: Stack(
              children: <Widget>[
                Positioned.fill(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    decoration: BoxDecoration(
                      color: Color.lerp(
                        theme.colors.textPrimary.withValues(alpha: 0.18),
                        theme.accent,
                        t,
                      ),
                      borderRadius: BorderRadius.circular(_height / 2),
                    ),
                  ),
                ),
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 150),
                  curve: Curves.easeOut,
                  left: _inset + (_width - _inset * 2 - _thumb) * t,
                  top: _inset,
                  width: _thumb,
                  height: _thumb,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xffffffff),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: theme.colors.shadow.withValues(alpha: 0.22),
                          blurRadius: 2,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A 1 px hairline inside a popover.
class PanelDivider extends StatelessWidget {
  const PanelDivider({required this.color, super.key});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 7,
      child: Center(child: SizedBox(height: 1, child: ColoredBox(color: color))),
    );
  }
}

/// The empty-state line shell27 centres at 56 pt.
class PanelEmpty extends StatelessWidget {
  const PanelEmpty(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    return SizedBox(
      height: 56,
      child: Center(
        child: Text(label, style: PanelText.body(theme).copyWith(
          color: theme.colors.textSecondary,
        )),
      ),
    );
  }
}

/// One row of a popover list.
///
/// shell27's network and device rows are 38 pt with a radius-8 accent wash on
/// hover, a 14 pt check at `x: 9` for the selected entry, the label at `x: 30`,
/// and the trailing detail pinned to `rightMargin: 12`.
class PanelRow extends StatefulWidget {
  const PanelRow({
    required this.label,
    this.height = 38,
    this.leading,
    this.trailing,
    this.onTap,
    this.selected = false,
    this.bold = false,
    super.key,
  });

  final String label;
  final double height;

  /// Replaces the checkmark slot when the row is not selected.
  final IconData? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool selected;
  final bool bold;

  @override
  State<PanelRow> createState() => _PanelRowState();
}

class _PanelRowState extends State<PanelRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final interactive = widget.onTap != null;
    final hot = _hovered && interactive;
    final ink = hot ? const Color(0xffffffff) : theme.colors.textPrimary;
    final glyph = widget.selected
        ? BarIcons.checkmark
        : widget.leading;
    return MouseRegion(
      cursor: interactive ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: SizedBox(
          height: widget.height,
          child: Stack(
            children: <Widget>[
              if (hot)
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: theme.accent,
                      borderRadius: theme.borderRadius(8),
                    ),
                  ),
                ),
              if (glyph != null)
                Positioned(
                  left: 9,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: BarGlyph(
                      glyph,
                      size: 14,
                      color: hot ? const Color(0xffffffff) : theme.colors.textSecondary,
                    ),
                  ),
                ),
              Positioned(
                left: 30,
                right: widget.trailing == null ? 12 : 96,
                top: 0,
                bottom: 0,
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        widget.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: (widget.bold
                                ? PanelText.bodyBold(theme)
                                : PanelText.body(theme))
                            .copyWith(color: ink),
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.trailing != null)
                Positioned(
                  right: 10,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: DefaultTextStyle.merge(
                      style: TextStyle(
                        color: hot
                            ? const Color(0xffffffff)
                            : theme.colors.textSecondary,
                      ),
                      child: widget.trailing!,
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

/// A full-width action row at the bottom of a popover, 30 pt high.
class PanelAction extends StatefulWidget {
  const PanelAction({required this.label, required this.onTap, super.key});

  final String label;
  final VoidCallback onTap;

  @override
  State<PanelAction> createState() => _PanelActionState();
}

class _PanelActionState extends State<PanelAction> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: SizedBox(
          height: 30,
          child: Stack(
            children: <Widget>[
              if (_hovered)
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: theme.accent,
                      borderRadius: theme.borderRadius(8),
                    ),
                  ),
                ),
              Positioned(
                left: 10,
                top: 0,
                bottom: 0,
                child: Center(
                  child: Text(
                    widget.label,
                    style: PanelText.body(theme).copyWith(
                      color: _hovered
                          ? const Color(0xffffffff)
                          : theme.colors.textPrimary,
                    ),
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

/// The volume track shared by the sound popover and Control Centre.
///
/// shell27 `CCSlider` draws a 4 pt rounded track with a speaker at each end and
/// a 18 pt knob; the ends are clickable and the left one mutes.
class VolumeSlider extends StatefulWidget {
  const VolumeSlider({
    required this.value,
    required this.onChanged,
    this.onChangeStart,
    this.onChangeEnd,
    super.key,
  });

  final double value;
  final ValueChanged<double> onChanged;
  final VoidCallback? onChangeStart;
  final ValueChanged<double>? onChangeEnd;

  @override
  State<VolumeSlider> createState() => _VolumeSliderState();
}

class _VolumeSliderState extends State<VolumeSlider> {
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final t = widget.value.clamp(0.0, 1.0);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        const knob = 18.0;
        final trackLeft = 24.0;
        final trackRight = 24.0;
        final trackWidth = math.max(1.0, width - trackLeft - trackRight);
        void update(Offset position) {
          final x = (position.dx - trackLeft) / trackWidth;
          widget.onChanged(x.clamp(0.0, 1.0).toDouble());
        }

        return SizedBox(
          height: 28,
          child: Stack(
            children: <Widget>[
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => widget.onChanged(0),
                    child: SizedBox(
                      width: 24,
                      child: Center(
                        child: BarGlyph(
                          t <= 0.001
                              ? BarIcons.volumeMute
                              : (t < 0.34
                                    ? BarIcons.volumeDown
                                    : BarIcons.volumeUp),
                          size: 14,
                          color: theme.colors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: trackLeft,
                width: trackWidth,
                top: 0,
                bottom: 0,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (details) {
                    widget.onChangeStart?.call();
                    update(details.localPosition);
                    widget.onChangeEnd?.call(t);
                  },
                  onHorizontalDragStart: (details) {
                    setState(() => _dragging = true);
                    widget.onChangeStart?.call();
                    update(details.localPosition);
                  },
                  onHorizontalDragUpdate: (details) =>
                      update(details.localPosition),
                  onHorizontalDragEnd: (_) {
                    setState(() => _dragging = false);
                    widget.onChangeEnd?.call(widget.value);
                  },
                  onHorizontalDragCancel: () =>
                      setState(() => _dragging = false),
                  child: Stack(
                    children: <Widget>[
                      Center(
                        child: Container(
                          height: 4,
                          decoration: BoxDecoration(
                            color: theme.colors.textPrimary.withValues(
                              alpha: 0.16,
                            ),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        width: trackWidth * t,
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
                        left: (trackWidth * t - knob / 2).clamp(
                          -knob / 2,
                          trackWidth - knob / 2,
                        ),
                        top: 0,
                        bottom: 0,
                        child: Center(
                          child: AnimatedScale(
                            scale: _dragging ? 1.12 : 1,
                            duration: const Duration(milliseconds: 120),
                            child: Container(
                              width: knob,
                              height: knob,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: theme.colors.sliderThumb,
                                boxShadow: <BoxShadow>[
                                  BoxShadow(
                                    color: theme.colors.shadow.withValues(
                                      alpha: 0.28,
                                    ),
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
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                child: SizedBox(
                  width: 24,
                  child: Center(
                    child: BarGlyph(
                      BarIcons.volumeUp,
                      size: 14,
                      color: theme.colors.textSecondary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The Wi-Fi arcs at a given strength, matching shell27's `WifiGlyph`.
class WifiStrengthGlyph extends StatelessWidget {
  const WifiStrengthGlyph({
    required this.strength,
    required this.size,
    required this.color,
    super.key,
  });

  final int strength;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size * 0.75,
      child: CustomPaint(
        painter: _WifiArcPainter(
          color: color,
          arcs: strength > 66
              ? 3
              : strength > 33
              ? 2
              : 1,
        ),
      ),
    );
  }
}

class _WifiArcPainter extends CustomPainter {
  const _WifiArcPainter({required this.color, required this.arcs});

  final Color color;
  final int arcs;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final centre = Offset(size.width / 2, size.height);
    for (var index = 0; index < arcs; index++) {
      final radius = size.width * (0.28 + index * 0.26);
      paint.strokeWidth = math.max(1.2, size.width * 0.1);
      canvas.drawArc(
        Rect.fromCircle(center: centre, radius: radius),
        math.pi * 1.25,
        math.pi * 0.5,
        false,
        paint,
      );
    }
    canvas.drawCircle(
      centre,
      math.max(1.2, size.width * 0.09),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _WifiArcPainter old) =>
      old.color != color || old.arcs != arcs;
}

/// The bar's own panel padding: shell27 loads popover content at `x: 11`,
/// `y: 11` inside a 320-wide shape, leaving 11 pt on each side.
const double panelInset = 11;

/// The width shell27 gives each popover.
abstract final class PanelWidth {
  static const double wifi = BarTokens.wifiPopoverWidth;
  static const double bluetooth = BarTokens.bluetoothPopoverWidth;
  static const double volume = BarTokens.volumePopoverWidth;
  static const double notifications = 380;
  static const double calendar = 310;
}
