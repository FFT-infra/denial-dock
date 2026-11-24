import 'dart:async';
import 'dart:io';

/// Lets a developer drive the dock without a pointer. When the file
/// `denial_dock.debug` exists beside the preferences at start, each write to
/// it is a command, so a screenshot can show what a pointer would open:
///
/// - `settings 3` opens the sheet on its fourth page
/// - `click 2` acts as a click on the second application
/// - `preview code`, `menu code` open an application's previews or menu
/// - `folder downloads fan` opens a folder's stack, optionally in one view
/// - `menu downloads` opens a folder's or the trash's menu
/// - `dockmenu` opens the dock's own menu, `close` shuts whatever is open
///
/// Without the file nothing is watched.
abstract final class DockDebug {
  static final StreamController<List<String>> _controller =
      StreamController<List<String>>.broadcast();
  static bool _started = false;

  static Stream<List<String>> get commands {
    _start();
    return _controller.stream;
  }

  static void _start() {
    if (_started) return;
    _started = true;
    final home = Platform.environment['HOME'];
    if (home == null) return;
    final file = File('$home/.config/denial/plugins/denial_dock.debug');
    if (!file.existsSync()) return;
    Timer? settle;
    file.parent.watch().where((event) => event.path == file.path).listen((_) {
      settle?.cancel();
      settle = Timer(const Duration(milliseconds: 60), () {
        try {
          final words = file.readAsStringSync().trim().split(RegExp(r'\s+'))
            ..removeWhere((word) => word.isEmpty);
          if (words.isNotEmpty) _controller.add(words);
        } on FileSystemException {
          return;
        }
      });
    }, onError: (Object _) {});
  }
}
