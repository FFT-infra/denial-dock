import 'dart:async';

/// A shortcut asking for the dock's Nth application, counted from one.
typedef DockHotkey = ({int slot, int? monitorId});

/// Carries shortcut actions from the plugin's entry point to the dock that is
/// on screen. The actions are created by the host and know nothing of the
/// widget tree; the dock listens here instead.
abstract final class DockHotkeys {
  static final StreamController<DockHotkey> _controller =
      StreamController<DockHotkey>.broadcast();

  static Stream<DockHotkey> get requests => _controller.stream;

  static void activate(int slot, {int? monitorId}) =>
      _controller.add((slot: slot, monitorId: monitorId));
}
