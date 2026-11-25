import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/widgets.dart';

import 'kit_material.dart';
import 'kit_motion_pace.dart';
import 'kit_store.dart';
import 'shell_preset.dart';

/// How a spring is tuned: stiffness and damping ratio, as Denial's liquid
/// motion recipe writes them.
@immutable
class KitSpringTuning {
  const KitSpringTuning(this.stiffness, this.dampingRatio);

  final double stiffness;
  final double dampingRatio;
}

/// One look for the dock and the top bar: where colour, type and corners come
/// from, and how things move. A preset is one constant of this class, so a
/// new look is new data and no widget changes.
@immutable
class KitStyle {
  const KitStyle({
    required this.id,
    required this.fixedAccent,
    required this.fontFamily,
    required this.scaleCorners,
    required this.liquid,
    required this.panelGrow,
    required this.panelShrink,
    required this.panelBead,
    required this.pressTuning,
    required this.accentMenuRows,
    this.label = '',
    this.fontPackage,
    this.fontScale = 1,
    this.cornerScale = 1,
    this.borderWidth = 1,
    this.borderFromAccent = false,
    this.opaque = false,
    this.shadow = 1,
    this.switchTuning,
    this.pace = 1,
    this.materials = KitMaterials.shell,
  });

  /// Denial's own material: the wallpaper's accent, the shell's font and
  /// corner scale, and liquid motion. A popup is born as a bead and stretches
  /// into its shape, a switch fills as the accent pours in.
  static const KitStyle denial = KitStyle(
    id: 'denial',
    label: 'Denial',
    fixedAccent: null,
    fontFamily: null,
    scaleCorners: true,
    liquid: true,
    panelGrow: KitSpringTuning(230, 0.6),
    panelShrink: KitSpringTuning(420, 1),
    panelBead: Size(0.9, 0.72),
    pressTuning: KitSpringTuning(520, 0.42),
    accentMenuRows: false,
  );

  /// macOS: the system blue, Inter, fixed corners, and a short settle with
  /// no overshoot.
  static const KitStyle mac = KitStyle(
    id: 'mac',
    label: 'macOS',
    fixedAccent: Color(0xff0a84ff),
    fontFamily: 'Inter',
    fontPackage: 'denial_topbar',
    scaleCorners: false,
    liquid: false,
    panelGrow: KitSpringTuning(620, 1),
    panelShrink: KitSpringTuning(900, 1),
    panelBead: Size(0.96, 0.96),
    pressTuning: KitSpringTuning(620, 0.7),
    accentMenuRows: true,
    materials: KitMaterials.mac,
  );

  /// Solid rounded panels: the shell's accent and font, tighter corners, no
  /// blur behind a panel and a lighter shadow under it, and motion that
  /// settles without a bounce.
  static const KitStyle soft = KitStyle(
    id: 'soft',
    label: 'Soft',
    fixedAccent: null,
    fontFamily: null,
    scaleCorners: true,
    liquid: false,
    panelGrow: KitSpringTuning(520, 1),
    panelShrink: KitSpringTuning(800, 1),
    panelBead: Size(0.94, 0.94),
    pressTuning: KitSpringTuning(620, 0.8),
    accentMenuRows: false,
    cornerScale: 0.6,
    opaque: true,
    shadow: 0.6,
    switchTuning: KitSpringTuning(620, 1),
  );

  /// A terminal's look: square corners, a 2 px line in the accent around
  /// every panel, opaque fills with no blur and no shadow, fixed-width type,
  /// and motion that is over at once.
  static const KitStyle terminal = KitStyle(
    id: 'terminal',
    label: 'Terminal',
    fixedAccent: null,
    fontFamily: 'JetBrainsMono',
    fontPackage: 'denial_flutter_sdk',
    fontScale: 0.93,
    scaleCorners: false,
    liquid: false,
    panelGrow: KitSpringTuning(1100, 1),
    panelShrink: KitSpringTuning(1400, 1),
    panelBead: Size(0.98, 0.98),
    pressTuning: KitSpringTuning(1000, 1),
    accentMenuRows: true,
    cornerScale: 0,
    borderWidth: 2,
    borderFromAccent: true,
    opaque: true,
    shadow: 0,
    switchTuning: KitSpringTuning(1000, 1),
    pace: 1.6,
  );

  static const List<KitStyle> presets = <KitStyle>[denial, mac, soft, terminal];

  static KitStyle byId(String? id) =>
      presets.firstWhere((style) => style.id == id, orElse: () => denial);

  final String id;

  /// The look's name, as its makers write it.
  final String label;

