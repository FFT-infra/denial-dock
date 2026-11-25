import 'dart:io';
import 'dart:math' as math;

import 'package:denial_shell_kit/kit_style.dart';
import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/material.dart';

import 'dock_pile.dart';

/// The dock's own items drawn the way macOS draws its: full-bleed artwork
/// rather than the accent-tinted rounded tile the Denial look uses.
///
/// A folder becomes a blue folder carrying a pile of its newest files, the
/// trash becomes a glass can, and the launcher becomes the applications tile.

/// One card in a stack icon: the picture to draw, or the type glyph when the
/// file has no thumbnail, and whether the entry is a folder. A folder draws
/// the blue folder at card size, so folders and files sit on the pile at one
/// size and cover one another by order.
class DockStackPreview {
  const DockStackPreview({
    this.path,
    this.folder = false,
    this.icon,
    this.color,
  });

  final String? path;
  final bool folder;
  final IconData? icon;
  final Color? color;
}

/// A folder shown as a stack: the newest files piled on a folder, each card
/// turned a little more than the one in front of it.
class DockStackIcon extends StatelessWidget {
  const DockStackIcon({
    required this.size,
    required this.previews,
    this.pressed = false,
    super.key,
  });

  final double size;

  /// Cards, newest first. Missing or broken entries fall back to a plain card,
  /// so a pile never collapses just because one thumbnail did.
  final List<DockStackPreview> previews;

  final bool pressed;

  Widget _card(DockStackPreview preview, double edge) {
    if (preview.folder) return DockFolderIcon(size: edge);
    final path = preview.path;
    if (path == null) {
      final icon = preview.icon;
      if (icon == null) return const SizedBox.shrink();
      return Center(
        child: Icon(icon, size: edge * 0.55, color: preview.color),
      );
    }
    return Image.file(
      File(path),
      fit: BoxFit.cover,
      cacheWidth: (size * 3).round(),
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => const SizedBox.shrink(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final radius = BorderRadius.circular(size * 0.24);
    final shown = math.min(DockPile.count, previews.length);
    return SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: CustomPaint(painter: _FolderPainter(theme.kitAccent)),
          ),
          // The oldest card is painted first so the newest sits on top, which
          // is the order the pile is read in.
          for (var i = shown - 1; i >= 0; i--)
            Positioned.fill(
              child: Transform.translate(
                offset: Offset(
                  size * DockPile.offset(i).dx,
                  size * DockPile.offset(i).dy,
                ),
                child: Transform.rotate(
                  angle: DockPile.angle(i),
                  child: Center(
                    child: SizedBox.square(
                      dimension: size * DockPile.edge(i),
                      child: ClipRRect(
                        // A card's corner is a share of its own edge. Scaling
                        // the tile's radius made the smallest card a circle.
                        borderRadius: BorderRadius.circular(
                          size * DockPile.edge(i) * 0.16,
                        ),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: theme.panelColor(
                              theme.colors.surfaceContainerHigh,
                            ),
                            border: Border.all(
                              color: Colors.black.withValues(alpha: 0.10),
                            ),
                          ),
                          child: _card(previews[i], size * DockPile.edge(i)),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (pressed)
            Positioned.fill(
              child: ClipRRect(
                borderRadius: radius,
                child: const ColoredBox(color: Color(0x29000000)),
              ),
            ),
        ],
      ),
    );
  }
}

/// The tile a stack shows while it is open: a plate with a chevron pointing
/// at the rows it just dealt out. The cards have left the icon, so none are
/// drawn here.
class DockStackOpenIcon extends StatelessWidget {
  const DockStackOpenIcon({
    required this.size,
    this.quarterTurns = 0,
    super.key,
  });

  final double size;

  /// Which way the chevron points, in quarter turns clockwise from down, so
  /// it points at the rows the stack just opened into.
  final int quarterTurns;

  @override
  Widget build(BuildContext context) {
    final ink = context.shellTheme.colors.textPrimary;
    return SizedBox.square(
      dimension: size,
      child: Padding(
        padding: EdgeInsets.all(size * 0.06),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(size * 0.24),
            color: ink.withValues(alpha: 0.10),
            border: Border.all(color: ink.withValues(alpha: 0.14)),
          ),
          child: RotatedBox(
            quarterTurns: quarterTurns,
            child: Icon(
              Icons.keyboard_arrow_down_rounded,
              size: size * 0.58,
              color: ink.withValues(alpha: 0.78),
            ),
          ),
        ),
      ),
    );
  }
}

/// The blue folder on its own, for a stack row that is a folder: macOS draws
/// it at the same size as a file card, so folders and files cover one another
/// in the fan.
class DockFolderIcon extends StatelessWidget {
  const DockFolderIcon({required this.size, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _FolderPainter(context.shellTheme.kitAccent)),
    );
  }
}

