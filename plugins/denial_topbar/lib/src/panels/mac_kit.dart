import 'package:denial_flutter_sdk/theme.dart';
import 'package:denial_shell_kit/kit_springs.dart';
import 'package:denial_shell_kit/kit_style.dart';
import 'package:flutter/widgets.dart';

import '../bar_icons.dart';
import '../bar_type.dart';

const Color macBlue = Color(0xff0a84ff);
const Color macPurple = Color(0xff5e5ce6);
const Color macOrange = Color(0xffff9f0a);
const Color macYellow = Color(0xffffd60a);
const Color macGreen = Color(0xff30d158);
const Color macRed = Color(0xffff453a);

/// Shrinks its child a little while a finger or button is down on it.
class Pressable extends StatefulWidget {
  const Pressable({
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.96,
    this.builder,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;

  /// Rebuilds the child with the hover and pressed state when given.
  final Widget Function(BuildContext context, bool hovered, bool pressed)?
  builder;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: Sprung(
          target: _pressed ? widget.scale : 1,
          tuning: KitStyle.of(context).pressTuning,
          builder: (context, value, child) =>
              Transform.scale(scale: value, child: child),
          child:
              widget.builder?.call(context, _hovered, _pressed) ?? widget.child,
        ),
      ),
    );
  }
}