  /// The package that carries [fontFamily].
  final String? fontPackage;

  /// Scales type set in [fontFamily], for a family that runs wide.
  final double fontScale;

  /// Multiplies every corner radius; 0 squares them all.
  final double cornerScale;

  /// The line around a panel.
  final double borderWidth;

  /// Whether that line takes the accent, or stays a hairline.
  final bool borderFromAccent;

  /// Whether panels are filled solid, which also leaves nothing to blur.
  final bool opaque;

  /// How much of the usual shadow a panel casts, 0 to 1.
  final double shadow;

  /// A switch's knob crossing over, when the look does not take the usual
  /// one for its kind; see [toggle].
  final KitSpringTuning? switchTuning;

  /// How much faster than written this look's timed transitions run. It
  /// multiplies the user's speed for durations only: the springs are tuned
  /// per look already.
  final double pace;

  /// What the look's surfaces are made of.
  final KitMaterials materials;

  /// The accent when the look brings its own; otherwise the shell's.
  final Color? fixedAccent;

  /// The font when the look brings its own; otherwise the shell's.
  final String? fontFamily;

  /// Whether corners follow the shell's roundness setting.
  final bool scaleCorners;

  /// Whether fills pour and bodies stretch, as Denial's own controls do.
  final bool liquid;

  /// A popup growing into its shape, and going back.
  final KitSpringTuning panelGrow;
  final KitSpringTuning panelShrink;

  /// The share of its width and height a popup starts from.
  final Size panelBead;

  /// A control springing back after a press.
  final KitSpringTuning pressTuning;

  /// Whether a menu's hot row takes the accent, or a quiet plate.
  final bool accentMenuRows;

  Color accent(ShellThemeData theme) => fixedAccent ?? theme.accent;

  /// Ink on an accent fill.
  Color onAccent(ShellThemeData theme) => fixedAccent == null
      ? theme.accentPalette.onPrimary
      : const Color(0xffffffff);

  /// The fill of a control that is on. A look with its own palette keeps the
  /// control's own [colour]; Denial pours the one accent into every control,
  /// and keeps a colour only where it carries [meaning] (a warning, a call).
  Color plate(ShellThemeData theme, Color colour, {bool meaning = false}) =>
      fixedAccent != null || meaning ? colour : theme.accent;

  /// Ink on [plate].
  Color onPlate(ShellThemeData theme, {bool meaning = false}) =>
      fixedAccent != null || meaning
      ? const Color(0xffffffff)
      : theme.accentPalette.onPrimary;

  /// The plate under a menu row and the ink on it; [hot] is the row under
  /// the pointer or the keyboard. One look fills the hot row with its
  /// accent, the other lays a quiet plate and leaves the ink alone.
  ({Color fill, Color ink, Color dim}) menuRow(
    ShellThemeData theme, {
    required bool hot,
    bool enabled = true,
  }) {
    final filled = hot && enabled && accentMenuRows;
    final on = onAccent(theme);
    return (
      fill: filled
          ? accent(theme)
          : hot && enabled
          ? theme.colors.textPrimary.withValues(alpha: 0.10)
          : const Color(0x00000000),
      ink: !enabled
          ? theme.colors.textTertiary
          : filled
          ? on
          : theme.colors.textPrimary,
      dim: filled ? on.withValues(alpha: 0.8) : theme.colors.textTertiary,
    );
  }

  double radius(ShellThemeData theme, double base) =>
      (scaleCorners ? theme.scaledRadius(base) : base) * cornerScale;

  /// A radius that does not follow the shell's roundness, such as a row's or
  /// a button's, in this look.
  double corner(double base) => base * cornerScale;

  /// Whether every corner is square. Round things then turn square too: a
  /// disc is a block, a pill a bar, a switch a block sliding in a slot.
  bool get square => cornerScale == 0;

  /// The corner radius of a pill [height] tall: half of it, so the ends are
  /// round, or none where the look is square.
  double pill(double height) => square ? 0 : height / 2;

  /// The outline of something round [size] across, such as an icon's plate
  /// or a knob: a circle, or a block where the look is square.
  BorderRadius disc(double size) => BorderRadius.circular(pill(size));

  /// Whether controls are flat fills behind a thin line, with no gloss, no
  /// inner shade and no shadow of their own.
  bool get flat => opaque && shadow == 0;

  /// Whether surfaces are glass: lit from above and blurring what is behind.
  bool get glassy => !opaque;

  /// The thin line around a control in a [flat] look; null where controls
  /// carry no line.
  Border? controlLine(ShellThemeData theme) =>
      flat ? Border.all(color: theme.colors.hairline) : null;

