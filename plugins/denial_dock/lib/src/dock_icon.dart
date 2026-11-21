import 'package:flutter/material.dart';

import 'dock_settings.dart' show DockIconMode;

/// Paints a host-provided application icon in the configured mode. The host
/// owns the texture; this only filters what it draws.
class DockIcon extends StatelessWidget {
  const DockIcon({
    required this.mode,
    required this.child,
    this.accent = const Color(0xFF000000),
    super.key,
  });

  final DockIconMode mode;
  final Widget child;

  /// Colour the tinted mode multiplies through the icon's luminance.
  final Color accent;

  @override
  Widget build(BuildContext context) => switch (mode) {
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
      colorFilter: ColorFilter.mode(accent, BlendMode.color),
      child: child,
    ),
  };
}
