import 'package:denial_dock/src/dock_click.dart';
import 'package:denial_dock/src/dock_settings.dart';

void main() {
  // The outcome a click resolves to, per action.
  ({DockClickKind kind, int index}) click(
    DockClickAction action,
    int count,
    int active,
  ) => DockClick.resolve(action: action, count: count, activeIndex: active);
  _expect(
    click(DockClickAction.minimize, 2, 1) ==
        (kind: DockClickKind.minimize, index: 1),
    'front app minimizes its active window',
  );
  _expect(
    click(DockClickAction.minimize, 2, -1) ==
        (kind: DockClickKind.activate, index: 0),
    'background app comes forward',
  );
  _expect(
    click(DockClickAction.cycle, 3, 0) ==
        (kind: DockClickKind.activate, index: 1),
    'cycle advances',
  );
  _expect(
    click(DockClickAction.previews, 2, 0).kind == DockClickKind.previews &&
        click(DockClickAction.previews, 2, -1).kind == DockClickKind.previews,
    'several windows open the previews',
  );
  _expect(
    click(DockClickAction.previews, 1, 0) ==
        (kind: DockClickKind.minimize, index: 0),
    'one window falls back to minimize',
  );
  _expect(
    click(DockClickAction.raise, 2, 0).kind == DockClickKind.nothing &&
        click(DockClickAction.raise, 1, 0).kind == DockClickKind.nothing &&
        click(DockClickAction.raise, 2, -1) ==
            (kind: DockClickKind.activate, index: 0),
    'raise never minimizes',
  );
  _expect(
    click(DockClickAction.minimize, 0, -1).kind == DockClickKind.nothing,
    'no windows',
  );

  // Minimize mode: a front-most application minimizes, anything else comes
  // forward.
  _expect(
    DockClick.nextIndex(
          action: DockClickAction.minimize,
          count: 3,
          activeIndex: 1,
        ) ==
        null,
    'minimize active',
  );
  _expect(
    DockClick.nextIndex(
          action: DockClickAction.minimize,
          count: 3,
          activeIndex: -1,
        ) ==
        0,
    'minimize raises',
  );

  // A minimized window waits at the end of the visit order, so a click brings
  // a restored window up before a hidden one.
  _expect(
    DockClick.visitOrder(3, const [false, true, false]).toString() ==
        '[0, 2, 1]',
    'minimized last',
  );
  _expect(
    DockClick.nextIndex(
          action: DockClickAction.cycle,
          count: 3,
          activeIndex: 2,
          minimized: const [false, true, false],
        ) ==
        1,
    'cycle enters minimized last',
  );
  _expect(
    DockClick.nextIndex(
          action: DockClickAction.minimize,
          count: 2,
          activeIndex: -1,
          minimized: const [true, false],
        ) ==
        1,
    'background app raises its restored window',
  );

  // Cycle mode advances in stable order and wraps.
  for (var i = 0; i < 3; i++) {
    _expect(
      DockClick.nextIndex(
            action: DockClickAction.cycle,
            count: 3,
            activeIndex: i,
          ) ==
          (i + 1) % 3,
      'cycle $i',
    );
  }
  _expect(
    DockClick.nextIndex(
          action: DockClickAction.cycle,
          count: 1,
          activeIndex: 0,
        ) ==
        0,
    'cycle single window',
  );
  _expect(
    DockClick.nextIndex(
          action: DockClickAction.cycle,
          count: 0,
          activeIndex: 0,
        ) ==
        null,
    'cycle empty',
  );
  // An out-of-range active index falls back to raising the first window.
  _expect(
    DockClick.nextIndex(
          action: DockClickAction.cycle,
          count: 2,
          activeIndex: 7,
        ) ==
        0,
    'cycle stale index',
  );

  _expect(DockClick.activeIndex([false, true, false]) == 1, 'active index');
  _expect(DockClick.activeIndex([false, false]) == -1, 'no active');

  // Settings parse both values and fall back on garbage.
  _expect(
    DockClickAction.parse('cycle') == DockClickAction.cycle,
    'parse cycle',
  );
  _expect(
    DockClickAction.parse('nonsense') == DockClickAction.minimize,
    'parse fallback',
  );
  _expect(
    DockSettings.fromJson({'clickAction': 'cycle'}).clickAction ==
        DockClickAction.cycle,
    'json cycle',
  );
  _expect(
    DockSettings.fromJson({'clickAction': 42}).clickAction ==
        DockClickAction.minimize,
    'json garbage',
  );

  // Wheel scrolling walks the window list in both directions and wraps.
  _expect(
    DockClick.scrollIndex(count: 3, activeIndex: 1, down: true) == 2,
    'scroll down advances',
  );
  _expect(
    DockClick.scrollIndex(count: 3, activeIndex: 1, down: false) == 0,
    'scroll up retreats',
  );
  _expect(
    DockClick.scrollIndex(count: 3, activeIndex: 2, down: true) == 0,
    'scroll down wraps',
  );
  _expect(
    DockClick.scrollIndex(count: 3, activeIndex: 0, down: false) == 2,
    'scroll up wraps',
  );
  _expect(
    DockClick.scrollIndex(count: 3, activeIndex: -1, down: true) == 0,
    'scroll raises a background app',
  );
  _expect(
    DockClick.scrollIndex(count: 1, activeIndex: 0, down: false) == 0,
    'single window stays',
  );
  _expect(
    DockClick.scrollIndex(count: 0, activeIndex: -1, down: true) == null,
    'no windows',
  );

  _expect(
    DockScrollAction.parse('switch-workspace') ==
        DockScrollAction.switchWorkspace,
    'parse workspace scroll',
  );
  _expect(
    DockScrollAction.parse('nonsense') == DockScrollAction.nothing,
    'scroll parse fallback',
  );
  _expect(
    DockSettings.fromJson({'scrollAction': 'cycle-windows'}).scrollAction ==
        DockScrollAction.cycleWindows,
    'json scroll action',
  );
  _expect(
    DockSettings.defaults.scrollAction == DockScrollAction.nothing,
    'scroll default',
  );
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
