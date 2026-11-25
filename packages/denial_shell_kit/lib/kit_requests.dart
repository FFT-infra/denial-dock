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

  static final StreamController<KitRequest> _controller =
      StreamController<KitRequest>.broadcast();

  static Stream<KitRequest> get stream => _controller.stream;

  /// Whether any plugin is listening. An item that can only send a request
  /// is worth showing only while this is true.
  static bool get answered => _controller.hasListener;

  static void send(String name, {int? monitorId}) =>
      _controller.add((name: name, monitorId: monitorId));
}
