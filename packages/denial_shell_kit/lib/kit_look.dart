/// A look as plain data: where colour, type and corners come from, what the
/// surfaces are made of and how things move. A look is read from JSON and
/// written back to it, so one the user made is a few overrides on top of a
/// look that ships.
///
/// No Flutter import, so the rules run as an ordinary Dart test.
/// `kit_style.dart` turns a look into colours and widgets' numbers.
library;

import 'dart:convert';

import 'kit_look_refs.dart';
import 'kit_material.dart';
import 'kit_palette.dart';

/// How a spring is tuned: stiffness and damping ratio, as Denial's liquid
/// motion recipe writes them.
class KitSpringTuning {
  const KitSpringTuning(this.stiffness, this.dampingRatio);

  final double stiffness;
  final double dampingRatio;
}

/// Where a look's accent comes from.
enum KitAccentSource {
  /// The shell's, which follows the wallpaper.
  wallpaper,

  /// The accent of the look's palette.
  palette,

  /// One colour the look names.
  fixed,
}

/// Which appearance a look is drawn in.
enum KitAppearance { system, dark, light }

/// What the line around a panel is drawn in.
enum KitBorderTone { hairline, accent, ink }

/// How a panel comes on screen.
enum KitPanelEntry {
  /// Out of a bead at the control that opened it.
  grow,

  /// Travelling a short way from that control.
  slide,

  /// In place.
  fade,

  /// Swelling evenly about its own centre.
  zoom,
}

/// How an icon is coloured.
enum KitIconTint { original, mono, accent }

/// [over] laid on [base], map by map. Anything that is no map replaces what
/// was there.
Map<String, Object?> kitJsonMerge(Map<dynamic, dynamic> base, Map<dynamic, dynamic> over) {
  final out = <String, Object?>{
    for (final entry in base.entries)
      if (entry.key is String) entry.key as String: entry.value,
  };
  for (final entry in over.entries) {
    final key = entry.key;
    if (key is! String) continue;
    final under = out[key];
    final value = entry.value;
    out[key] = under is Map && value is Map
        ? kitJsonMerge(under, value)
        : value;
  }
  return out;
}

/// Whether two decoded JSON values are the same; 6 is 6.0.
bool kitJsonSame(Object? a, Object? b) {
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || !kitJsonSame(a[key], b[key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      if (!kitJsonSame(a[index], b[index])) return false;
    }
    return true;
  }
  return a == b;
}

/// The keys of [edited] that differ from [base], map by map: what laid over
/// [base] and read gives [edited] again.
Map<String, Object?> kitJsonDiff(Map<dynamic, dynamic> base, Map<dynamic, dynamic> edited) {
  final out = <String, Object?>{};
  for (final entry in edited.entries) {
    final key = entry.key;
    if (key is! String) continue;
    final under = base[key];
    final value = entry.value;
    if (base.containsKey(key) && kitJsonSame(under, value)) continue;
    if (under is Map && value is Map) {
      final inner = kitJsonDiff(under, value);
      if (inner.isNotEmpty) out[key] = inner;
    } else {
      out[key] = value;
    }
  }
  // A key [edited] dropped is written as null, which is how a look says it
  // no longer sets something its base does.
  for (final key in base.keys) {
    if (key is String && !edited.containsKey(key)) out[key] = null;
  }
  return out;
}

/// What [json] holds that [known] does not, map by map.
Map<String, Object?> _unknown(Map<dynamic, dynamic> json, Map<dynamic, dynamic> known) {
  final out = <String, Object?>{};
  for (final entry in json.entries) {
    final key = entry.key;
    if (key is! String) continue;
    if (!known.containsKey(key)) {
      out[key] = entry.value;
      continue;
    }
    final value = entry.value;
    final mine = known[key];
    if (value is Map && mine is Map) {
      final inner = _unknown(value, mine);
      if (inner.isNotEmpty) out[key] = inner;
    }
  }
  return out;
}

