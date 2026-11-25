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

  final double restCenter;
  final double center;
  final double restHalf;
  final double half;
  final double scale;

  double get dx => center - restCenter;
}

class DockLayoutFrame {
  const DockLayoutFrame({
    required this.slots,
    required this.restExtent,
    required this.total,
    required this.extent,
    required this.capsuleStart,
    required this.padding,
  });

  final List<DockSlotLayout> slots;

  /// Capsule length with no magnification.
  final double restExtent;

  /// Extra length introduced by magnification.
  final double total;

  /// Capsule length with magnification.
  final double extent;

  /// Leading edge of the capsule in surface coordinates.
  final double capsuleStart;

  final double padding;

  DockSlotLayout? operator [](int index) =>
      index >= 0 && index < slots.length ? slots[index] : null;

  (int index, DockSlotLayout slot, double distance)? nearest(double pointer) {
    if (slots.isEmpty || !pointer.isFinite) return null;
    var bestIndex = 0;
    var bestDistance = double.infinity;
    for (var i = 0; i < slots.length; i++) {
      final distance = (pointer - slots[i].center).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        bestIndex = i;
      }
    }
    return (bestIndex, slots[bestIndex], bestDistance);
  }
}

/// Axis-agnostic dock layout with real growth. The row is always laid out
/// along one axis, so a side dock reuses the same kernel as a bottom dock.
abstract final class DockLayout {
  static double plateauFor({required double pitch, required double radius}) =>
      math.min(pitch / 2, radius * 0.6);

