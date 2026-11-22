import 'package:denial_dock/src/dock_recents.dart';

void main() {
  // A launched app joins the end and never moves an existing slot.
  _expect(
    DockRecents.extended(['a', 'b'], ['c']).join(',') == 'a,b,c',
    'new id appends',
  );
  _expect(
    DockRecents.extended(['a', 'b'], ['b', 'a']).join(',') == 'a,b',
    'known ids keep their slot',
  );
  _expect(
    DockRecents.extended(['a'], ['b', 'a', 'c']).join(',') == 'a,b,c',
    'order of the incoming list decides the new slots',
  );
  _expect(DockRecents.extended(const [], const []).isEmpty, 'nothing in');
  _expect(
    DockRecents.extended(const [], ['a']).join(',') == 'a',
    'first id starts the order',
  );
  // Growth is capped by trimmed(), not here: the cap has to know which ids the
  // row paints, and only the caller has that.
  _expect(
    DockRecents.extended(List.generate(DockRecents.remembered, (i) => 'a$i'), [
          'extra',
        ]).length ==
        DockRecents.remembered + 1,
    'extended appends without a cap',
  );

  // The section paints running apps wherever they sit, plus the first N
  // closed ones. This is what keeps a neighbour still when one app quits.
  const order = ['a', 'b', 'c', 'd'];
  _expect(
    DockRecents.visible(
          order: order,
          running: {'a', 'b', 'c', 'd'},
          count: 3,
        ).join(',') ==
        'a,b,c,d',
    'running apps all show',
  );
  _expect(
    DockRecents.visible(order: order, running: {'a'}, count: 3).join(',') ==
        'a,b,c,d',
    'three closed apps fill the rest',
  );
  _expect(
    DockRecents.visible(order: order, running: {'a'}, count: 1).join(',') ==
        'a,b',
    'one closed app',
  );
  _expect(
    DockRecents.visible(order: order, running: {'a'}, count: 0).join(',') ==
        'a',
    'zero closed apps leaves only the running ones',
  );
  _expect(
    DockRecents.visible(order: order, running: {'b'}, count: 1).join(',') ==
        'a,b',
    'the running app keeps its own slot, not the front',
  );

  // A dismissed id is skipped while closed and returns once it runs.
  _expect(
    DockRecents.visible(
          order: order,
          running: const {},
          count: 3,
          dismissed: {'a'},
        ).join(',') ==
        'b,c,d',
    'dismissed closed id is skipped',
  );
  _expect(
    DockRecents.visible(
          order: order,
          running: {'a'},
          count: 3,
          dismissed: {'a'},
        ).join(',') ==
        'a,b,c,d',
    'a dismissed app that starts running comes back',
  );

  // A quit app does not shift the row: the slot it held is where it returns.
  final before = DockRecents.visible(
    order: order,
    running: {'a', 'b', 'c'},
    count: 3,
  );
  final after = DockRecents.visible(
    order: order,
    running: {'a', 'c'},
    count: 3,
  );
  _expect(
    before.join(',') == after.join(','),
    'quitting one app leaves the row unchanged: $before vs $after',
  );

  // An app that is not in the order at all is simply absent, not appended
  // here; the caller extends the order first.
  _expect(
    DockRecents.visible(
          order: const ['a'],
          running: {'z'},
          count: 3,
        ).join(',') ==
        'a',
    'unknown running id is not painted',
  );

  // Trimming drops idle ids from the tail and never a painted one, so the cap
  // stays invisible: the row looks the same before and after.
  const long = ['a', 'b', 'c', 'd', 'e', 'f'];
  final capped = DockRecents.trimmed(
    order: long,
    running: const {'a'},
    count: 2,
    limit: 4,
  );
  _expect(
    capped.join(',') == 'a,b,c,f',
    'trim drops the unpainted tail and keeps the painted prefix: $capped',
  );
  _expect(
    DockRecents.trimmed(
          order: long,
          running: const {},
          count: 2,
          limit: 4,
        ).join(',') ==
        'a,b,e,f',
    'trim keeps a painted id that sits past the limit',
  );
  _expect(
    DockRecents.trimmed(
          order: long,
          running: const {},
          count: 2,
          limit: 9,
        ).join(',') ==
        long.join(','),
    'trim does nothing under the limit',
  );
  _expect(
    DockRecents.trimmed(
          order: const ['a', 'b', 'c'],
          running: const {'a', 'b', 'c'},
          count: 0,
          limit: 2,
        ).join(',') ==
        'a,b,c',
    'a painted slot is never dropped to meet the cap',
  );
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