/// The blue folder the pile sits on.
class _FolderPainter extends CustomPainter {
  const _FolderPainter(this.accent);

  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final tab = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF7FBDF9), Color(0xFF4E96E8)],
      ).createShader(Rect.fromLTWH(0, 0, w, h * 0.5));
    final body = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color.lerp(const Color(0xFF6FB4F8), accent, 0.08)!,
          Color.lerp(const Color(0xFF3586E8), accent, 0.10)!,
        ],
      ).createShader(Rect.fromLTWH(0, h * 0.2, w, h * 0.7));
    final r = Radius.circular(w * 0.10);
    // The tab is drawn first and the body covers its lower half, which is how
    // a folder's silhouette reads at dock size.
    canvas.drawRRect(
      RRect.fromLTRBR(
        w * 0.09,
        h * 0.17,
        w * 0.50,
        h * 0.36,
        Radius.circular(w * 0.05),
      ),
      tab,
    );
    canvas.drawRRect(
      RRect.fromLTRBR(w * 0.05, h * 0.24, w * 0.95, h * 0.86, r),
      body,
    );
  }

  @override
  bool shouldRepaint(_FolderPainter old) => old.accent != accent;
}

/// A macOS trash can: an open can of frosted glass, with what was thrown
/// away standing out of it once it holds anything.
class DockTrashIcon extends StatelessWidget {
  const DockTrashIcon({
    required this.size,
    this.pressed = false,
    this.full = false,
    super.key,
  });

  final double size;
  final bool pressed;

  /// Whether the can holds something. macOS draws an empty can as bare glass
  /// and a used one with its contents standing out of it.
  final bool full;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _TrashPainter(pressed, full)),
    );
  }
}

class _TrashPainter extends CustomPainter {
  const _TrashPainter(this.pressed, this.full);

  final bool pressed;
  final bool full;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    // An open can of frosted glass, a little narrower at its foot, with a
    // bright rim. The plate shows through it, as it does through the real
    // one.
    final body = Path()
      ..moveTo(w * 0.17, h * 0.17)
      ..lineTo(w * 0.83, h * 0.17)
      ..lineTo(w * 0.775, h * 0.85)
      ..quadraticBezierTo(w * 0.765, h * 0.93, w * 0.68, h * 0.93)
      ..lineTo(w * 0.32, h * 0.93)
      ..quadraticBezierTo(w * 0.235, h * 0.93, w * 0.225, h * 0.85)
      ..close();
    final area = Rect.fromLTWH(0, h * 0.13, w, h * 0.80);

    if (full) {
      // What was thrown away stands out of the can's mouth; the part
      // inside shows dimly through the glass drawn over it.
      void scrap(List<double> points, Color colour) {
        final path = Path()..moveTo(w * points[0], h * points[1]);
        for (var k = 2; k < points.length; k += 2) {
          path.lineTo(w * points[k], h * points[k + 1]);
        }
        canvas.drawPath(path..close(), Paint()..color = colour);
      }

      scrap(const [0.24, 0.30, 0.30, 0.07, 0.46, 0.12, 0.44, 0.34],
          const Color(0xFFB9BCC4));
      scrap(const [0.40, 0.34, 0.50, 0.05, 0.66, 0.16, 0.60, 0.36],
          const Color(0xFFF2B63C));
      scrap(const [0.56, 0.34, 0.70, 0.09, 0.80, 0.20, 0.72, 0.36],
          const Color(0xFF4AA8E8));
    }

