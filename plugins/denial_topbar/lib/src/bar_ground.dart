import 'package:denial_flutter_sdk/effects.dart';
import 'package:flutter/widgets.dart';

import 'bar_settings.dart';
import 'bar_tokens.dart';

/// The strip behind the bar content.
///
/// macOS 27 draws no background by default: titles and status items sit
/// straight on the wallpaper, and the system picks black or white ink from
/// what is behind them [S30][S29]. Turning the background on adds a veil
/// tinted to the appearance, never to the wallpaper, which is what shell27's
/// `#1E1E1E` / `#F5F5F7` pair does. `glass` is the compositor's backdrop blur
/// for people who want the Tahoe look back.
///
/// With no veil at all the type can still land on a busy wallpaper, so a
/// short gradient feather sits under the strip exactly like shell27's
/// `barFeather`: 30% at the top edge fading to nothing 14 below.
class BarGroundLayer extends StatelessWidget {
  const BarGroundLayer({
    required this.settings,
    required this.borderRadius,
    required this.backdrop,
    required this.child,
    super.key,
  });

  final BarSettings settings;
  final BorderRadius borderRadius;

  /// Dominant wallpaper colour, used to pick the plate and the ink.
  final Color backdrop;
  final Widget child;

  static double luminanceOf(Color color) =>
      color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722;

  static bool isDark(Color color) =>
      luminanceOf(color) <= BarTokens.plateLuminanceThreshold;

  /// The veil matches the wallpaper's own lightness: a dark wallpaper gets
  /// the dark neutral, a light one the light neutral. shell27 `content`.
  static Color plateFor(Color backdrop) => isDark(backdrop)
      ? const Color(BarTokens.plateDark)
      : const Color(BarTokens.plateLight);

  /// The ink the type is drawn in.
  ///
  /// macOS flips black/white against what sits under the bar, so this reads
  /// the backdrop when there is no veil and the veil's own lightness when
  /// there is one.
  static Color inkFor(Color backdrop, BarSettings settings) {
    final dark = switch (settings.ground) {
      BarGround.none => isDark(backdrop),
      BarGround.plate || BarGround.glass => isDark(plateFor(backdrop)),
    };
    return dark ? const Color(0xffffffff) : const Color(0xff000000);
  }

  /// What the strip actually looks like, for callers that need to match it.
  static Color stripColour(Color backdrop, BarSettings settings) {
    final plate = plateFor(backdrop);
    return Color.lerp(backdrop, plate, settings.groundOpacity) ?? plate;
  }

  @override
  Widget build(BuildContext context) {
    final ground = settings.ground;
    final dark = isDark(plateFor(backdrop));

    Widget surface = child;
    if (ground == BarGround.plate) {
      surface = DecoratedBox(
        decoration: BoxDecoration(
          color: plateFor(backdrop).withValues(alpha: settings.groundOpacity),
          borderRadius: borderRadius,
          border: settings.hairline
              ? Border.all(
                  color: dark
                      ? const Color(0xffffffff).withValues(alpha: 0.12)
                      : const Color(0xff000000).withValues(alpha: 0.08),
                  width: 0.8,
                )
              : null,
        ),
        child: surface,
      );
    } else if (ground == BarGround.glass) {
      surface = ShellBackdropBlur(
        borderRadius: borderRadius,
        blendMode: BlendMode.srcOver,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: plateFor(backdrop).withValues(alpha: settings.groundOpacity),
            borderRadius: borderRadius,
            border: settings.hairline
                ? Border.all(
                    color: dark
                        ? const Color(0xffffffff).withValues(alpha: 0.12)
                        : const Color(0xff000000).withValues(alpha: 0.08),
                    width: 0.8,
                  )
                : null,
          ),
          child: surface,
        ),
      );
    }
    return surface;
  }
}

/// The soft fade shell27 paints when the bar is completely clear.
///
/// The tint is the veil colour, not the ink: a white wash sits under black
/// type and a black wash under white type, which is what shell27's `barFeather`
/// does. It is skipped whenever a veil already does that job.
class BarFeather extends StatelessWidget {
  const BarFeather({
    required this.tint,
    required this.height,
    required this.visible,
    super.key,
  });

  final Color tint;
  final double height;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    return IgnorePointer(
      child: SizedBox(
        height: height + 14,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                tint.withValues(alpha: 0.30),
                tint.withValues(alpha: 0.20),
                tint.withValues(alpha: 0.08),
                tint.withValues(alpha: 0.02),
                tint.withValues(alpha: 0),
              ],
              stops: const <double>[0.0, 0.35, 0.65, 0.85, 1.0],
            ),
          ),
        ),
      ),
    );
  }
}
