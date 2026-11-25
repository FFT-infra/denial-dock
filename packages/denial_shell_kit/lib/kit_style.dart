import 'dart:convert';
import 'dart:io';

import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/widgets.dart';

import 'kit_motion_pace.dart';

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

File? _kitFile() {
  final env = Platform.environment;
  final configured = env['XDG_CONFIG_HOME'];
  final home = env['HOME'];
  final root = configured != null && configured.startsWith('/')
      ? configured
      : home != null && home.startsWith('/')
      ? '$home/.config'
      : null;
  return root == null
      ? null
      : File('$root/denial/plugins/denial_shell_kit.json');
}

Map<String, dynamic> _readKitJson() {
  final file = _kitFile();
  if (file == null) return <String, dynamic>{};
  try {
    final json = jsonDecode(file.readAsStringSync());
    return json is Map<String, dynamic> ? json : <String, dynamic>{};
  } on Object {
    return <String, dynamic>{};
  }
}

/// Writes the keys given, keeping every other key the file already has: the
/// look and the speed are separate settings in one file, and a newer build
/// may have added more.
void _writeKitJson(Map<String, dynamic> json) {
  final file = _kitFile();
  if (file == null) return;
  try {
    file.parent.createSync(recursive: true);
    final temp = File('${file.path}.$pid.tmp')
      ..writeAsStringSync('${jsonEncode(json)}\n');
    temp.renameSync(file.path);
  } on FileSystemException {
    return;
  }
}

/// Both settings reach most widgets without a subscription, and a switch is
/// rare, so everything is built again.
void _rebuildEverything() {
  void visit(Element element) {
    element.markNeedsBuild();
    element.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
}

/// The store's version, written on every save. A file without it was written
/// when the store held only the look, which is what version 1 held; a file
/// with a newer version is read but never written, so a build cannot drop
/// settings it does not know.
const int _storeVersion = 2;

/// Whether this build may write the file, decided once from its version.
final bool _mayWrite = (() {
  final version = _readKitJson()['version'];
  return version is! int || version <= _storeVersion;
})();

/// The file's keys in the shape this build writes them: the version it knows,
/// and every key it did not write left as it was.
Map<String, dynamic> _withVersion(Map<String, dynamic> json) =>
    json..['version'] = _storeVersion;

class KitStyleNotifier extends ValueNotifier<KitStyle> {
  KitStyleNotifier._() : super(_read());

  static KitStyle _read() {
    final style = _readKitJson()['style'];
    return KitStyle.byId(style is String ? style : null);
  }

  /// Switches the look and remembers it.
  void choose(KitStyle style) {
    if (style.id == value.id) return;
    value = style;
    _rebuildEverything();
    if (!_mayWrite) return;
    final json = _withVersion(_readKitJson())..['style'] = style.id;
    _writeKitJson(json);
  }
}

class KitSpeedNotifier extends ValueNotifier<double> {
  KitSpeedNotifier._() : super(_read());

  static double _read() => KitMotionPace.clampSpeed(_readKitJson()['speed']);

  /// Sets the speed multiplier and remembers it. A missing value in a file
  /// written by an older build means normal speed; anything else lands on one
  /// of [KitMotionPace.speeds].
  @override
  set value(double next) {
    final speed = KitMotionPace.clampSpeed(next);
    if (speed == super.value) return;
    super.value = speed;
    _rebuildEverything();
    if (!_mayWrite) return;
    final json = _withVersion(_readKitJson())..['speed'] = speed;
    _writeKitJson(json);
  }
}

extension KitThemeAccent on ShellThemeData {
  /// The accent of the look in force: the shell's, or the look's own.
  Color get kitAccent => kitStyle.value.accent(this);
}
