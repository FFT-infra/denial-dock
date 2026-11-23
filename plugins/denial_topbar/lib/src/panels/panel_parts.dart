import 'dart:math' as math;

import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/material.dart';

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
