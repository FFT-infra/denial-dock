/// How a spring is tuned: stiffness and damping ratio, as Denial's liquid
/// motion recipe writes them. A ratio of 1 is critically damped: the value
/// reaches its target without passing it.
class KitSpringTuning {
  const KitSpringTuning(this.stiffness, this.dampingRatio);

  final double stiffness;
  final double dampingRatio;
}

/// How one look moves, kept free of Flutter so the rules every look has to
/// keep run as an ordinary Dart test.
///
/// The rule the looks share: only a [liquid] look may pass its target. Every
/// spring of another look is critically damped or heavier, and a surface
/// going away never overshoots in any look.
class KitLookMotion {
  const KitLookMotion({
    required this.liquid,
    required this.panelGrow,
    required this.panelShrink,
    required this.pressTuning,
    this.switchTuning,
    this.pace = 1,
  });

  /// Denial: a popup stretches into its shape and a released control springs
  /// back past its size.
  static const KitLookMotion denial = KitLookMotion(
    liquid: true,
    panelGrow: KitSpringTuning(230, 0.6),
    panelShrink: KitSpringTuning(420, 1),
    pressTuning: KitSpringTuning(520, 0.42),
  );

  /// macOS: a short settle with no overshoot.
  static const KitLookMotion mac = KitLookMotion(
    liquid: false,
    panelGrow: KitSpringTuning(620, 1),
    panelShrink: KitSpringTuning(900, 1),
    pressTuning: KitSpringTuning(620, 1),
  );

  /// Soft: settles without a bounce.
  static const KitLookMotion soft = KitLookMotion(
    liquid: false,
    panelGrow: KitSpringTuning(520, 1),
    panelShrink: KitSpringTuning(800, 1),
    pressTuning: KitSpringTuning(620, 1),
    switchTuning: KitSpringTuning(620, 1),
  );

  /// Terminal: over at once.
  static const KitLookMotion terminal = KitLookMotion(
    liquid: false,
    panelGrow: KitSpringTuning(1100, 1),
    panelShrink: KitSpringTuning(1400, 1),
    pressTuning: KitSpringTuning(1000, 1),
    switchTuning: KitSpringTuning(1000, 1),
    pace: 1.6,
  );

  /// Every look's motion, in the order the looks are offered.
  static const List<KitLookMotion> presets = <KitLookMotion>[
    denial,
    mac,
    soft,
    terminal,
  ];

  /// Whether fills pour and bodies stretch, as Denial's own controls do.
  /// Only such a look may overshoot.
  final bool liquid;

  /// A popup growing into its shape, and going back.
  final KitSpringTuning panelGrow;
  final KitSpringTuning panelShrink;

  /// A control springing back after a press.
  final KitSpringTuning pressTuning;

  /// A switch's knob crossing over, when the look does not take the usual
  /// one for its kind; see [toggle].
  final KitSpringTuning? switchTuning;

  /// How much faster than written this look's timed transitions run.
  final double pace;

  /// A switch's knob crossing over: with a little life where the look is
  /// liquid, and dead-beat everywhere else.
  KitSpringTuning get toggle =>
      switchTuning ??
      (liquid
          ? const KitSpringTuning(520, 0.6)
          : const KitSpringTuning(620, 1));

  /// [tuning] as this look may run it: untouched where the look is liquid,
  /// and critically damped where it is not, so a spring written for Denial
  /// cannot bounce in a look that settles. A look with a pace of its own
  /// also takes its popup spring where that is stiffer, so a brisk look is
  /// never slower than its popups.
  KitSpringTuning settled(KitSpringTuning tuning) {
    if (liquid) return tuning;
    final stiffness = pace > 1 && panelGrow.stiffness > tuning.stiffness
        ? panelGrow.stiffness
        : tuning.stiffness;
    if (tuning.dampingRatio >= 1 && stiffness == tuning.stiffness) {
      return tuning;
    }
    return KitSpringTuning(
      stiffness,
      tuning.dampingRatio < 1 ? 1 : tuning.dampingRatio,
    );
  }
}