  static DockLayoutFrame compute({
    required double surfaceExtent,
    required List<DockSlot> slots,
    required double padding,
    required double gap,
    required double pointer,
    required double hover,
    required double maxScale,
    required double radius,
    double? plateau,
    DockSpread? spread,
  }) {
    final safeExtent = surfaceExtent.isFinite
        ? surfaceExtent
        : slots.fold<double>(padding * 2, (sum, slot) => sum + slot.half * 2);
    if (spread != null && slots.isNotEmpty && surfaceExtent.isFinite) {
      final frame = _spread(
        surfaceExtent: surfaceExtent,
        slots: slots,
        padding: padding,
        gap: gap,
        pointer: pointer,
        hover: hover,
        maxScale: maxScale,
        radius: radius,
        plateau: plateau,
        spread: spread,
      );
      if (frame != null) return frame;
    }
    if (slots.isEmpty) {
      return DockLayoutFrame(
        slots: const [],
        restExtent: padding * 2,
        total: 0,
        extent: padding * 2,
        capsuleStart: (safeExtent - padding * 2) / 2,
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
    final contentExtent = cursor - gap - padding;
    final restExtent = contentExtent + padding * 2;
    final restStart = safeExtent / 2 - restExtent / 2;

    final shoulder = plateau ?? plateauFor(pitch: pitch, radius: radius);
    final growth = (maxScale - 1.0) * hover.clamp(0.0, 1.0);
    final scales = <double>[];
    var total = 0.0;
    for (var i = 0; i < slots.length; i++) {
      final slot = slots[i];
      var scale = 1.0;
      if (slot.growable && growth > 0) {
        final influence = DockMath.influenceAt(
          pointer - (restStart + restCenters[i]),
          radius,
          plateau: shoulder,
        );
        scale = 1.0 + growth * influence;
      }
      scales.add(scale);
      total += slot.half * 2 * (scale - 1.0);
    }

    final extent = restExtent + total;
    final start = safeExtent / 2 - extent / 2;
    final layouts = <DockSlotLayout>[];
    var x = start + padding;
    for (var i = 0; i < slots.length; i++) {
      final half = slots[i].half * scales[i];
      layouts.add(
        DockSlotLayout(
          restCenter: restStart + restCenters[i],
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
      restExtent: restExtent,
      total: total,
      extent: extent,
      capsuleStart: start,
      padding: padding,
    );
  }

  /// The row of a dock that lies along its whole edge: the leading slots at
  /// the start of the edge, the trailing ones at its end, and the rest in
  /// the middle of the edge or right after the leading ones. The capsule is
  /// the edge itself, so it neither moves nor grows; magnified slots push
  /// their own group apart. Null when the row does not fit, and the caller
  /// falls back to one centred group.
  static DockLayoutFrame? _spread({
    required double surfaceExtent,
    required List<DockSlot> slots,
    required double padding,
    required double gap,
    required double pointer,
    required double hover,
    required double maxScale,
    required double radius,
    required double? plateau,
    required DockSpread spread,
  }) {
    final leading = spread.leading.clamp(0, slots.length);
    final trailing = spread.trailing.clamp(0, slots.length - leading);
    final middleEnd = slots.length - trailing;

    double run(List<double> halves, int from, int to) {
      var sum = 0.0;
      for (var i = from; i < to; i++) {
        sum += halves[i] * 2;
      }
      return to > from ? sum + gap * (to - from - 1) : 0;
    }

    /// The centre of every slot for the given half extents.
    List<double>? place(List<double> halves) {
      final head = run(halves, 0, leading);
      final body = run(halves, leading, middleEnd);
      final tail = run(halves, middleEnd, slots.length);
      final bodyMin = padding + head + (head > 0 ? gap : 0);
      final bodyMax =
          surfaceExtent - padding - tail - (tail > 0 ? gap : 0) - body;
      if (bodyMax < bodyMin) return null;
      final bodyStart = spread.centered
          ? ((surfaceExtent - body) / 2).clamp(bodyMin, bodyMax).toDouble()
          : bodyMin;
      final centers = List<double>.filled(slots.length, 0);
      void lay(int from, int to, double start) {
        var x = start;
        for (var i = from; i < to; i++) {
          centers[i] = x + halves[i];
          x += halves[i] * 2 + gap;
        }
      }

      lay(0, leading, padding);
      lay(leading, middleEnd, bodyStart);
      lay(middleEnd, slots.length, surfaceExtent - padding - tail);
      return centers;
    }

    final restHalves = <double>[for (final slot in slots) slot.half];
    final rest = place(restHalves);
    if (rest == null) return null;

    var pitch = gap;
    for (final slot in slots) {
      if (slot.growable) pitch = math.max(pitch, slot.half * 2 + gap);
    }
    final shoulder = plateau ?? plateauFor(pitch: pitch, radius: radius);
    final growth = (maxScale - 1.0) * hover.clamp(0.0, 1.0);
    final scales = <double>[
      for (var i = 0; i < slots.length; i++)
        slots[i].growable && growth > 0
            ? 1.0 +
                  growth *
                      DockMath.influenceAt(
                        pointer - rest[i],
                        radius,
                        plateau: shoulder,
                      )
            : 1.0,
    ];
    final halves = <double>[
      for (var i = 0; i < slots.length; i++) slots[i].half * scales[i],
    ];
    // A row that fits at rest but not magnified stays at rest.
    final grown = place(halves);
    final centers = grown ?? rest;
    final used = grown == null ? restHalves : halves;
    return DockLayoutFrame(
      slots: <DockSlotLayout>[
        for (var i = 0; i < slots.length; i++)
          DockSlotLayout(
            restCenter: rest[i],
            center: centers[i],
            restHalf: slots[i].half,
            half: used[i],
            scale: grown == null ? 1.0 : scales[i],
          ),
      ],
      restExtent: surfaceExtent,
      total: 0,
      extent: surfaceExtent,
      capsuleStart: 0,
      padding: padding,
    );
  }
}

/// How a dock that lies along its whole edge shares the edge out: how many
/// slots belong to its start and to its end, and where the rest go.
class DockSpread {
  const DockSpread({
    required this.leading,
    required this.trailing,
    required this.centered,
  });

  /// The number of slots, counted from the first, held at the edge's start.
  final int leading;

  /// The number of slots, counted from the last, held at the edge's end.
  final int trailing;

  /// Whether the slots between sit in the middle of the edge, or right
  /// after the leading ones.
  final bool centered;
}
