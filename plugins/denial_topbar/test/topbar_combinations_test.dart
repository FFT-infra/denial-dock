import 'dart:convert';
import 'dart:io';

import 'package:denial_shell_kit/shell_preset.dart';
import 'package:denial_topbar/src/bar_settings.dart';

void _expect(bool ok, String what) {
  if (!ok) throw StateError(what);
}

/// What must hold for any bar the settings can describe.
void _sound(BarSettings s, String what) {
  final zones = s.zones;
  final once = <String>{};
  for (final id in zones.parts) {
    _expect(BarPart.known(id), '$what: unknown part $id');
    if (id == BarPart.spacer || id == BarPart.separator || id == BarPart.gap) {
      continue;
    }
    _expect(once.add(id), '$what: $id twice');
  }
  _expect(
    !zones.start.contains(BarPart.island) &&
        !zones.end.contains(BarPart.island),
    '$what: island outside the centre',
  );
  // The island shows only with its switch on, and never shows the switcher
  // while a zone holds it.
  _expect(!s.showsIsland || s.islandEnabled, '$what: island without switch');
  _expect(
    !s.workspacesInIsland || !zones.contains(BarPart.workspaces),
    '$what: switcher twice',
  );
  // Written and read back, nothing moves.
  final json = <String, dynamic>{};
  s.writeJson(json);
  final back = BarSettings.fromJson(
    jsonDecode(jsonEncode(json)) as Map<String, dynamic>,
  );
  _expect(
    jsonEncode(back.layoutJson()) == jsonEncode(s.layoutJson()),
    '$what: changed by a round trip',
  );
  // Laying the layout over itself changes nothing.
  _expect(
    jsonEncode(s.withLayout(s.layoutJson()).layoutJson()) ==
        jsonEncode(s.layoutJson()),
    '$what: its own layout is not a fixed point',
  );
}

void main() {
  const toggled = <String>[BarPart.system, BarPart.app, BarPart.island];
  var checked = 0;
  // From a bar never arranged and from every preset: every order of the old
  // switches and every placement of the switcher, then on to every other
  // preset and back.
  final starts = <(String, BarSettings)>[
    ('plain', BarSettings.defaults),
    for (final preset in ShellPreset.all)
      (preset.id, BarSettings.defaults.withLayout(preset.bar)),
  ];
  for (final (name, start) in starts) {
    _sound(start, name);
    for (var mask = 0; mask < 1 << toggled.length; mask++) {
      for (final placement in BarWorkspacePlacement.values) {
        var s = start;
        for (var bit = 0; bit < toggled.length; bit++) {
          s = s.withPart(toggled[bit], mask & (1 << bit) != 0);
        }
        s = s.withWorkspacePlacement(placement);
        final what = '$name mask $mask ${placement.name}';
        _sound(s, what);
        for (var bit = 0; bit < toggled.length; bit++) {
          final id = toggled[bit];
          final shown = mask & (1 << bit) != 0;
          // A part switched off is gone; one switched on is there, the
          // island as long as the centre has a place for it.
          if (!shown) {
            _expect(!s.hasPart(id), '$what: $id still shown');
          } else if (id != BarPart.island) {
            _expect(s.hasPart(id), '$what: $id missing');
          }
        }
        // Switched back on, each comes back.
        var again = s;
        for (final id in toggled) {
          again = again.withPart(id, true);
        }
        _sound(again, '$what, all on');
        _expect(
          again.hasPart(BarPart.system) && again.hasPart(BarPart.app),
          '$what: a part does not come back',
        );
        // Any preset laid over it gives exactly that preset's layout, with
        // nothing of this bar left behind.
        for (final preset in ShellPreset.all) {
          final over = s.withLayout(preset.bar);
          _sound(over, '$what then ${preset.id}');
          final clean = BarSettings.defaults.withLayout(preset.bar);
          _expect(
            jsonEncode(over.layoutJson()) == jsonEncode(clean.layoutJson()),
            '$what then ${preset.id}: something is left behind',
          );
          checked++;
        }
      }
    }
  }
  stdout.writeln('All $checked bar combinations hold.');
}
