import 'package:denial_shell_kit/kit_look.dart';
import 'package:denial_shell_kit/shell_preset.dart';
import 'package:denial_topbar/src/bar_settings.dart';

void _expect(bool ok, String what) {
  if (!ok) throw StateError(what);
}

void main() {
  for (final pill in BarPartPill.values) {
    _expect(BarPartPill.parse(pill.key) == pill, 'round-trips ${pill.key}');
  }
  _expect(
    BarPartPill.parse('unknown') == BarPartPill.none,
    'unknown partPill falls back to none',
  );

  final fromJson = BarSettings.fromJson(<String, Object?>{
    'partPill': 'tinted',
    'barHeight': 80,
    'concaveEdge': true,
    'islandNotch': true,
  });
  _expect(fromJson.partPill == BarPartPill.tinted, 'parses partPill');
  _expect(fromJson.barHeight == BarMetric.barHeightMax, 'clamps barHeight');
  _expect(fromJson.concaveEdge, 'parses concaveEdge');
  _expect(fromJson.islandNotch, 'parses islandNotch');

  final defaults = BarSettings.defaults;
  final noctalia = defaults.withLayout(ShellPreset.noctalia.bar);
  _expect(
    noctalia.barHeight == 34 &&
        noctalia.concaveEdge &&
        noctalia.partPill == BarPartPill.uniform,
    'Noctalia applies verified structural layout',
  );
  final material = defaults.withLayout(ShellPreset.material.bar);
  _expect(
    material.barHeight == 38 &&
        material.shape == BarShape.floating &&
        material.partPill == BarPartPill.uniform,
    'Material applies verified structural layout',
  );
  final ax = defaults.withLayout(ShellPreset.axShell.bar);
  _expect(
    ax.shape == BarShape.islands && ax.islandNotch,
    'Ax-Shell enables top-edge notch',
  );
  _expect(
    KitLook.omarchy.dock['opacity'] == 0 &&
        KitLook.omarchy.dock['border'] == false,
    'Omarchy uses borderless transparent dock',
  );
}
