import 'dart:math' as math;

import 'package:denial_flutter_sdk/theme.dart';
import 'package:denial_shell_kit/kit_glass.dart' show kitToneColor;
import 'package:denial_shell_kit/kit_material.dart';
import 'package:denial_shell_kit/kit_style.dart';
import 'package:flutter/widgets.dart';

import '../bar_tokens.dart';

/// What the island is made of in the look in force: its body, the ink on
/// it, its line and its corners. Everything the island and its cards draw
/// takes its colours and radii from here, and this takes them from the
/// look's own fields and its table of materials, so a new look needs no
/// change to the island.
///
/// - A look that is glass elsewhere keeps the island a black body: it is
///   the one thing on the bar that is not glass. A liquid look tints that
///   black with its accent and rims it in the accent.
/// - A look that fills its panels solid fills the island like a panel,
///   with the panel's line around it at the look's own width, and casts
///   the look's share of shadow.
/// - Corners scale with the look, down to square.
@immutable
class IslandSkin {
  const IslandSkin({
    required this.style,
    required this.fill,
    required this.ink,
    required this.dim,
    required this.faint,
    required this.plate,
    required this.edge,
    required this.edgeWidth,
    required this.shadow,
    required this.accent,
    required this.onAccent,
    required this.controlLine,
    required this.pours,
  });

  /// The island before any theme is known: black, white ink, no accent.
  static const IslandSkin plain = IslandSkin(
    style: KitStyle.mac,
    fill: Color(BarTokens.islandFill),
    ink: Color(0xffffffff),
    dim: Color(0x99ffffff),
    faint: Color(0x33ffffff),
    plate: Color(0x29ffffff),
    edge: Color(0x1fffffff),
    edgeWidth: 0.6,
    shadow: 1,
    accent: Color(0xffffffff),
    onAccent: Color(0xff000000),
    controlLine: null,
    pours: false,
  );

  factory IslandSkin.resolve(
    KitStyle style,
    ShellThemeData theme, {
    bool dark = true,
  }) {
    final accent = style.accent(theme);
    const black = Color(BarTokens.islandFill);
    final Color fill;
    final Color ink;
    final Color edge;
    final double edgeWidth;
    if (style.look.opaque) {
      // A panel of this look, as its table of materials fills and lines it.
      final panel = style.materials.tier(KitTier.popover).of(dark: dark);
      fill = kitToneColor(panel.fill, theme, style).withValues(alpha: 1);
      ink = theme.colors.textPrimary;
      final line = panel.inner ?? panel.outer;
      edge = line == null
          ? style.border(theme)
          : kitToneColor(line.tone, theme, style);
      edgeWidth = line?.width ?? style.borderWidth;
    } else {
      fill = style.liquid ? Color.lerp(black, accent, 0.09)! : black;
      ink = const Color(0xffffffff);
      edge = style.liquid
          ? accent.withValues(alpha: 0.42)
          : const Color(0x1fffffff);
      edgeWidth = style.liquid ? 1 : 0.6;
    }
    return IslandSkin(
      style: style,
      fill: fill,
      ink: ink,
      dim: ink.withValues(alpha: 0.6),
      faint: ink.withValues(alpha: 0.2),
      plate: ink.withValues(alpha: style.flat ? 0.08 : 0.16),
      edge: edge,
      edgeWidth: edgeWidth,
      shadow: style.shadow,
      accent: accent,
      onAccent: style.onAccent(theme),
      controlLine: style.flat ? ink.withValues(alpha: 0.28) : null,
      pours: style.fixedAccent == null,
    );
  }

  static IslandSkin of(BuildContext context) {
    final theme = context.shellTheme;
    return IslandSkin.resolve(
      KitStyle.of(context),
      theme,
      dark: theme.brightness == Brightness.dark,
    );
  }

  final KitStyle style;

  /// The body.
  final Color fill;

  /// Text and glyphs on the body, and their quieter second voice.
  final Color ink;
  final Color dim;

  /// An empty track: a level bar's groove, a ring's unfilled part.
  final Color faint;

  /// The plate under a round control.
  final Color plate;

  /// The line around the body.
  final Color edge;
  final double edgeWidth;

  /// How much of its shadow the open card casts, 0 to 1.
  final double shadow;

  final Color accent;
  final Color onAccent;

  /// The thin line around a control where the look's controls are flat.
  final Color? controlLine;

  /// Whether the look pours its one accent into every control; see
  /// [KitStyle.plate].
  final bool pours;

  /// Whether content may blur as it comes and goes. A look with no blur
  /// behind its panels has none inside its island either.
  bool get blurs => style.glassy;

  /// The resting pill's width at [height].
  double rest(double height) => height * style.islandAspect;

  /// The one place a corner of the island comes from. [natural] is the
  /// radius the design asks for and [extent] the shorter side it rounds;
  /// the look scales it, and a square look squares it.
  double corner(double natural, double extent) =>
      math.min(style.corner(natural), extent / 2);

  /// The resting pill and a bubble: as round as the look lets a pill be.
  double pill(double height) => math.min(1.0, style.cornerScale) * height / 2;

  /// The outline of a round control [size] across.
  BorderRadius disc(double size) => BorderRadius.circular(pill(size));

  /// The colour an activity is drawn in, given the colour it has on its
  /// own: its ring, its digits, its bar. A look with one accent pours it
  /// into all of them, and keeps a colour only where it carries [meaning]
  /// (a recording, a charge).
  Color tone(Color own, {bool meaning = false}) =>
      pours && !meaning ? accent : own;

  @override
  bool operator ==(Object other) =>
      other is IslandSkin &&
      other.style == style &&
      other.fill == fill &&
      other.ink == ink &&
      other.edge == edge &&
      other.edgeWidth == edgeWidth &&
      other.shadow == shadow &&
      other.accent == accent &&
      other.onAccent == onAccent;

  @override
  int get hashCode =>
      Object.hash(style, fill, ink, edge, edgeWidth, shadow, accent, onAccent);
}
