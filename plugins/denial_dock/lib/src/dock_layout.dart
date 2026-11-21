import 'dart:math' as math;

import 'dock_math.dart';

/// One resting slot in the dock row. [half] is measured from the slot centre
/// to its painted edge before magnification.
class DockSlot {
  const DockSlot({required this.half, this.growable = true});

  final double half;
  final bool growable;
}

/// Painted geometry for one slot, in surface coordinates.
class DockSlotLayout {
  const DockSlotLayout({
    required this.restCenter,
    required this.center,
    required this.restHalf,
    required this.half,
    required this.scale,
  });

  /// Centre the slot would occupy without magnification.
  final double restCenter;

  /// Centre after magnification and neighbour push.
  final double center;

  final double restHalf;

  /// Half width after magnification.
  final double half;

  final double scale;

  double get dx => center - restCenter;
}

class DockLayoutFrame {
  const DockLayoutFrame({
    required this.slots,
    required this.restWidth,
    required this.total,
    required this.width,
    required this.capsuleLeft,
    required this.padding,
  });

  final List<DockSlotLayout> slots;

  /// Capsule width with no magnification.
  final double restWidth;

  /// Extra width introduced by magnification.
  final double total;

  /// Capsule width with magnification.
  final double width;

  /// Left edge of the capsule in surface coordinates.
  final double capsuleLeft;

  final double padding;

  DockSlotLayout? operator [](int index) =>
      index >= 0 && index < slots.length ? slots[index] : null;

  /// The slot whose painted centre is closest to [pointerX], plus that distance.
  (int index, DockSlotLayout slot, double distance)? nearest(double pointerX) {
    if (slots.isEmpty || !pointerX.isFinite) return null;
    var bestIndex = 0;
    var bestDistance = double.infinity;
    for (var i = 0; i < slots.length; i++) {
      final distance = (pointerX - slots[i].center).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        bestIndex = i;
      }
    }
    return (bestIndex, slots[bestIndex], bestDistance);
  }
}

/// Horizontal dock layout with real growth. Magnified slots take more room and
/// push their neighbours out; the capsule widens and stays centred on the
/// surface. Influence is measured against resting centres so the layout has no
/// feedback loop while the pointer is still.
abstract final class DockLayout {
  /// The kernel holds its peak across one slot before it starts to decay.
  /// Without a plateau the scale peaks only at the exact slot centre, so
  /// sliding the pointer along the row makes every icon breathe as it crosses
  /// the gaps.
  static double plateauFor({required double pitch, required double radius}) =>
      math.min(pitch / 2, radius * 0.6);

  static DockLayoutFrame compute({
    required double surfaceWidth,
    required List<DockSlot> slots,
    required double padding,
    required double gap,
    required double pointerX,
    required double hover,
    required double maxScale,
    required double radius,
    double? plateau,
  }) {
    final safeSurfaceWidth = surfaceWidth.isFinite
        ? surfaceWidth
        : slots.fold<double>(padding * 2, (sum, slot) => sum + slot.half * 2);
    if (slots.isEmpty) {
      return DockLayoutFrame(
        slots: const [],
        restWidth: padding * 2,
        total: 0,
        width: padding * 2,
        capsuleLeft: (safeSurfaceWidth - padding * 2) / 2,
        padding: padding,
      );
    }

    final restCenters = <double>[];
    var cursor = padding;
    var pitch = gap;
    for (final slot in slots) {
      restCenters.add(cursor + slot.half);
      if (slot.growable) pitch = math.max(pitch, slot.half * 2 + gap);
      cursor += slot.half * 2 + gap;
    }
    // [cursor] still carries the leading padding and one trailing gap.
    final contentWidth = cursor - gap - padding;
    final restWidth = contentWidth + padding * 2;
    final restLeft = safeSurfaceWidth / 2 - restWidth / 2;

    final shoulder = plateau ?? plateauFor(pitch: pitch, radius: radius);
    final growth = (maxScale - 1.0) * hover.clamp(0.0, 1.0);
    final scales = <double>[];
    var total = 0.0;
    for (var i = 0; i < slots.length; i++) {
      final slot = slots[i];
      var scale = 1.0;
      if (slot.growable && growth > 0) {
        final influence = DockMath.influenceAt(
          pointerX - (restLeft + restCenters[i]),
          radius,
          plateau: shoulder,
        );
        scale = 1.0 + growth * influence;
      }
      scales.add(scale);
      total += slot.half * 2 * (scale - 1.0);
    }

    final width = restWidth + total;
    final left = safeSurfaceWidth / 2 - width / 2;
    final layouts = <DockSlotLayout>[];
    var x = left + padding;
    for (var i = 0; i < slots.length; i++) {
      final half = slots[i].half * scales[i];
      layouts.add(
        DockSlotLayout(
          restCenter: restLeft + restCenters[i],
          center: x + half,
          restHalf: slots[i].half,
          half: half,
          scale: scales[i],
        ),
      );
      x += half * 2 + gap;
    }

    return DockLayoutFrame(
      slots: layouts,
      restWidth: restWidth,
      total: total,
      width: width,
      capsuleLeft: left,
      padding: padding,
    );
  }
}
