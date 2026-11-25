import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/widgets.dart';

import 'kit_glass.dart';
import 'kit_material.dart';
import 'kit_style.dart';

/// The card every popup of the dock and the top bar draws on: continuous
/// corners, backdrop blur, a hairline and one soft shadow, each as the look
/// in force has them.
class GlassCard extends StatelessWidget {
  const GlassCard({
    required this.radius,
    required this.child,
    this.fill,
    this.elevation = 1,
    this.minOpacity = 0,
    this.blurStrength = 1,
    this.fade,
    this.grouped = false,
    this.tier = KitTier.popover,
    super.key,
  });

  /// The corner radius at the shell's normal roundness; where the look
  /// follows the shell, the card scales it.
  final double radius;

  /// The panel colour unless given.
  final Color? fill;
  final double elevation;

  /// Floor for the fill's opacity. A window of settings sits over other
  /// windows and needs more than a menu does to keep its text readable.
  final double minOpacity;
  final double blurStrength;

  /// Fades the shadow, the backdrop and the content together, for a card
  /// that appears with its layer.
  final Animation<double>? fade;

  /// Shares one backdrop with the other grouped cards under the nearest
  /// [BackdropGroup], for cards that sit side by side and move together.
  /// Every ungrouped card reads the screen back for itself.
  final bool grouped;

  /// Which of the look's materials the card is made of.
  final KitTier tier;
  final Widget child;

  static Color fillOf(ShellThemeData theme, {double minOpacity = 0}) {
    final fill = theme.panelColor(theme.colors.panelBackground);
    return fill.a < minOpacity ? fill.withValues(alpha: minOpacity) : fill;
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final style = KitStyle.of(context);
    final material = kitMaterialOf(context, tier);
    return KitGlass(
      material: material,
      // A material with corners of its own keeps them.
      radius: style.radius(theme, material.radius ?? radius),
      // A material that brings its own fill keeps it, whatever the caller
      // mixed from the theme; one filled from the theme takes the caller's.
      fill: material.fill.fixed
          ? null
          : style.panelFill(fill ?? fillOf(theme, minOpacity: minOpacity)),
      minOpacity: minOpacity,
      elevation: elevation,
      blurScale: blurStrength,
      grouped: grouped,
      fade: fade,
      child: child,
    );
  }
}
