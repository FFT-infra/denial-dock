/// A look's own colours, as data: one set of tones for the dark appearance
/// and one for the light. A look that names a palette draws its panels, its
/// text and its lines in these in place of the shell's.
///
/// No Flutter import, so the tables and their JSON run as an ordinary Dart
/// test. Colours are 0xRRGGBB and are written `#rrggbb` in JSON.
library;

/// `#rrggbb` (the `#` may be left out) as 0xRRGGBB, or null.
int? kitParseRgb(Object? value) {
  if (value is! String) return null;
  final text = value.startsWith('#') ? value.substring(1) : value;
  if (text.length != 6) return null;
  return int.tryParse(text, radix: 16);
}

String kitRgbText(int rgb) =>
    '#${(rgb & 0xffffff).toRadixString(16).padLeft(6, '0')}';

/// The tones of one appearance.
class KitTones {
  const KitTones({
    required this.background,
    required this.surface,
    required this.raised,
    required this.text,
    required this.subtext,
    required this.faint,
    required this.outline,
    required this.accent,
    required this.onAccent,
  });

  /// What lies under everything, and what a panel is filled with.
  final int background;
  final int surface;

  /// A control or a tile standing on a panel.
  final int raised;

  /// Ink in three strengths.
  final int text;
  final int subtext;
  final int faint;

  /// Lines.
  final int outline;

  final int accent;
  final int onAccent;

  static const List<String> keys = <String>[
    'background',
    'surface',
    'raised',
    'text',
    'subtext',
    'faint',
    'outline',
    'accent',
    'onAccent',
  ];

  List<int> get _values => <int>[
    background,
    surface,
    raised,
    text,
    subtext,
    faint,
    outline,
    accent,
    onAccent,
  ];

  Map<String, Object?> toJson() => <String, Object?>{
    for (var index = 0; index < keys.length; index++)
      keys[index]: kitRgbText(_values[index]),
  };

  /// [json] over [base], tone by tone: a missing or malformed tone keeps
  /// the one of [base].
  static KitTones fromJson(Object? json, KitTones base) {
    final map = json is Map ? json : const <Object?, Object?>{};
    final from = base._values;
    int at(int index) => kitParseRgb(map[keys[index]]) ?? from[index];
    return KitTones(
      background: at(0),
      surface: at(1),
      raised: at(2),
      text: at(3),
      subtext: at(4),
      faint: at(5),
      outline: at(6),
      accent: at(7),
      onAccent: at(8),
    );
  }
}

class KitPalette {
  const KitPalette({
    required this.id,
    required this.label,
    required this.dark,
    required this.light,
  });

  final String id;
  final String label;
  final KitTones dark;
  final KitTones light;

  KitTones of({required bool dark}) => dark ? this.dark : light;

  /// A palette that ships is written by its id alone; any other in full.
  Object toJson() => identical(byId(id), this)
      ? id
      : <String, Object?>{
          'id': id,
          'label': label,
          'dark': dark.toJson(),
          'light': light.toJson(),
        };

  /// An id of [all], or a palette written in full over [base] (the graphite
  /// one when the look had none). Anything else is no palette.
  static KitPalette? fromJson(Object? json, {KitPalette? base}) {
    if (json is String) return byId(json);
    if (json is! Map) return null;
    final under = base ?? graphite;
    final id = json['id'];
    final label = json['label'];
    return KitPalette(
      id: id is String && id.isNotEmpty ? id : 'custom',
      label: label is String ? label : 'Custom',
      dark: KitTones.fromJson(json['dark'], under.dark),
      light: KitTones.fromJson(json['light'], under.light),
    );
  }

  static KitPalette? byId(String? id) {
    for (final palette in all) {
      if (palette.id == id) return palette;
    }
    return null;
  }

