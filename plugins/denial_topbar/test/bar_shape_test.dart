import 'dart:io';

import 'package:denial_topbar/src/bar_segments.dart';
import 'package:denial_topbar/src/bar_settings.dart';

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}

bool _near(BarPoint a, BarPoint b) =>
    (a.x - b.x).abs() < 1e-9 && (a.y - b.y).abs() < 1e-9;

/// Area of a polygon, positive when it runs clockwise on a y-down canvas.
double _area(List<BarPoint> points) {
  var sum = 0.0;
  for (var index = 0; index < points.length; index++) {
    final a = points[index];
    final b = points[(index + 1) % points.length];
    sum += a.x * b.y - b.x * a.y;
  }
  return sum / 2;
}

void main() {
  // A file from before shapes: the layout decides, and every measure is what
  // the bar had then.
  const defaults = BarSettings.defaults;
  _expect(defaults.shape == BarShape.strip, 'default shape');
  _expect(defaults.cap == BarCap.round, 'default cap');
  _expect(defaults.textScale == 1 && defaults.partGap == 6, 'default measures');
  _expect(defaults.edgeMargin == 6 && defaults.endInset == null, 'margins');
  _expect(defaults.cornerRadius == 14, 'default radius is the old capsule');
  _expect(defaults.contentPadding == 0, 'default padding');
  _expect(defaults.borderWidth == 0 && !defaults.hairline, 'default border');
  _expect(defaults.groundTint == BarGroundTint.wallpaper, 'default tint');
  _expect(defaults.borderColour == BarBorderColour.ink, 'default line');

  BarSettings read(Map<String, dynamic> json) => BarSettings.fromJson(json);
  _expect(
    read({'layout': 'floating'}).shape == BarShape.floating,
    'old floating layout is the floating shape',
  );
  _expect(
    read({'layout': 'attached'}).shape == BarShape.strip,
    'old attached layout is the strip',
  );
  _expect(
    read({'layout': 'attached', 'shape': 'islands'}).shape == BarShape.islands,
    'a stored shape wins',
  );
  _expect(
    read({'layout': 'floating', 'shape': 'wavy'}).shape == BarShape.floating,
    'an unknown shape falls back to the layout',
  );
  _expect(
    read({'hairline': true}).borderWidth == BarMetric.hairline,
    'an old hairline is a 0.8 line',
  );
  _expect(
    read({'hairline': true, 'borderWidth': 2}).borderWidth == 2,
    'a stored width wins',
  );
  _expect(read({'cap': 'arrow'}).cap == BarCap.arrow, 'cap is read');
  _expect(read({'cap': 7}).cap == BarCap.round, 'unknown cap falls back');

  // Clamps.
  _expect(read({'textScale': 9}).textScale == BarMetric.textScaleMax, 'scale');
  _expect(read({'partGap': -3}).partGap == 0, 'gap floor');
  _expect(read({'edgeMargin': 99}).edgeMargin == 16, 'margin ceiling');
  _expect(read({'endInset': 500}).endInset == 48, 'inset ceiling');
  _expect(read({'endInset': 'x'}).endInset == null, 'bad inset is unset');
  _expect(read({'cornerRadius': 99}).cornerRadius == 20, 'radius ceiling');
  _expect(read({'borderWidth': 10}).borderWidth == 3, 'border ceiling');
  _expect(read({'groundOpacity': 1}).groundOpacity == 1, 'opaque is allowed');

  // Round trip; older builds still find the keys they know.
  final json = <String, dynamic>{};
  final styled = defaults.copyWith(
    shape: BarShape.islands,
    cap: BarCap.arrow,
    groundTint: BarGroundTint.accent,
    borderWidth: 2,
    borderColour: BarBorderColour.accent,
    textScale: 1.1,
    partGap: 4,
    edgeMargin: 3,
    endInset: 0.0,
    contentPadding: 8,
    cornerRadius: 9,
  );
  styled.writeJson(json);
  _expect(json['layout'] == 'floating', 'islands read as floating before');
  _expect(json['hairline'] == true, 'a line reads as a hairline before');
  final back = read(json);
  _expect(
    back.shape == BarShape.islands &&
        back.cap == BarCap.arrow &&
        back.groundTint == BarGroundTint.accent &&
        back.borderWidth == 2 &&
        back.borderColour == BarBorderColour.accent &&
        back.textScale == 1.1 &&
        back.partGap == 4 &&
        back.edgeMargin == 3 &&
        back.endInset == 0 &&
        back.contentPadding == 8 &&
        back.cornerRadius == 9,
    'shape settings survive a round trip',
  );
  styled.copyWith(endInset: null).writeJson(json);
  _expect(!json.containsKey('endInset'), 'an unset inset writes no key');

  // Edges of a zone's segments.
  String cuts(int zone, int count) => barZoneEdges(
    zone,
    count,
  ).map((edges) => '${edges.left.name}>${edges.right.name}').join(' ');
  _expect(cuts(0, 1) == 'flat>point', 'start zone points at the centre');
  _expect(cuts(2, 1) == 'point>flat', 'end zone points at the centre');
  _expect(cuts(1, 1) == 'point>point', 'centre zone points both ways');
  _expect(
    cuts(0, 3) == 'flat>tip notch>tip notch>point',
    'start segments all point forward',
  );
  _expect(
    cuts(2, 3) == 'point>notch tip>notch tip>flat',
    'end segments all point back',
  );
  _expect(
    cuts(1, 3) == 'point>notch tip>tip notch>point',
    'centre segments point away from the middle one',
  );
  _expect(barZoneEdges(1, 0).isEmpty, 'no segments, no edges');

  // A tip and the notch it enters are one line, so neighbours leave no gap
  // and do not overlap.
  const height = 28.0;
  final depth = barArrowDepth(height);
  for (final zone in <int>[0, 1, 2]) {
    final widths = <double>[40, 64, 52, 30];
    final edges = barZoneEdges(zone, widths.length);
    var x = 0.0;
    var area = 0.0;
    List<BarPoint>? before;
    for (var index = 0; index < widths.length; index++) {
      final outline = barSegmentOutline(
        width: widths[index],
        height: height,
        depth: depth,
        left: edges[index].left,
        right: edges[index].right,
      ).map((point) => (x: point.x + x, y: point.y)).toList();
      _expect(outline.length == 6, 'six points');
      _expect(_area(outline) > 0, 'clockwise outline');
      area += _area(outline);
      if (before != null) {
        // before: top right, right middle, bottom right;
        // this: top left, left middle, bottom left.
        _expect(
          _near(before[1], outline[0]) &&
              _near(before[2], outline[5]) &&
              _near(before[3], outline[4]),
          'zone $zone join $index is shared',
        );
      }
      before = outline;
      x += widths[index];
    }
    // The run stays inside its box, and only its pointed ends leave part of
    // the box bare: half the depth times the height for each.
    final first = edges.first.left, last = edges.last.right;
    final points =
        (first == BarEdge.point ? 1 : 0) + (last == BarEdge.point ? 1 : 0);
    final expected = x * height - points * depth * height / 2;
    _expect((area - expected).abs() < 1e-6, 'zone $zone area');
  }

  // Outer points stay inside the box; content keeps clear of the cut.
  final lone = barSegmentOutline(
    width: 50,
    height: height,
    depth: depth,
    left: BarEdge.point,
    right: BarEdge.point,
  );
  _expect(
    lone.every((point) => point.x >= 0 && point.x <= 50),
    'a pointed end does not leave its box',
  );
  _expect(lone[5].x == 0 && lone[2].x == 50, 'the points touch the ends');
  _expect(barEdgeInset(BarEdge.flat, depth) == 0, 'flat needs no room');
  _expect(barEdgeInset(BarEdge.notch, depth) == depth / 2, 'notch room');
  _expect(
    barEdgeInset(BarEdge.point, depth) > 0 &&
        barEdgeInset(BarEdge.point, depth) < depth,
    'point room',
  );
  stdout.writeln('All bar shape tests passed.');
}
