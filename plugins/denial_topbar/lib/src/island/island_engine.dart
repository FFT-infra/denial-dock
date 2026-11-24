/// What the island can show. The order is the pre-emption order: a later
/// kind takes the island from an earlier one.
enum IslandKind {
  home,
  media,
  progress,
  timer,
  recording,
  charging,
  track,
  status,
  notice,
  hud;

  /// Transients leave on their own; the kinds before [charging] are live
  /// activities and stay for as long as their source says so.
  bool get transient => index >= IslandKind.charging.index;

  /// Whether the pill can grow into a card.
  bool get expandable => this != IslandKind.hud && this != IslandKind.status;
}

class IslandItem {
  const IslandItem(this.kind, this.id, this.until);

  final IslandKind kind;

  /// Distinguishes two items of one kind, e.g. two notifications.
  final String id;
  final DateTime until;
}

/// Decides what the island shows.
///
/// Live activities sit underneath; the strongest one, or the one the user
/// swiped to, has the pill and the next one rides beside it. Transient items
/// take the island for a while and hand it back. A stronger transient interrupts a
/// weaker one, which waits its turn and returns with the time it had left;
/// a weaker one arriving during a stronger one simply waits.
class IslandEngine {
  final Set<IslandKind> _live = <IslandKind>{};
  IslandKind? _picked;
  IslandItem? _current;
  final List<({IslandItem item, Duration left})> _waiting =
      <({IslandItem item, Duration left})>[];
  bool _expanded = false;

  IslandItem? get transient => _current;

  /// Live activities, strongest first, with the picked one in front.
  List<IslandKind> get live {
    final sorted = _live.toList()..sort((a, b) => b.index.compareTo(a.index));
    final picked = _picked;
    if (picked != null && sorted.remove(picked)) sorted.insert(0, picked);
    return sorted;
  }

  IslandKind? get primary => live.firstOrNull;

  IslandKind? get kind => _current?.kind ?? primary;

  /// The live activity shown as a bubble beside the pill.
  IslandKind? get secondary {
    if (_current != null || _expanded) return null;
    final rest = live.where((kind) => kind != IslandKind.home).toList();
    return rest.length > 1 ? rest[1] : null;
  }

  bool get expanded => _expanded && (kind?.expandable ?? false);

  /// When the engine next needs [tick], or null.
  DateTime? get nextDeadline => _current?.until;

  void setMedia(bool playing) => setLive(IslandKind.media, playing);

  void setLive(IslandKind kind, bool on) {
    assert(!kind.transient);
    final shown = this.kind;
    if (!(on ? _live.add(kind) : _live.remove(kind))) return;
    if (!on && _picked == kind) _picked = null;
    if (this.kind != shown) _expanded = false;
  }

  /// Hands the pill to the next live activity, or the previous one.
  void cycle(int step) {
    if (_current != null) return;
    final order = _live.where((kind) => kind != IslandKind.home).toList()
      ..sort((a, b) => b.index.compareTo(a.index));
    if (order.length < 2) return;
    final at = order.indexOf(primary!);
    _picked = order[(at + step) % order.length];
    _expanded = false;
  }

  void pick(IslandKind kind) {
    if (_current != null || !_live.contains(kind)) return;
    _picked = kind;
    _expanded = false;
  }

  void show(IslandKind kind, String id, Duration hold, DateTime now) {
    assert(kind.transient);
    final item = IslandItem(kind, id, now.add(hold));
    final current = _current;
    if (current == null || current.kind == kind) {
      if (current?.id != id) _expanded = false;
      _current = item;
      return;
    }
    _waiting.removeWhere((entry) => entry.item.kind == kind);
    if (kind.index > current.kind.index) {
      final left = current.until.difference(now);
      if (left > Duration.zero) _waiting.insert(0, (item: current, left: left));
      _current = item;
      _expanded = false;
    } else {
      _waiting.add((item: item, left: hold));
      _waiting.sort((a, b) => b.item.kind.index.compareTo(a.item.kind.index));
    }
  }

  /// Ends the transient of [kind], wherever it is.
  void end(IslandKind kind, DateTime now, {String? id}) {
    bool matches(IslandItem item) =>
        item.kind == kind && (id == null || item.id == id);
    _waiting.removeWhere((entry) => matches(entry.item));
    final current = _current;
    if (current != null && matches(current)) _advance(now);
  }

  void tick(DateTime now) {
    final current = _current;
    if (current != null && !now.isBefore(current.until)) {
      // An open card is being read; it stays until it is closed.
      if (_expanded) return;
      _advance(now);
    }
  }

  void _advance(DateTime now) {
    _expanded = false;
    if (_waiting.isEmpty) {
      _current = null;
      return;
    }
    final next = _waiting.removeAt(0);
    _current = IslandItem(next.item.kind, next.item.id, now.add(next.left));
  }

  void expand() {
    if (kind?.expandable ?? false) _expanded = true;
  }

  void collapse(DateTime now) {
    if (!_expanded) return;
    _expanded = false;
    tick(now);
  }
}
