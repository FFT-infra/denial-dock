import 'package:denial_shell_kit/kit_style.dart';
import 'package:flutter/widgets.dart';

/// Type for the menu bar and its panels.
///
/// shell27 draws the bar at 14 pt (menu titles, clock) and the dropdown at
/// 13 pt with a 12 pt shortcut column. The family comes from the look: the
/// shell's own; Inter, vendored under `assets/` so the macOS look keeps its
/// proportions without shipping SF Pro; or JetBrains Mono, which the SDK
/// bundles for its own system bar, for a look set in fixed-width type. The
/// fallback families carry Chinese under every one of them.
abstract final class BarType {
  static const List<String> _fallback = <String>[
    'Source Han Sans CN',
    'Noto Sans CJK SC',
  ];

  static TextStyle _style(
    double size,
    FontWeight weight, {
    double spacing = 0,
  }) => TextStyle(
    // Without a family the text takes the shell's own, from the default
    // text style it is built under.
    fontFamily: kitStyle.value.fontFamily,
    package: kitStyle.value.fontFamily == null
        ? null
        : kitStyle.value.fontPackage,
    fontFamilyFallback: _fallback,
    fontSize: size * kitStyle.value.fontScale,
    fontWeight: kitStyle.value.weight(weight),
    height: 1.2,
    letterSpacing: spacing,
    leadingDistribution: TextLeadingDistribution.even,
    decoration: TextDecoration.none,
  );

  /// The look's family and scale and nothing else, for text that keeps the
  /// line height of the text style it is built under.
  static TextStyle bare(double size, FontWeight weight) => TextStyle(
    fontFamily: kitStyle.value.fontFamily,
    package: kitStyle.value.fontFamily == null
        ? null
        : kitStyle.value.fontPackage,
    fontFamilyFallback: _fallback,
    fontSize: size * kitStyle.value.fontScale,
    fontWeight: kitStyle.value.weight(weight),
  );

  /// A menu bar title: shell27 `font.pixelSize: 14`.
  static TextStyle get item => _style(14, FontWeight.w400);

  /// The active app's name: 14 DemiBold, which is what shell27 sets and what
  /// the HIG requires of the app menu.
  static TextStyle get appName => _style(14, FontWeight.w600);

  /// The clock: 14 DemiBold with `letterSpacing: 0.1`, and tabular digits so
  /// the row never jitters as the minute changes.
  static TextStyle get clock => _style(
    14,
    FontWeight.w600,
    spacing: 0.1,
  ).copyWith(fontFeatures: const <FontFeature>[FontFeature.tabularFigures()]);

  /// A dropdown row: shell27 `font.pixelSize: 13`.
  static TextStyle get menuRow => _style(13, FontWeight.w400);

  /// A dropdown row's shortcut column: shell27 `font.pixelSize: 12`.
  static TextStyle get shortcut => _style(12, FontWeight.w400);

  /// Secondary text: dates, detail lines.
  static TextStyle get caption => _style(11, FontWeight.w400);

  /// A card or panel title.
  static TextStyle get title => _style(13, FontWeight.w600);

  /// A card's main value (a network name, a track title).
  static TextStyle get value => _style(13, FontWeight.w500);

  /// A small label under an icon in Control Centre.
  static TextStyle get cellLabel => _style(10, FontWeight.w400);

  /// The battery percentage in the bar: shell27 `font.pixelSize: 12`.
  static TextStyle get batteryPercent => _style(12, FontWeight.w400);

  /// A popover section heading: shell27 `12` DemiBold.
  static TextStyle get section => _style(12, FontWeight.w600);

  /// The island's compact label.
  static TextStyle get islandLabel => _style(12, FontWeight.w500);

  /// The island's expanded title.
  static TextStyle get islandTitle => _style(14, FontWeight.w600);

  /// The island's expanded caption.
  static TextStyle get islandCaption => _style(11, FontWeight.w400);

  /// Numeric display inside a panel.
  static TextStyle get display => _style(26, FontWeight.w600);
}
