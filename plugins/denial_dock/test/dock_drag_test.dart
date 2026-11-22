import 'package:denial_dock/src/dock_drag.dart';

void main() {
  const list = ['a', 'b', 'c', 'd'];

  // Remove-then-insert ordering used by the drag preview and the saved pins.
  _expect(DockDrag.moved(list, 0, 2).join() == 'bcad', 'move right');
  _expect(DockDrag.moved(list, 3, 1).join() == 'adbc', 'move left');
  _expect(DockDrag.moved(list, 1, 1).join() == 'abcd', 'move to self');
  _expect(DockDrag.moved(list, 0, 9).join() == 'bcda', 'clamp to end');
  _expect(DockDrag.moved(list, 9, 0).join() == 'abcd', 'invalid source');
  _expect(list.join() == 'abcd', 'input list untouched');

  // A running application joins the pinned order at the drop slot.
  _expect(DockDrag.inserted(list, 'x', 0).join() == 'xabcd', 'insert start');
  _expect(DockDrag.inserted(list, 'x', 2).join() == 'abxcd', 'insert middle');
  _expect(DockDrag.inserted(list, 'x', 99).join() == 'abcdx', 'insert end');
  _expect(DockDrag.inserted(list, 'x', -3).join() == 'xabcd', 'insert clamp');
  _expect(list.join() == 'abcd', 'insert leaves input untouched');

  // Insertion follows the nearest painted centre.
  const centers = [100.0, 160.0, 220.0, 280.0];
  _expect(
    DockDrag.insertionIndex(centers: centers, pointerX: 165, fallback: 0) == 1,
    'nearest 1',
  );
  _expect(
    DockDrag.insertionIndex(centers: centers, pointerX: 10, fallback: 0) == 0,
    'clamp start',
  );
  _expect(
    DockDrag.insertionIndex(centers: centers, pointerX: 999, fallback: 0) == 3,
    'clamp end',
  );
  _expect(
    DockDrag.insertionIndex(centers: const [], pointerX: 0, fallback: 2) == 2,
    'empty fallback',
  );
  _expect(
    DockDrag.insertionIndex(centers: centers, pointerX: 999, fallback: 9) == 3,
    'fallback clamped',
  );

  // Dropping outside the dock. A pin is the user's own choice and goes whether
  // or not the app is running; a suggestion leaves only while its app is
  // closed; a running app that is neither stays, because the dock is the only
  // way back to its windows.
  _expect(
    DockDrag.removalFor(
          pinned: true,
          suggestion: false,
          running: false,
          outside: true,
        ) ==
        DockRemoval.unpin,
    'pinned, not running: unpin',
  );
  _expect(
    DockDrag.removalFor(
          pinned: true,
          suggestion: false,
          running: true,
          outside: true,
        ) ==
        DockRemoval.unpin,
    'pinned and running: still unpin',
  );
  _expect(
    DockDrag.removalFor(
          pinned: false,
          suggestion: true,
          running: false,
          outside: true,
        ) ==
        DockRemoval.dismissRecent,
    'closed suggestion: dismiss',
  );
  _expect(
    DockDrag.removalFor(
          pinned: false,
          suggestion: true,
          running: true,
          outside: true,
        ) ==
        DockRemoval.none,
    'a suggestion that started running stays',
  );
  _expect(
    DockDrag.removalFor(
          pinned: false,
          suggestion: false,
          running: true,
          outside: true,
        ) ==
        DockRemoval.none,
    'running, not pinned: keep',
  );
  for (final pinned in [true, false]) {
    for (final suggestion in [true, false]) {
      for (final running in [true, false]) {
        _expect(
          DockDrag.removalFor(
                pinned: pinned,
                suggestion: suggestion,
                running: running,
                outside: false,
              ) ==
              DockRemoval.none,
          'inside never removes (pinned=$pinned, suggestion=$suggestion, '
          'running=$running)',
        );
      }
    }
  }
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
