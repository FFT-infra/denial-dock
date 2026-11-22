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
    _members(['a', 'b', 'c', 'd'], running: const {}, count: 2) == 'c,d',
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
}

String _members(
  List<String> order, {
  Set<String> running = const {},
  Iterable<String> recent = const [],
  int count = 3,
  Set<String> removed = const {},
}) => DockRecents.members(
  order: order,
  running: running,
  recent: recent,
  count: count,
  removed: removed,
).join(',');

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
