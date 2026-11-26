import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/widgets.dart';

import 'kit_look.dart';
import 'kit_material.dart';
import 'kit_motion_pace.dart';
import 'kit_palette.dart';
import 'kit_store.dart';
import 'shell_preset.dart';

export 'kit_look.dart'
    show
        KitAccentSource,
        KitAppearance,
        KitBorderTone,
        KitIconTint,
        KitLook,
        KitPanelEntry,
        KitSpringTuning;

/// One look for the dock and the top bar: where colour, type and corners come
/// from, and how things move. The values are a [KitLook], which is plain
/// data, so a new look is new data and no widget changes; this class turns
/// them into colours and the numbers widgets ask for.
@immutable
class KitStyle {
  const KitStyle(this.look);

  static const KitStyle denial = KitStyle(KitLook.denial);
  static const KitStyle mac = KitStyle(KitLook.mac);
  static const KitStyle soft = KitStyle(KitLook.soft);
  static const KitStyle terminal = KitStyle(KitLook.terminal);

  /// The looks the shell has always had, which a short row of choices can
  /// hold.
  static const List<KitStyle> presets = <KitStyle>[denial, mac, soft, terminal];

  /// Every look that ships.
  static final List<KitStyle> builtins = List<KitStyle>.unmodifiable(<KitStyle>[
    ...presets,
    for (final look in KitLook.builtins.skip(presets.length)) KitStyle(look),
  ]);

  /// The looks the user made.
  static List<KitStyle> get user => kitLooks.value;

  /// The look called [id], among those that ship and those the user made;
  /// Denial for any other.
  static KitStyle byId(String? id) {
    for (final style in builtins) {
      if (style.id == id) return style;
    }
    for (final style in kitLooks.value) {
      if (style.id == id) return style;
    }
    return denial;
  }

  /// The look's values.
  final KitLook look;

  String get id => look.id;

  /// The look's name, as its makers write it.
  String get label => look.label;

  /// Whether the user made it.
  bool get custom => look.base != null;

  /// The package that carries [fontFamily].
  String? get fontPackage => look.fontPackage;

  /// Scales type set in [fontFamily], for a family that runs wide.
  double get fontScale => look.fontScale;

  /// Multiplies every corner radius; 0 squares them all.
  double get cornerScale => look.cornerScale;

  /// The line around a panel.
  double get borderWidth => look.borderWidth;

  /// Whether that line takes the accent, or stays a hairline.
  bool get borderFromAccent => look.borderTone == KitBorderTone.accent;

  /// Whether panels are filled solid, which also leaves nothing to blur.
  bool get opaque => look.opaque;

  /// How much of the usual shadow a panel casts, 0 to 1.
  double get shadow => look.shadow;

  /// A switch's knob crossing over, when the look does not take the usual
  /// one for its kind; see [toggle].
  KitSpringTuning? get switchTuning => look.switchTuning;

  /// How much faster than written this look's timed transitions run. It
  /// multiplies the user's speed for durations only: the springs are tuned
  /// per look already.
  double get pace => look.pace;

  /// What the look's surfaces are made of.
  KitMaterials get materials => look.materials;

  /// The accent when the look names one colour; otherwise the palette's or
  /// the shell's.
  Color? get fixedAccent => look.accentSource == KitAccentSource.fixed
      ? Color(0xff000000 | look.accentRgb)
      : null;

  /// The font when the look brings its own; otherwise the shell's.
  String? get fontFamily => look.fontFamily;

  /// Whether corners follow the shell's roundness setting.
  bool get scaleCorners => look.scaleCorners;

  /// Whether fills pour and bodies stretch, as Denial's own controls do.
  bool get liquid => look.liquid;

  /// A popup growing into its shape, and going back.
  KitSpringTuning get panelGrow => look.panelGrow;
  KitSpringTuning get panelShrink => look.panelShrink;

  /// The share of its width and height a popup starts from.
  Size get panelBead => Size(look.beadWidth, look.beadHeight);

  /// How a popup comes on screen.
  KitPanelEntry get entry => look.entry;

  /// A control springing back after a press.
  KitSpringTuning get pressTuning => look.pressTuning;

  /// Whether a menu's hot row takes the accent, or a quiet plate.
  bool get accentMenuRows => look.accentMenuRows;

  /// Multiplies the room between and around things.
  double get density => look.density;

  /// Whether the look is drawn dark under [theme]: as the look insists, or
  /// as the shell is.
  bool dark(ShellThemeData theme) => switch (look.appearance) {
    KitAppearance.system => theme.brightness == Brightness.dark,
    KitAppearance.dark => true,
    KitAppearance.light => false,
  };

  /// The tones of the look's palette under [theme]'s appearance; null for a
  /// look that takes the shell's colours.
  KitTones? tones(ShellThemeData theme) =>
      look.palette?.of(dark: dark(theme));

