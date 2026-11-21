import 'package:denial_dock/src/dock_layout.dart';

void main() {
  const surface = 1000.0;
  const padding = 8.0;
  const gap = 8.0;
  const maxScale = 1.6;
  const radius = 140.0;
  final slots = [
    const DockSlot(half: 24),
    const DockSlot(half: 24),
    const DockSlot(half: 0.5, growable: false),
    const DockSlot(half: 24),
  ];

  DockLayoutFrame layout(double pointer, double hover) => DockLayout.compute(
    surfaceExtent: surface,
    slots: slots,
    padding: padding,
    gap: gap,
    pointer: pointer,
    hover: hover,
    maxScale: maxScale,
    radius: radius,
  );

  // Resting layout: no growth, capsule centred.
  final rest = layout(-10000, 0);
  _expect(rest.total == 0, 'rest total ${rest.total}');
  _expect(rest.extent == rest.restExtent, 'rest extent ${rest.extent}');
  for (final slot in rest.slots) {
    _expect(slot.scale == 1.0, 'rest scale ${slot.scale}');
    _expect((slot.center - slot.restCenter).abs() < 1e-9, 'rest dx');
  }
  final restCenter =
      (rest.slots.first.center -
          rest.slots.first.half +
          rest.slots.last.center +
          rest.slots.last.half) /
      2;
  _expect((restCenter - surface / 2).abs() < 1e-9, 'rest centre $restCenter');

  // Hover the second icon: it reaches full scale, the capsule grows, and the
  // grown row stays centred on the surface.
  final hovered = layout(rest.slots[1].center, 1);
  _expect(
    (hovered.slots[1].scale - maxScale).abs() < 1e-9,
    'hovered scale ${hovered.slots[1].scale}',
  );
  _expect(hovered.total > 0, 'total ${hovered.total}');
  _expect(
    (hovered.extent - (rest.restExtent + hovered.total)).abs() < 1e-9,
    'extent ${hovered.extent}',
  );
  _expect(
    (hovered.slots[2].scale - 1.0).abs() < 1e-9,
    'divider must not grow: ${hovered.slots[2].scale}',
  );
  final hoveredCenter =
      (hovered.slots.first.center -
          hovered.slots.first.half +
          hovered.slots.last.center +
          hovered.slots.last.half) /
      2;
  _expect(
    (hoveredCenter - surface / 2).abs() < 1e-6,
    'hovered centre $hoveredCenter',
  );

  // Real push: painted neighbours keep the resting gap and never overlap.
  for (var i = 0; i < hovered.slots.length - 1; i++) {
    final right = hovered.slots[i].center + hovered.slots[i].half;
    final nextLeft = hovered.slots[i + 1].center - hovered.slots[i + 1].half;
    final spacing = nextLeft - right;
    _expect((spacing - gap).abs() < 1e-6, 'gap $i = $spacing');
  }

  // The capsule hugs the painted row.
  final firstLeft = hovered.slots.first.center - hovered.slots.first.half;
  final lastRight = hovered.slots.last.center + hovered.slots.last.half;
  _expect(
    (firstLeft - (hovered.capsuleStart + padding)).abs() < 1e-6,
    'start hug ${firstLeft - hovered.capsuleStart}',
  );
  _expect(
    (hovered.capsuleStart + hovered.extent - padding - lastRight).abs() < 1e-6,
    'right hug',
  );

  // Nearest slot selection follows painted centres.
  final nearest = hovered.nearest(hovered.slots[3].center + 2);
  _expect(nearest != null && nearest.$1 == 3, 'nearest ${nearest?.$1}');

  // Plateau: sliding the pointer from one slot centre to the next keeps the
  // hovered scale at full for a stretch, so the row does not breathe in the
  // gaps.
  final nearA = layout(rest.slots[1].center + 4, 1);
  final nearB = layout(rest.slots[1].center + 12, 1);
  _expect(
    (nearA.slots[1].scale - nearB.slots[1].scale).abs() < 1e-9,
    'plateau should hold the scale: ${nearA.slots[1].scale} '
    '${nearB.slots[1].scale}',
  );
  // The plateau is derived from the slot pitch: half an icon plus half a gap.
  final pitchPlateau = DockLayout.plateauFor(pitch: 48 + gap, radius: radius);
  _expect(pitchPlateau == 28.0, 'plateau $pitchPlateau');

  // Empty dock is just the capsule padding.
  final empty = DockLayout.compute(
    surfaceExtent: surface,
    slots: const [],
    padding: padding,
    gap: gap,
    pointer: 0,
    hover: 1,
    maxScale: maxScale,
    radius: radius,
  );
  _expect(empty.extent == padding * 2, 'empty extent ${empty.extent}');
  _expect(empty.slots.isEmpty, 'empty slots');
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
