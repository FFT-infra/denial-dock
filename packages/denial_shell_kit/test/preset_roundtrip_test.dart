import 'dart:io';

import 'package:denial_shell_kit/kit_look.dart';
import 'package:denial_shell_kit/kit_look_refs.dart';
import 'package:denial_shell_kit/kit_material.dart';
import 'package:denial_shell_kit/shell_preset.dart';

void _expect(bool cond, String msg) {
  if (!cond) throw StateError('FAIL: $msg');
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
      dockVisible: curDockVis,
    ) && curDockVis == true,
    'round-trip back to Denial restores dockVisible and matches cleanly',
  );

  // 2b. Real user edit A -> B -> A ring (including dock switch + bar key):
  final memory = <String, Object?>{};
  var active = ShellPreset.denial;
  var uLook = active.look;
  var uBarMode = active.barMode;
  var uBar = Map<String, Object?>.of(active.bar);
  var uDock = Map<String, Object?>.of(active.dock);
  var uDockVis = active.dockVisible ?? true;

  void switchTo(ShellPreset next) {
    final diff = active.remember(
      look: uLook,
      barMode: uBarMode,
      bar: uBar,
      dock: uDock,
      dockVisible: uDockVis,
      before: memory[active.id],
    );
    if (diff.isEmpty) {
      memory.remove(active.id);
    } else {
      memory[active.id] = diff;
    }
    final recalled = next.recall(memory[next.id]);
    active = next;
    uLook = recalled.look;
    uBarMode = recalled.barMode;
    uBar = Map<String, Object?>.of(recalled.bar);
    uDock = Map<String, Object?>.of(recalled.dock);
    if (recalled.dockVisible != null) uDockVis = recalled.dockVisible!;
  }

  // Edit Denial: turn dock OFF and change groundOpacity.
  uDockVis = false;
  uBar['groundOpacity'] = 0.77;
  // Switch to Mac (dockVisible: true), then HyprPanel (dockVisible: false), then back to Denial.
  switchTo(ShellPreset.mac);
  _expect(uDockVis == true, 'switching to mac turns dock on');
  switchTo(ShellPreset.byId('hyprpanel'));
  _expect(uDockVis == false, 'switching to hyprpanel turns dock off');
  switchTo(ShellPreset.denial);
  _expect(
    uDockVis == false && uBar['groundOpacity'] == 0.77,
    'A->B->C->A ring preserves custom dockVisible and bar edits on Denial',
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

  // 5. All reference looks carry non-default per-family material tables and
  // explicit data-driven archetypes that round-trip through JSON.
  for (final look in kitReferenceLooks) {
    _expect(
      !identical(look.materials, KitMaterials.shell),
      'reference look ${look.id} uses its own dedicated KitMaterials table',
    );
    final roundTripped = KitLook.fromJson(look.toJson());
    _expect(
      roundTripped.archetype == look.archetype &&
          look.archetype != KitShellArchetype.denial,
      'reference look ${look.id} preserves explicit archetype ${look.archetype}',
    );
  }
  final customMac = KitLook.mac.change(<String, Object?>{'id': 'user-mac-clone'});
  _expect(
    customMac.archetype == KitShellArchetype.macos,
    'custom look cloned from mac retains macos archetype via data field',
  );

  if (exitCode == 0) {
    stdout.writeln('All Batch 6 preset round-trip & light/dark tests passed.');
  }
}
