/// Looks made after other desktop shells, as data.
///
/// Each one is this shell's own components set to resemble what the named
/// project draws by default: its colours, its corners, its materials and the
/// way its panels come on. Nothing of those projects is used here, neither
/// code nor artwork, and none of these is a port: the labels say "style".
/// What a look cannot reproduce is written above it.
///
/// The arrangement of the bar and the dock that goes with each look is the
/// preset of the same id in `shell_preset.dart`.
library;

import 'kit_look.dart';
import 'kit_palette.dart';

/// After Noctalia's default: solid, softly rounded surfaces in a deep
/// indigo with a pale gold accent, little shadow, panels that scale in.
///
/// Not reproduced: its bar widgets' own capsule backgrounds, and its
/// panels being attached to the bar with an inverted corner.
const KitLook _noctalia = KitLook(
  id: 'noctalia',
  label: 'Noctalia style',
  palette: KitPalette.midnight,
  accentSource: KitAccentSource.palette,
  scaleCorners: false,
  opaque: true,
  shadow: 0.45,
  cornerScale: 0.85,
  accentMenuRows: true,
  panelGrow: KitSpringTuning(560, 0.92),
  beadWidth: 0.9,
  beadHeight: 0.9,
  entry: KitPanelEntry.zoom,
  switchTuning: KitSpringTuning(620, 1),
  dockKin: 'soft',
  dock: <String, Object?>{'radius': 16, 'indicator': 'dot', 'magnify': false},
);

/// After DankMaterialShell's default: Material 3 tones with the baseline
/// purple, large corners, filled accent rows, lively springs.
///
/// Not reproduced: Material's state layers and ripples, its type scale
/// (the look keeps the shell's font unless the user names one), and colour
/// schemes generated from the wallpaper beyond the accent.
const KitLook _material = KitLook(
  id: 'material',
  label: 'Material style',
  palette: KitPalette.material,
  accentSource: KitAccentSource.palette,
  scaleCorners: false,
  opaque: true,
  shadow: 0.7,
  cornerScale: 1.35,
  borderWidth: 0,
  accentMenuRows: true,
  liquid: true,
  panelGrow: KitSpringTuning(480, 0.78),
  panelShrink: KitSpringTuning(760, 1),
  pressTuning: KitSpringTuning(560, 0.7),
  switchTuning: KitSpringTuning(520, 0.75),
  beadWidth: 0.86,
  beadHeight: 0.86,
  entry: KitPanelEntry.zoom,
  dockKin: 'soft',
  dock: <String, Object?>{'radius': 24, 'indicator': 'pill', 'magnify': false},
);

/// After HyprPanel's default: Catppuccin Mocha / Latte following system
/// appearance, flat and solid, heavier type, panels that fade in.
const KitLook _hyprpanel = KitLook(
  id: 'hyprpanel',
  label: 'HyprPanel style',
  palette: KitPalette.catppuccin,
  accentSource: KitAccentSource.palette,
  scaleCorners: false,
  opaque: true,
  shadow: 0.3,
  cornerScale: 0.6,
  weightShift: 1,
  accentMenuRows: true,
  panelGrow: KitSpringTuning(700, 1),
  entry: KitPanelEntry.fade,
  switchTuning: KitSpringTuning(700, 1),
  dockKin: 'soft',
  dock: <String, Object?>{'radius': 12, 'indicator': 'line', 'magnify': false},
);

/// After Ax-Shell's default: solid pills coloured from the wallpaper,
/// round corners, panels that slide out with an overshoot.
const KitLook _axShell = KitLook(
  id: 'axshell',
  label: 'Ax-Shell style',
  palette: KitPalette.graphite,
  scaleCorners: false,
  opaque: true,
  shadow: 0.5,
  cornerScale: 1.15,
  borderWidth: 0,
  panelGrow: KitSpringTuning(620, 0.68),
  panelShrink: KitSpringTuning(900, 1),
  pressTuning: KitSpringTuning(620, 0.7),
  entry: KitPanelEntry.slide,
  pace: 0.9,
  dockKin: 'soft',
  dock: <String, Object?>{'radius': 18, 'indicator': 'dot'},
);

