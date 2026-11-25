import 'dock_look.dart';
import 'dock_settings.dart';

/// How the name over an icon is drawn.
enum DockLabelShape {
  /// A pill with a tail pointing at its icon.
  bubble,

  /// A pill with no tail, as macOS draws it.
  capsule,

  /// A plate with the look's own corners and line, and no tail.
  tag,
}

/// What a look of the shell gives the dock besides its capsule: how large the
/// icons are and how they sit on the plate, how a running application is
/// marked, what the pointer does to an icon, and the measures of the label,
/// the divider and the menus. One immutable value per look, so a look is
/// data and nothing in the dock asks which look is in force.
///
/// What the user changed is kept as overrides in the same map as the
/// capsule's, see [DockLook], so switching the look moves every value the
/// user left alone and keeps the ones they set.
///
/// The macOS values are measured on a 2x capture of the real Dock: a 65 pt
/// plate, icon bodies 36 pt across on a 48.6 pt pitch and 14.5 pt from every
/// edge of the plate, a 4 pt marker centred 6 pt above the plate's edge, and
/// a 1 pt divider 47 pt long that sets its two neighbours 22.5 pt further
/// apart.
///
/// No Flutter import, so the rules run as an ordinary Dart test.
class DockMetrics {
  const DockMetrics({
    required this.iconSize,
    required this.padding,
    required this.gap,
    required this.endInset,
    required this.magnify,
    required this.magnifyAmount,
    required this.indicator,
    required this.markerSize,
    required this.markerLength,
    required this.markerFrontStretch,
    required this.markerInset,
    required this.markerAlpha,
    required this.markerAlphaLight,
    required this.markerFrontAlpha,
    required this.highlight,
    required this.highlightOutline,
    required this.activePlate,
    required this.pressScale,
    required this.hop,
    required this.dividerSpan,
    required this.dividerLength,
    required this.dividerAlpha,
    required this.dividerAlphaLight,
    required this.label,
    required this.labelGap,
    required this.labelFontSize,
    required this.labelWeight,
    required this.menuWidth,
    required this.menuRowHeight,
    required this.menuRadius,
    required this.menuRowRadius,
    required this.menuSeparator,
    this.taskTitles = false,
    this.taskWidth = 168,
    this.scaleSpacing = false,
    this.menuTail = false,
    double? baseIconSize,
  }) : baseIconSize = baseIconSize ?? iconSize;

  /// Denial's own dock: large icons close to the plate's edge, a wave of
  /// magnification, and a drop of the accent under the application in front
  /// that stretches as it arrives.
  static const DockMetrics denial = DockMetrics(
    iconSize: 48,
    padding: 5,
    gap: 8,
    endInset: 5,
    magnify: true,
    magnifyAmount: 0.6,
    indicator: DockIndicatorStyle.dot,
    markerSize: 5,
    markerLength: 5,
    markerFrontStretch: 2.2,
    markerInset: 2.5,
    markerAlpha: 0.55,
    markerAlphaLight: 0.55,
    markerFrontAlpha: null,
    highlight: false,
    highlightOutline: false,
    activePlate: false,
    pressScale: 0.92,
    hop: true,
    dividerSpan: 1,
    dividerLength: 0.43,
    dividerAlpha: null,
    dividerAlphaLight: null,
    label: DockLabelShape.bubble,
    labelGap: 6,
    labelFontSize: null,
    labelWeight: 600,
    menuWidth: 248,
    menuRowHeight: 30,
    menuRadius: 13,
    menuRowRadius: 8,
    menuSeparator: 11,
    menuTail: true,
  );

  /// The macOS Dock, as measured.
  static const DockMetrics mac = DockMetrics(
    iconSize: 36,
    padding: 14.5,
    gap: 12.5,
    endInset: 0,
    scaleSpacing: true,
    magnify: true,
    magnifyAmount: 0.6,
    indicator: DockIndicatorStyle.dot,
    markerSize: 4,
    markerLength: 4,
    markerFrontStretch: 1,
    markerInset: 6,
    markerAlpha: 0.5,
    markerAlphaLight: 0.6,
    markerFrontAlpha: null,
    highlight: false,
    highlightOutline: false,
    activePlate: false,
    pressScale: 1,
    hop: true,
    dividerSpan: 10.5,
    dividerLength: 0.72,
    dividerAlpha: 0.26,
    dividerAlphaLight: 0.3,
    label: DockLabelShape.capsule,
    labelGap: 8,
    labelFontSize: 13,
    labelWeight: 500,
    menuWidth: 220,
    menuRowHeight: 24,
    menuRadius: 11,
    menuRowRadius: 5,
    menuSeparator: 11,
  );

