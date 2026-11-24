import 'dart:io';
import 'dart:math' as math;

import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/material.dart';

import 'dock_pile.dart';

/// The dock's own items drawn the way macOS draws its: full-bleed artwork
/// rather than the accent-tinted rounded tile the Denial look uses.
///
/// A folder becomes a blue folder carrying a pile of its newest files, the
/// trash becomes a wire can, and the launcher becomes the Launchpad grid.

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
            child: CustomPaint(painter: _FolderPainter(theme.accent)),
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
      child: CustomPaint(painter: _FolderPainter(context.shellTheme.accent)),
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

/// A macOS trash can: a tapered wire basket under its lid, holding paper once
/// it has anything in it.
class DockTrashIcon extends StatelessWidget {
  const DockTrashIcon({
    required this.size,
    this.pressed = false,
    this.full = false,
    super.key,
  });

  final double size;
  final bool pressed;

  /// Whether the can holds something. macOS draws an empty can as bare metal
  /// and a used one with paper inside it.
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
    final stroke = w * 0.038;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeJoin = StrokeJoin.round
      ..color = const Color(0xFF9B9EA6);
    final metal = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFF7F8FA), Color(0xFFDDE0E6)],
      ).createShader(Rect.fromLTWH(0, h * 0.18, w, h * 0.65));

    final lid = RRect.fromLTRBR(
      w * 0.21,
      h * 0.24,
      w * 0.79,
      h * 0.31,
      Radius.circular(w * 0.035),
    );
    final handle = RRect.fromLTRBR(
      w * 0.41,
      h * 0.17,
      w * 0.59,
      h * 0.245,
      Radius.circular(w * 0.03),
    );
    canvas.drawRRect(handle, metal);
    canvas.drawRRect(handle, line);
    canvas.drawRRect(lid, metal);
    canvas.drawRRect(lid, line);

    final body = Path()
      ..moveTo(w * 0.265, h * 0.325)
      ..lineTo(w * 0.735, h * 0.325)
      ..lineTo(w * 0.700, h * 0.78)
      ..quadraticBezierTo(w * 0.697, h * 0.845, w * 0.645, h * 0.845)
      ..lineTo(w * 0.355, h * 0.845)
      ..quadraticBezierTo(w * 0.303, h * 0.845, w * 0.300, h * 0.78)
      ..close();
    canvas.drawPath(body, metal);
    canvas.drawPath(body, line);

    if (full) {
      // Paper seen through the wire: two sheets, the nearer one paler, both
      // clipped to the basket so nothing spills past the wire.
      canvas.save();
      canvas.clipPath(body);
      final back = Path()
        ..moveTo(w * 0.32, h * 0.62)
        ..lineTo(w * 0.46, h * 0.44)
        ..lineTo(w * 0.58, h * 0.58)
        ..lineTo(w * 0.70, h * 0.40)
        ..lineTo(w * 0.74, h * 0.86)
        ..lineTo(w * 0.30, h * 0.86)
        ..close();
      canvas.drawPath(back, Paint()..color = const Color(0xFFF4F1EA));
      final front = Path()
        ..moveTo(w * 0.36, h * 0.86)
        ..lineTo(w * 0.42, h * 0.56)
        ..lineTo(w * 0.54, h * 0.70)
        ..lineTo(w * 0.62, h * 0.52)
        ..lineTo(w * 0.66, h * 0.86)
        ..close();
      canvas.drawPath(front, Paint()..color = const Color(0xFFFFFFFF));
      canvas.drawPath(
        front,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke * 0.6
          ..color = const Color(0xFFD8D3C8),
      );
      canvas.restore();
    }

    final rib = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke * 0.8
      ..color = const Color(0xFFB4B7BE)
      ..strokeCap = StrokeCap.round;
    for (final x in const [0.395, 0.5, 0.605]) {
      canvas.drawLine(
        Offset(w * x, h * 0.39),
        Offset(w * (0.5 + (x - 0.5) * 0.90), h * 0.78),
        rib,
      );
    }
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

/// The Launchpad grid: nine tinted squares on a pale tile.
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
    Color(0xFFFF9F0A),
    Color(0xFFFF375F),
    Color(0xFFBF5AF2),
    Color(0xFF40C8E0),
    Color(0xFFFFD60A),
    Color(0xFFFF6B3D),
    Color(0xFF5E5CE6),
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
    final cell = w * 0.185;
    final gap = w * 0.055;
    final block = cell * 3 + gap * 2;
    final left = (w - block) / 2;
    final top = (h - block) / 2;
    final square = Radius.circular(cell * 0.30);
    for (var i = 0; i < 9; i++) {
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
