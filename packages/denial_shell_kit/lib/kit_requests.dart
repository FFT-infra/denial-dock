import 'dart:async';

/// Something one plugin asks another to show.
///
/// [name] says what; [monitorId] is the output the request was made on, so
/// the plugin that answers can open its window there and the same plugin on
/// another output can leave it alone. Null means any output.
typedef KitRequest = ({String name, int? monitorId});

/// Carries requests between the plugins of the shell. They run in one
/// program but may not import one another, so the one that owns a window
/// listens here and any other asks for it by name.
abstract final class KitRequests {
  /// The system's about box, which the top bar owns.
  static const String about = 'about';

  /// The bar's panels and the shell's settings, which a shortcut may ask for
  /// while the bar draws no strip to click.
  static const String controlCentre = 'controlCentre';
  static const String notificationCentre = 'notificationCentre';
  static const String settings = 'settings';

  /// Cross-plugin search/launcher entry point. Spotlight or another launcher
  /// plugin may register a handler via [registerSearchHandler]; when none is
  /// registered, [triggerSearch] falls back to the host launcher callback.
  static const String search = 'search';

  static bool Function(int? monitorId)? _searchHandler;

  /// Registers a handler that intercepts shell search requests (returning true
  /// if handled). Pass `null` to unregister.
  static void registerSearchHandler(bool Function(int? monitorId)? handler) {
    _searchHandler = handler;
  }

  /// Dispatches a search request to a registered Spotlight/launcher plugin,
  /// invoking [fallback] only when no search handler claims it.
  static void triggerSearch({
    required void Function() fallback,
    int? monitorId,
  }) {
    final handler = _searchHandler;
    if (handler != null && handler(monitorId)) return;
    fallback();
  }

  static KitRequest? _taken;

  /// Whether the caller is the one to answer [request]: the first to ask
  /// is, so a panel asked for on any output opens once and is not opened
  /// and shut again by the bar of a second screen.
  static bool take(KitRequest request) {
    if (_taken == request) return false;
    _taken = request;
    Timer.run(() => _taken = null);
    return true;
  }

  static final StreamController<KitRequest> _controller =
      StreamController<KitRequest>.broadcast();

  static Stream<KitRequest> get stream => _controller.stream;

  /// Whether any plugin is listening. An item that can only send a request
  /// is worth showing only while this is true.
  static bool get answered => _controller.hasListener;

  static void send(String name, {int? monitorId}) =>
      _controller.add((name: name, monitorId: monitorId));
}
