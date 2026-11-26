import 'dart:math' as math;

import 'package:denial_flutter_sdk/theme.dart';
import 'package:denial_shell_kit/kit_style.dart';
import 'package:flutter/widgets.dart';

import '../bar_tokens.dart';

/// What the island is made of in the look in force: its body, the ink on
/// it, its line and its corners. Everything the island and its cards draw
/// takes its colours and radii from here.
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
  });

  factory IslandSkin.resolve(KitStyle style, ShellThemeData theme) =>
      IslandSkin(
        style: style,
        fill: const Color(BarTokens.islandFill),
        ink: const Color(0xffffffff),
        dim: const Color(0x99ffffff),
        faint: const Color(0x33ffffff),
        plate: const Color(0x29ffffff),
        edge: const Color(0x1fffffff),
        edgeWidth: 0.6,
        shadow: 1,
        accent: style.accent(theme),
      );

  static IslandSkin of(BuildContext context) =>
      IslandSkin.resolve(KitStyle.of(context), context.shellTheme);

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

  /// The one place a corner of the island comes from. [natural] is the
  /// radius the design asks for and [extent] the shorter side it rounds.
  double corner(double natural, double extent) =>
      math.min(natural, extent / 2);

  /// The resting pill and a bubble: as round as their height allows.
  double pill(double height) => corner(double.infinity, height);

  /// Something set inside an outline of [outer], [inset] from its edge.
  double nested(double outer, double inset) => math.max(4, outer - inset);

  /// The outline of a round control [size] across.
  BorderRadius disc(double size) => style.disc(size);

  /// The colour an activity is drawn in, given the colour it has on its
  /// own: its ring, its digits, its button.
  Color tone(Color own) => own;

  @override
  bool operator ==(Object other) =>
      other is IslandSkin &&
      other.style == style &&
      other.fill == fill &&
      other.ink == ink &&
      other.dim == dim &&
      other.faint == faint &&
      other.plate == plate &&
      other.edge == edge &&
      other.edgeWidth == edgeWidth &&
      other.shadow == shadow &&
      other.accent == accent;

  @override
  int get hashCode =>
      Object.hash(style, fill, ink, dim, faint, plate, edge, edgeWidth, shadow);
}
