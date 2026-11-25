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

  // A finger that wobbles is still resting; six pixels away it has left.
  _expect(!DockDrag.leftRest(0), 'still is resting');
  _expect(!DockDrag.leftRest(5.9), 'a wobble is resting');
  _expect(DockDrag.leftRest(DockDrag.restSlop), 'the slop itself has left');
  _expect(DockDrag.leftRest(40), 'a swipe has left');
  _expect(!DockDrag.leftRest(double.nan), 'a broken distance never leaves');

  // A mouse keeps its rule: travel alone picks the icon up, and resting on
  // the icon neither lifts it nor turns the release into a menu.
  _expect(
    DockDrag.pressTravelled(DockPress.down, DockPointerKind.precise) ==
        DockPress.dragging,
    'mouse: travel drags without a hold',
  );
  _expect(
    DockDrag.pressRested(DockPress.down, DockPointerKind.precise) ==
        DockPress.down,
    'mouse: resting does not lift',
  );
  _expect(
    _release([_Step.rest], DockPointerKind.precise) == DockPressEnd.none,
    'mouse: a long click is still a click',
  );
  _expect(
    _release([_Step.travel], DockPointerKind.precise) == DockPressEnd.drop,
    'mouse: a drag ends in a drop',
  );

  // A finger has to rest first. Travelling before the hold is a swipe, and a
  // swipe stays one even if the finger then stops on the icon.
  _expect(
    DockDrag.pressTravelled(DockPress.down, DockPointerKind.touch) ==
        DockPress.swipe,
    'touch: travel before the hold is a swipe',
  );
  _expect(
    _release([_Step.travel], DockPointerKind.touch) == DockPressEnd.none,
    'touch: a swipe picks nothing up',
  );
  _expect(
    _run([_Step.travel, _Step.rest], DockPointerKind.touch) == DockPress.swipe,
    'touch: a swipe that stops does not lift',
  );
  _expect(
    _release([_Step.travel, _Step.rest, _Step.travel], DockPointerKind.touch) ==
        DockPressEnd.none,
    'touch: a swipe never drags',
  );
  _expect(
    _release([], DockPointerKind.touch) == DockPressEnd.none,
    'touch: a short tap is only a tap',
  );

  // Holding lifts the icon. From there, letting go is the long press and
  // moving is the drag; a drag stays a drag when the finger comes to rest.
  _expect(
    _run([_Step.rest], DockPointerKind.touch) == DockPress.lifted,
    'touch: a hold lifts',
  );
  _expect(
    _release([_Step.rest], DockPointerKind.touch) == DockPressEnd.menu,
    'touch: hold then release opens the menu',
  );
  _expect(
    _run([_Step.rest, _Step.travel], DockPointerKind.touch) ==
        DockPress.dragging,
    'touch: hold then move drags',
  );
  _expect(
    _release([_Step.rest, _Step.travel], DockPointerKind.touch) ==
        DockPressEnd.drop,
    'touch: hold then move drops, no menu',
  );
  _expect(
    _release([_Step.rest, _Step.travel, _Step.rest], DockPointerKind.touch) ==
        DockPressEnd.drop,
    'touch: a drag that pauses is still a drag',
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

/// What happens to a press between down and up.
enum _Step { travel, rest }

/// Plays [steps] on a fresh press, the way the icon feeds its pointer events.
DockPress _run(List<_Step> steps, DockPointerKind kind) {
  var press = DockPress.down;
  for (final step in steps) {
    press = switch (step) {
      _Step.travel => DockDrag.pressTravelled(press, kind),
      _Step.rest => DockDrag.pressRested(press, kind),
    };
  }
  return press;
}

DockPressEnd _release(List<_Step> steps, DockPointerKind kind) =>
    DockDrag.pressReleased(_run(steps, kind));