  /// [shadows] as this look casts them: fainter, or none at all.
  List<BoxShadow> cast(List<BoxShadow> shadows) => shadow >= 1
      ? shadows
      : shadow <= 0
      ? const <BoxShadow>[]
      : <BoxShadow>[
          for (final one in shadows)
            one.copyWith(
              color: one.color.withValues(alpha: one.color.a * shadow),
            ),
        ];

  /// A switch's knob crossing over: with a little life where the look has
  /// any, and dead-beat where it asks for that.
  KitSpringTuning get toggle =>
      switchTuning ??
      (liquid
          ? const KitSpringTuning(520, 0.6)
          : const KitSpringTuning(620, 0.72));

  /// A panel's fill in this look.
  Color panelFill(Color fill) => opaque ? fill.withValues(alpha: 1) : fill;

  /// The colour of the line around a panel.
  Color border(ShellThemeData theme) =>
      borderFromAccent ? accent(theme) : theme.colors.hairline;

  /// The look in force. Both plugins run in one program, so this one value
  /// serves the dock and the top bar alike, popups included.
  static KitStyle of(BuildContext context) => kitStyle.value;
}

/// The chosen look, kept in `denial_shell_kit.json` beside the plugins'
/// preferences.
final KitStyleNotifier kitStyle = KitStyleNotifier._();

/// How fast the shell's motion runs, kept in the same file as the look so a
/// program with both plugins has one value.
final KitSpeedNotifier kitSpeed = KitSpeedNotifier._();

/// Both settings reach most widgets without a subscription, and a switch is
/// rare, so everything is built again.
void _rebuildEverything() {
  void visit(Element element) {
    element.markNeedsBuild();
    element.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
}

class KitStyleNotifier extends ValueNotifier<KitStyle> {
  KitStyleNotifier._()
    : super(KitStyle.byId(KitStore.textOf(kitStore.read(), 'style')));

  /// Switches the look and remembers it.
  void choose(KitStyle style) {
    if (style.id == value.id) return;
    value = style;
    _rebuildEverything();
    kitStore.put('style', style.id);
  }
}

class KitSpeedNotifier extends ValueNotifier<double> {
  KitSpeedNotifier._()
    : super(KitMotionPace.clampSpeed(kitStore.read()['speed']));

  /// Sets the speed multiplier and remembers it. A missing value in a file
  /// written by an older build means normal speed; anything else lands on one
  /// of [KitMotionPace.speeds].
  @override
  set value(double next) {
    final speed = KitMotionPace.clampSpeed(next);
    if (speed == super.value) return;
    super.value = speed;
    _rebuildEverything();
    kitStore.put('speed', speed);
  }
}

/// Whether a material may saturate what is behind it. The colour filter
/// rides in the same backdrop pass as the blur; turning it off leaves the
/// blur alone, for a device that cannot afford the extra work.
final KitSaturateNotifier kitSaturate = KitSaturateNotifier._();

class KitSaturateNotifier extends ValueNotifier<bool> {
  KitSaturateNotifier._() : super(kitStore.read()['saturate'] != false);

  @override
  set value(bool next) {
    if (next == super.value) return;
    super.value = next;
    _rebuildEverything();
    kitStore.put('saturate', next);
  }
}

/// Whether the dock shows at all. The dock reads it when the shell places
/// its surfaces, so a change rebuilds everything to have them placed again.
final KitDockNotifier kitDockEnabled = KitDockNotifier._();

class KitDockNotifier extends ValueNotifier<bool> {
  KitDockNotifier._() : super(KitStore.dockOf(kitStore.read()));

  @override
  set value(bool next) {
    if (next == super.value) return;
    super.value = next;
    _rebuildEverything();
    kitStore.put('dock', next);
  }
}

/// The preset last applied, by id. It only names where the arrangement
/// started from; the look and the bar's own settings are what is drawn.
final KitPresetNotifier kitPreset = KitPresetNotifier._();

class KitPresetNotifier extends ValueNotifier<String> {
  KitPresetNotifier._()
    : super(ShellPreset.byId(KitStore.textOf(kitStore.read(), 'preset')).id);

  @override
  set value(String next) {
    final id = ShellPreset.byId(next).id;
    if (id == super.value) return;
    super.value = id;
    kitStore.put('preset', id);
  }
}

extension KitThemeAccent on ShellThemeData {
  /// The accent of the look in force: the shell's, or the look's own.
  Color get kitAccent => kitStyle.value.accent(this);
}
