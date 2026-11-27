import 'dart:io';

import 'package:denial_shell_kit/kit_look.dart';
import 'package:denial_shell_kit/kit_look_refs.dart';
import 'package:denial_shell_kit/kit_material.dart';
import 'package:denial_shell_kit/shell_preset.dart';

void _expect(bool cond, String msg) {
  if (!cond) {
    stderr.writeln('FAIL: $msg');
    exitCode = 1;
  }
}

void main() {
  // 1. Every shipped preset resolves to a built-in look with valid dark & light
  //    tones and a dedicated material table.
  for (final preset in ShellPreset.all) {
    final look = KitLook.builtin(preset.look);
    _expect(look != null, 'preset ${preset.id} look ${preset.look} exists');
    if (look == null) continue;
    final palette = look.palette;
    if (palette != null) {
      _expect(
        palette.dark.background != palette.light.background,
        '${look.id} has distinct dark and light backgrounds',
      );
      _expect(
        palette.dark.text != palette.light.text,
        '${look.id} has distinct dark and light text colours',
      );
    }
    // Every material table produces valid dark & light tiers.
    for (final tier in KitTier.values) {
      final pair = look.materials.tier(tier);
      _expect(pair.dark.solid > 0 && pair.light.solid > 0, '${look.id} $tier solid');
    }
  }

  // 2. Full preset round-trip: cycle from Denial through every shipped preset
  //    and back to Denial without leaving stale keys or diff bloat.
  final start = ShellPreset.denial;
  var curLook = start.look;
  var curBarMode = start.barMode;
  var curBar = Map<String, Object?>.of(start.bar);
  var curDock = Map<String, Object?>.of(start.dock);
  var curDockVis = start.dockVisible ?? true;

  void apply(ShellPreset p) {
    curLook = p.look;
    curBarMode = p.barMode;
    curBar = Map<String, Object?>.of(p.bar);
    curDock = Map<String, Object?>.of(p.dock);
    if (p.dockVisible != null) curDockVis = p.dockVisible!;
  }

  for (final preset in ShellPreset.all) {
    apply(preset);
    _expect(
      preset.matches(
        look: curLook,
        bar: curBar,
        dock: curDock,
        barMode: curBarMode,
        dockVisible: curDockVis,
      ),
      'preset ${preset.id} matches after apply',
    );
    final mem = preset.remember(
      look: curLook,
      barMode: curBarMode,
      bar: curBar,
      dock: curDock,
      dockVisible: curDockVis,
    );
    _expect(mem.isEmpty, 'preset ${preset.id} produces empty diff when unmodified');
  }
  apply(start);
  _expect(
    start.matches(
      look: curLook,
      bar: curBar,
      dock: curDock,
      barMode: curBarMode,
    ),
    'round-trip back to Denial matches cleanly',
  );

  // 3. Caelestia preset & Segments split end zone checks.
  final caelestia = ShellPreset.byId('caelestia');
  _expect(caelestia.id == 'caelestia', 'caelestia preset registered');
  _expect(caelestia.look == 'caelestia', 'caelestia look wired');
  final caelLook = KitLook.builtin('caelestia')!;
  _expect(
    caelLook.archetype == KitShellArchetype.caelestia,
    'caelestia archetype resolves',
  );
  _expect(
    (ShellPreset.segments.bar['end'] as List).contains('separator'),
    'segments end zone splits into multiple arrow segments',
  );

  // 4. KitGlassPreset serialization check.
  for (final gp in KitGlassPreset.values) {
    _expect(KitGlassPreset.tryParse(gp.name) == gp, 'glass preset ${gp.name} round-trips');
  }

  // 5. All reference looks carry non-default per-family material tables.
  for (final look in kitReferenceLooks) {
    _expect(
      !identical(look.materials, KitMaterials.shell),
      'reference look ${look.id} uses its own dedicated KitMaterials table',
    );
  }

  if (exitCode == 0) {
    stdout.writeln('All Batch 6 preset round-trip & light/dark tests passed.');
  }
}
