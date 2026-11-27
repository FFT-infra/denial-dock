/// Tracks system-tray icon interaction frequency so infrequently clicked tray
/// icons can be automatically folded behind the tray handle.
///
/// Pure Dart (no Flutter import) for unit tests; persistence is wired via a
/// lightweight read/write callback injected by the topbar runtime.
library;

/// In-memory + pluggable-store usage frequency table for tray items.
class TrayUsageTracker {
  TrayUsageTracker({this.reader, this.writer});

  final Map<String, int> Function()? reader;
  final void Function(Map<String, int>)? writer;

  Map<String, int>? _counts;
  final List<void Function()> _listeners = <void Function()>[];

  Map<String, int> get counts => Map<String, int>.unmodifiable(_ensure());

  int countOf(String key) => _ensure()[key] ?? 0;

  void addListener(void Function() fn) => _listeners.add(fn);
  void removeListener(void Function() fn) => _listeners.remove(fn);

  void record(String key) {
    final clean = key.trim();
    if (clean.isEmpty) return;
    final map = _ensure();
    map[clean] = (map[clean] ?? 0) + 1;
    writer?.call(map);
    for (final fn in List<void Function()>.of(_listeners)) {
      fn();
    }
  }

  void clear() {
    _counts = <String, int>{};
    writer?.call(_counts!);
    for (final fn in List<void Function()>.of(_listeners)) {
      fn();
    }
  }

  Map<String, int> _ensure() {
    final existing = _counts;
    if (existing != null) return existing;
    final loaded = reader?.call();
    return _counts = <String, int>{...?loaded};
  }
}

/// Parses a persisted JSON map into sanitized non-negative click counts.
Map<String, int> parseTrayUsageMap(Object? raw) {
  if (raw is! Map) return const <String, int>{};
  final out = <String, int>{};
  for (final entry in raw.entries) {
    final k = entry.key;
    final v = entry.value;
    if (k is String && k.isNotEmpty && v is num && v.isFinite && v > 0) {
      out[k] = v.round();
    }
  }
  return out;
}