  /// A neutral grey with a blue accent; what a palette written in part
  /// falls back on.
  static const KitPalette graphite = KitPalette(
    id: 'graphite',
    label: 'Graphite',
    dark: KitTones(
      background: 0x16171a,
      surface: 0x1f2125,
      raised: 0x2b2e34,
      text: 0xf2f2f4,
      subtext: 0xc3c5cb,
      faint: 0x8e9199,
      outline: 0x3d4047,
      accent: 0x6aa5ff,
      onAccent: 0x0b1e3a,
    ),
    light: KitTones(
      background: 0xf4f4f6,
      surface: 0xffffff,
      raised: 0xe9eaee,
      text: 0x1b1c1f,
      subtext: 0x4c4f57,
      faint: 0x7d8089,
      outline: 0xd3d5db,
      accent: 0x2f6fe4,
      onAccent: 0xffffff,
    ),
  );

  /// Catppuccin: Mocha in the dark, Latte in the light.
  static const KitPalette catppuccin = KitPalette(
    id: 'catppuccin',
    label: 'Catppuccin',
    dark: KitTones(
      background: 0x11111b,
      surface: 0x1e1e2e,
      raised: 0x313244,
      text: 0xcdd6f4,
      subtext: 0xa6adc8,
      faint: 0x8087a2,
      outline: 0x45475a,
      accent: 0xcba6f7,
      onAccent: 0x1e1e2e,
    ),
    light: KitTones(
      background: 0xdce0e8,
      surface: 0xeff1f5,
      raised: 0xdce0e8,
      text: 0x4c4f69,
      subtext: 0x5c5f77,
      faint: 0x6c6f85,
      outline: 0xbcc0cc,
      accent: 0x7632d6,
      onAccent: 0xeff1f5,
    ),
  );

  static const KitPalette gruvbox = KitPalette(
    id: 'gruvbox',
    label: 'Gruvbox',
    dark: KitTones(
      background: 0x1d2021,
      surface: 0x282828,
      raised: 0x3c3836,
      text: 0xebdbb2,
      subtext: 0xbdae93,
      faint: 0x928374,
      outline: 0x504945,
      accent: 0xfabd2f,
      onAccent: 0x282828,
    ),
    light: KitTones(
      background: 0xf2e5bc,
      surface: 0xfbf1c7,
      raised: 0xebdbb2,
      text: 0x3c3836,
      subtext: 0x5c524a,
      faint: 0x7c6f64,
      outline: 0xd5c4a1,
      accent: 0x935c04,
      onAccent: 0xfbf1c7,
    ),
  );

  /// Tokyo Night: Night in the dark, Day in the light.
  static const KitPalette tokyoNight = KitPalette(
    id: 'tokyo-night',
    label: 'Tokyo Night',
    dark: KitTones(
      background: 0x16161e,
      surface: 0x1a1b26,
      raised: 0x292e42,
      text: 0xc0caf5,
      subtext: 0xa9b1d6,
      faint: 0x737aa2,
      outline: 0x414868,
      accent: 0x7aa2f7,
      onAccent: 0x16161e,
    ),
    light: KitTones(
      background: 0xd0d5e3,
      surface: 0xe1e2e7,
      raised: 0xc4c8da,
      text: 0x24283b,
      subtext: 0x3760bf,
      faint: 0x5b6388,
      outline: 0xa8aecb,
      accent: 0x245bc5,
      onAccent: 0xe1e2e7,
    ),
  );

  static const KitPalette nord = KitPalette(
    id: 'nord',
    label: 'Nord',
    dark: KitTones(
      background: 0x242933,
      surface: 0x2e3440,
      raised: 0x3b4252,
      text: 0xeceff4,
      subtext: 0xd8dee9,
      faint: 0x8893ad,
      outline: 0x4c566a,
      accent: 0x88c0d0,
      onAccent: 0x2e3440,
    ),
    light: KitTones(
      background: 0xe5e9f0,
      surface: 0xeceff4,
      raised: 0xd8dee9,
      text: 0x2e3440,
      subtext: 0x434c5e,
      faint: 0x5f6b82,
      outline: 0xc2c9d6,
      accent: 0x486a94,
      onAccent: 0xeceff4,
    ),
  );

