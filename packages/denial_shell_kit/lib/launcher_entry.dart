/// What an application publishes about itself through the Unity launcher API:
/// the `com.canonical.Unity.LauncherEntry.Update(s, a{sv})` signal on the
/// session bus. Browsers send download progress this way, mail and chat
/// clients their unread count.
///
/// No Flutter and no D-Bus imports: the caller unpacks the signal into plain
/// Dart values, so the rules here run as an ordinary Dart test.
class LauncherEntry {
  const LauncherEntry({
    this.count = 0,
    this.countVisible = false,
    this.progress = 0,
    this.progressVisible = false,
    this.urgent = false,
  });

  final int count;
  final bool countVisible;

  /// 0–1.
  final double progress;
  final bool progressVisible;
  final bool urgent;

  /// The count to draw, or zero when the sender hides it.
  int get shownCount => countVisible && count > 0 ? count : 0;

  /// The progress to draw, or null when the sender hides it.
  double? get shownProgress => progressVisible ? progress : null;

  /// Nothing to draw and nothing to react to.
  bool get idle => shownCount == 0 && !progressVisible && !urgent;

  /// This entry with [properties] applied. A property the signal leaves out
  /// keeps its value, and one of the wrong type is ignored rather than
  /// trusted: any process on the bus can send this signal.
  LauncherEntry merge(Map<String, Object?> properties) {
    var count = this.count;
    final rawCount = properties['count'];
    if (rawCount is int && rawCount >= 0 && rawCount <= 0x7fffffff) {
      count = rawCount;
    }
    var progress = this.progress;
    final rawProgress = properties['progress'];
    if (rawProgress is num) {
      final value = rawProgress.toDouble();
      progress = value.isFinite ? value.clamp(0.0, 1.0).toDouble() : 0;
    }
    final countVisible = properties['count-visible'];
    final progressVisible = properties['progress-visible'];
    final urgent = properties['urgent'];
    return LauncherEntry(
      count: count,
      countVisible: countVisible is bool ? countVisible : this.countVisible,
      progress: progress,
      progressVisible: progressVisible is bool
          ? progressVisible
          : this.progressVisible,
      urgent: urgent is bool ? urgent : this.urgent,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LauncherEntry &&
      other.count == count &&
      other.countVisible == countVisible &&
      other.progress == progress &&
      other.progressVisible == progressVisible &&
      other.urgent == urgent;

  @override
  int get hashCode =>
      Object.hash(count, countVisible, progress, progressVisible, urgent);

  @override
  String toString() =>
      'LauncherEntry(count: $count/$countVisible, '
      'progress: $progress/$progressVisible, urgent: $urgent)';
}

/// Every sender's entries, folded into one entry per application.
///
/// Two processes can publish for the same application, so each sender keeps
/// its own copy and the one that spoke last is shown. A sender that leaves the
/// bus takes its copy with it; otherwise a crashed download would leave its
/// bar on the icon for good.
class LauncherEntries {
  /// sender → application → entry.
  final Map<String, Map<String, LauncherEntry>> _bySender = {};

  /// application → senders, the most recent last.
  final Map<String, List<String>> _order = {};

  /// application → the desktop id as its sender last spelled it.
  final Map<String, String> _spelling = {};

  /// The application an `application://foo.desktop` URI names: lower case,
  /// without the scheme or the `.desktop` suffix. Null when nothing is left.
  static String? applicationId(String uri) {
    var text = uri.trim();
    final scheme = RegExp(r'^\w+://').firstMatch(text);
    if (scheme != null) text = text.substring(scheme.end);
    text = text.toLowerCase();
    if (text.endsWith('.desktop')) {
      text = text.substring(0, text.length - '.desktop'.length);
    }
    return text.isEmpty ? null : text;
  }

  /// The desktop id an `application://Foo.desktop` URI names, case kept, for
  /// looking the application up where ids are compared exactly.
  static String? desktopId(String uri) {
    var text = uri.trim();
    final scheme = RegExp(r'^\w+://').firstMatch(text);
    if (scheme != null) text = text.substring(scheme.end);
    if (text.toLowerCase().endsWith('.desktop')) {
      text = text.substring(0, text.length - '.desktop'.length);
    }
    return text.isEmpty ? null : text;
  }

  /// The desktop id for [id] as its sender spelled it, or [id] itself.
  String spelling(String id) => _spelling[id] ?? id;

  /// Applies one `Update` signal. Returns the application whose entry
  /// changed, or null when the signal changed nothing that is shown.
  String? update(String sender, String uri, Map<String, Object?> properties) {
    if (sender.isEmpty) return null;
    final id = applicationId(uri);
    if (id == null) return null;
    final before = entry(id);
    final mine = _bySender.putIfAbsent(sender, () => {});
    mine[id] = (mine[id] ?? const LauncherEntry()).merge(properties);
    final order = _order.putIfAbsent(id, () => []);
    order
      ..remove(sender)
      ..add(sender);
    _spelling[id] = desktopId(uri) ?? id;
    return entry(id) == before ? null : id;
  }

  /// Drops everything [sender] published. Returns the applications whose
  /// entry changed.
  List<String> removeSender(String sender) {
    final mine = _bySender.remove(sender);
    if (mine == null) return const [];
    final changed = <String>[];
    for (final id in mine.keys) {
      final before = mine[id];
      final order = _order[id];
      final wasTop = order != null && order.isNotEmpty && order.last == sender;
      order?.remove(sender);
      if (order != null && order.isEmpty) {
        _order.remove(id);
        _spelling.remove(id);
      }
      if (wasTop && entry(id) != before) changed.add(id);
    }
    return changed;
  }

  /// The entry shown for [id], which is the last sender's.
  LauncherEntry? entry(String id) {
    final order = _order[id];
    if (order == null || order.isEmpty) return null;
    return _bySender[order.last]?[id];
  }

  /// Every application with something to show, keyed the way
  /// [applicationId] spells it.
  Map<String, LauncherEntry> get active {
    final result = <String, LauncherEntry>{};
    for (final id in _order.keys) {
      final current = entry(id);
      if (current != null && !current.idle) result[id] = current;
    }
    return result;
  }

  bool get isEmpty => _bySender.isEmpty;
}
