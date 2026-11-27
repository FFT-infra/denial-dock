/// Geometry of a bar drawn as pointed segments. Plain numbers, so it is
/// tested without a canvas.
library;

/// How one side of a segment is cut.
enum BarEdge {
  /// Straight down the side of the box.
  flat,

  /// A point that reaches past the box into the neighbour's notch.
  tip,

  /// The cut a neighbour's tip fits into.
  notch,

  /// A point at the end of a run, kept inside the box.
  point,
}

typedef BarPoint = ({double x, double y});
typedef BarSegmentEdges = ({BarEdge left, BarEdge right});

/// How deep a point is for a segment of [height].
double barArrowDepth(double height) => height * 0.36;

/// Where a side's corners and its middle sit, measured outwards from the
/// side of the box. A tip and the notch it enters are the same line seen
/// from the two sides, which is what makes neighbours meet without a gap.
({double corner, double middle}) barEdgeOffsets(BarEdge edge, double depth) =>
    switch (edge) {
      BarEdge.flat => (corner: 0, middle: 0),
      BarEdge.tip => (corner: -depth / 2, middle: depth / 2),
      BarEdge.notch => (corner: depth / 2, middle: -depth / 2),
      BarEdge.point => (corner: -depth, middle: 0),
    };

/// How far content keeps from a side so the cut does not run through it.
/// Content sits in the middle of the height, where a notch and a point are
/// at their deepest.
double barEdgeInset(BarEdge edge, double depth) => switch (edge) {
  BarEdge.flat || BarEdge.tip => 0,
  BarEdge.notch => depth / 2,
  BarEdge.point => depth * 0.6,
};

/// The outline of one segment in its own box.
///
/// When [horizontal] is true (default), cuts run along left/right edges
/// clockwise from top-left. When [horizontal] is false (vertical bar), [left]
/// cuts the top edge and [right] cuts the bottom edge clockwise from top-left.
List<BarPoint> barSegmentOutline({
  required double width,
  required double height,
  required double depth,
  required BarEdge left,
  required BarEdge right,
  bool horizontal = true,
}) {
  final l = barEdgeOffsets(left, depth);
  final r = barEdgeOffsets(right, depth);
  if (!horizontal) {
    final middle = width / 2;
    return <BarPoint>[
      (x: 0, y: -l.corner),
      (x: middle, y: -l.middle),
      (x: width, y: -l.corner),
      (x: width, y: height + r.corner),
      (x: middle, y: height + r.middle),
      (x: 0, y: height + r.corner),
    ];
  }
  final middle = height / 2;
  return <BarPoint>[
    (x: -l.corner, y: 0),
    (x: width + r.corner, y: 0),
    (x: width + r.middle, y: middle),
    (x: width + r.corner, y: height),
    (x: -l.corner, y: height),
    (x: -l.middle, y: middle),
  ];
}

/// The cuts of the [count] segments of one zone (0 start, 1 centre, 2 end).
///
/// Points face away from where the zone is anchored: the start zone's face
/// the centre of the screen, the end zone's too, and the centre zone's face
/// outwards from its own middle. The side a zone is anchored on stays flat.
List<BarSegmentEdges> barZoneEdges(int zone, int count) {
  if (count <= 0) return const <BarSegmentEdges>[];
  // Whether the join after segment [index] points towards the end.
  bool forward(int index) => switch (zone) {
    0 => true,
    2 => false,
    _ => (index + 1) * 2 > count,
  };
  return <BarSegmentEdges>[
    for (var index = 0; index < count; index++)
      (
        left: index == 0
            ? (zone == 0 ? BarEdge.flat : BarEdge.point)
            : (forward(index - 1) ? BarEdge.notch : BarEdge.tip),
        right: index == count - 1
            ? (zone == 2 ? BarEdge.flat : BarEdge.point)
            : (forward(index) ? BarEdge.tip : BarEdge.notch),
      ),
  ];
}