    canvas.drawPath(
      body,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Color(0xD9F4F5F7),
            Color(0xB3DCDEE3),
            Color(0xC7EEF0F3),
            Color(0xD9FAFAFB),
          ],
          stops: [0, 0.38, 0.72, 1],
        ).createShader(area),
    );
    // Shade toward the foot, where the glass is thickest.
    canvas.drawPath(
      body,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00000000), Color(0x1F3C4048)],
        ).createShader(area),
    );
    canvas.drawPath(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, w * 0.016)
        ..strokeJoin = StrokeJoin.round
        ..color = const Color(0x40585C66),
    );
    final rim = RRect.fromLTRBR(
      w * 0.145,
      h * 0.135,
      w * 0.855,
      h * 0.205,
      Radius.circular(h * 0.035),
    );
    canvas.drawRRect(rim, Paint()..color = const Color(0xF2FDFDFE));
    canvas.drawRRect(
      rim,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, w * 0.014)
        ..color = const Color(0x4D585C66),
    );
    if (pressed) {
      canvas.drawRRect(
        RRect.fromLTRBR(
          w * 0.10,
          h * 0.12,
          w * 0.90,
          h * 0.90,
          Radius.circular(w * 0.2),
        ),
        Paint()..color = const Color(0x1F000000),
      );
    }
  }

  @override
  bool shouldRepaint(_TrashPainter old) =>
      old.pressed != pressed || old.full != full;
}

/// The launcher as macOS draws it now: a search field over six tinted
/// squares on a pale tile.
class DockLaunchpadIcon extends StatelessWidget {
  const DockLaunchpadIcon({
    required this.size,
    this.pressed = false,
    super.key,
  });

  final double size;
  final bool pressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _LaunchpadPainter(pressed)),
    );
  }
}

class _LaunchpadPainter extends CustomPainter {
  const _LaunchpadPainter(this.pressed);

  final bool pressed;

  static const List<Color> _tints = [
    Color(0xFF0A84FF),
    Color(0xFF30D158),
    Color(0xFFFF375F),
    Color(0xFFFF9F0A),
    Color(0xFFBF5AF2),
    Color(0xFF98989D),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final tile = RRect.fromLTRBR(0, 0, w, h, Radius.circular(w * 0.24));
    canvas.save();
    canvas.clipRRect(tile);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFCFCFE), Color(0xFFE7E9EF)],
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );
    // A search field over two rows of three applications.
    canvas.drawRRect(
      RRect.fromLTRBR(
        w * 0.17,
        h * 0.225,
        w * 0.83,
        h * 0.36,
        Radius.circular(h * 0.0675),
      ),
      Paint()..color = const Color(0xFFD6D7DC),
    );
    final glass = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1, w * 0.022)
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFFFFFFF);
    canvas.drawCircle(Offset(w * 0.255, h * 0.287), w * 0.027, glass);
    canvas.drawLine(
      Offset(w * 0.276, h * 0.308),
      Offset(w * 0.295, h * 0.327),
      glass,
    );
    final cell = w * 0.155;
    final gap = w * 0.075;
    final left = (w - cell * 3 - gap * 2) / 2;
    final top = h * 0.455;
    final square = Radius.circular(cell * 0.30);
    for (var i = 0; i < _tints.length; i++) {
      final col = i % 3;
      final row = i ~/ 3;
      canvas.drawRRect(
        RRect.fromLTRBR(
          left + col * (cell + gap),
          top + row * (cell + gap),
          left + col * (cell + gap) + cell,
          top + row * (cell + gap) + cell,
          square,
        ),
        Paint()..color = _tints[i],
      );
    }
    if (pressed) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, w, h),
        Paint()..color = const Color(0x1F000000),
      );
    }
    canvas.restore();
    canvas.drawRRect(
      tile,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, w * 0.012)
        ..color = const Color(0x14000000),
    );
  }

  @override
  bool shouldRepaint(_LaunchpadPainter old) => old.pressed != pressed;
}