double _number(Object? value, double min, double max, double fallback) =>
    value is num && value.isFinite
    ? value.toDouble().clamp(min, max).toDouble()
    : fallback;

/// A number that may be null: a missing key or a value of the wrong kind
/// keeps [fallback], an explicit null is null.
double? _optional(
  Map<dynamic, dynamic> map,
  String key,
  double min,
  double max,
  double? fallback,
) {
  if (!map.containsKey(key)) return fallback;
  final value = map[key];
  if (value == null) return null;
  return value is num && value.isFinite
      ? value.toDouble().clamp(min, max).toDouble()
      : fallback;
}

T _named<T extends Enum>(Object? value, List<T> values, T fallback) {
  for (final candidate in values) {
    if (candidate.name == value) return candidate;
  }
  return fallback;
}

Map<dynamic, dynamic> _map(Object? value) =>
    value is Map ? value : const <Object?, Object?>{};

/// The reading and writing of a material table.
abstract final class KitMaterialJson {
  /// `panel`, `panel@0.5` or `#222222@0.36`.
  static String tone(KitTone tone) {
    final alpha = tone.alpha;
    final head = tone.fixed ? kitRgbText(tone.rgb) : tone.role!.name;
    return alpha == null ? head : '$head@$alpha';
  }

  static KitTone parseTone(Object? value, KitTone fallback) {
    if (value is! String) return fallback;
    final at = value.indexOf('@');
    final head = at < 0 ? value : value.substring(0, at);
    double? alpha;
    if (at >= 0) {
      final parsed = double.tryParse(value.substring(at + 1));
      if (parsed == null || !parsed.isFinite) return fallback;
      alpha = parsed.clamp(0.0, 1.0).toDouble();
    }
    final rgb = kitParseRgb(head);
    if (rgb != null) return KitTone(rgb, alpha ?? 1);
    for (final role in KitRole.values) {
      if (role.name == head) return KitTone.of(role, alpha: alpha);
    }
    return fallback;
  }

  static Map<String, Object?>? line(KitLine? line) => line == null
      ? null
      : <String, Object?>{
          'tone': tone(line.tone),
          'width': line.width,
          'edges': line.edges.name,
          'tail': line.tail,
          'reach': line.reach,
        };

  static const KitLine _plainLine = KitLine(KitTone.of(KitRole.hairline));

  static KitLine? parseLine(
    Map<dynamic, dynamic> map,
    String key,
    KitLine? fallback,
  ) {
    if (!map.containsKey(key)) return fallback;
    final json = map[key];
    if (json == null) return null;
    if (json is! Map) return fallback;
    final base = fallback ?? _plainLine;
    return KitLine(
      parseTone(json['tone'], base.tone),
      width: _optional(json, 'width', 0, 6, base.width),
      edges: _named(json['edges'], KitEdges.values, base.edges),
      tail: _number(json['tail'], 0, 1, base.tail),
      reach: _number(json['reach'], 0, 24, base.reach),
    );
  }

  static Map<String, Object?>? shadow(KitShadow? shadow) => shadow == null
      ? null
      : <String, Object?>{
          'tone': tone(shadow.tone),
          'blur': shadow.blur,
          'dy': shadow.dy,
          'byLook': shadow.byLook,
        };

  static const KitShadow _plainShadow = KitShadow(
    KitTone.of(KitRole.shadow, alpha: 0.3),
    blur: 24,
    dy: 8,
  );

  static KitShadow? parseShadow(
    Map<dynamic, dynamic> map,
    String key,
    KitShadow? fallback,
  ) {
    if (!map.containsKey(key)) return fallback;
    final json = map[key];
    if (json == null) return null;
    if (json is! Map) return fallback;
    final base = fallback ?? _plainShadow;
    final byLook = json['byLook'];
    return KitShadow(
      parseTone(json['tone'], base.tone),
      blur: _number(json['blur'], 0, 80, base.blur),
      dy: _number(json['dy'], -8, 40, base.dy),
      byLook: byLook is bool ? byLook : base.byLook,
    );
  }

