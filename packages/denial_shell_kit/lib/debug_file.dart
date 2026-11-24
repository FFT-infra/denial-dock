import 'dart:async';
import 'dart:io';

final Map<String, StreamController<List<String>>> _controllers =
    <String, StreamController<List<String>>>{};

/// Lets a developer drive a plugin without a pointer, so a screenshot can
/// show what a pointer would open. When the file `<plugin>.debug` exists
/// beside the plugin's preferences at the first call, each write to it is one
/// command, delivered here split into words. Without the file nothing is
/// watched.
Stream<List<String>> debugFileCommands(String plugin) {
  final existing = _controllers[plugin];
  if (existing != null) return existing.stream;
  final controller = _controllers[plugin] =
      StreamController<List<String>>.broadcast();
  final home = Platform.environment['HOME'];
  if (home == null) return controller.stream;
  final file = File('$home/.config/denial/plugins/$plugin.debug');
  if (!file.existsSync()) return controller.stream;
  Timer? settle;
  file.parent.watch().where((event) => event.path == file.path).listen((_) {
    settle?.cancel();
    settle = Timer(const Duration(milliseconds: 60), () {
      try {
        final words = file.readAsStringSync().trim().split(RegExp(r'\s+'))
          ..removeWhere((word) => word.isEmpty);
        if (words.isNotEmpty) controller.add(words);
      } on FileSystemException {
        return;
      }
    });
  }, onError: (Object _) {});
  return controller.stream;
}
