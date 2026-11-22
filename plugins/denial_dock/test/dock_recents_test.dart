import 'package:denial_dock/src/dock_recents.dart';

void main() {
  // A launch joins at the end; an id already there keeps its slot.
  _expect(_members(['a', 'b'], running: {'c'}) == 'a,b,c', 'new app appends');
  _expect(
    _members(['a', 'b', 'c'], running: {'a', 'c'}) == 'a,b,c',
    'known ids keep their slot',
  );
  _expect(
    _members(const [], running: {'b', 'a'}) == 'b,a',
    'running apps seed an empty section in window order',
  );
  _expect(_members(const [], running: const {}).isEmpty, 'nothing in');

  // Quitting never changes the row: the app holds its slot as a closed entry,
  // so no older app is pulled back in.
  _expect(
    _members(['a', 'b', 'c'], running: {'a', 'b'}) == 'a,b,c',
    'a quit app keeps its slot',
  );
  _expect(
    _members(['a', 'b', 'c'], running: {'a', 'b'}, recent: ['d']) == 'a,b,c',
    'a full section ignores a recent while the app is open',
  );

  // A launch over the cap pushes the oldest closed slot out.
  _expect(
    _members(['a', 'b', 'c'], running: {'d'}) == 'b,c,d',
    'the oldest closed slot leaves',
  );
  _expect(
    _members(['a', 'b', 'c', 'd'], count: 2) == 'c,d',
    'the cap keeps the newest closed slots',
  );

  // Running apps are never dropped to meet the cap: the dock is the only
  // handle on their windows.
  _expect(
    _members(['a', 'b', 'c'], running: {'a', 'b', 'c'}, count: 1) == 'a,b,c',
    'running apps are never dropped',
  );
  _expect(
    _members(['a', 'b', 'c'], running: {'b'}, count: 2) == 'b,c',
    'the oldest closed slot leaves before a running one',
  );
  _expect(
    _members(['a', 'b'], running: {'a'}, count: 0) == 'a',
    'zero closed slots leaves the running apps',
  );

  // The compositor's own recents only fill spare slots; they never evict a
  // member, which is how the section fills after the count is raised.
  _expect(
    _members(['a', 'b'], recent: ['z']) == 'a,b,z',
    'a spare slot takes a recent',
  );
  _expect(
    _members(['a', 'b'], recent: ['z'], count: 2) == 'a,b',
    'a full section ignores a recent',
  );

  // A dragged-out app is gone, and the launcher's recents cannot put it back
  // while it is closed. It returns on its next launch and then stays put.
  _expect(
    _members(['a', 'b'], recent: ['c'], removed: {'c'}) == 'a,b',
    'a removed app is not refilled from the launcher',
  );
  _expect(
    _members(['a', 'b'], running: {'c'}, removed: {'c'}) == 'a,b,c',
    'a removed app returns when it runs',
  );
  _expect(
    _members(['a', 'b', 'c'], running: {'a', 'b'}, removed: {'c'}) == 'a,b,c',
    'a relaunched app stays after it quits',
  );

  // An evicted id is parked, not forgotten: lowering the count and raising it
  // again brings the same apps back.
  final shrunk = _resolve(['a', 'b', 'c', 'd', 'e'], count: 2);
  _expect(shrunk.members == 'd,e', 'count 2 keeps the newest: $shrunk');
  _expect(shrunk.parked == 'a,b,c', 'evicted ids are parked: $shrunk');
  final grown = _resolve(
    shrunk.members.split(','),
    parked: shrunk.parked.split(','),
  );
  _expect(grown.members == 'c,d,e', 'the newest evicted id comes back first');
  final restored = _resolve(
    shrunk.members.split(','),
    parked: shrunk.parked.split(','),
    count: 5,
  );
  _expect(
    restored.members == 'a,b,c,d,e',
    'raising the count by three restores all three in order: $restored',
  );

  // Hiding the section stores the members but paints only the running apps,
  // so turning it back on restores the row instead of seeding it.
  final hidden = _resolve(['a', 'b', 'c'], running: {'a'}, count: 0);
  _expect(hidden.members == 'a,b,c', 'a hidden section keeps its members');
  _expect(hidden.shown == 'a', 'a hidden section paints the running apps only');
  final backOn = _resolve(
    hidden.members.split(','),
    running: {'a'},
    parked: hidden.parked.split(','),
  );
  _expect(backOn.shown == 'a,b,c', 'showing the section brings the row back');

  // The park list is bounded and keeps the newest ids.
  final long = _resolve(
    List.generate(DockRecents.parkedLimit + 6, (i) => 'a$i'),
    count: 1,
  );
  _expect(
    long.parked.split(',').length == DockRecents.parkedLimit,
    'the park list is bounded: ${long.parked.split(',').length}',
  );
  _expect(
    long.parked.split(',').last == 'a${DockRecents.parkedLimit + 4}',
    'the park list keeps the newest evicted id: ${long.parked}',
  );
  _expect(
    long.parked.split(',').first == 'a5',
    'the park list drops the oldest ids: ${long.parked}',
  );
}

String _members(
  List<String> order, {
  Set<String> running = const {},
  Iterable<String> recent = const [],
  int count = 3,
  Set<String> removed = const {},
  List<String> parked = const [],
}) => _resolve(
  order,
  running: running,
  recent: recent,
  count: count,
  removed: removed,
  parked: parked,
).shown;

({String members, String parked, String shown}) _resolve(
  List<String> order, {
  Set<String> running = const {},
  Iterable<String> recent = const [],
  int count = 3,
  Set<String> removed = const {},
  List<String> parked = const [],
}) {
  final resolved = DockRecents.resolve(
    order: order,
    parked: parked,
    running: running,
    recent: recent,
    count: count,
    removed: removed,
  );
  return (
    members: resolved.members.join(','),
    parked: resolved.parked.join(','),
    shown: resolved.shown.join(','),
  );
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