  static Map<String, Object?> material(KitMaterial material) =>
      <String, Object?>{
        'fill': tone(material.fill),
        'sigma': material.sigma,
        'strength': material.strength,
        'saturation': material.saturation,
        'radius': material.radius,
        'continuous': material.continuous,
        'outer': line(material.outer),
        'inner': line(material.inner),
        'shadow': shadow(material.shadow),
        'solid': material.solid,
      };

  static KitMaterial parseMaterial(Object? value, KitMaterial base) {
    if (value is! Map) return base;
    final continuous = value['continuous'];
    return KitMaterial(
      fill: parseTone(value['fill'], base.fill),
      sigma: _optional(value, 'sigma', 0, 40, base.sigma),
      strength: _number(value['strength'], 0, 1, base.strength),
      saturation: _number(value['saturation'], 0, 3, base.saturation),
      radius: _optional(value, 'radius', 0, 48, base.radius),
      continuous: continuous is bool ? continuous : base.continuous,
      outer: parseLine(value, 'outer', base.outer),
      inner: parseLine(value, 'inner', base.inner),
      shadow: parseShadow(value, 'shadow', base.shadow),
      solid: _number(value['solid'], 0, 1, base.solid),
    );
  }

  static Map<String, Object?> _pair(KitMaterialPair pair) => <String, Object?>{
    'dark': material(pair.dark),
    'light': material(pair.light),
  };

  static KitMaterialPair _parsePair(Object? value, KitMaterialPair base) =>
      value is! Map
      ? base
      : KitMaterialPair(
          dark: parseMaterial(value['dark'], base.dark),
          light: parseMaterial(value['light'], base.light),
        );

  static Map<String, Object?> table(KitMaterials table) => <String, Object?>{
    for (final tier in KitTier.values) tier.name: _pair(table.tier(tier)),
    'cardLayout': <String, Object?>{
      'width': table.cardLayout.width,
      'gap': table.cardLayout.gap,
      'edge': table.cardLayout.edge,
      'peek': table.cardLayout.peek,
      'inset': table.cardLayout.inset,
      'dim': table.cardLayout.dim,
      'dimReach': table.cardLayout.dimReach,
    },
  };

  static KitMaterials parseTable(Object? value, KitMaterials base) {
    if (value is! Map) return base;
    final layout = _map(value['cardLayout']);
    final cards = base.cardLayout;
    return KitMaterials(
      dock: _parsePair(value['dock'], base.dock),
      popover: _parsePair(value['popover'], base.popover),
      menu: _parsePair(value['menu'], base.menu),
      card: _parsePair(value['card'], base.card),
      cardLayout: KitCardLayout(
        width: _number(layout['width'], 280, 480, cards.width),
        gap: _number(layout['gap'], 0, 24, cards.gap),
        edge: _number(layout['edge'], 0, 40, cards.edge),
        peek: _number(layout['peek'], 0, 20, cards.peek),
        inset: _number(layout['inset'], 0, 30, cards.inset),
        dim: _number(layout['dim'], 0, 0.8, cards.dim),
        dimReach: _number(layout['dimReach'], 0, 400, cards.dimReach),
      ),
    );
  }
}

