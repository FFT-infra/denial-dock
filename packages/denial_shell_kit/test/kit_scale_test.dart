import 'dart:io';

import 'package:denial_shell_kit/kit_material.dart';
import 'package:denial_shell_kit/kit_store.dart';

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void main() {
  _expect(
    resolveKitScale(1.25, null) == 1.25,
    'follows host scale 1.25 when override is null',
  );
  _expect(
    resolveKitScale(1.0, null) == 1.0,
    'follows host scale 1.0 when override is null',
  );
  _expect(resolveKitScale(0, null) == 1.0, 'falls back cleanly on 0');
  _expect(
    resolveKitScale(double.nan, null) == 1.0,
    'falls back cleanly on NaN',
  );

  _expect(resolveKitScale(1.25, 0.5) == 0.75, 'clamps below 0.75');
  _expect(resolveKitScale(1.25, 1.0) == 1.0, 'allows explicit 1.0 override');
  _expect(resolveKitScale(1.0, 1.25) == 1.25, 'allows explicit 1.25 override');
  _expect(resolveKitScale(1.0, 2.0) == 1.50, 'clamps above 1.50');
  _expect(
    resolveKitScale(1.25, double.nan) == 1.25,
    'ignores non-finite override',
  );

  const fixed = KitMaterial(sigma: 14, fill: KitTone(0x404040, 0.5));
  const inherit = KitMaterial(fill: KitTone(0x404040, 0.5));
  final fixedPlan = KitBlurMath.plan(
    fixed,
    enabled: true,
    glass: true,
    base: 28,
  );
  final inheritPlan = KitBlurMath.plan(
    inherit,
    enabled: true,
    glass: true,
    base: 28,
  );
  _expect(fixedPlan.sigma == 14, 'fixed material sigma kept distinct');
  _expect(inheritPlan.sigma == 28, 'inherited material sigma uses base');

  final dir = Directory.systemTemp.createTempSync('kit_scale_test_');
  try {
    final file = File('${dir.path}/kit.json');
    final store = KitStore(file);
    store.put('shellScale', 1.15);
    _expect(store.read()['shellScale'] == 1.15, 'stores numeric shellScale');
    store.put('shellScale', null);
    _expect(store.read()['shellScale'] == null, 'stores null shellScale');
  } finally {
    dir.deleteSync(recursive: true);
  }
}
