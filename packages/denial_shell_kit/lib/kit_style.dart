import 'dart:convert';
import 'dart:io';

import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/widgets.dart';

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
  });

  /// Denial's own material: the wallpaper's accent, the shell's font and
  /// corner scale, and liquid motion. A popup is born as a bead and stretches
  /// into its shape, a switch fills as the accent pours in.
  static const KitStyle denial = KitStyle(
    id: 'denial',
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
    fixedAccent: Color(0xff0a84ff),
    fontFamily: 'Inter',
    scaleCorners: false,
    liquid: false,
    panelGrow: KitSpringTuning(620, 1),
    panelShrink: KitSpringTuning(900, 1),
    panelBead: Size(0.96, 0.96),
    pressTuning: KitSpringTuning(620, 0.7),
    accentMenuRows: true,
  );

  static const List<KitStyle> presets = <KitStyle>[denial, mac];

  static KitStyle byId(String? id) =>
      presets.firstWhere((style) => style.id == id, orElse: () => denial);

  final String id;

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
      scaleCorners ? theme.scaledRadius(base) : base;

  /// The look in force. Both plugins run in one program, so this one value
  /// serves the dock and the top bar alike, popups included.
  static KitStyle of(BuildContext context) => kitStyle.value;
}

/// The chosen look, kept in `denial_shell_kit.json` beside the plugins'
/// preferences.
final KitStyleNotifier kitStyle = KitStyleNotifier._();

class KitStyleNotifier extends ValueNotifier<KitStyle> {
  KitStyleNotifier._() : super(_read());

  static File? _file() {
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

  static KitStyle _read() {
    try {
      final json = jsonDecode(_file()!.readAsStringSync());
      return KitStyle.byId(json is Map ? json['style'] as String? : null);
    } on Object {
      return KitStyle.denial;
    }
  }

  /// Switches the look and remembers it.
  void choose(KitStyle style) {
    if (style.id == value.id) return;
    value = style;
    // The look reaches into type, colour and motion everywhere, and most
    // widgets read it without subscribing. A switch is rare, so everything
    // is simply built again.
    void visit(Element element) {
      element.markNeedsBuild();
      element.visitChildren(visit);
    }

    WidgetsBinding.instance.rootElement?.visitChildren(visit);
    final file = _file();
    if (file == null) return;
    try {
      file.parent.createSync(recursive: true);
      final temp = File('${file.path}.$pid.tmp')
        ..writeAsStringSync('${jsonEncode({'style': style.id})}\n');
      temp.renameSync(file.path);
    } on FileSystemException {
      return;
    }
  }
}

extension KitThemeAccent on ShellThemeData {
  /// The accent of the look in force: the shell's, or the look's own.
  Color get kitAccent => kitStyle.value.accent(this);
}