class KitLook {
  const KitLook({
    required this.id,
    this.label = '',
    this.base,
    this.accentSource = KitAccentSource.wallpaper,
    this.accentRgb = 0x0a84ff,
    this.palette,
    this.appearance = KitAppearance.system,
    this.accentMenuRows = false,
    this.fontFamily,
    this.fontPackage,
    this.fontScale = 1,
    this.weightShift = 0,
    this.density = 1,
    this.scaleCorners = true,
    this.cornerScale = 1,
    this.borderWidth = 1,
    this.borderTone = KitBorderTone.hairline,
    this.opaque = false,
    this.shadow = 1,
    this.materials = KitMaterials.shell,
    this.liquid = false,
    this.panelGrow = const KitSpringTuning(520, 1),
    this.panelShrink = const KitSpringTuning(800, 1),
    this.beadWidth = 0.94,
    this.beadHeight = 0.94,
    this.pressTuning = const KitSpringTuning(620, 0.8),
    this.switchTuning,
    this.pace = 1,
    this.entry = KitPanelEntry.grow,
    this.iconTint = KitIconTint.original,
    this.iconWeight = 1,
    this.dockKin = 'denial',
    this.dock = const <String, Object?>{},
    this.extra = const <String, Object?>{},
  });

  /// Denial's own material: the wallpaper's accent, the shell's font and
  /// corner scale, and liquid motion. A popup is born as a bead and stretches
  /// into its shape, a switch fills as the accent pours in.
  static const KitLook denial = KitLook(
    id: 'denial',
    label: 'Denial',
    liquid: true,
    panelGrow: KitSpringTuning(230, 0.6),
    panelShrink: KitSpringTuning(420, 1),
    beadWidth: 0.9,
    beadHeight: 0.72,
    pressTuning: KitSpringTuning(520, 0.42),
  );

  /// macOS: the system blue, Inter, fixed corners, and a short settle with
  /// no overshoot.
  static const KitLook mac = KitLook(
    id: 'mac',
    label: 'macOS',
    accentSource: KitAccentSource.fixed,
    accentRgb: 0x0a84ff,
    fontFamily: 'Inter',
    fontPackage: 'denial_topbar',
    scaleCorners: false,
    panelGrow: KitSpringTuning(620, 1),
    panelShrink: KitSpringTuning(900, 1),
    beadWidth: 0.96,
    beadHeight: 0.96,
    pressTuning: KitSpringTuning(620, 0.7),
    accentMenuRows: true,
    materials: KitMaterials.mac,
    dockKin: 'mac',
  );

  /// Solid rounded panels: the shell's accent and font, tighter corners, no
  /// blur behind a panel and a lighter shadow under it, and motion that
  /// settles without a bounce.
  static const KitLook soft = KitLook(
    id: 'soft',
    label: 'Soft',
    cornerScale: 0.6,
    opaque: true,
    shadow: 0.6,
    switchTuning: KitSpringTuning(620, 1),
    dockKin: 'soft',
  );

  /// A terminal's look: square corners, a 2 px line in the accent around
  /// every panel, opaque fills with no blur and no shadow, fixed-width type,
  /// and motion that is over at once.
  static const KitLook terminal = KitLook(
    id: 'terminal',
    label: 'Terminal',
    fontFamily: 'JetBrainsMono',
    fontPackage: 'denial_flutter_sdk',
    fontScale: 0.93,
    scaleCorners: false,
    panelGrow: KitSpringTuning(1100, 1),
    panelShrink: KitSpringTuning(1400, 1),
    beadWidth: 0.98,
    beadHeight: 0.98,
    pressTuning: KitSpringTuning(1000, 1),
    accentMenuRows: true,
    cornerScale: 0,
    borderWidth: 2,
    borderTone: KitBorderTone.accent,
    opaque: true,
    shadow: 0,
    switchTuning: KitSpringTuning(1000, 1),
    pace: 1.6,
    dockKin: 'terminal',
  );

  /// The looks the shell has always had.
  static const List<KitLook> core = <KitLook>[denial, mac, soft, terminal];

  /// Every look that ships: the shell's own, then the ones made after
  /// other shells.
  static const List<KitLook> builtins = <KitLook>[
    ...core,
    ...kitReferenceLooks,
  ];

  static KitLook? builtin(String? id) {
    for (final look in builtins) {
      if (look.id == id) return look;
    }
    return null;
  }