  /// A solid rounded dock: nothing grows, the icon under the pointer gets a
  /// quiet plate, and a short capsule under a running application widens
  /// and takes the accent when it comes to the front.
  static const DockMetrics soft = DockMetrics(
    iconSize: 44,
    padding: 7,
    gap: 6,
    endInset: 1,
    magnify: false,
    magnifyAmount: 0.4,
    indicator: DockIndicatorStyle.pill,
    markerSize: 3,
    markerLength: 6,
    markerFrontStretch: 2.6,
    markerInset: 3.5,
    markerAlpha: 0.45,
    markerAlphaLight: 0.45,
    markerFrontAlpha: 1,
    highlight: true,
    highlightOutline: false,
    activePlate: false,
    pressScale: 0.96,
    hop: true,
    dividerSpan: 1,
    dividerLength: 0.5,
    dividerAlpha: null,
    dividerAlphaLight: null,
    label: DockLabelShape.tag,
    labelGap: 8,
    labelFontSize: 12,
    labelWeight: 500,
    menuWidth: 240,
    menuRowHeight: 30,
    menuRadius: 12,
    menuRowRadius: 8,
    menuSeparator: 9,
  );

  /// A terminal's dock: a tight square row, an underline for what runs, an
  /// outline around the icon under the pointer, and nothing that grows or
  /// hops.
  static const DockMetrics terminal = DockMetrics(
    iconSize: 40,
    padding: 7,
    gap: 6,
    endInset: 0,
    magnify: false,
    magnifyAmount: 0.3,
    indicator: DockIndicatorStyle.line,
    markerSize: 2,
    markerLength: 2,
    markerFrontStretch: 1,
    markerInset: 4,
    markerAlpha: 0.5,
    markerAlphaLight: 0.5,
    markerFrontAlpha: 1,
    highlight: true,
    highlightOutline: true,
    activePlate: false,
    pressScale: 1,
    hop: false,
    dividerSpan: 1,
    dividerLength: 0.6,
    dividerAlpha: null,
    dividerAlphaLight: null,
    label: DockLabelShape.tag,
    labelGap: 8,
    labelFontSize: 12,
    labelWeight: 500,
    menuWidth: 240,
    menuRowHeight: 26,
    menuRadius: 0,
    menuRowRadius: 0,
    menuSeparator: 9,
  );

  /// Every look's metrics by the look's id.
  static const Map<String, DockMetrics> presets = <String, DockMetrics>{
    'denial': denial,
    'mac': mac,
    'soft': soft,
    'terminal': terminal,
  };

  /// The metrics for the shell look called [styleId]; Denial's for any
  /// other.
  static DockMetrics preset(String? styleId) => presets[styleId] ?? denial;

  // The ranges the settings offer. A value from a file is clamped into them.
  static const double minIconSize = 32, maxIconSize = 72;
  static const double minMagnifyAmount = 0, maxMagnifyAmount = 1;

  /// The smallest an icon is drawn when the row has to shrink to fit.
  static const double fitFloor = 20;

  /// The keys the overrides are stored under, in the capsule's map.
  static const String iconSizeKey = 'iconSize';
  static const String magnifyKey = 'magnify';
  static const String magnifyAmountKey = 'magnifyAmount';
  static const String indicatorKey = 'indicator';
  static const String highlightKey = 'highlight';
  static const String taskTitlesKey = 'taskTitles';

  /// Edge of an icon before magnification.
  final double iconSize;

  /// Space between the plate's long edges and the icons.
  final double padding;

  /// Space between two icons.
  final double gap;

  /// How much looser the two ends of the row are than [padding].
  final double endInset;

  /// Whether icons grow under the pointer, and by how much of the dock's
  /// largest scale.
  final bool magnify;
  final double magnifyAmount;

  /// How a running application is marked.
  final DockIndicatorStyle indicator;

  /// Thickness of the marker, and the length of one dot or pill of it.
  final double markerSize;
  final double markerLength;

  /// How many times longer the marker of the application in front is.
  final double markerFrontStretch;

  /// From the plate's edge to the middle of the marker. The marker rests on
  /// the plate: it does not follow an icon that grows, lifts or hops.
  final double markerInset;

  /// Opacity of the marker's ink on a dark and on a light plate, and under
  /// the application in front.
  final double markerAlpha;
  final double markerAlphaLight;

  /// Null draws the application in front like any other, as macOS does.
  final double? markerFrontAlpha;

  /// Whether the icon under the pointer gets a plate, and whether that
  /// plate is a line in the accent rather than a fill.
  final bool highlight;
  final bool highlightOutline;

  /// Whether the application in front keeps a plate over its whole cell.
  final bool activePlate;

  /// How far an icon shrinks while it is held down; 1 leaves it alone.
  final double pressScale;

  /// Whether a launch may hop. A look that does not hop pulses instead.
  final bool hop;

  /// The room a divider takes along the row, the line's length as a share
  /// of the plate's thickness, and the opacity of its ink on a dark and on
  /// a light plate. No opacity draws the theme's hairline.
  final double dividerSpan;
  final double dividerLength;
  final double? dividerAlpha;
  final double? dividerAlphaLight;

  final DockLabelShape label;

  /// From the icon to its label.
  final double labelGap;

  /// The label's type size; null scales it with the icon.
  final double? labelFontSize;

  /// The label's weight, as a CSS number.
  final int labelWeight;

