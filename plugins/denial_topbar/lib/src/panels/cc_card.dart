import 'dart:math' as math;

import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/material.dart';

import '../bar_icons.dart';
import '../bar_tokens.dart';
import '../bar_type.dart';
import 'panel_parts.dart' show WifiStrengthGlyph;

/// The blue macOS paints every "on" control with.
///
/// NextKDE `SubmenuCard.qml` hardcodes `#0a84ff` for the Wi-Fi/Bluetooth
/// switch and `WifiCard.qml` colours the active disc from the same family
/// (`ThemeService.tileActiveFill`). The shell accent here follows the
/// wallpaper, which would turn a Wi-Fi disc lavender on a purple desktop, so
/// the Control Centre keeps the system blue instead.
const Color ccBlue = Color(0xff0a84ff);

/// One card in the Control Centre.
///
/// Ports NextKDE `ControlCenterCard.qml`: a rounded fill with a 1 px rim, a
/// hover/press wash over it (`ControlCenterSelection.qml`), and a press scale.
/// NextKDE gives each card its own KWin glass region; a Denial popup only has
/// the one `ShellBackdropBlur` its frame draws, so the card paints the tint
/// and rim that would sit on top of that glass.
class CcCard extends StatefulWidget {
  const CcCard({
    required this.radius,
    required this.child,
    this.onTap,
    this.active = false,
    this.activeFill,
    this.padding,
    super.key,
  });

  final double radius;
  final Widget child;
  final VoidCallback? onTap;

  /// Paints the rim brighter, the way NextKDE's `selected` does.
  final bool active;

  /// The wash behind an "on" card. Defaults to the neutral glass fill.
  final Color? activeFill;
  final EdgeInsetsGeometry? padding;

  @override
  State<CcCard> createState() => _CcCardState();
}

class _CcCardState extends State<CcCard> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final dark = theme.colors.brightness == Brightness.dark;
    final radius = BorderRadius.circular(widget.radius);
    final base =
        widget.activeFill ??
        Colors.white.withValues(alpha: dark ? 0.10 : 0.42);
    final scale = _pressed ? 0.97 : (_hovered && widget.onTap != null ? 1.015 : 1.0);

    Widget body = DecoratedBox(
      decoration: BoxDecoration(
        color: base,
        borderRadius: radius,
        border: Border.all(
          color: Colors.white.withValues(
            alpha: dark ? (widget.active ? 0.26 : 0.16) : 0.70,
          ),
          width: 0.8,
        ),
      ),
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: AnimatedContainer(
              duration: Motion.cardSettle,
              curve: Curves.easeOut,
              decoration: BoxDecoration(
                color: _hovered && widget.onTap != null
                    ? Colors.white.withValues(alpha: dark ? 0.025 : 0.07)
                    : Colors.transparent,
                borderRadius: radius,
              ),
            ),
          ),
          if (widget.padding != null)
            Positioned.fill(
              child: Padding(padding: widget.padding!, child: widget.child),
            )
          else
            Positioned.fill(child: widget.child),
        ],
      ),
    );

    if (widget.onTap != null) {
      body = MouseRegion(
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
          child: body,
        ),
      );
    }

    return AnimatedScale(
      scale: scale,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      child: body,
    );
  }
}

/// The 21 pt arc a Wi-Fi or Bluetooth toggle spins while the radio changes.
///
/// NextKDE `WifiCard.qml`'s `wifiBusySpinner`: a 270° arc, 2 pt round-capped
/// stroke, one turn every 900 ms, over a disc that drops to 0.55.
class CcBusyArc extends StatefulWidget {
  const CcBusyArc({required this.color, this.size = 21, super.key});

  final Color color;
  final double size;

  @override
  State<CcBusyArc> createState() => _CcBusyArcState();
}

class _CcBusyArcState extends State<CcBusyArc>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _spin,
      child: CustomPaint(
        size: Size.square(widget.size),
        painter: _BusyArcPainter(widget.color),
      ),
    );
  }
}

