import 'dart:convert';

import 'package:denial_shell_kit/kit_look.dart';
import 'package:denial_shell_kit/kit_material.dart';
import 'package:denial_shell_kit/kit_palette.dart';

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}

/// What a file holds: the look's JSON through text and back.
Map<String, dynamic> _disk(KitLook look) =>
    jsonDecode(jsonEncode(look.toJson())) as Map<String, dynamic>;

void main() {
  // Every look that ships reads back as itself, from its own JSON alone:
  // nothing is filled in from the look it is read over.
  _expect(KitLook.builtins.length >= 4, 'the four looks ship');
  final ids = <String>{for (final look in KitLook.builtins) look.id};
  _expect(ids.length == KitLook.builtins.length, 'no two looks share an id');
  for (final look in KitLook.builtins) {
    for (final under in <KitLook>[KitLook.denial, KitLook.terminal]) {
      final back = KitLook.fromJson(_disk(look), base: under);
      _expect(back == look, '${look.id} survives its JSON over ${under.id}');
      _expect(
        jsonEncode(back.toJson()) == jsonEncode(look.toJson()),
        '${look.id} writes the same JSON twice',
      );
    }
    _expect(look.base == null, '${look.id} ships, so it has no base');
    _expect(
      KitLook.dockKins.contains(look.dockKin),
      '${look.id} takes after a dock preset that exists',
    );
    final palette = look.palette;
    _expect(
      palette == null || identical(KitPalette.byId(palette.id), palette),
      '${look.id} names a palette that ships',
    );
  }

  // The materials are part of that: the measured macOS numbers come back
  // digit for digit.
  final mac = KitLook.fromJson(_disk(KitLook.mac));
  final dock = mac.materials.dock.dark;
  _expect(dock.sigma == 1.6 && dock.saturation == 2.0, 'the dock blur');
  _expect(
    dock.fill.fixed && dock.fill.rgb == 0x222222 && dock.fill.alpha == 0.36,
    'the dock fill',
  );
  _expect(
    dock.inner!.edges == KitEdges.topBottom &&
        dock.inner!.tail == 0.07 &&
        dock.inner!.reach == 7 &&
        dock.outer!.width == 0.5 &&
        dock.outer!.edges == KitEdges.ends,
    'the dock rim',
  );
  _expect(
    mac.materials.popover.light.shadow!.blur == 36 &&
        mac.materials.popover.light.shadow!.tone.alpha == 0.08 &&
        mac.materials.cardLayout.width == 344,
    'the popover shadow and the card column',
  );
  final shell = KitLook.fromJson(_disk(KitLook.denial), base: KitLook.mac);
  _expect(
    shell.materials.popover.dark.fill.role == KitRole.panel &&
        shell.materials.popover.dark.fill.alpha == null &&
        shell.materials.popover.dark.sigma == null &&
        shell.materials.popover.dark.outer == null &&
        shell.materials.popover.dark.shadow!.byLook,
    'a theme tone, a blur that follows the shell and a missing line stay so',
  );

  // Tones as text.
  _expect(
    KitMaterialJson.tone(const KitTone(0x222222, 0.36)) == '#222222@0.36' &&
        KitMaterialJson.tone(const KitTone.of(KitRole.panel)) == 'panel' &&
        KitMaterialJson.tone(const KitTone.of(KitRole.shadow, alpha: 0.3)) ==
            'shadow@0.3',
    'a tone is written as text',
  );
  const fallback = KitTone.of(KitRole.hairline);
  _expect(
    identical(KitMaterialJson.parseTone('nonsense', fallback), fallback) &&
        identical(KitMaterialJson.parseTone('#12@x', fallback), fallback) &&
        identical(KitMaterialJson.parseTone(7, fallback), fallback) &&
        KitMaterialJson.parseTone('#ffffff@7', fallback).alpha == 1 &&
        KitMaterialJson.parseTone('abcdef', fallback).rgb == 0xabcdef,
    'a tone that cannot be read keeps the old one, and its alpha is clamped',
  );

  // Bad data: nothing throws, a wrong kind keeps the base's value, a number
  // out of range is brought into it.
  final bad = KitLook.fromJson(<String, Object?>{
    'id': 7,
    'label': null,
    'accent': '#zzzzzz',
    'palette': 'no-such-palette',
    'appearance': 'purple',
    'accentMenuRows': 'yes',
    'font': <String, Object?>{'family': 12, 'scale': 99, 'weight': -40},
    'density': double.nan,
    'corners': <String, Object?>{'scale': -3, 'followShell': 1},
    'border': <String, Object?>{'width': 1e9, 'tone': 'dotted'},
    'opaque': 'no',
    'shadow': 4,
    'materials': <String, Object?>{
      'dock': 'glass',
      'popover': <String, Object?>{
        'dark': <String, Object?>{
          'fill': 42,
          'sigma': 4000,
          'saturation': -1,
          'radius': 'round',
          'inner': <String, Object?>{'width': -5, 'edges': 'diagonal'},
          'shadow': <String, Object?>{'blur': 9999, 'dy': -9999},
          'solid': 3,
        },
      },
      'cardLayout': <String, Object?>{'width': 5, 'dim': 2},
    },
    'motion': <String, Object?>{
      'liquid': 0,
      'pace': 0,
      'entry': 'explode',
      'bead': <Object?>[9, 'x'],
      'panelGrow': <Object?>[1e9, -1],
      'panelShrink': 'fast',
      'press': <Object?>[1, 2, 3],
      'switch': <Object?>[0, 0],
    },
    'icons': <String, Object?>{'tint': 'rainbow', 'weight': 50},
    'dock': <String, Object?>{'kin': 'windows', 'iconSize': 'big', 'gap': 6},
  }, base: KitLook.mac);
  _expect(bad.id == 'mac' && bad.label == 'macOS', 'the name stays');
  _expect(
    bad.accentSource == KitAccentSource.fixed && bad.accentRgb == 0x0a84ff,
    'a colour that cannot be read keeps the accent',
  );
  _expect(bad.palette == null, 'an unknown palette is none');
  _expect(bad.appearance == KitAppearance.system, 'the appearance stays');
  _expect(bad.accentMenuRows, 'a flag of the wrong kind stays');
  _expect(
    bad.fontFamily == 'Inter' && bad.fontScale == 1.5 && bad.weightShift == -3,
    'the font: family kept, scale and weight clamped',
  );
  _expect(bad.density == 1, 'not-a-number keeps the density');
  _expect(bad.cornerScale == 0 && !bad.scaleCorners, 'corners clamped');
  _expect(
    bad.borderWidth == 6 && bad.borderTone == KitBorderTone.hairline,
    'the border clamped, its tone kept',
  );
  _expect(!bad.opaque && bad.shadow == 1, 'opaque kept, shadow clamped');
  final hurt = bad.materials.popover.dark;
  final sound = KitMaterials.mac.popover.dark;
  _expect(
    identical(bad.materials.dock, KitMaterials.mac.dock),
    'a tier that is no map is the base tier',
  );
  _expect(
    hurt.fill.rgb == sound.fill.rgb &&
        hurt.sigma == 40 &&
        hurt.saturation == 0 &&
        hurt.radius == sound.radius &&
        hurt.inner!.width == 0 &&
        hurt.inner!.edges == sound.inner!.edges &&
        hurt.inner!.tone.rgb == sound.inner!.tone.rgb &&
        hurt.shadow!.blur == 80 &&
        hurt.shadow!.dy == -8 &&
        hurt.solid == 1,
    'a material clamped value by value',
  );
  _expect(
    identical(bad.materials.popover.light, KitMaterials.mac.popover.light),
    'the appearance the data does not name is untouched',
  );
  _expect(
    bad.materials.cardLayout.width == 280 &&
        bad.materials.cardLayout.dim == 0.8 &&
        bad.materials.cardLayout.gap == 6,
    'the card column clamped',
  );
  _expect(
    !bad.liquid &&
        bad.pace == 0.25 &&
        bad.entry == KitPanelEntry.grow &&
        bad.beadWidth == 1 &&
        bad.beadHeight == 0.96 &&
        bad.panelGrow.stiffness == 3000 &&
        bad.panelGrow.dampingRatio == 0.15 &&
        bad.panelShrink.stiffness == 900 &&
        bad.pressTuning.stiffness == 620 &&
        bad.switchTuning!.stiffness == 40,
    'motion clamped',
  );
  _expect(
    bad.iconTint == KitIconTint.original && bad.iconWeight == 2,
    'icons clamped',
  );
  _expect(
    bad.dockKin == 'mac' &&
        !bad.dock.containsKey('iconSize') &&
        bad.dock['gap'] == 6,
    'the dock: an unknown preset and a value of the wrong kind are dropped',
  );
  // And what comes out is sound: it reads back as itself.
  _expect(KitLook.fromJson(_disk(bad)) == bad, 'a clamped look is stable');
  for (final junk in <Map<dynamic, dynamic>>[
    const <String, Object?>{},
    const <Object?, Object?>{1: 2, null: 3},
    const <String, Object?>{'materials': 3, 'motion': 'x', 'font': <int>[1]},
  ]) {
    _expect(
      KitLook.fromJson(junk, base: KitLook.soft) == KitLook.soft,
      'junk gives the base look',
    );
  }

  // Keys this build does not know are kept, at any depth.
  final newer = KitLook.fromJson(<String, Object?>{
    ..._disk(KitLook.soft),
    'sparkle': <String, Object?>{'amount': 3},
    'motion': <String, Object?>{'wobble': true, 'pace': 2},
    'dock': <String, Object?>{'glow': 'on'},
  }, base: KitLook.soft);
  final kept = newer.toJson();
  _expect(
    (kept['sparkle'] as Map)['amount'] == 3 &&
        (kept['motion'] as Map)['wobble'] == true &&
        (kept['motion'] as Map)['pace'] == 2 &&
        (kept['dock'] as Map)['glow'] == 'on' &&
        (kept['dock'] as Map)['kin'] == 'soft',
    'unknown keys survive a read and a write',
  );
  _expect(newer.pace == 2, 'beside the ones it does know');
  _expect(
    (newer.change(<String, Object?>{'density': 1.2}).toJson()['sparkle']
            as Map)['amount'] ==
        3,
    'and a change to another key',
  );

  // A look the user made is its base and a few overrides, and an override
  // moves only its own key.
  final mine = KitLook.mac.change(<String, Object?>{
    'id': 'look-1',
    'label': 'Mine',
    'base': 'mac',
    'corners': <String, Object?>{'scale': 0.5},
    'materials': <String, Object?>{
      'popover': <String, Object?>{
        'dark': <String, Object?>{'sigma': 20},
      },
    },
  });
  final set = mine.overrides(KitLook.mac);
  _expect(
    jsonEncode(set) ==
        jsonEncode(<String, Object?>{
          'corners': <String, Object?>{'scale': 0.5},
          'materials': <String, Object?>{
            'popover': <String, Object?>{
              'dark': <String, Object?>{'sigma': 20.0},
            },
          },
        }),
    'only the changed keys are kept: $set',
  );
  final stored = jsonDecode(jsonEncode(mine.toStored()));
  final again = KitLook.stored('look-1', stored);
  _expect(again == mine, 'a stored look reads back as it was');
  _expect(
    again.cornerScale == 0.5 &&
        again.materials.popover.dark.sigma == 20 &&
        again.materials.popover.dark.saturation == 2.4 &&
        again.materials.popover.light.sigma == 10 &&
        again.materials.menu.dark.sigma == 13 &&
        again.fontFamily == 'Inter' &&
        again.accentRgb == 0x0a84ff &&
        !again.scaleCorners,
    'every key the overrides do not name is the base look\'s',
  );
  final expected = _disk(KitLook.mac)
    ..['id'] = 'look-1'
    ..['label'] = 'Mine'
    ..['base'] = 'mac';
  (expected['corners'] as Map)['scale'] = 0.5;
  (((expected['materials'] as Map)['popover'] as Map)['dark'] as Map)['sigma'] =
      20.0;
  _expect(
    kitJsonSame(expected, _disk(again)),
    'and nothing else in the whole look moved',
  );
  // A stored look with a missing or unknown base, or no overrides at all.
  _expect(
    KitLook.stored('x', const <String, Object?>{'base': 'gone'}).base ==
            'denial' &&
        KitLook.stored('x', null).liquid &&
        KitLook.stored('x', 'junk').label == 'x',
    'a stored look that cannot be read is Denial under its id',
  );
  // An explicit null is a value: a blur that follows the shell again.
  final loose = mine.change(<String, Object?>{
    'materials': <String, Object?>{
      'popover': <String, Object?>{
        'dark': <String, Object?>{'sigma': null, 'outer': null},
      },
    },
  });
  _expect(
    loose.materials.popover.dark.sigma == null &&
        loose.materials.popover.dark.outer == null &&
        KitLook.stored('look-1', jsonDecode(jsonEncode(loose.toStored()))) ==
            loose,
    'null overrides a number and a line, and is stored',
  );

  // Palettes: each has both appearances, an inline one is read tone by tone.
  for (final palette in KitPalette.all) {
    _expect(
      identical(KitPalette.fromJson(palette.toJson()), palette),
      '${palette.id} is written by its id',
    );
  }
  final inline = KitPalette.fromJson(<String, Object?>{
    'id': 'mine',
    'dark': <String, Object?>{'accent': '#ff0000', 'text': 'oops'},
  }, base: KitPalette.nord)!;
  _expect(
    inline.dark.accent == 0xff0000 &&
        inline.dark.text == KitPalette.nord.dark.text &&
        inline.light.accent == KitPalette.nord.light.accent,
    'an inline palette takes what it lacks from the one before it',
  );
  final painted = KitLook.soft.change(<String, Object?>{
    'palette': inline.toJson(),
    'accent': 'palette',
  });
  _expect(
    painted.palette!.dark.accent == 0xff0000 &&
        painted.accentSource == KitAccentSource.palette &&
        KitLook.fromJson(_disk(painted)) == painted,
    'a look carries an inline palette through its JSON',
  );
}
