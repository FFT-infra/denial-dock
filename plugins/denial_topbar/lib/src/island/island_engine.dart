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

  /// Whether the kind has a card of its own. A level or a one-line status is
  /// complete as it is.
  bool get expandable => this != IslandKind.hud && this != IslandKind.status;

  /// Whether an item that arrives while a panel is pinned open is kept for
  /// when the panel closes. Everything else is about a moment that has passed
  /// by then, and is dropped.
  bool get waitsForPanel => this == IslandKind.notice;
}

class IslandItem {
  const IslandItem(this.kind, this.id, this.until);

  final IslandKind kind;

  /// Distinguishes two items of one kind, e.g. two notifications.
  final String id;
  final DateTime until;
}

/// What a light tap on the compact island does.
enum IslandTap {
  /// Opens the panel.
  open,

  /// Sends away an item that has no card: a level, a status line.
  dismiss,
}

/// The engine's time limits, apart from each item's own hold.
class IslandRules {
  const IslandRules({
    this.minResume = const Duration(milliseconds: 700),
    this.maxWait = const Duration(seconds: 8),
    this.afterHold = const Duration(milliseconds: 1200),
  });

  /// An interrupted item with less than this left does not come back: it
  /// would only flash.
  final Duration minResume;

  /// An item that has waited longer than this for its turn is stale.
  final Duration maxWait;

  /// What an item keeps, at least, once the pointer that held it leaves.
  final Duration afterHold;
}

typedef _Waiting = ({
  IslandKind kind,
  String id,
  Duration left,
  DateTime since,
  bool shown,
});

/// Decides what the island shows. Plain Dart, driven by the caller's clock.
///
/// **Layers.** Home is always underneath. Live activities sit on it; the
/// strongest one, or the one the user picked, has the pill, and the next one
/// rides beside it. A transient item takes the pill for its hold and hands it
/// back to whatever was there.
///
/// **Pre-emption.** A stronger transient interrupts a weaker one, which waits
/// and returns with the time it had left, unless that is under
/// [IslandRules.minResume]. A weaker one arriving during a stronger one waits
/// its turn with its full hold. One item per kind waits; a newer one of the
/// same kind replaces it. An item that has waited past [IslandRules.maxWait]
/// is dropped.
///
/// **Hold.** While the pointer rests on the island ([hold]) the current item
/// does not run out; [release] gives it what it had left, and at least
/// [IslandRules.afterHold].
///
/// **Panel.** [expand] opens the card of what the pill shows, or the home
/// card. A preview (not pinned) gives way to any new item. A pinned panel is
/// in use: it stays, an item that [IslandKind.waitsForPanel] is kept for
/// later, and anything else is dropped. A live activity that ends under a
/// pinned panel leaves the panel on the next activity, or on its home page; a
/// transient item that ends takes its card with it. An open card never runs
/// out by itself.
class IslandEngine {
  IslandEngine({this.rules = const IslandRules()});

  final IslandRules rules;

  final Set<IslandKind> _live = <IslandKind>{};
  IslandKind? _picked;
  IslandItem? _current;
  final List<_Waiting> _waiting = <_Waiting>[];
  IslandKind? _card;
  bool _pinned = false;
  bool _holding = false;
  Duration _frozen = Duration.zero;
  int _arrivals = 0;

  /// Whether the resting island has a card of its own. Without one the pill
  /// opens only while an activity has it.
  bool homeCard = true;

  /// Counts the items that have taken the pill as news: a new item, not one
  /// coming back after an interruption. The view plays its arrival on a
  /// change.
  int get arrivals => _arrivals;

  IslandItem? get transient => _current;

  /// How many items wait their turn.
  int get waiting => _waiting.length;

  List<IslandKind> get _ranked =>
      _live.toList()..sort((a, b) => b.index.compareTo(a.index));

  /// Live activities, strongest first, with the picked one in front.
  List<IslandKind> get live {
    final sorted = _ranked;
    final picked = _picked;
    if (picked != null && sorted.remove(picked)) sorted.insert(0, picked);
    return sorted;
  }

  /// The live activity that has the pill when no transient does.
  IslandKind get primary => live.firstOrNull ?? IslandKind.home;

  /// What the compact pill shows.
  IslandKind get kind => _current?.kind ?? primary;

  /// The open card, or null while the island is compact.
  IslandKind? get card => _card;

  bool get expanded => _card != null;

  /// Whether the open panel was asked for, rather than previewed.
  bool get pinned => _card != null && _pinned;

  bool get holding => _holding;