  static ShellThemeData? _themedFrom;
  static KitLook? _themedLook;
  static ShellThemeData? _themed;

  /// [theme] as this look colours it: the palette's tones in place of the
  /// shell's, and the appearance the look insists on. A look with neither
  /// gets [theme] itself. Everything under a [KitThemed] reads the result,
  /// so a widget that asks the theme for a colour gets the look's.
  ShellThemeData themed(ShellThemeData theme) {
    if (look.palette == null && look.appearance == KitAppearance.system) {
      return theme;
    }
    if (identical(theme, _themedFrom) && identical(look, _themedLook)) {
      return _themed!;
    }
    final dark = this.dark(theme);
    final base = dark == (theme.brightness == Brightness.dark)
        ? theme.colors
        : dark
        ? ShellColorScheme.dark
        : ShellColorScheme.light;
    final tones = this.tones(theme);
    final own = tones == null ? null : _own(theme);
    final next = theme.copyWith(
      colors: tones == null ? base : _scheme(tones, base),
      accent: own,
    );
    _themedFrom = theme;
    _themedLook = look;
    return _themed = next;
  }

  static ShellColorScheme _scheme(KitTones tones, ShellColorScheme base) {
    Color solid(int rgb, [int alpha = 0xff]) =>
        Color((alpha << 24) | (rgb & 0xffffff));
    final background = solid(tones.background);
    final surface = solid(tones.surface);
    final raised = solid(tones.raised);
    final text = solid(tones.text);
    final highest = Color.lerp(raised, text, 0.08)!;
    final outline = solid(tones.outline);
    return ShellColorScheme(
      brightness: base.brightness,
      background: background,
      surfaceContainerLow: Color.lerp(
        background,
        surface,
        0.5,
      )!.withValues(alpha: 0.95),
      surfaceContainer: surface.withValues(alpha: 0.95),
      surfaceContainerHigh: raised.withValues(alpha: 0.96),
      surfaceContainerHighest: highest.withValues(alpha: 0.965),
      textPrimary: text,
      panelText: text,
      textSecondary: solid(tones.subtext),
      textTertiary: solid(tones.faint),
      panelBackground: surface.withValues(alpha: 0.933),
      panelBackgroundBottom: Color.lerp(
        surface,
        background,
        0.3,
      )!.withValues(alpha: 0.95),
      panelHighlight: base.panelHighlight,
      tileOff: raised.withValues(alpha: 0.96),
      tileIcon: highest.withValues(alpha: 0.965),
      chip: raised.withValues(alpha: 0.96),
      overviewScrim: base.overviewScrim,
      hairline: outline.withValues(alpha: 0.9),
      hairlineSoft: outline.withValues(alpha: 0.5),
      hairlineWindow: base.hairlineWindow,
      windowFrameSurface: surface,
      shadow: base.shadow,
      shadowSoft: base.shadowSoft,
      sliderThumb: base.sliderThumb,
      brightnessTrack: highest.withValues(alpha: 0.965),
      volumeTrack: highest.withValues(alpha: 0.965),
      wallpaperEffectTrack: highest.withValues(alpha: 0.965),
      gestureArmed: base.gestureArmed,
      gesturePill: base.gesturePill,
      launchSurface: base.launchSurface,
      fallbackAppIcon: base.fallbackAppIcon,
      performanceGood: base.performanceGood,
      performanceWarning: base.performanceWarning,
      performanceBad: base.performanceBad,
      glyphInactive: text.withValues(alpha: 0.4),
    );
  }

  /// The accent the look brings under [theme], if it brings one.
  Color? _own(ShellThemeData theme) {
    switch (look.accentSource) {
      case KitAccentSource.fixed:
        return fixedAccent;
      case KitAccentSource.palette:
        final tones = this.tones(theme);
        return tones == null ? null : Color(0xff000000 | tones.accent);
      case KitAccentSource.wallpaper:
        return null;
    }
  }

  Color accent(ShellThemeData theme) => _own(theme) ?? theme.accent;

  /// Ink on an accent fill.
  Color onAccent(ShellThemeData theme) {
    switch (look.accentSource) {
      case KitAccentSource.fixed:
        // White on a colour dark enough to carry it, as on the system blue.
        return fixedAccent!.computeLuminance() < 0.5
            ? const Color(0xffffffff)
            : const Color(0xff141414);
      case KitAccentSource.palette:
        final tones = this.tones(theme);
        if (tones != null) return Color(0xff000000 | tones.onAccent);
      case KitAccentSource.wallpaper:
    }
    return theme.accentPalette.onPrimary;
  }

  /// The fill of a control that is on. A look with its own palette keeps the
  /// control's own [colour]; Denial pours the one accent into every control,
  /// and keeps a colour only where it carries [meaning] (a warning, a call).
  Color plate(ShellThemeData theme, Color colour, {bool meaning = false}) =>
      fixedAccent != null || meaning ? colour : accent(theme);

