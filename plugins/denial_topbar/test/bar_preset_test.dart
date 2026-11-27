import 'dart:convert';
import 'dart:io';

import 'package:denial_shell_kit/shell_preset.dart';
import 'package:denial_topbar/src/bar_settings.dart';

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void main() {
  // A bar that was never touched is the Denial preset, and macOS differs
  // from it only by the look.
  const defaults = BarSettings.defaults;
  _expect(
    ShellPreset.denial.matches(look: 'denial', bar: defaults.layoutJson()),
    'the default bar is the Denial preset',
  );
  _expect(
    ShellPreset.mac.matches(look: 'mac', bar: defaults.layoutJson()),
    'and the macOS preset under its look',
  );
  _expect(
    !ShellPreset.mac.matches(look: 'denial', bar: defaults.layoutJson()),
    'but not under another',
  );

  // The user's own settings, which no preset decides.
  final mine = defaults.copyWith(
    showWifi: false,
    showBatteryPercent: true,
    autoHide: true,
    clockWeekday: false,
    statusOrder: const <String>['battery', 'wifi'],
    islandEnabled: false,
    workspacePlacement: BarWorkspacePlacement.trailing,
  );
  _expect(
    !ShellPreset.denial.matches(look: 'denial', bar: mine.layoutJson()),
    'a moved switcher and a hidden island are a change',
  );

  for (final preset in ShellPreset.all) {
    final applied = mine.withLayout(preset.bar);
    _expect(
      preset.matches(look: preset.look, bar: applied.layoutJson()),
      '${preset.id} matches right after it is applied',
    );
    _expect(
      !applied.showWifi &&
          applied.showBatteryPercent &&
          applied.autoHide &&
          !applied.clockWeekday &&
          applied.statusOrder.first == 'battery',
      '${preset.id} keeps the settings it does not decide',
    );
    _expect(applied.explicitZones != null, '${preset.id} arranges the zones');
    // Stored and read back, it is still that preset.
    final json = <String, dynamic>{};
    applied.writeJson(json);
    final back = BarSettings.fromJson(
      jsonDecode(jsonEncode(json)) as Map<String, dynamic>,
    );
    _expect(
      preset.matches(look: preset.look, bar: back.layoutJson()),
      '${preset.id} survives a round trip',
    );
    // Going on to any other preset leaves nothing of this one behind.
    for (final other in ShellPreset.all) {
      _expect(
        other.matches(
          look: other.look,
          bar: applied.withLayout(other.bar).layoutJson(),
        ),
        '${preset.id} then ${other.id}',
      );
    }
  }

  // What each preset means for the bar.
  final denial = mine.withLayout(ShellPreset.denial.bar);
  _expect(
    denial.showsIsland && denial.workspacesInIsland,
    'Denial brings the island back with the switcher inside',
  );
  final omarchy = defaults.withLayout(ShellPreset.omarchy.bar);
  _expect(
    omarchy.shape == BarShape.strip &&
        omarchy.ground == BarGround.plate &&
        omarchy.groundOpacity == 1 &&
        omarchy.endInset == 0 &&
        omarchy.workspaceStyle == BarWorkspaceStyle.numbers &&
        !omarchy.showsIsland &&
        omarchy.zones.start.single == 'workspaces' &&
        omarchy.zones.center.single == 'clock' &&
        omarchy.zones.end.single == 'status',
    'Omarchy is a solid strip with no island',
  );
  final segments = defaults.withLayout(ShellPreset.segments.bar);
  _expect(
    segments.shape == BarShape.islands &&
        segments.cap == BarCap.arrow &&
        BarZones.segments(segments.zones.center).length == 3 &&
        segments.zones.end.single == 'status',
    'Segments is three runs of pointed segments',
  );
  final compact = defaults.withLayout(ShellPreset.compact.bar);
  _expect(
    compact.shape == BarShape.floating &&
        compact.cornerRadius == 10 &&
        compact.zones.start.join(',') == 'system,workspaces,app',
    'Compact is one solid rounded bar',
  );

  // Any change afterwards shows.
  bool modified(BarSettings settings) =>
      !ShellPreset.omarchy.matches(look: 'omarchy', bar: settings.layoutJson());
  _expect(!modified(omarchy), 'fresh');
  _expect(!modified(omarchy.copyWith(showWifi: false)), 'own settings do not');
  _expect(modified(omarchy.copyWith(partGap: 9)), 'a measure does');
  _expect(modified(omarchy.copyWith(cap: BarCap.square)), 'a cap does');
  _expect(
    modified(omarchy.copyWith(zones: omarchy.zones.inserted(2, 'clock'))),
    'a moved part does',
  );
  _expect(modified(omarchy.withPart('island', true)), 'the island does');
  _expect(
    modified(omarchy.withWorkspacePlacement(BarWorkspacePlacement.hidden)),
    'hiding the switcher does',
  );
  stdout.writeln('All bar preset tests passed.');
}