  /// The dock presets a look may take after.
  static const List<String> dockKins = <String>[
    'denial',
    'mac',
    'soft',
    'terminal',
  ];

  /// The dock's own values a look may set, under the keys the dock stores
  /// its overrides by, and the kind each takes. The dock clamps them.
  static const Map<String, Type> dockKeys = <String, Type>{
    'blur': num,
    'opacity': num,
    'tint': String,
    'tintShade': num,
    'radius': num,
    'border': bool,
    'borderWidth': num,
    'shadow': num,
    'padding': num,
    'gap': num,
    'edgeMargin': num,
    'markerColor': String,
    'iconSize': num,
    'magnify': bool,
    'magnifyAmount': num,
    'indicator': String,
    'highlight': bool,
  };

  final String id;

  /// The look's name, as its makers write it.
  final String label;

  /// The look that ships which this one was made from; null for one that
  /// ships.
  final String? base;

  final KitAccentSource accentSource;

  /// The accent while [accentSource] is fixed, 0xRRGGBB.
  final int accentRgb;

  /// The look's own colours; null takes the shell's.
  final KitPalette? palette;
  final KitAppearance appearance;

  /// Whether a menu's hot row takes the accent, or a quiet plate.
  final bool accentMenuRows;

  /// The font when the look brings its own, and the package that carries
  /// it; a family with no package is one installed on the system.
  final String? fontFamily;
  final String? fontPackage;

  /// Scales type, for a family that runs wide.
  final double fontScale;

  /// Steps of a hundred added to every weight: 1 turns regular into medium.
  final int weightShift;

  /// Multiplies the room between and around things.
  final double density;

  /// Whether corners follow the shell's roundness setting.
  final bool scaleCorners;

  /// Multiplies every corner radius; 0 squares them all.
  final double cornerScale;

  /// The line around a panel.
  final double borderWidth;
  final KitBorderTone borderTone;

  /// Whether panels are filled solid, which also leaves nothing to blur.
  final bool opaque;

  /// How much of the usual shadow a panel casts, 0 to 1.
  final double shadow;

  /// What the look's surfaces are made of.
  final KitMaterials materials;

  /// Whether fills pour and bodies stretch, as Denial's own controls do.
  final bool liquid;

  /// A popup growing into its shape, and going back.
  final KitSpringTuning panelGrow;
  final KitSpringTuning panelShrink;

  /// The share of its width and height a popup starts from.
  final double beadWidth;
  final double beadHeight;

  /// A control springing back after a press.
  final KitSpringTuning pressTuning;

  /// A switch's knob crossing over, when the look does not take the usual
  /// one for its kind.
  final KitSpringTuning? switchTuning;

  /// How much faster than written this look's timed transitions run.
  final double pace;
  final KitPanelEntry entry;

  final KitIconTint iconTint;

  /// The stroke of a drawn glyph, as a share of the usual.
  final double iconWeight;

  /// Which dock preset the look takes after, and what it changes in it.
  final String dockKin;
  final Map<String, Object?> dock;

  /// Keys this build does not know, kept so that writing a look back does
  /// not drop what a newer build put there.
  final Map<String, Object?> extra;

  static List<double> _tuning(KitSpringTuning tuning) => <double>[
    tuning.stiffness,
    tuning.dampingRatio,
  ];

  static KitSpringTuning _parseTuning(Object? value, KitSpringTuning base) =>
      value is List && value.length == 2
      ? KitSpringTuning(
          _number(value[0], 40, 3000, base.stiffness),
          _number(value[1], 0.15, 2, base.dampingRatio),
        )
      : base;

