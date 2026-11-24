import 'package:flutter/widgets.dart';

/// SF Symbols-shaped glyphs taken from the Cupertino icon font.
///
/// The font is vendored in `assets/CupertinoIcons.ttf` and declared in
/// `pubspec.yaml` under the package-qualified family, so these codepoints
/// resolve without depending on the `cupertino_icons` package.
abstract final class BarIcons {
  static const IconData batteryFull = IconData(
    0xf113,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const IconData battery75 = IconData(
    0xf114,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const IconData battery25 = IconData(
    0xf115,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const IconData batteryEmpty = IconData(
    0xf112,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const IconData batteryCharging = IconData(
    0xf111,
    fontFamily: _family,
    fontPackage: _package,
  );

  static const IconData volumeUp = IconData(
    0xf3ba,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const IconData volumeDown = IconData(
    0xf3b7,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const IconData volumeMute = IconData(
    0xf3b8,
    fontFamily: _family,
    fontPackage: _package,
  );

  static const IconData wifi = IconData(
    0xf89b,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const IconData wifiSlash = IconData(
    0xf89d,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const IconData wifiWarning = IconData(
    0xf89c,
    fontFamily: _family,
    fontPackage: _package,
  );

  static const IconData bluetooth = IconData(
    0xf116,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const IconData bell = IconData(
    0xf3e1,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const IconData bellFill = IconData(
    0xf3e2,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const IconData bellSlash = IconData(
    0xf58c,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const IconData gear = IconData(
    0xf43c,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const IconData search = IconData(
    0xf4a5,
    fontFamily: _family,
    fontPackage: _package,
  );

  static const IconData chevronLeft = IconData(
    0xf3d2,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const IconData chevronRight = IconData(
    0xf3d3,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const IconData chevronDown = IconData(
    0xf5d5,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const IconData chevronUp = IconData(
    0xf5e5,
    fontFamily: _family,
    fontPackage: _package,
  );

  static const IconData play = IconData(
    0xf487,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const IconData playFill = IconData(
    0xf488,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const IconData pause = IconData(
    0xf477,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const IconData pauseFill = IconData(
    0xf478,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const IconData forward = IconData(
    0xf3d1,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const IconData backward = IconData(
    0xf577,
    fontFamily: _family,
    fontPackage: _package,
  );

  static const IconData moon = IconData(
    0xf716,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const IconData moonFill = IconData(
    0xf719,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const IconData lock = IconData(
    0xf4c8,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const IconData power = IconData(
    0xf785,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const IconData ellipsis = IconData(
    0xf46a,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const IconData sunMax = IconData(
    0xf4b6,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const IconData sunMaxFill = IconData(
    0xf4b7,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const IconData airplane = IconData(
    0xf4d4,
    fontFamily: _family,
    fontPackage: _package,
  );

  static const IconData arrowClockwise = IconData(
    0xf49a,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const IconData plus = IconData(
    0xf489,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const IconData minus = IconData(
    0xf70f,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const IconData checkmark = IconData(
    0xf3fd,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const IconData xmark = IconData(
    0xf404,
    fontFamily: _family,
    fontPackage: _package,
  );

  static const IconData folder = IconData(
    0xf434,
    fontFamily: _family,
    fontPackage: _package,
  );

  static const IconData clipboard = IconData(
    0xf632,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const IconData doc = IconData(
    0xf62d,
    fontFamily: _family,
    fontPackage: _package,
  );

  static const IconData chevronLeft2 = IconData(
    0xf5da,
    fontFamily: _family,
    fontPackage: _package,
  );

  static const IconData chevronRight2 = IconData(
    0xf5e0,
    fontFamily: _family,
    fontPackage: _package,
  );

  static const IconData trash = IconData(
    0xf4c4,
    fontFamily: _family,
    fontPackage: _package,
  );

  static const IconData speaker1Fill = IconData(
    0xf3b7,
    fontFamily: _family,
    fontPackage: _package,
  );

  static const IconData speaker3Fill = IconData(
    0xf3ba,
    fontFamily: _family,
    fontPackage: _package,
  );

  static const IconData headphones = IconData(
    0xf6bb,
    fontFamily: _family,
    fontPackage: _package,
  );

  static const IconData lockFill = IconData(
    0xf4c9,
    fontFamily: _family,
    fontPackage: _package,
  );

  static const IconData desktopcomputer = IconData(
    0xf625,
    fontFamily: _family,
    fontPackage: _package,
  );

  static const IconData circleHalf = IconData(
    0xf5f0,
    fontFamily: _family,
    fontPackage: _package,
  );

  static const IconData rectangleStack = IconData(
    0xf7b0,
    fontFamily: _family,
    fontPackage: _package,
  );

  static const IconData tv = IconData(
    0xf881,
    fontFamily: _family,
    fontPackage: _package,
  );

  static const IconData xmarkCircleFill = IconData(
    0xf36e,
    fontFamily: _family,
    fontPackage: _package,
  );

  static const IconData resize = IconData(
    0xf386,
    fontFamily: _family,
    fontPackage: _package,
  );

  static const IconData stopFill = IconData(
    0xf82b,
    fontFamily: _family,
    fontPackage: _package,
  );

  static const IconData eyeSlash = IconData(
    0xf662,
    fontFamily: _family,
    fontPackage: _package,
  );

  static const IconData timer = IconData(
    0xf868,
    fontFamily: _family,
    fontPackage: _package,
  );

  static const IconData speakerSlashFill = IconData(
    0xf3b9,
    fontFamily: _family,
    fontPackage: _package,
  );

  static const IconData camera = IconData(
    0xf3f5,
    fontFamily: _family,
    fontPackage: _package,
  );

  static const IconData bolt = IconData(
    0xf593,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const IconData boltFill = IconData(
    0xf598,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const IconData arrowUp = IconData(
    0xf366,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const IconData arrowDown = IconData(
    0xf35d,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const IconData grid = IconData(
    0xf804,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const IconData circleFill = IconData(
    0xf400,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const IconData person = IconData(
    0xf47d,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const IconData house = IconData(
    0xf447,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const IconData sliderHorizontal3 = IconData(
    0xf7dc,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const IconData display = IconData(
    0xf7dd,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const IconData capslock = IconData(
    0xf5ba,
    fontFamily: _family,
    fontPackage: _package,
  );

  static const String _family = 'CupertinoIcons';
  static const String _package = 'denial_topbar';
  static const IconData calendar = IconData(
    0xf5b0,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const IconData globe = IconData(
    0xf68d,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const IconData clock = IconData(
    0xf4be,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const IconData paintbrushFill = IconData(
    0xf72f,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const IconData capsuleFill = IconData(
    0xf5bd,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const IconData squareGrid = IconData(
    0xf805,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const IconData appBadgeFill = IconData(
    0xf4df,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const IconData rectangle3 = IconData(
    0xf79d,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const IconData lineHorizontal3 = IconData(
    0xf6e1,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const IconData macwindow = IconData(
    0xf702,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const IconData cpu = IconData(
    0xf7f5,
    fontFamily: _family,
    fontPackage: _package,
  );
}

/// A glyph sized for the bar's status cluster.
class BarGlyph extends StatelessWidget {
  const BarGlyph(
    this.icon, {
    required this.size,
    required this.color,
    this.semanticLabel,
    super.key,
  });

  final IconData icon;
  final double size;
  final Color color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Icon(icon, size: size, color: color, semanticLabel: semanticLabel);
  }
}