class MacSwitch extends StatelessWidget {
  const MacSwitch({
    required this.value,
    required this.onChanged,
    this.busy = false,
    super.key,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final style = KitStyle.of(context);
    final enabled = onChanged != null && !busy;
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? () => onChanged!(!value) : null,
        onHorizontalDragEnd: enabled
            ? (details) {
                final right = (details.primaryVelocity ?? 0) > 0;
                if (right != value) onChanged!(right);
              }
            : null,
        child: MouseRegion(
          cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
          child: SizedBox(
            width: 46,
            height: 26,
            child: LiquidFill(
              level: value ? 1 : 0,
              sideways: true,
              color: style.accent(theme),
              base: theme.colors.textPrimary.withValues(alpha: 0.18),
              radius: BorderRadius.circular(13),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Sprung(
                  target: value ? 1 : -1,
                  tuning: style.liquid
                      ? const KitSpringTuning(520, 0.6)
                      : const KitSpringTuning(620, 0.72),
                  builder: (context, x, child) =>
                      Align(alignment: Alignment(x, 0), child: child),
                  child: style.liquid
                      // Denial's knob is ink on the fill, not a white bead.
                      ? Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: value
                                ? style.onAccent(theme)
                                : theme.colors.textPrimary.withValues(
                                    alpha: 0.82,
                                  ),
                          ),
                        )
                      : Container(
                          width: 28,
                          height: 22,
                          decoration: BoxDecoration(
                            color: const Color(0xffffffff),
                            borderRadius: BorderRadius.circular(11),
                            boxShadow: const <BoxShadow>[
                              BoxShadow(
                                color: Color(0x33000000),
                                blurRadius: 4,
                                offset: Offset(0, 1),
                              ),
                            ],
                          ),
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The round icon plate: a solid colour while on, a quiet grey while off.
class MacDisc extends StatelessWidget {
  const MacDisc({
    required this.icon,
    required this.on,
    this.size = 28,
    this.colour = macBlue,
    this.meaning = false,
    this.child,
    super.key,
  });

  final IconData icon;
  final bool on;
  final double size;
  final Color colour;

  /// Whether [colour] says something (a warning, a recording) and so stays
  /// where the look would otherwise pour its one accent.
  final bool meaning;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final style = KitStyle.of(context);
    return SizedBox(
      width: size,
      height: size,
      child: LiquidFill(
        level: on ? 1 : 0,
        color: style.plate(theme, colour, meaning: meaning),
        base: theme.colors.textPrimary.withValues(alpha: 0.14),
        radius: BorderRadius.circular(size / 2),
        child: Center(
          child:
              child ??
              BarGlyph(
                icon,
                size: size * 0.5,
                color: on
                    ? style.onPlate(theme, meaning: meaning)
                    : theme.colors.textPrimary,
              ),
        ),
      ),
    );
  }
}

class MacDivider extends StatelessWidget {
  const MacDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: SizedBox(
        height: 1,
        child: ColoredBox(color: context.shellTheme.colors.hairline),
      ),
    );
  }
}

class MacSection extends StatelessWidget {
  const MacSection(this.title, {this.trailing, super.key});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 4),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              title,
              style: BarType.section.copyWith(
                color: context.shellTheme.colors.textSecondary,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// The popover's title line with an optional switch at its end.
class MacHeader extends StatelessWidget {
  const MacHeader({required this.title, this.trailing, this.onBack, super.key});

  final String title;
  final Widget? trailing;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 2, 6, 2),
      child: SizedBox(
        height: 30,
        child: Row(
          children: <Widget>[
            if (onBack != null)
              Pressable(
                onTap: onBack,
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: BarGlyph(
                    BarIcons.chevronLeft,
                    size: 14,
                    color: theme.colors.textPrimary,
                  ),
                ),
              ),
            Expanded(
              child: Text(
                title,
                style: BarType.title.copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: theme.colors.textPrimary,
                ),
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

/// One list row: an optional disc, a title, optional detail and trailing.
class MacRow extends StatelessWidget {
  const MacRow({
    required this.title,
    this.leading,
    this.detail,
    this.trailing,
    this.onTap,
    this.height = 38,
    super.key,
  });

  final Widget? leading;
  final String title;
  final String? detail;
  final Widget? trailing;
  final VoidCallback? onTap;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    return Pressable(
      onTap: onTap,
      scale: 0.985,
      child: const SizedBox.shrink(),
      builder: (context, hovered, pressed) => AnimatedContainer(
        duration: const Duration(milliseconds: 110),
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: theme.colors.textPrimary.withValues(
            alpha: onTap == null
                ? 0
                : pressed
                ? 0.14
                : hovered
                ? 0.08
                : 0,
          ),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          children: <Widget>[
            if (leading != null) ...<Widget>[
              leading!,
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: BarType.menuRow.copyWith(
                      color: theme.colors.textPrimary,
                    ),
                  ),
                  if (detail != null && detail!.isNotEmpty)
                    Text(
                      detail!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: BarType.caption.copyWith(
                        color: theme.colors.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

/// A thin track with a blue fill and a white pill for a knob. While held,
/// the knob swells into a clear lens that shows the track through it. Works
/// with a drag or a tap anywhere along the track.
class MacSlider extends StatefulWidget {
  const MacSlider({
    required this.value,
    required this.onChanged,
    this.onChangeStart,
    this.onChangeEnd,
    this.leading,
    this.trailing,
    this.height = 18,
    super.key,
  });

  final double value;
  final ValueChanged<double> onChanged;
  final VoidCallback? onChangeStart;
  final ValueChanged<double>? onChangeEnd;
  final IconData? leading;
  final IconData? trailing;

  /// Height of the resting knob.
  final double height;

  @override
  State<MacSlider> createState() => _MacSliderState();
}

class _MacSliderState extends State<MacSlider> {
  double? _pending;
  bool _held = false;

  double get _value => (_pending ?? widget.value).clamp(0.0, 1.0);
  double get _knobWidth => widget.height * 1.5;

  void _set(double dx, double width) {
    final knob = _knobWidth;
    final next = ((dx - knob / 2) / (width - knob)).clamp(0.0, 1.0);
    if (_pending == null) widget.onChangeStart?.call();
    setState(() {
      _pending = next;
      _held = true;
    });
    widget.onChanged(next);
  }

  void _end() {
    final value = _pending;
    setState(() {
      _pending = null;
      _held = false;
    });
    if (value != null) widget.onChangeEnd?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final ink = theme.colors.textPrimary;
    final h = widget.height;
    final knob = _knobWidth;
    final track = h / 3;
    Widget glyph(IconData icon) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: BarGlyph(icon, size: 15, color: theme.colors.textSecondary),
    );
    return Row(
      children: <Widget>[
        if (widget.leading != null) glyph(widget.leading!),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final centre = knob / 2 + _value * (width - knob);
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) => _set(d.localPosition.dx, width),
                onTapUp: (_) => _end(),
                onTapCancel: () {
                  if (!_dragging) _end();
                },
                onHorizontalDragStart: (d) {
                  _dragging = true;
                  _set(d.localPosition.dx, width);
                },
                onHorizontalDragUpdate: (d) => _set(d.localPosition.dx, width),
                onHorizontalDragEnd: (_) {
                  _dragging = false;
                  _end();
                },
                onHorizontalDragCancel: () {
                  _dragging = false;
                  _end();
                },
                child: SizedBox(
                  height: h + 14,
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.centerLeft,
                    children: <Widget>[
                      Container(
                        height: track,
                        decoration: BoxDecoration(
                          color: ink.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(track / 2),
                        ),
                      ),
                      Container(
                        width: centre,
                        height: track,
                        decoration: BoxDecoration(
                          color: KitStyle.of(context).accent(theme),
                          borderRadius: BorderRadius.circular(track / 2),
                        ),
                      ),
                      Positioned(
                        left: centre - knob / 2,
                        child: AnimatedScale(
                          duration: Duration(milliseconds: _held ? 140 : 320),
                          curve: _held ? Curves.easeOut : Curves.easeOutBack,
                          scale: _held ? 1.3 : 1,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            width: knob,
                            height: h,
                            decoration: BoxDecoration(
                              color: const Color(0xffffffff)
                                  .withValues(alpha: _held ? 0.22 : 1),
                              borderRadius: BorderRadius.circular(h / 2),
                              border: Border.all(
                                color: const Color(0xffffffff)
                                    .withValues(alpha: _held ? 0.85 : 0),
                                width: 1.2,
                              ),
                              boxShadow: <BoxShadow>[
                                BoxShadow(
                                  color: const Color(0xff000000)
                                      .withValues(alpha: _held ? 0.18 : 0.26),
                                  blurRadius: _held ? 10 : 5,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        if (widget.trailing != null) glyph(widget.trailing!),
      ],
    );
  }

  bool _dragging = false;
}

/// Fades and sizes between a collapsed and an expanded child.
class Reveal extends StatelessWidget {
  const Reveal({required this.open, required this.child, super.key});

  final bool open;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        heightFactor: open ? 1 : 0,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: open ? 1 : 0,
          child: child,
        ),
      ),
    );
  }
}