  Map<String, Object?> _known() => <String, Object?>{
    'id': id,
    'label': label,
    if (base != null) 'base': base,
    'accent': switch (accentSource) {
      KitAccentSource.fixed => kitRgbText(accentRgb),
      final source => source.name,
    },
    'palette': palette?.toJson(),
    'appearance': appearance.name,
    'accentMenuRows': accentMenuRows,
    'font': <String, Object?>{
      'family': fontFamily,
      'package': fontPackage,
      'scale': fontScale,
      'weight': weightShift,
    },
    'density': density,
    'corners': <String, Object?>{
      'scale': cornerScale,
      'followShell': scaleCorners,
    },
    'border': <String, Object?>{
      'width': borderWidth,
      'tone': borderTone.name,
    },
    'opaque': opaque,
    'shadow': shadow,
    'materials': KitMaterialJson.table(materials),
    'motion': <String, Object?>{
      'liquid': liquid,
      'pace': pace,
      'entry': entry.name,
      'bead': <double>[beadWidth, beadHeight],
      'panelGrow': _tuning(panelGrow),
      'panelShrink': _tuning(panelShrink),
      'press': _tuning(pressTuning),
      'switch': switchTuning == null ? null : _tuning(switchTuning!),
    },
    'icons': <String, Object?>{'tint': iconTint.name, 'weight': iconWeight},
    // In the order of [dockKeys], so two looks that set the same values
    // write the same text.
    'dock': <String, Object?>{
      'kin': dockKin,
      for (final key in dockKeys.keys)
        if (dock.containsKey(key)) key: dock[key],
    },
  };

  /// The whole look, every key written out.
  Map<String, Object?> toJson() => kitJsonMerge(extra, _known());

  /// [json] over [base]: a key that is missing, or holds a value of the
  /// wrong kind, takes the one of [base]; a number out of range is brought
  /// into it. Nothing in [json] can make this throw.
  static KitLook fromJson(Map<dynamic, dynamic> json, {KitLook base = denial}) {
    final id = json['id'];
    final label = json['label'];
    final from = json['base'];
    final accent = json['accent'];
    final accentRgb = kitParseRgb(accent);
    final font = _map(json['font']);
    final corners = _map(json['corners']);
    final border = _map(json['border']);
    final motion = _map(json['motion']);
    final icons = _map(json['icons']);
    final dock = _map(json['dock']);
    final bead = motion['bead'];
    final weight = font['weight'];
    final kin = dock['kin'];
    final menuRows = json['accentMenuRows'];
    final follow = corners['followShell'];
    final opaque = json['opaque'];
    final liquid = motion['liquid'];

    String? text(Map<dynamic, dynamic> map, String key, String? fallback) {
      if (!map.containsKey(key)) return fallback;
      final value = map[key];
      if (value == null) return null;
      return value is String && value.isNotEmpty && value.length <= 80
          ? value
          : fallback;
    }

    KitLook make(Map<String, Object?> extra) => KitLook(
      id: id is String && id.isNotEmpty ? id : base.id,
      label: label is String ? label : base.label,
      base: from is String ? from : base.base,
      accentSource: accentRgb != null
          ? KitAccentSource.fixed
          : accent == KitAccentSource.fixed.name
          ? base.accentSource
          : _named(accent, KitAccentSource.values, base.accentSource),
      accentRgb: accentRgb ?? base.accentRgb,
      palette: json.containsKey('palette')
          ? KitPalette.fromJson(json['palette'], base: base.palette)
          : base.palette,
      appearance: _named(
        json['appearance'],
        KitAppearance.values,
        base.appearance,
      ),
      accentMenuRows: menuRows is bool ? menuRows : base.accentMenuRows,
      fontFamily: text(font, 'family', base.fontFamily),
      fontPackage: text(font, 'package', base.fontPackage),
      fontScale: _number(font['scale'], 0.7, 1.5, base.fontScale),
      weightShift: weight is num && weight.isFinite
          ? weight.round().clamp(-3, 3)
          : base.weightShift,
      density: _number(json['density'], 0.7, 1.5, base.density),
      scaleCorners: follow is bool ? follow : base.scaleCorners,
      cornerScale: _number(corners['scale'], 0, 2.5, base.cornerScale),
      borderWidth: _number(border['width'], 0, 6, base.borderWidth),
      borderTone: _named(
        border['tone'],
        KitBorderTone.values,
        base.borderTone,
      ),
      opaque: opaque is bool ? opaque : base.opaque,
      shadow: _number(json['shadow'], 0, 1, base.shadow),
      materials: KitMaterialJson.parseTable(json['materials'], base.materials),
      liquid: liquid is bool ? liquid : base.liquid,
      panelGrow: _parseTuning(motion['panelGrow'], base.panelGrow),
      panelShrink: _parseTuning(motion['panelShrink'], base.panelShrink),
      beadWidth: bead is List && bead.length == 2
          ? _number(bead[0], 0.3, 1, base.beadWidth)
          : base.beadWidth,
      beadHeight: bead is List && bead.length == 2
          ? _number(bead[1], 0.3, 1, base.beadHeight)
          : base.beadHeight,
      pressTuning: _parseTuning(motion['press'], base.pressTuning),
      switchTuning: !motion.containsKey('switch')
          ? base.switchTuning
          : motion['switch'] == null
          ? null
          : _parseTuning(
              motion['switch'],
              base.switchTuning ?? const KitSpringTuning(620, 0.72),
            ),
      pace: _number(motion['pace'], 0.25, 4, base.pace),
      entry: _named(motion['entry'], KitPanelEntry.values, base.entry),
      iconTint: _named(icons['tint'], KitIconTint.values, base.iconTint),
      iconWeight: _number(icons['weight'], 0.5, 2, base.iconWeight),
      dockKin: dockKins.contains(kin) ? kin as String : base.dockKin,
      // A key written as null is one the look stops setting; any other
      // value of the wrong kind leaves what [base] sets.
      dock: <String, Object?>{
        for (final entry in base.dock.entries)
          if (!dock.containsKey(entry.key) || dock[entry.key] != null)
            entry.key: entry.value,
        for (final entry in dockKeys.entries)
          if (_fits(dock[entry.key], entry.value))
            entry.key: dock[entry.key],
      },
      extra: extra,
    );

    final look = make(const <String, Object?>{});
    final extra = _unknown(json, look._known());
    return extra.isEmpty ? look : make(extra);
  }