  /// The card [expand] would open now.
  IslandKind get opens {
    final current = _current;
    return current != null && current.kind.expandable ? current.kind : primary;
  }

  /// The cards an open panel can turn between: the live activities in a
  /// steady order, then home. A transient's card stands alone.
  List<IslandKind> get pages {
    final card = _card;
    if (card != null && card.transient) return <IslandKind>[card];
    return <IslandKind>[..._ranked, if (homeCard) IslandKind.home];
  }

  /// Whether [expand] has a card to open.
  bool get canExpand => opens != IslandKind.home || homeCard;

  /// The live activity shown as a bubble beside the pill.
  IslandKind? get secondary {
    if (_current != null || _card != null) return null;
    final all = live;
    return all.length > 1 ? all[1] : null;
  }

  IslandTap get tap {
    final current = _current;
    return current != null && !current.kind.expandable
        ? IslandTap.dismiss
        : IslandTap.open;
  }

  /// When the engine next needs [tick], or null.
  DateTime? get nextDeadline =>
      _holding || _card != null ? null : _current?.until;

  void setMedia(bool playing) => setLive(IslandKind.media, playing);

  void setLive(IslandKind kind, bool on) {
    assert(!kind.transient && kind != IslandKind.home);
    if (!(on ? _live.add(kind) : _live.remove(kind))) return;
    if (on) return;
    if (_picked == kind) _picked = null;
    if (_card != kind) return;
    final next = primary;
    _card = _pinned && (next != IslandKind.home || homeCard) ? next : null;
  }

  /// Hands the pill to the next live activity, or the previous one; in an
  /// open panel, turns the page. Returns whether anything moved.
  bool cycle(int step) {
    final card = _card;
    if (card != null) {
      final all = pages;
      if (all.length < 2) return false;
      _turn(all[(all.indexOf(card) + step) % all.length]);
      return true;
    }
    if (_current != null) return false;
    final order = _ranked;
    if (order.length < 2) return false;
    _picked = order[(order.indexOf(primary) + step) % order.length];
    return true;
  }

  /// Gives the pill to a live activity.
  void pick(IslandKind kind) {
    if (_current != null || _card != null || !_live.contains(kind)) return;
    _picked = kind;
  }

  /// Turns an open panel to [kind], one of its [pages].
  void showPage(IslandKind kind) {
    if (_card == null || _card == kind || !pages.contains(kind)) return;
    _turn(kind);
  }

  void _turn(IslandKind page) {
    _card = page;
    // The activity last looked at keeps the pill once the panel closes.
    if (page != IslandKind.home) _picked = page;
  }

  /// Offers an item to the island. Returns whether it was taken or queued.
  bool show(IslandKind kind, String id, Duration hold, DateTime now) {
    assert(kind.transient);
    if (_card != null) {
      if (_current?.kind == kind) {
        // The open card is this kind's: it takes the new content.
        _setCurrent(kind, id, hold, now);
        return true;
      }
      if (_pinned) {
        if (!kind.waitsForPanel) return false;
        _queue(kind, id, hold, now, shown: false);
        return true;
      }
      _card = null;
    }
    final current = _current;
    if (current == null) {
      _setCurrent(kind, id, hold, now);
      _arrivals++;
      return true;
    }
    if (current.kind == kind) {
      if (current.id != id) _arrivals++;
      _setCurrent(kind, id, hold, now);
      return true;
    }
    if (kind.index < current.kind.index) {
      _queue(kind, id, hold, now, shown: false);
      return true;
    }
    final left = _left(current, now);
    _waiting.removeWhere((entry) => entry.kind == kind);
    if (left >= rules.minResume) {
      _queue(current.kind, current.id, left, now, shown: true);
    }
    _setCurrent(kind, id, hold, now);
    _arrivals++;
    return true;
  }

  /// Ends the transient of [kind], wherever it is.
  void end(IslandKind kind, DateTime now, {String? id}) {
    _waiting.removeWhere(
      (entry) => entry.kind == kind && (id == null || entry.id == id),
    );
    final current = _current;
    if (current == null || current.kind != kind) return;
    if (id != null && current.id != id) return;
    if (_card == kind) {
      _card = null;
      _pinned = false;
    }
    _advance(now);
  }

  /// Sends away what the pill shows, if it is a transient.
  void dismiss(DateTime now) {
    final current = _current;
    if (current != null) end(current.kind, now, id: current.id);
  }

  void tick(DateTime now) {
    final current = _current;
    if (current == null || _holding || _card != null) return;
    if (!now.isBefore(current.until)) _advance(now);
  }

