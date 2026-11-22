import 'package:flutter/widgets.dart';

/// Type for the menu bar and its panels.
///
/// macOS sets its interface in SF Pro. Inter is the closest open metric match
/// and is vendored under `assets/`, so the bar keeps SF Pro's proportions
/// without shipping Apple's font. Sizes follow the HIG: 13 pt body, 11 pt
/// minimum [S4]; the active app's name is bold [S2]. The SDK's own
/// `systemBarValue` is JetBrains Mono, which is why the bar cannot use it.
abstract final class BarType {
  static const String _family = 'Inter';
  static const String _package = 'denial_topbar';
  static const List<String> _fallback = <String>[
    'Source Han Sans CN',
    'Noto Sans CJK SC',
  ];

  static TextStyle _style(double size, FontWeight weight) => TextStyle(
    fontFamily: _family,
    package: _package,
    fontFamilyFallback: _fallback,
    fontSize: size,
    fontWeight: weight,
    height: 1.2,
    letterSpacing: -0.1,
    leadingDistribution: TextLeadingDistribution.even,
    decoration: TextDecoration.none,
  );

  /// A menu bar title: 13 pt regular.
  static TextStyle get item => _style(13, FontWeight.w400);

  /// The active app's name: 13 pt bold, per the HIG.
  static TextStyle get appName => _style(13, FontWeight.w600);

  /// The clock: 13 pt medium with fixed-advance digits so the row never
  /// jitters as the minute changes.
  static TextStyle get clock => _style(
    13,
    FontWeight.w500,
  ).copyWith(fontFeatures: const <FontFeature>[FontFeature.tabularFigures()]);

  /// A row inside a menu.
  static TextStyle get menuRow => _style(13, FontWeight.w400);

  /// A menu row's shortcut column.
  static TextStyle get shortcut => _style(12, FontWeight.w400);

  /// Secondary text: dates, detail lines, 11 pt.
  static TextStyle get caption => _style(11, FontWeight.w400);

  /// A panel or card title.
  static TextStyle get title => _style(13, FontWeight.w600);

  /// A card's main value (a network name, a track title).
  static TextStyle get value => _style(13, FontWeight.w500);

  /// A small label under an icon in Control Centre.
  static TextStyle get cellLabel => _style(10, FontWeight.w400);

  /// The island's compact label.
  static TextStyle get islandLabel => _style(12, FontWeight.w500);

  /// The island's expanded title.
  static TextStyle get islandTitle => _style(14, FontWeight.w600);

  /// The island's expanded caption.
  static TextStyle get islandCaption => _style(11, FontWeight.w400);

  /// Numeric display inside a panel.
  static TextStyle get display => _style(26, FontWeight.w600);
}