  static bool _fits(Object? value, Type kind) =>
      (kind == num && value is num && value.isFinite) ||
      (kind == bool && value is bool) ||
      (kind == String && value is String && value.length <= 40);

  /// This look with [changes] laid over it, read as [fromJson] reads.
  KitLook change(Map<String, Object?> changes) =>
      fromJson(kitJsonMerge(toJson(), changes), base: this);

  /// What sets this look apart from [from]: the overrides a look the user
  /// made is stored as. Its name and its id are kept beside them.
  Map<String, Object?> overrides(KitLook from) =>
      kitJsonDiff(from.toJson(), toJson())
        ..remove('id')
        ..remove('label')
        ..remove('base');

  /// A look the user made, from how the store holds it: `base` names a look
  /// that ships and `set` holds the overrides. An unknown base is Denial.
  static KitLook stored(String id, Object? entry) {
    final map = _map(entry);
    final under = builtin(map['base'] is String ? map['base'] as String : null)
        ?? denial;
    final label = map['label'];
    return fromJson(<String, Object?>{
      ...kitJsonMerge(under.toJson(), _map(map['set'])),
      'id': id,
      'label': label is String && label.isNotEmpty ? label : id,
      'base': under.id,
    }, base: under);
  }

  /// This look as the store holds one the user made.
  Map<String, Object?> toStored() {
    final under = builtin(base) ?? denial;
    return <String, Object?>{
      'label': label,
      'base': under.id,
      'set': overrides(under),
    };
  }

  String get _text => jsonEncode(toJson());

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is KitLook && other._text == _text);

  @override
  int get hashCode => _text.hashCode;
}