  /// Ink on [plate].
  Color onPlate(ShellThemeData theme, {bool meaning = false}) =>
      fixedAccent != null || meaning
      ? const Color(0xffffffff)
      : onAccent(theme);

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
  Color border(ShellThemeData theme) => switch (look.borderTone) {
    KitBorderTone.hairline => theme.colors.hairline,
    KitBorderTone.accent => accent(theme),
    KitBorderTone.ink => theme.colors.textPrimary.withValues(alpha: 0.85),
  };

  /// [weight] as this look sets it: heavier or lighter by the look's steps.
  FontWeight weight(FontWeight weight) {
    final shift = look.weightShift;
    final at = FontWeight.values.indexOf(weight);
    if (shift == 0 || at < 0) return weight;
    return FontWeight.values[(at + shift).clamp(0, FontWeight.values.length - 1)];
  }

  /// The look in force. Both plugins run in one program, so this one value
  /// serves the dock and the top bar alike, popups included.
  static KitStyle of(BuildContext context) => kitStyle.value;
}

/// Puts the look's colours in force for everything under it: the theme the
/// shell hands down, as [KitStyle.themed] colours it. Each surface and each
/// popup of the plugins is built under one.
class KitThemed extends StatelessWidget {
  const KitThemed({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final themed = KitStyle.of(context).themed(theme);
    // The same widgets whatever the look, so going from a look with a
    // palette to one without keeps the state of everything below.
    return ShellTheme(
      data: themed,
      child: DefaultTextStyle.merge(
        style: TextStyle(
          color: identical(themed, theme) ? null : themed.colors.textPrimary,
        ),
        child: child,
      ),
    );
  }
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

  /// The id of the look the user chose, which a look being tried out in the
  /// editor stands in front of.
  late String _chosen = value.id;

  /// The id of the look that is kept, whatever is being tried out.
  String get chosen => _chosen;

  /// Switches the look and remembers it.
  void choose(KitStyle style) {
    final kept = style.id == _chosen;
    if (kept && identical(style, value)) return;
    _chosen = style.id;
    value = style;
    _rebuildEverything();
    if (!kept) kitStore.put('style', style.id);
  }

  /// Draws [style] without keeping it, for an editor to show what it holds;
  /// null goes back to the look that was chosen.
  void preview(KitStyle? style) {
    final next = style ?? KitStyle.byId(_chosen);
    if (identical(next, value)) return;
    final same = next.look == value.look;
    value = next;
    if (!same) _rebuildEverything();
  }
}

/// The looks the user made, kept under `looks` in `denial_shell_kit.json`
/// as overrides on top of a look that ships.
final KitLooksNotifier kitLooks = KitLooksNotifier._();

class KitLooksNotifier extends ValueNotifier<List<KitStyle>> {
  KitLooksNotifier._() : super(_read());

  static List<KitStyle> _read() {
    final stored = kitStore.read()['looks'];
    return List<KitStyle>.unmodifiable(<KitStyle>[
      if (stored is Map)
        for (final entry in stored.entries)
          if (entry.key is String && KitLook.builtin(entry.key as String) == null)
            KitStyle(KitLook.stored(entry.key as String, entry.value)),
    ]);
  }

  /// An id no look has yet.
  String freshId() {
    final taken = <String>{
      for (final style in KitStyle.builtins) style.id,
      for (final style in value) style.id,
    };
    final stamp = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    var id = 'look-$stamp';
    for (var n = 2; taken.contains(id); n++) {
      id = 'look-$stamp-$n';
    }
    return id;
  }

  void _write(List<KitStyle> next) {
    value = List<KitStyle>.unmodifiable(next);
    kitStore.put('looks', <String, Object?>{
      for (final style in next) style.id: style.look.toStored(),
    });
  }

  /// Adds [look], or puts it in place of the one with its id, and returns
  /// it as kept. A look that ships cannot be replaced. The look in force is
  /// drawn again when it was the one changed.
  KitStyle? save(KitLook look) {
    if (KitLook.builtin(look.id) != null) return null;
    // Through the stored form, so what is drawn is what a restart reads.
    final style = KitStyle(KitLook.stored(look.id, look.toStored()));
    final next = <KitStyle>[
      for (final one in value)
        if (one.id == style.id) style else one,
      if (!value.any((one) => one.id == style.id)) style,
    ];
    _write(next);
    if (kitStyle.chosen == style.id) kitStyle.choose(style);
    return style;
  }

  /// Drops the look called [id]. When it was in force the shell goes to the
  /// look it was made from.
  void remove(String id) {
    final gone = value.where((one) => one.id == id).firstOrNull;
    if (gone == null) return;
    _write(<KitStyle>[
      for (final one in value)
        if (one.id != id) one,
    ]);
    if (kitStyle.chosen == id) kitStyle.choose(KitStyle.byId(gone.look.base));
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
