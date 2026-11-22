import 'dart:async';
import 'dart:io';

/// Watches a stack folder while its stack is open, so a file that lands while
/// the user is looking appears without reopening the stack.
///
/// A directory watch reports the folder's own entries changing, which is what a
/// stack shows. It does not recurse: a stack lists one directory, so a change
/// three levels down is not its business.
class DockStackWatch {
  DockStackWatch(this.path, this.onChange);

  final String path;
  final void Function() onChange;

  StreamSubscription<FileSystemEvent>? _subscription;
  Timer? _debounce;

  /// Starts watching. A folder that is gone, or a platform that cannot watch
  /// one, leaves the stack working — it just does not live-update.
  void start() {
    if (_subscription != null) return;
    try {
      _subscription = Directory(path).watch().listen(
        (_) => _schedule(),
        onError: (Object _) => stop(),
        cancelOnError: true,
      );
    } on FileSystemException {
      _subscription = null;
    }
  }

  void stop() {
    _debounce?.cancel();
    _debounce = null;
    _subscription?.cancel();
    _subscription = null;
  }

  /// A download writes many events a second; the stack re-reads the whole
  /// directory on each, so the events are folded into one read.
  void _schedule() {
    if (_debounce != null) return;
    _debounce = Timer(const Duration(milliseconds: 180), () {
      _debounce = null;
      onChange();
    });
  }
}
