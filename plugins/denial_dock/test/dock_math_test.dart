import 'dart:io';

import 'package:denial_dock/src/dock_math.dart';

void main() {
  // 1. Influence function checks
  const radius = 120.0;
  final peak = DockMath.influenceAt(0.0, radius);
  if ((peak - 1.0).abs() > 1e-6) {
    throw StateError('Peak influence at distance 0 should be 1.0, got $peak');
  }

  final edge = DockMath.influenceAt(radius, radius);
  if (edge.abs() > 1e-6) {
    throw StateError(
      'Edge influence at distance radius should be 0.0, got $edge',
    );
  }

  final outside = DockMath.influenceAt(radius + 20.0, radius);
  if (outside.abs() > 1e-6) {
    throw StateError('Outside influence should be 0.0, got $outside');
  }

  // Smoothness / zero derivatives check at t = 0 and t = 1
  final eps = 0.001;
  final dAtZero =
      (DockMath.influenceAt(eps, radius) - DockMath.influenceAt(0.0, radius)) /
      eps;
  if (dAtZero.abs() > 0.01) {
    throw StateError('Derivative at t=0 should be near 0, got $dAtZero');
  }

  final dAtEdge =
      (DockMath.influenceAt(radius, radius) -
          DockMath.influenceAt(radius - eps, radius)) /
      eps;
  if (dAtEdge.abs() > 0.01) {
    throw StateError('Derivative at t=1 should be near 0, got $dAtEdge');
  }

  // 1b. Plateau: the peak holds across the slot, then decays to zero at the
  // radius. Without it the scale dips in every gap as the pointer glides.
  const plateau = 28.0;
  for (final distance in [0.0, 14.0, 28.0]) {
    final held = DockMath.influenceAt(distance, radius, plateau: plateau);
    if ((held - 1.0).abs() > 1e-6) {
      throw StateError('Plateau should hold 1.0 at $distance, got $held');
    }
  }
  final midShoulder = DockMath.influenceAt(
    plateau + 1.0,
    radius,
    plateau: plateau,
  );
  if (midShoulder >= 1.0 || midShoulder <= 0.0) {
    throw StateError(
      'Influence should decay past the plateau, got $midShoulder',
    );
  }
  final shoulderEdge = DockMath.influenceAt(radius, radius, plateau: plateau);
  if (shoulderEdge.abs() > 1e-6) {
    throw StateError(
      'Plateau must still reach 0 at the radius, got $shoulderEdge',
    );
  }
  // A plateau wider than the radius collapses to a hard edge, not NaN.
  final degenerate = DockMath.influenceAt(1.0, radius, plateau: radius * 2);
  if (!degenerate.isFinite || (degenerate - 1.0).abs() > 1e-6) {
    throw StateError('Degenerate plateau should clamp, got $degenerate');
  }

  // 2. Integral function checks
  final i0 = DockMath.integralAt(0.0);
  if (i0.abs() > 1e-6) {
    throw StateError('Integral at 0 should be 0, got $i0');
  }

  final i1 = DockMath.integralAt(1.0);
  // F(1) = 1 - 2.5 + 3 - 1 = 0.5
  if ((i1 - 0.5).abs() > 1e-6) {
    throw StateError('Integral at 1 should be 0.5, got $i1');
  }

  // 3. First order exponential decay advance checks
  var val = 0.0;
  const target = 100.0;
  // Advance 200ms in steps of 16ms (~60Hz)
  for (var i = 0; i < 20; i++) {
    val = DockMath.advance(val, target, 0.016, responseSeconds: 0.026);
  }
  if ((val - target).abs() > 0.01) {
    throw StateError(
      'Value should converge close to target after 20 frames, got $val',
    );
  }

  // High refresh rate (120Hz = 8.33ms) convergence check
  val = 0.0;
  for (var i = 0; i < 40; i++) {
    val = DockMath.advance(val, target, 0.00833, responseSeconds: 0.026);
  }
  if ((val - target).abs() > 0.01) {
    throw StateError('120Hz steps should converge to target, got $val');
  }

  // 4. Ballistic bounce checks
  final b0 = DockMath.launchBounce(0.0);
  final bApex = DockMath.launchBounce(0.41);
  final bLand = DockMath.launchBounce(0.82);
  final bPost = DockMath.launchBounce(0.95);
  if (b0.abs() > 1e-5) throw StateError('b0 should be 0, got $b0');
  if ((bApex - 1.0).abs() > 0.01)
    throw StateError('bApex should be near 1.0, got $bApex');
  if (bLand.abs() > 1e-5) throw StateError('bLand should be 0, got $bLand');
  if (bPost.abs() > 1e-5)
    throw StateError('bPost should remain 0 after flight, got $bPost');

  // 5. Name owner midpoint tests
  final centers = [50.0, 110.0, 170.0];
  final halfWidths = [24.0, 24.0, 24.0];
  // Pointer at 70 is between icon 0 (center 50) and icon 1 (center 110) -> midpoint is 80 -> should be 0
  final owner0 = DockMath.resolveNameOwner(
    iconCenters: centers,
    iconHalfWidths: halfWidths,
    pointerX: 70.0,
  );
  if (owner0 != 0) throw StateError('Expected owner 0, got $owner0');

  // Pointer at 85 -> past midpoint 80 -> should be 1
  final owner1 = DockMath.resolveNameOwner(
    iconCenters: centers,
    iconHalfWidths: halfWidths,
    pointerX: 85.0,
  );
  if (owner1 != 1) throw StateError('Expected owner 1, got $owner1');

  stdout.writeln('All DockMath unit tests passed successfully!');
}