  static const KitPalette everforest = KitPalette(
    id: 'everforest',
    label: 'Everforest',
    dark: KitTones(
      background: 0x232a2e,
      surface: 0x2d353b,
      raised: 0x3d484d,
      text: 0xd3c6aa,
      subtext: 0xa7b3a9,
      faint: 0x859289,
      outline: 0x475258,
      accent: 0xa7c080,
      onAccent: 0x2d353b,
    ),
    light: KitTones(
      background: 0xf4f0d9,
      surface: 0xfdf6e3,
      raised: 0xefebd4,
      text: 0x3d484d,
      subtext: 0x5c6a72,
      faint: 0x708074,
      outline: 0xe0dcc7,
      accent: 0x5c6a00,
      onAccent: 0xfdf6e3,
    ),
  );

  /// Rosé Pine: the main variant in the dark, Dawn in the light.
  static const KitPalette rosePine = KitPalette(
    id: 'rose-pine',
    label: 'Rosé Pine',
    dark: KitTones(
      background: 0x191724,
      surface: 0x1f1d2e,
      raised: 0x26233a,
      text: 0xe0def4,
      subtext: 0xa29ec0,
      faint: 0x7f7a9c,
      outline: 0x403d52,
      accent: 0xc4a7e7,
      onAccent: 0x191724,
    ),
    light: KitTones(
      background: 0xf2e9e1,
      surface: 0xfaf4ed,
      raised: 0xfffaf3,
      text: 0x4b466a,
      subtext: 0x676284,
      faint: 0x787394,
      outline: 0xdfdad9,
      accent: 0x72598d,
      onAccent: 0xfaf4ed,
    ),
  );

  /// The Material 3 baseline scheme.
  static const KitPalette material = KitPalette(
    id: 'material',
    label: 'Material',
    dark: KitTones(
      background: 0x141218,
      surface: 0x211f24,
      raised: 0x2b2930,
      text: 0xe6e0e9,
      subtext: 0xcac4d0,
      faint: 0x938f99,
      outline: 0x49454f,
      accent: 0xd0bcff,
      onAccent: 0x381e72,
    ),
    light: KitTones(
      background: 0xfef7ff,
      surface: 0xf2ecf4,
      raised: 0xe6e0e9,
      text: 0x1d1b20,
      subtext: 0x49454f,
      faint: 0x6b6670,
      outline: 0xcac4d0,
      accent: 0x6750a4,
      onAccent: 0xffffff,
    ),
  );

  /// A deep indigo with a pale gold accent, after Noctalia's palette.
  static const KitPalette midnight = KitPalette(
    id: 'midnight',
    label: 'Midnight',
    dark: KitTones(
      background: 0x111226,
      surface: 0x15162e,
      raised: 0x20213d,
      text: 0xece9f4,
      subtext: 0xa5a7c6,
      faint: 0x7d80a1,
      outline: 0x3e4166,
      accent: 0xf7e9a8,
      onAccent: 0x302c1e,
    ),
    light: KitTones(
      background: 0xd2d4e4,
      surface: 0xdcddea,
      raised: 0xcfd2e4,
      text: 0x292b45,
      subtext: 0x414765,
      faint: 0x5c6282,
      outline: 0xa4aac9,
      accent: 0x5058b1,
      onAccent: 0xf0eff7,
    ),
  );

  /// The greys and the blue of KDE's Breeze.
  static const KitPalette breeze = KitPalette(
    id: 'breeze',
    label: 'Breeze',
    dark: KitTones(
      background: 0x1b1e20,
      surface: 0x2a2e32,
      raised: 0x31363b,
      text: 0xfcfcfc,
      subtext: 0xbdc3c7,
      faint: 0x8b9398,
      outline: 0x4d5257,
      accent: 0x3daee9,
      onAccent: 0x0b1d2b,
    ),
    light: KitTones(
      background: 0xdee0e2,
      surface: 0xeff0f1,
      raised: 0xfcfcfc,
      text: 0x232629,
      subtext: 0x4f5458,
      faint: 0x6c757a,
      outline: 0xc4c7ca,
      accent: 0x3daee9,
      onAccent: 0x0b1d2b,
    ),
  );