/// After KDE Plasma's default panel: Breeze greys and blue, translucent
/// and blurred, small corners, a hairline around every surface, panels
/// that slide out of the panel.
const KitLook _plasma = KitLook(
  id: 'plasma',
  label: 'Plasma style',
  palette: KitPalette.breeze,
  accentSource: KitAccentSource.palette,
  scaleCorners: false,
  shadow: 0.7,
  cornerScale: 0.45,
  accentMenuRows: true,
  panelGrow: KitSpringTuning(640, 1),
  entry: KitPanelEntry.slide,
  pace: 0.85,
  switchTuning: KitSpringTuning(700, 1),
  dockKin: 'soft',
  dock: <String, Object?>{
    'radius': 8,
    'indicator': 'line',
    'iconSize': 40,
    'magnify': false,
    'opacity': 0.8,
  },
);

/// After GNOME Shell's default: Adwaita, following system light/dark, solid
/// rounded popovers that scale in, a rounded dash.
const KitLook _gnome = KitLook(
  id: 'gnome',
  label: 'GNOME style',
  palette: KitPalette.adwaita,
  accentSource: KitAccentSource.palette,
  scaleCorners: false,
  opaque: true,
  shadow: 0.6,
  cornerScale: 0.95,
  borderWidth: 0,
  accentMenuRows: false,
  panelGrow: KitSpringTuning(600, 1),
  beadWidth: 0.9,
  beadHeight: 0.9,
  entry: KitPanelEntry.zoom,
  switchTuning: KitSpringTuning(620, 1),
  dockKin: 'soft',
  dock: <String, Object?>{'radius': 22, 'indicator': 'dot', 'magnify': false},
);

/// After the Windows 11 taskbar: Fluent greys and blue, translucent and
/// blurred, 8 px corners, a hairline, flyouts that slide up, a short
/// underline under a running application.
const KitLook _windows = KitLook(
  id: 'windows',
  label: 'Windows 11 style',
  palette: KitPalette.fluent,
  accentSource: KitAccentSource.palette,
  scaleCorners: false,
  shadow: 0.8,
  cornerScale: 0.55,
  panelGrow: KitSpringTuning(600, 1),
  entry: KitPanelEntry.slide,
  pace: 0.85,
  switchTuning: KitSpringTuning(700, 1),
  dockKin: 'soft',
  dock: <String, Object?>{
    'radius': 0,
    'indicator': 'line',
    'iconSize': 36,
    'magnify': false,
    'opacity': 0.82,
    'highlight': true,
  },
);

/// After COSMIC's default: a flat charcoal with a teal accent, solid, the
/// "slightly round" corners, little shadow, panels that fade in.
const KitLook _cosmic = KitLook(
  id: 'cosmic',
  label: 'COSMIC style',
  palette: KitPalette.slate,
  accentSource: KitAccentSource.palette,
  scaleCorners: false,
  opaque: true,
  shadow: 0.4,
  cornerScale: 0.55,
  accentMenuRows: true,
  panelGrow: KitSpringTuning(680, 1),
  entry: KitPanelEntry.fade,
  switchTuning: KitSpringTuning(700, 1),
  dockKin: 'soft',
  dock: <String, Object?>{'radius': 12, 'indicator': 'dot', 'magnify': false},
);

/// After Cutefish OS: clean translucent top bar and rounded floating dock,
/// blue accent, soft rounded geometry and zoom panels.
const KitLook _cutefish = KitLook(
  id: 'cutefish',
  label: 'Cutefish style',
  palette: KitPalette.cutefish,
  accentSource: KitAccentSource.palette,
  scaleCorners: false,
  shadow: 0.75,
  cornerScale: 0.85,
  accentMenuRows: true,
  panelGrow: KitSpringTuning(560, 1),
  entry: KitPanelEntry.zoom,
  switchTuning: KitSpringTuning(640, 1),
  dockKin: 'mac',
  dock: <String, Object?>{
    'radius': 18,
    'indicator': 'dot',
    'iconSize': 44,
    'magnify': false,
    'opacity': 0.76,
  },
);

const List<KitLook> kitReferenceLooks = <KitLook>[
  _noctalia,
  _material,
  _hyprpanel,
  _axShell,
  _plasma,
  _gnome,
  _windows,
  _cosmic,
  _cutefish,
];
