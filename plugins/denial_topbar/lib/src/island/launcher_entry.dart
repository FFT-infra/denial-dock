/// The state behind `com.canonical.Unity.LauncherEntry.Update` signals. An
/// update only carries the properties that changed, so each application's
/// entry is kept and patched.
class LauncherEntries {
  final Map<String, _Entry> _byApp = <String, _Entry>{};

  /// Desktop id from `application://firefox.desktop`, or '' when malformed.
  static String appId(String uri) {
    const scheme = 'application://';
    if (!uri.startsWith(scheme)) return '';
    final name = uri.substring(scheme.length);
    return name.endsWith('.desktop')
        ? name.substring(0, name.length - '.desktop'.length)
        : name;
  }

  void update(String uri, Map<String, Object?> props, DateTime now) {
    final id = appId(uri);
    if (id.isEmpty) return;
    final entry = _byApp.putIfAbsent(id, _Entry.new)..seen = now;
    final visible = props['progress-visible'];
    if (visible is bool) entry.visible = visible;
    final progress = props['progress'];
    if (progress is num) entry.progress = progress.toDouble().clamp(0.0, 1.0);
  }

  void dropOlderThan(DateTime limit) =>
      _byApp.removeWhere((_, entry) => entry.seen.isBefore(limit));

  /// Applications with a visible progress, in the order they first appeared.
  Map<String, double> get progress => <String, double>{
    for (final entry in _byApp.entries)
      if (entry.value.visible) entry.key: entry.value.progress,
  };
}

class _Entry {
  bool visible = false;
  double progress = 0;
  DateTime seen = DateTime(0);
}
