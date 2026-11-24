import 'dart:async';

/// A countdown the island shows as a live activity. One per shell, so a timer
/// started on one monitor shows on all of them.
class IslandTimer {
  final List<void Function()> _listeners = <void Function()>[];

  void addListener(void Function() listener) => _listeners.add(listener);
  void removeListener(void Function() listener) => _listeners.remove(listener);

  void notifyListeners() {
    for (final listener in List<void Function()>.of(_listeners)) {
      listener();
    }
  }

  DateTime? _end;
  Duration? _paused;
  Duration _total = Duration.zero;
  Timer? _fire;

  /// When the last countdown ran out.
  DateTime? finishedAt;

  bool get active => _end != null || _paused != null;
  bool get paused => _paused != null;
  Duration get total => _total;

  Duration remaining(DateTime now) {
    final left = _paused ?? _end?.difference(now) ?? Duration.zero;
    return left.isNegative ? Duration.zero : left;
  }

  void start(Duration length, DateTime now) {
    _total = length;
    _paused = null;
    _run(length, now);
  }

  void add(Duration extra, DateTime now) {
    if (!active) return;
    _total += extra;
    final paused = _paused;
    if (paused != null) {
      _paused = paused + extra;
      notifyListeners();
    } else {
      _run(remaining(now) + extra, now);
    }
  }

  void toggle(DateTime now) {
    final paused = _paused;
    if (paused != null) {
      _paused = null;
      _run(paused, now);
    } else if (_end != null) {
      _paused = remaining(now);
      _end = null;
      _fire?.cancel();
      notifyListeners();
    }
  }

  void cancel() {
    if (!active) return;
    _stop();
    notifyListeners();
  }

  void _run(Duration left, DateTime now) {
    _end = now.add(left);
    _fire?.cancel();
    _fire = Timer(left, () {
      _stop();
      finishedAt = DateTime.now();
      notifyListeners();
    });
    notifyListeners();
  }

  void _stop() {
    _fire?.cancel();
    _end = null;
    _paused = null;
  }
}

final IslandTimer islandTimer = IslandTimer();

/// `m:ss`, or `h:mm:ss` from an hour up.
String clockSpan(Duration span) {
  final seconds = (span.inMilliseconds / 1000).ceil();
  String two(int value) => value.toString().padLeft(2, '0');
  final h = seconds ~/ 3600, m = seconds % 3600 ~/ 60, s = seconds % 60;
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
}