  /// The greys and the blue of GNOME's Adwaita.
  static const KitPalette adwaita = KitPalette(
    id: 'adwaita',
    label: 'Adwaita',
    dark: KitTones(
      background: 0x1d1d20,
      surface: 0x2a2a2e,
      raised: 0x3a3a3f,
      text: 0xffffff,
      subtext: 0xc0bfbc,
      faint: 0x9a9996,
      outline: 0x47474c,
      accent: 0x2974d1,
      onAccent: 0xffffff,
    ),
    light: KitTones(
      background: 0xebebed,
      surface: 0xfafafb,
      raised: 0xe1e1e4,
      text: 0x1f1f23,
      subtext: 0x5e5c64,
      faint: 0x77767b,
      outline: 0xcfced4,
      accent: 0x246fd1,
      onAccent: 0xffffff,
    ),
  );

  /// The greys and the blues of Windows 11's Fluent.
  static const KitPalette fluent = KitPalette(
    id: 'fluent',
    label: 'Fluent',
    dark: KitTones(
      background: 0x202020,
      surface: 0x2c2c2c,
      raised: 0x383838,
      text: 0xffffff,
      subtext: 0xc5c5c5,
      faint: 0x9a9a9a,
      outline: 0x454545,
      accent: 0x60cdff,
      onAccent: 0x003a57,
    ),
    light: KitTones(
      background: 0xf3f3f3,
      surface: 0xfbfbfb,
      raised: 0xeaeaea,
      text: 0x1a1a1a,
      subtext: 0x5f5f5f,
      faint: 0x7a7a7a,
      outline: 0xd9d9d9,
      accent: 0x005fb8,
      onAccent: 0xffffff,
    ),
  );

  /// A flat charcoal with a teal accent, after COSMIC's default theme.
  static const KitPalette slate = KitPalette(
    id: 'slate',
    label: 'Slate',
    dark: KitTones(
      background: 0x1b1b1b,
      surface: 0x272727,
      raised: 0x343434,
      text: 0xe6e6e6,
      subtext: 0xbebebe,
      faint: 0x8c8c8c,
      outline: 0x454545,
      accent: 0x63d0df,
      onAccent: 0x00252b,
    ),
    light: KitTones(
      background: 0xd9d9d9,
      surface: 0xeeeeee,
      raised: 0xe2e2e2,
      text: 0x1b1b1b,
      subtext: 0x4a4a4a,
      faint: 0x686868,
      outline: 0xc2c2c2,
      accent: 0x00525a,
      onAccent: 0xffffff,
    ),
  );

  /// Crisp frosted neutrals with sky blue, after Cutefish OS.
  static const KitPalette cutefish = KitPalette(
    id: 'cutefish',
    label: 'Cutefish',
    dark: KitTones(
      background: 0x1a1a1c,
      surface: 0x242426,
      raised: 0x333336,
      text: 0xf4f4f6,
      subtext: 0xbabac0,
      faint: 0x8a8a92,
      outline: 0x424247,
      accent: 0x3b8bff,
      onAccent: 0x08162b,
    ),
    light: KitTones(
      background: 0xf2f4f7,
      surface: 0xfafbfc,
      raised: 0xeaeef5,
      text: 0x1c1e21,
      subtext: 0x5c6068,
      faint: 0x707680,
      outline: 0xd5dae2,
      accent: 0x1863d6,
      onAccent: 0xffffff,
    ),
  );

  static const List<KitPalette> all = <KitPalette>[
    graphite,
    catppuccin,
    gruvbox,
    tokyoNight,
    nord,
    everforest,
    rosePine,
    material,
    midnight,
    breeze,
    adwaita,
    fluent,
    slate,
    cutefish,
  ];
}
