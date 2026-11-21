import 'package:denial_dock/src/dock_click.dart';
import 'package:denial_dock/src/dock_settings.dart';

void main() {
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
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
