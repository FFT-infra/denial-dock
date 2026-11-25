import 'package:denial_dock/src/dock_look.dart';
import 'package:denial_dock/src/dock_settings.dart';

void main() {
  // Each look of the shell has its own preset; an unknown one is Denial's.
  _expect(identical(DockLook.preset('mac'), DockLook.mac), 'mac preset');
  _expect(identical(DockLook.preset('denial'), DockLook.denial), 'denial');
  _expect(identical(DockLook.preset(null), DockLook.denial), 'no look');
  _expect(identical(DockLook.preset('other'), DockLook.denial), 'unknown look');

  // A look of the shell dresses the preset from its own values. One that
  // changes nothing leaves the preset as it is, object for object.
  _expect(
    identical(DockLook.styled(DockLook.denial), DockLook.denial) &&
        identical(DockLook.styled(DockLook.mac), DockLook.mac),
    'a plain look keeps the preset',
  );
  // Opaque panels with a lighter shadow: a solid fill, nothing blurred.
  final solid = DockLook.styled(DockLook.denial, opaque: true, shadow: 0.6);
  _expect(solid.opacity == 1 && solid.blur == 0, 'solid fill, no blur');
  _expect(solid.shadow > 0 && solid.shadow < 0.3, 'a light shadow');
  _expect(
    solid.radius == DockLook.denial.radius &&
        solid.padding == DockLook.denial.padding &&
        solid.edgeMargin == DockLook.denial.edgeMargin &&
        !solid.accentBorder,
    'the measures stay',
  );
  // A 2 px accent line, opaque, no shadow.
  final lined = DockLook.styled(
    DockLook.denial,
    borderWidth: 2,
    accentBorder: true,
    opaque: true,
    shadow: 0,
  );
  _expect(
    lined.borderWidth == 2 &&
        lined.accentBorder &&
        lined.opacity == 1 &&
        lined.shadow == 0,
    'outlined in the accent',
  );
  // The user's overrides still lie on top, and the accent rim survives them.
  final mine = DockLook.resolve(lined, const {'opacity': 0.5, 'shadow': 0.4});
  _expect(
    mine.opacity == 0.5 && mine.shadow == 0.4 && mine.accentBorder,
    'overrides on a styled preset',
  );

  // The macOS preset is the measured one: a blur counted in pixels, corners
  // of 22, no shadow, 5 from the edge.
  _expect(DockLook.mac.blur < DockLook.denial.blur, 'mac blurs less');
  _expect(
    (DockLook.mac.blurSigma! - 1.6).abs() < 1e-9,
    'mac blurs 1.6 logical pixels',
  );
  _expect(
    DockLook.mac.radius == 22 &&
        DockLook.mac.shadow == 0 &&
        DockLook.mac.edgeMargin == 5,
    'mac geometry',
  );
  _expect(
    DockLook.mac.opacity != null && DockLook.mac.opacity! < 0.5,
    'mac names a light fill',
  );
  _expect(DockLook.denial.opacity == null, 'denial follows the system');
  _expect(DockLook.denial.blurSigma == null, 'denial follows the system blur');

  // A blur kept from when the macOS preset counted it as a share of the
  // system's blur: it reads in pixels now, as what that share drew on the
  // shell's starting level (0.45 of 6 was the old preset), and the slider's
  // range holds it. Under Denial the same number is still a share.
  final kept45 = DockLook.resolve(DockLook.mac, const {'blur': 0.45});
  _expect((kept45.blurSigma! - 2.7).abs() < 1e-9, 'an old 0.45 is 2.7 px');
  final full = DockLook.resolve(DockLook.mac, const {'blur': 1});
  _expect(full.blurSigma == DockLook.shellBlurSigma, 'the slider ends at 6');
  final off = DockLook.resolve(DockLook.mac, const {'blur': 0});
  _expect(off.blurSigma == 0, 'and starts at none');
  _expect(
    DockLook.resolve(DockLook.denial, const {'blur': 0.45}).blurSigma == null,
    'a share stays a share under denial',
  );
  _expect(
    DockLook.mac.blur >= DockLook.minBlur && DockLook.mac.blur <= DockLook.maxBlur,
    'the preset lies inside the slider',
  );
  _expect(
    DockLook.mac.edgeMargin < DockLook.denial.edgeMargin,
    'mac sits closer to the edge',
  );

  // Denial's preset is what the dock always drew.
  const denial = DockLook.denial;
  _expect(
    denial.blur == 1 &&
        denial.radius == 20 &&
        denial.border &&
        denial.borderWidth == 1 &&
        denial.shadow == 0 &&
        denial.padding == DockSettings.padding &&
        denial.endPadding == DockSettings.edgePadding &&
        denial.gap == DockSettings.gap &&
        denial.edgeMargin == 10 &&
        denial.magnifyRange == DockSettings.magnificationRadius &&
        denial.shape == DockShape.floating &&
        denial.markerColor == DockMarkerColor.auto,
    'denial keeps the old numbers',
  );

  // No overrides is the preset itself, value for value.
  final plain = DockLook.resolve(DockLook.mac, const {});
  _expect(
    plain.blur == DockLook.mac.blur &&
        plain.opacity == DockLook.mac.opacity &&
        plain.radius == DockLook.mac.radius &&
        plain.shape == DockLook.mac.shape,
    'no overrides keeps the preset',
  );

  // An override replaces one value and leaves the rest on the preset, so the
  // same overrides read differently under another look.
  const overrides = {'blur': 0.8, 'shape': 'bar', 'border': false};
  final onMac = DockLook.resolve(DockLook.mac, overrides);
  final onDenial = DockLook.resolve(DockLook.denial, overrides);
  _expect(onMac.blur == 0.8 && onDenial.blur == 0.8, 'the override wins');
  _expect(!onMac.border && onMac.shape == DockShape.bar, 'bool and enum read');
  _expect(
    onMac.radius == DockLook.mac.radius &&
        onDenial.radius == DockLook.denial.radius,
    'untouched values follow the look',
  );

  // A bar lies on its edge with square corners, whatever the numbers say.
  _expect(
    onMac.effectiveEdgeMargin == 0 && onMac.effectiveRadius == 0,
    'a bar has no margin and no radius',
  );
  _expect(
    plain.effectiveEdgeMargin == plain.edgeMargin &&
        plain.effectiveRadius == plain.radius,
    'a floating capsule keeps both',
  );

  // Numbers are clamped into their ranges; anything of the wrong kind, and
  // any name this build does not know, keeps the preset's value.
  final wild = DockLook.resolve(DockLook.denial, const {
    'blur': 7,
    'opacity': -2,
    'radius': 900,
    'borderWidth': 0,
    'padding': 'wide',
    'gap': double.nan,
    'tint': 'plaid',
    'markerColor': 'ink',
    'border': 'yes',
    'someday': 3,
  });
  _expect(wild.blur == DockLook.maxBlur, 'blur clamps');
  _expect(wild.opacity == DockLook.minOpacity, 'opacity clamps');
  _expect(wild.radius == DockLook.maxRadius, 'radius clamps');
  _expect(wild.borderWidth == DockLook.minBorderWidth, 'width clamps');
  _expect(wild.padding == DockLook.denial.padding, 'a string is not a number');
  _expect(wild.gap == DockLook.denial.gap, 'nan is not a number');
  _expect(wild.tint == DockLook.denial.tint, 'an unknown name is ignored');
  _expect(wild.markerColor == DockMarkerColor.ink, 'a known name reads');
  _expect(wild.border == DockLook.denial.border, 'a string is not a bool');

  // What the file holds is carried as it is, unknown keys included; anything
  // that is not a map reads as no overrides.
  final kept = DockLook.cleaned(const {'blur': 0.3, 'someday': 3, 4: 'x'});
  _expect(
    kept.length == 2 && kept['someday'] == 3 && kept['blur'] == 0.3,
    'unknown keys survive',
  );
  _expect(DockLook.cleaned('glass').isEmpty, 'a string is no overrides');
  _expect(DockLook.cleaned(null).isEmpty, 'nothing is no overrides');

  // Setting and restoring one value leaves the others alone.
  final set = DockLook.withOverride(kept, 'gap', 12.0);
  _expect(set['gap'] == 12.0 && set['someday'] == 3, 'one value is set');
  final restored = DockLook.withOverride(set, 'gap', null);
  _expect(
    !restored.containsKey('gap') && restored['someday'] == 3,
    'null restores the preset',
  );

  // A settings file written before the look existed reads as the preset, and
  // a round trip through the settings keeps overrides this build ignores.
  final old = DockSettings.fromJson(const {'visibility': 'smart'});
  _expect(old.look.isEmpty, 'an old file has no overrides');
  _expect(
    old.lookFor('mac').blur == DockLook.mac.blur &&
        old.lookFor(null).blur == DockLook.denial.blur,
    'an old file follows the look',
  );
  final newer = DockSettings.fromJson(const {
    'look': {'blur': 0.2, 'someday': true},
  });
  _expect(newer.lookFor('mac').blur == 0.2, 'the file overrides the preset');
  _expect(newer.look['someday'] == true, 'the unknown key is carried');
  _expect(
    newer.copyWith(iconSize: 56).look['someday'] == true,
    'and survives a change elsewhere',
  );
  _expect(
    DockSettings.fromJson(const {'look': 'broken'}).look.isEmpty,
    'a malformed look reads as none',
  );
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