  /// Stops the current item's clock while the pointer rests on the island.
  void hold(DateTime now) {
    if (_holding) return;
    final current = _current;
    _frozen = current == null ? Duration.zero : _left(current, now);
    _holding = true;
  }

  void release(DateTime now) {
    if (!_holding) return;
    _holding = false;
    final current = _current;
    if (current == null) return;
    final left = _frozen > rules.afterHold ? _frozen : rules.afterHold;
    _current = IslandItem(current.kind, current.id, now.add(left));
  }

  /// Opens the card of what the pill shows. An item with no card of its own
  /// gives way to the card underneath it.
  void expand({bool pinned = true}) {
    if (_card != null) {
      _pinned = _pinned || pinned;
      return;
    }
    if (!canExpand) return;
    _card = opens;
    _pinned = pinned;
    if (_current?.kind != _card) _current = null;
  }

  /// Makes a previewed panel one the user asked for.
  void pin() {
    if (_card != null) _pinned = true;
  }

  void collapse(DateTime now) {
    if (_card == null) return;
    _card = null;
    _pinned = false;
    final current = _current;
    if (current == null) {
      _advance(now);
    } else if (!_holding && !now.isBefore(current.until)) {
      _advance(now);
    }
  }

  Duration _left(IslandItem item, DateTime now) {
    if (_holding) return _frozen;
    final left = item.until.difference(now);
    return left.isNegative ? Duration.zero : left;
  }

  void _setCurrent(IslandKind kind, String id, Duration left, DateTime now) {
    _current = IslandItem(kind, id, now.add(left));
    if (_holding) _frozen = left;
  }

  void _queue(
    IslandKind kind,
    String id,
    Duration left,
    DateTime now, {
    required bool shown,
  }) {
    _waiting
      ..removeWhere((entry) => entry.kind == kind)
      ..add((kind: kind, id: id, left: left, since: now, shown: shown))
      ..sort((a, b) => b.kind.index.compareTo(a.kind.index));
  }

  void _advance(DateTime now) {
    _current = null;
    while (_waiting.isNotEmpty) {
      final next = _waiting.removeAt(0);
      if (now.difference(next.since) > rules.maxWait) continue;
      _setCurrent(next.kind, next.id, next.left, now);
      if (!next.shown) _arrivals++;
      return;
    }
  }
}

/// Tells a level the user changed from one a source merely reported.
///
/// Sources publish a placeholder while they start, start over when the
/// display layout changes (a workspace switch does that), and report their
/// first real value as a change. None of those is news. A level counts only
/// when it differs from the last one the gate trusted, the source is not
/// loading, and neither a start nor a reload happened within the quiet time
/// before it.
class IslandLevelGate {
  IslandLevelGate({
    required DateTime born,
    Duration startup = const Duration(seconds: 4),
    this.quiet = const Duration(milliseconds: 1500),
    this.step = 0.004,
  }) : _quietUntil = born.add(startup);

  /// How long after a reload a level is still the source settling.
  final Duration quiet;

  /// The smallest difference that counts as a change.
  final double step;

  double? _level;
  bool _trusted = false;
  DateTime _quietUntil;

  void _settling(DateTime now) {
    final until = now.add(quiet);
    if (until.isAfter(_quietUntil)) _quietUntil = until;
  }

  /// Takes the source's level now and returns whether to announce it.
  /// [from] is the level the source had before, for a gate that has not
  /// seen one yet.
  bool feed(double? level, DateTime now, {double? from, bool loading = false}) {
    if (level == null) {
      // The source lost its output; whatever comes next starts afresh.
      _level = null;
      _trusted = false;
      _settling(now);
      return false;
    }
    if (loading) {
      _settling(now);
      return false;
    }
    if (now.isBefore(_quietUntil)) {
      // A level the gate already trusts outlives a reload: the source's
      // placeholder must not replace it, or the real value coming back
      // afterwards would look like a change.
      if (!_trusted) _level = level;
      return false;
    }
    final last = _level ?? from;
    _level = level;
    _trusted = true;
    return last != null && (last - level).abs() >= step;
  }
}

/// Whether the compact island steps out of the pointer's way: it fades and
/// stops taking input, so what it covers can be seen and clicked.
///
/// Only where the user asked for it ([fade]) and the pointer has rested on
/// the island for a moment ([dwelt]). An open panel, an item that has just
/// arrived, and a press in progress all keep it in view.
bool islandYields({
  required bool fade,
  required bool dwelt,
  required bool expanded,
  required bool arriving,
  required bool pressed,
}) => fade && dwelt && !expanded && !arriving && !pressed;