  final double menuWidth;
  final double menuRowHeight;
  final double menuRadius;
  final double menuRowRadius;

  /// The height a separator takes in a menu, its line included.
  final double menuSeparator;

  /// Whether an application on a bar shows its window's title beside its
  /// icon, and how wide such a button may get.
  final bool taskTitles;
  final double taskWidth;

  /// Whether the spacing follows the icons: the plate, the gaps and the
  /// divider all grow and shrink with the icon size, as the macOS Dock
  /// does. [padding], [gap] and the rest are then the values at
  /// [baseIconSize], the size the look itself gives.
  final bool scaleSpacing;
  final double baseIconSize;

  /// Whether a menu points at what it belongs to with a tail.
  final bool menuTail;

  /// How much larger than the look's own the spacing is at [size].
  double spacingScale(double size) => scaleSpacing ? size / baseIconSize : 1;

  /// The marker's opacity on a plate of the given darkness.
  double markerAlphaFor({required bool dark, bool front = false}) =>
      (front ? markerFrontAlpha : null) ??
      (dark ? markerAlpha : markerAlphaLight);

  /// The divider's opacity on a plate of the given darkness, or null for
  /// the theme's hairline.
  double? dividerAlphaFor({required bool dark}) =>
      dark ? dividerAlpha : dividerAlphaLight;

  /// How large icons get under the pointer: 1 when nothing grows.
  double get maxScale =>
      magnify ? 1.0 + (DockSettings.maxScale - 1.0) * magnifyAmount : 1.0;

  /// These metrics for a dock of [shape]. A dock lying along its whole edge
  /// is a taskbar: nothing grows, the cell under the pointer lights up, the
  /// application in front keeps its cell lit, and a bar on the screen edge
  /// with one piece per window marks what runs.
  DockMetrics shaped(DockShape shape) => shape == DockShape.bar
      ? _copy(
          magnify: false,
          highlight: true,
          activePlate: true,
          indicator: DockIndicatorStyle.segments,
          markerSize: markerSize < 3 ? markerSize : 3,
          markerInset: (markerSize < 3 ? markerSize : 3) / 2,
        )
      : this;

  /// [base] with the overrides a settings file holds. A missing key, or a
  /// value of the wrong kind, keeps the preset's; a number is clamped into
  /// its range.
  static DockMetrics resolve(DockMetrics base, Map<String, Object?> overrides) {
    final size = overrides[iconSizeKey];
    final amount = overrides[magnifyAmountKey];
    final magnify = overrides[magnifyKey];
    final highlight = overrides[highlightKey];
    final titles = overrides[taskTitlesKey];
    final indicator = overrides[indicatorKey];
    return base._copy(
      iconSize: size is num && size.isFinite
          ? size.toDouble().clamp(minIconSize, maxIconSize).toDouble()
          : null,
      magnify: magnify is bool ? magnify : null,
      magnifyAmount: amount is num && amount.isFinite
          ? amount.toDouble().clamp(minMagnifyAmount, maxMagnifyAmount).toDouble()
          : null,
      indicator: indicator is String
          ? DockIndicatorStyle.parse(indicator, fallback: base.indicator)
          : null,
      highlight: highlight is bool ? highlight : null,
      taskTitles: titles is bool ? titles : null,
    );
  }

  DockMetrics _copy({
    double? iconSize,
    bool? magnify,
    double? magnifyAmount,
    DockIndicatorStyle? indicator,
    double? markerSize,
    double? markerInset,
    bool? highlight,
    bool? activePlate,
    bool? taskTitles,
  }) => DockMetrics(
    iconSize: iconSize ?? this.iconSize,
    padding: padding,
    gap: gap,
    endInset: endInset,
    magnify: magnify ?? this.magnify,
    magnifyAmount: magnifyAmount ?? this.magnifyAmount,
    indicator: indicator ?? this.indicator,
    markerSize: markerSize ?? this.markerSize,
    markerLength: markerLength,
    markerFrontStretch: markerFrontStretch,
    markerInset: markerInset ?? this.markerInset,
    markerAlpha: markerAlpha,
    markerAlphaLight: markerAlphaLight,
    markerFrontAlpha: markerFrontAlpha,
    highlight: highlight ?? this.highlight,
    highlightOutline: highlightOutline,
    activePlate: activePlate ?? this.activePlate,
    pressScale: pressScale,
    hop: hop,
    dividerSpan: dividerSpan,
    dividerLength: dividerLength,
    dividerAlpha: dividerAlpha,
    dividerAlphaLight: dividerAlphaLight,
    label: label,
    labelGap: labelGap,
    labelFontSize: labelFontSize,
    labelWeight: labelWeight,
    menuWidth: menuWidth,
    menuRowHeight: menuRowHeight,
    menuRadius: menuRadius,
    menuRowRadius: menuRowRadius,
    menuSeparator: menuSeparator,
    taskTitles: taskTitles ?? this.taskTitles,
    taskWidth: taskWidth,
    scaleSpacing: scaleSpacing,
    menuTail: menuTail,
    baseIconSize: baseIconSize,
  );
}
