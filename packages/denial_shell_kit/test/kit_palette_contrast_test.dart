import 'dart:math' as math;

import 'package:denial_shell_kit/kit_look.dart';
import 'package:denial_shell_kit/kit_look_refs.dart';
import 'package:denial_shell_kit/kit_palette.dart';
import 'package:denial_shell_kit/shell_preset.dart';

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}

double _channel(int c) {
  final s = c / 255.0;
  return s <= 0.03928 ? s / 12.92 : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
}

double _luminance(int rgb) {
  final r = _channel((rgb >> 16) & 0xff);
  final g = _channel((rgb >> 8) & 0xff);
  final b = _channel(rgb & 0xff);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

double _contrast(int a, int b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  for (final palette in KitPalette.all) {
    for (final (name, tones) in <({String name, KitTones tones})>[
      (name: 'dark', tones: palette.dark),
      (name: 'light', tones: palette.light),
    ].map((e) => (e.name, e.tones))) {
      final textOnSurface = _contrast(tones.text, tones.surface);
      final textOnRaised = _contrast(tones.text, tones.raised);
      final subtextOnSurface = _contrast(tones.subtext, tones.surface);
      final faintOnSurface = _contrast(tones.faint, tones.surface);
      final onAccent = _contrast(tones.onAccent, tones.accent);
      _expect(
        textOnSurface >= 4.5,
        '${palette.id}.$name text/surface contrast too low: $textOnSurface',
      );
      _expect(
        textOnRaised >= 4.5,
        '${palette.id}.$name text/raised contrast too low: $textOnRaised',
      );
      _expect(
        subtextOnSurface >= 3.5,
        '${palette.id}.$name subtext/surface contrast too low: $subtextOnSurface',
      );
      _expect(
        faintOnSurface >= 2.8,
        '${palette.id}.$name faint/surface contrast too low: $faintOnSurface',
      );
      _expect(
        onAccent >= 4.5,
        '${palette.id}.$name onAccent/accent contrast too low: $onAccent',
      );
    }
  }

  for (final look in KitLook.builtins) {
    _expect(
      look.appearance == KitAppearance.system,
      '${look.id} follows system light/dark by default',
    );
  }
  for (final look in kitReferenceLooks) {
    _expect(!look.scaleCorners, '${look.id} keeps reference corner geometry');
  }
  _expect(
    ShellPreset.omarchy.look == 'omarchy',
    'omarchy preset uses dedicated omarchy look',
  );
  _expect(
    ShellPreset.taskbar.dockVisible == true &&
        ShellPreset.plasma.dockVisible == true &&
        ShellPreset.mac.dockVisible == true,
    'dock-bearing presets set dockVisible = true',
  );
}