class _BusyArcPainter extends CustomPainter {
  const _BusyArcPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.width / 2 - 1.5;
    canvas.drawArc(
      Rect.fromCircle(center: size.center(Offset.zero), radius: radius),
      0,
      math.pi * 1.5,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_BusyArcPainter oldDelegate) => oldDelegate.color != color;
}

/// The round button a sub-page uses to go back.
///
/// NextKDE `SubmenuCard.qml`: 26 × 26, radius 13, a 1 px rim, white 0.10 fill
/// that rises to 0.18 on hover and 0.26 pressed, and the glyph nudged 1 pt
/// left so the chevron reads centred.
class CcBackButton extends StatefulWidget {
  const CcBackButton({required this.onTap, super.key});

  final VoidCallback onTap;

  @override
  State<CcBackButton> createState() => _CcBackButtonState();
}

class _CcBackButtonState extends State<CcBackButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final dark = theme.colors.brightness == Brightness.dark;
    final alpha = _pressed
        ? (dark ? 0.26 : 0.14)
        : (_hovered ? (dark ? 0.18 : 0.09) : (dark ? 0.10 : 0.05));
    return MouseRegion(
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
          scale: _pressed ? 0.92 : 1,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: alpha),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: Colors.white.withValues(alpha: dark ? 0.18 : 0.08),
              ),
            ),
            child: Center(
              child: Transform.translate(
                offset: const Offset(-1, 0),
                child: BarGlyph(
                  BarIcons.chevronLeft,
                  size: 18,
                  color: theme.colors.textPrimary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The 38 × 22 switch a sub-page puts at the right of its header.
///
/// NextKDE `SubmenuCard.qml` draws it here rather than reusing the panel
/// switch, so it keeps the reference's own geometry and `#0a84ff` track.
class CcSwitch extends StatelessWidget {
  const CcSwitch({
    required this.value,
    required this.onChanged,
    this.busy = false,
    super.key,
  });

  final bool value;
  final VoidCallback? onChanged;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final dark = theme.colors.brightness == Brightness.dark;
    return Opacity(
      opacity: busy ? 0.6 : 1,
      child: MouseRegion(
        cursor: onChanged == null
            ? MouseCursor.defer
            : SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: busy ? null : onChanged,
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: value ? 1 : 0, end: value ? 1 : 0),
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            builder: (context, t, _) => SizedBox(
              width: 38,
              height: 22,
              child: Stack(
                children: <Widget>[
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Color.lerp(
                          Colors.white.withValues(alpha: dark ? 0.20 : 0.14),
                          ccBlue,
                          t,
                        ),
                        borderRadius: BorderRadius.circular(11),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 2 + (38 - 18 - 4) * t,
                    top: 2,
                    width: 18,
                    height: 18,
                    child: const DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xffffffff),
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

/// A sub-page's group heading: 22 high, 14 in from either edge.
class CcSectionHeader extends StatelessWidget {
  const CcSectionHeader({
    required this.title,
    this.trailing,
    this.titleSize = 11,
    super.key,
  });

  final String title;
  final Widget? trailing;
  final double titleSize;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    return SizedBox(
      height: 22,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: BarType.caption.copyWith(
                  fontSize: titleSize,
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

/// A sub-page's settings footer: a hairline 12 in from either edge and a
/// label at 16 with the matching glyph at the far right.
class CcFooter extends StatefulWidget {
  const CcFooter({
    required this.label,
    required this.icon,
    required this.onTap,
    this.labelSize = 12,
    super.key,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final double labelSize;

  @override
  State<CcFooter> createState() => _CcFooterState();
}

class _CcFooterState extends State<CcFooter> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final dark = theme.colors.brightness == Brightness.dark;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: SizedBox(
          height: 38,
          child: Stack(
            children: <Widget>[
              Positioned.fill(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 90),
                  decoration: BoxDecoration(
                    color: _hovered
                        ? Colors.white.withValues(alpha: dark ? 0.06 : 0.04)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              Positioned(
                left: 12,
                right: 12,
                top: 0,
                height: 1,
                child: ColoredBox(
                  color: Colors.white.withValues(alpha: dark ? 0.08 : 0.06),
                ),
              ),
              Positioned(
                left: 16,
                top: 0,
                bottom: 0,
                child: Center(
                  child: Text(
                    widget.label,
                    style: BarType.caption.copyWith(
                      fontSize: widget.labelSize,
                      fontWeight: FontWeight.w700,
                      color: theme.colors.textPrimary,
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 16,
                top: 0,
                bottom: 0,
                child: Center(
                  child: BarGlyph(
                    widget.icon,
                    size: 13,
                    color: theme.colors.textPrimary,
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

/// The 42 pt row every network and device list uses.
///
/// NextKDE `WifiPage.qml` / `BluetoothPage.qml`: radius 10, a hover wash at
/// white 0.12 (black 0.06 on light), the leading glyphs at 8 and 26, the label
/// at 48 and a trailing cluster 8 in from the right.
class CcListRow extends StatefulWidget {
  const CcListRow({
    required this.child,
    this.onTap,
    this.leading,
    this.trailing,
    this.height = 42,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final Widget? leading;
  final Widget? trailing;
  final double height;

  @override
  State<CcListRow> createState() => _CcListRowState();
}

class _CcListRowState extends State<CcListRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final dark = theme.colors.brightness == Brightness.dark;
    return MouseRegion(
      cursor: widget.onTap == null
          ? MouseCursor.defer
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: SizedBox(
          height: widget.height,
          child: Stack(
            children: <Widget>[
              Positioned.fill(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 90),
                  decoration: BoxDecoration(
                    color: _hovered && widget.onTap != null
                        ? (dark
                              ? Colors.white.withValues(alpha: 0.12)
                              : Colors.black.withValues(alpha: 0.06))
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              if (widget.leading != null)
                Positioned(
                  left: 8,
                  top: 0,
                  bottom: 0,
                  child: Center(child: widget.leading!),
                ),
              Positioned.fill(
                child: Padding(
                  padding: EdgeInsets.only(
                    left: widget.leading == null ? 12 : 48,
                    right: widget.trailing == null ? 12 : 6,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: widget.child,
                  ),
                ),
              ),
              if (widget.trailing != null)
                Positioned(
                  right: 8,
                  top: 0,
                  bottom: 0,
                  child: Center(child: widget.trailing!),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The signal and lock glyphs a Wi-Fi row carries on its right.
class CcWifiTrailing extends StatelessWidget {
  const CcWifiTrailing({
    required this.secured,
    required this.connected,
    required this.strength,
    this.busy = false,
    this.onDisconnect,
    super.key,
  });

  final bool secured;
  final bool connected;
  final int strength;
  final bool busy;
  final VoidCallback? onDisconnect;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    if (busy) {
      return Text(
        'Connecting…',
        style: BarType.caption.copyWith(
          fontSize: 10,
          color: theme.colors.textSecondary,
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (secured)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: SizedBox(
              width: 12,
              height: 14,
              child: Center(
                child: BarGlyph(
                  BarIcons.lock,
                  size: 12,
                  color: theme.colors.textPrimary,
                ),
              ),
            ),
          ),
        WifiStrengthGlyph(
          strength: strength,
          size: 16,
          color: connected ? ccBlue : theme.colors.textPrimary,
        ),
        if (connected) ...<Widget>[
          const SizedBox(width: 6),
          _DisconnectPill(onTap: onDisconnect),
        ],
      ],
    );
  }
}

class _DisconnectPill extends StatefulWidget {
  const _DisconnectPill({required this.onTap});

  final VoidCallback? onTap;

  @override
  State<_DisconnectPill> createState() => _DisconnectPillState();
}

class _DisconnectPillState extends State<_DisconnectPill> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final dark = theme.colors.brightness == Brightness.dark;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          width: 38,
          height: 20,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white.withValues(
              alpha: (dark ? 0.14 : 0.08) + (_hovered ? 0.08 : 0),
            ),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: Colors.white.withValues(alpha: dark ? 0.20 : 0.10),
            ),
          ),
          child: Text(
            'Disconnect',
            style: BarType.caption.copyWith(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: theme.colors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

/// The track, fill and thumb NextKDE `ControlCenterSlider.qml` draws.
///
/// Dark: white 0.16 track, white 0.90 fill, white 0.38 thumb with a 0.45 rim.
/// Light: black 0.10 track, black 0.72 fill, white 0.72 thumb with a 0.16 rim.
class CcSlider extends StatefulWidget {
  const CcSlider({
    required this.value,
    required this.left,
    required this.right,
    required this.dark,
    required this.onChangeStart,
    required this.onChanged,
    required this.onChangeEnd,
    this.height = BarTokens.ccSliderHeight2,
    super.key,
  });

  final double value;
  final double left;
  final double right;
  final bool dark;
  final VoidCallback onChangeStart;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;
  final double height;

  @override
  State<CcSlider> createState() => _CcSliderState();
}

class _CcSliderState extends State<CcSlider> {
  bool _dragging = false;
  double? _pending;

  double get _value => (_pending ?? widget.value).clamp(0.0, 1.0).toDouble();

  void _update(Offset position, double width) {
    if (width <= 0) return;
    final next = (position.dx / width).clamp(0.0, 1.0).toDouble();
    if (_pending == null) widget.onChangeStart();
    setState(() => _pending = next);
    widget.onChanged(next);
  }

  void _end() {
    final value = _pending;
    setState(() {
      _pending = null;
      _dragging = false;
    });
    if (value != null) widget.onChangeEnd(value);
  }

  @override
  Widget build(BuildContext context) {
    final dark = widget.dark;
    final track = dark
        ? Colors.white.withValues(alpha: 0.16)
        : Colors.black.withValues(alpha: 0.10);
    final fill = dark
        ? Colors.white.withValues(alpha: 0.90)
        : Colors.black.withValues(alpha: 0.72);
    final thumb = dark
        ? Colors.white.withValues(alpha: 0.38)
        : Colors.white.withValues(alpha: 0.72);
    final rim = dark
        ? Colors.white.withValues(alpha: 0.45)
        : Colors.black.withValues(alpha: 0.16);
    return LayoutBuilder(
      builder: (context, constraints) {
        final trackX = widget.left;
        final trackW = (constraints.maxWidth - widget.left - widget.right).clamp(
          1.0,
          constraints.maxWidth,
        );
        final knobX =
            trackX + _value * trackW - BarTokens.ccSliderThumbWidth / 2;
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) {
              widget.onChangeStart();
              _update(Offset(details.localPosition.dx - trackX, 0), trackW);
            },
            onTapUp: (_) => _end(),
            onHorizontalDragStart: (details) {
              setState(() => _dragging = true);
              widget.onChangeStart();
              _update(Offset(details.localPosition.dx - trackX, 0), trackW);
            },
            onHorizontalDragUpdate: (details) => _update(
              Offset(details.localPosition.dx - trackX, 0),
              trackW,
            ),
            onHorizontalDragEnd: (_) => _end(),
            onHorizontalDragCancel: _end,
            child: Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                Positioned(
                  left: trackX,
                  width: trackW,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: Container(
                      height: BarTokens.ccSliderTrackHeight,
                      decoration: BoxDecoration(
                        color: track,
                        borderRadius: BorderRadius.circular(
                          BarTokens.ccSliderTrackHeight / 2,
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: trackX,
                  width: trackW * _value,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: Container(
                      height: BarTokens.ccSliderTrackHeight,
                      decoration: BoxDecoration(
                        color: fill,
                        borderRadius: BorderRadius.circular(
                          BarTokens.ccSliderTrackHeight / 2,
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: knobX,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 90),
                      curve: Curves.easeOut,
                      width: BarTokens.ccSliderThumbWidth,
                      height: BarTokens.ccSliderThumbHeight,
                      decoration: BoxDecoration(
                        color: thumb,
                        borderRadius: BorderRadius.circular(
                          BarTokens.ccSliderThumbHeight / 2,
                        ),
                        border: Border.all(color: rim),
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color: Colors.black.withValues(
                              alpha: _dragging ? 0.30 : 0.18,
                            ),
                            blurRadius: _dragging ? 8 : 4,
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
    );
  }
}
