import 'package:denial_dock/src/dock_pile.dart';

void main() {
  // The pile leans up and to the left behind the front card, the way a macOS
  // stack sits on its folder.
  _expect(DockPile.count == 3, 'three cards');
  for (var i = 1; i < DockPile.count; i++) {
    final offset = DockPile.offset(i);
    _expect(offset.dx < 0, 'card $i sits left of the front');
    _expect(offset.dy < 0, 'card $i sits above the front');
    _expect(
      offset.dx < DockPile.offset(i - 1).dx,
      'card $i is further back than ${i - 1}',
    );
  }
  _expect(
    DockPile.offset(0).dx == 0 && DockPile.offset(0).dy == 0,
    'the front card is centred',
  );

  // Each card turns a little further and sits a little smaller.
  _expect(DockPile.angle(0) == 0, 'the front card is square');
  _expect(DockPile.angle(2) < DockPile.angle(1), 'cards turn with depth');
  _expect(DockPile.scale(0) == 1, 'the front card is full size');
  _expect(DockPile.scale(2) < DockPile.scale(1), 'cards shrink with depth');

  // The pile's edge is also the size a fan row starts from, so it has to
  // stay inside the tile and shrink with depth.
  for (var i = 0; i < DockPile.count; i++) {
    _expect(DockPile.edge(i) > 0 && DockPile.edge(i) < 1, 'card $i fits');
  }
  _expect(DockPile.edge(2) < DockPile.edge(0), 'deeper cards sit smaller');
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
