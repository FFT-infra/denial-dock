import 'package:flutter/material.dart';

import 'dock_settings.dart' show DockIconMode;

/// The tinted mode's colour: a stored `#rrggbb`, or the shell accent when the
/// setting is empty.
Color dockTintColor(String? stored, Color accent) {
  if (stored == null || stored.length != 7 || !stored.startsWith('#')) {
    return accent;
  }
  final value = int.tryParse(stored.substring(1), radix: 16);
  return value == null ? accent : Color(0xFF000000 | value);
}

/// Tinted mode as a colour matrix: luminance drives a black-to-accent ramp.
/// A matrix runs in the raster shader, while [BlendMode.color] needs a
/// saveLayer with an advanced blend per icon and stalled the compositor.
List<double> _tintMatrix(Color accent) {
  const lr = 0.2126, lg = 0.7152, lb = 0.0722;
  return <double>[
    lr * accent.r,
    lg * accent.r,
    lb * accent.r,
    0,
    0,
    lr * accent.g,
    lg * accent.g,
    lb * accent.g,
    0,
    0,
    lr * accent.b,
    lg * accent.b,
    lb * accent.b,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ];
}

/// Paints a host-provided application icon in the configured mode. The host
/// owns the texture; this only filters what it draws.
class DockIcon extends StatelessWidget {
  const DockIcon({
    required this.mode,
    required this.child,
    this.opacity = 1.0,
    this.accent = const Color(0xFF000000),
    super.key,
  });

  final DockIconMode mode;
  final Widget child;

  /// Strength of the filtered modes; colour icons stay opaque, as in the
  /// reference dock.
  final double opacity;

  /// Colour the tinted mode multiplies through the icon's luminance.
  final Color accent;

  @override
  Widget build(BuildContext context) {
    if (mode == DockIconMode.color) return child;
    return Opacity(
      opacity: opacity,
      child: switch (mode) {
        DockIconMode.color => child,
        DockIconMode.grayscale => ColorFiltered(
          colorFilter: const ColorFilter.matrix(<double>[
            0.2126,
            0.7152,
            0.0722,
            0,
            0,
            0.2126,
            0.7152,
            0.0722,
            0,
            0,
            0.2126,
            0.7152,
            0.0722,
            0,
            0,
            0,
            0,
            0,
            1,
            0,
          ]),
          child: child,
        ),
        DockIconMode.tinted => ColorFiltered(
          colorFilter: ColorFilter.matrix(_tintMatrix(accent)),
          child: child,
        ),
      },
    );
  }
}
