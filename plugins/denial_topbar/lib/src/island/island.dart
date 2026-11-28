import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter, lerpDouble;

import 'package:denial_flutter_sdk/input.dart';
import 'package:denial_flutter_sdk/models.dart';
import 'package:denial_flutter_sdk/services.dart';
import 'package:denial_flutter_sdk/settings.dart' show shellSettingsProvider;
import 'package:denial_flutter_sdk/state.dart';
import 'package:denial_flutter_sdk/system_services.dart'
    show systemActionsServiceProvider;
import 'package:denial_sdk/system.dart' show BatteryStatus;
import 'package:denial_shell_kit/continuous_corners.dart';
import 'package:denial_shell_kit/kit_control_math.dart';
import 'package:denial_shell_kit/kit_layer.dart'
    show kitOpenPanel, kitPressTargets;
import 'package:denial_shell_kit/kit_motion.dart';
import 'package:denial_shell_kit/kit_requests.dart';
import 'package:denial_shell_kit/kit_springs.dart';
import 'package:denial_shell_kit/kit_store.dart';
import 'package:denial_shell_kit/kit_style.dart';
import 'package:denial_shell_kit/launcher_entry_bus.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bar_icons.dart';
import '../bar_settings.dart';
import '../bar_tokens.dart';
import '../bar_type.dart';
import '../debug_remote.dart';
import '../l10n.dart';
import '../mic_watch.dart';
import '../night_light.dart';
import '../panels/mac_kit.dart';
import '../panels/popovers.dart' show outputDeviceIcon;
import 'island_cards.dart';
import 'island_engine.dart';
import 'island_lyric_source.dart';
import 'island_motion.dart';
import 'island_parts.dart';
import 'island_shape.dart';
import 'island_skin.dart';
import 'island_subline.dart';
import 'island_timer.dart';

/// How far below the bar the island may grow; the bar's surface reserves it.
const double islandReach = 240;

/// Customizable quick-action ids for the resting Island home card.
const List<String> defaultIslandHomeActions = <String>[
  'dnd',
  'cc',
  'nc',
  'search',
];

const List<(String, String)> islandHomeActionCatalog = <(String, String)>[
  ('dnd', 'Focus'),
  ('cc', 'Control Centre'),
  ('nc', 'Notifications'),
  ('search', 'Search'),
  ('screenshot', 'Screenshot'),
  ('recording', 'Screen Recording'),
  ('night', 'Night Light'),
  ('dark', 'Dark Mode'),
  ('lock', 'Lock Screen'),
];

List<String> _readIslandHomeActions() {
  final raw = kitStore.read()['islandHomeActions'];
  if (raw is List) {
    final valid = <String>{for (final item in islandHomeActionCatalog) item.$1};
    final parsed = <String>[
      for (final id in raw)
        if (id is String && valid.contains(id)) id,
    ];
    if (parsed.isNotEmpty) return parsed;
  }
  return defaultIslandHomeActions;
}

/// Persisted list of quick-action ids shown on [IslandHomeCard], hydrated once
/// at initialization so `build()` never performs I/O or mutates a notifier.
final ValueNotifier<List<String>> islandHomeActions =
    ValueNotifier<List<String>>(_readIslandHomeActions());

void ensureIslandHomeActionsLoaded() {
  // Touch the lazy global once so startup hydration is deterministic without
  // mutating ValueNotifier state during widget build.
  islandHomeActions.value;
}

void setIslandHomeActions(List<String> ids) {
  final next = ids.isEmpty ? defaultIslandHomeActions : List<String>.of(ids);
  islandHomeActions.value = next;
  kitStore.put('islandHomeActions', next);
}

abstract final class _I {
  static const double rest = 58;
  static const double media = 126;
  static const double hud = 188;
  static const double charging = 176;
  static const double timer = 104;
  static const double progress = 92;
  static const double gap = 6;
  static const double textMin = 150;
  static const double textMax = 280;
  static const double cover = 20;
  static const double bigCover = 60;
  static const double pad = 18;
  static const Duration hudHold = Duration(seconds: 2);
  static const Duration chargeHold = Duration(seconds: 3);
  static const Duration lowHold = Duration(seconds: 5);

  /// How far the pill leans towards a pointer at its edge.
  static const double leanX = 6.5;
  static const double leanY = 2.8;
  static const Duration trackHold = Duration(seconds: 3);
  static const Duration statusHold = Duration(milliseconds: 2600);
  static const Duration settle = Duration(seconds: 6);

  /// How many reporting applications the progress card lists.
  static const int progressRows = 3;
}

/// Which spring the outline is on.
enum _Shaping { reshape, grow, shrink }

/// The island. It lives in the bar and grows in place: the same black shape
/// is the resting pill, the compact activity, and the open panel.
///
/// The outline (width, height, corner) runs on one set of springs that keep
/// their velocity when the target changes; what is inside crosses over on a
/// spring of its own, so the shape leads and the content follows.
class Island extends ConsumerStatefulWidget {
  const Island({
    required this.services,
    required this.monitorId,
    required this.settings,
    required this.height,
    required this.reserved,
    this.workspace,
    this.workspaceWidth = 0,
    this.timeLabel = '',
    this.dateLabel = '',
    this.dateLabelFor,
    this.onControlCenter,
    this.onNotifications,
    this.subline,
    this.notch = false,
    super.key,
  });

  final ShellServices services;
  final int monitorId;
  final BarSettings settings;
  final double height;

  /// Receives the width the bar should keep clear for the compact pill.
  final ValueNotifier<double> reserved;
  final Widget? workspace;
  final double workspaceWidth;

  /// What the home card shows and opens. When [timeLabel] is empty, the home
  /// card watches [services.clock] directly so clock ticks never rebuild the
  /// entire top bar.
  final String timeLabel;
  final String dateLabel;
  final String Function(BuildContext context, DateTime now)? dateLabelFor;
  final VoidCallback? onControlCenter;
  final VoidCallback? onNotifications;

  /// A second line for the playback card. Left null, the card shows the
  /// lyrics found on this machine for the track; see [IslandLyricSource].
  final IslandSubline? subline;
  final bool notch;

  @override
  ConsumerState<Island> createState() => _IslandState();
}

class _IslandState extends ConsumerState<Island> with TickerProviderStateMixin {
  final IslandEngine _engine = IslandEngine();
  final IslandLyricSource _lyrics = IslandLyricSource();
  final DateTime _born = DateTime.now();
  late final IslandLevelGate _volumeGate = IslandLevelGate(born: _born);
  late final IslandLevelGate _brightnessGate = IslandLevelGate(born: _born);
  final GlobalKey _bodyKey = GlobalKey();
  final FocusNode _focus = FocusNode(debugLabel: 'island');

  Timer? _deadline;
  Timer? _intent;
  Timer? _leave;
  Timer? _progress;
  Timer? _clock;
  Timer? _dwell;
  Timer? _long;
  StreamSubscription<Object?>? _outside;
  StreamSubscription<Offset>? _cursor;

  /// The card the outline is drawn for: the open one, the one being pulled
  /// open, or the one still closing.
  IslandKind _card = IslandKind.home;
  IslandKind _bubble = IslandKind.media;
  IslandKind _bubbleLeft = IslandKind.media;
  IslandSkin _skin = IslandSkin.plain;

  // What the cards whose size follows their content hold now.
  int _progressCount = 1;
  bool _noticeAnswers = false;

  /// The size the outline opens to for [kind]'s card.
  Size _cardSize(IslandKind kind) => switch (kind) {
    IslandKind.notice => Size(
      400,
      _noticeAnswers ? IslandNoticeCard.answered : IslandNoticeCard.plain,
    ),
    IslandKind.charging => const Size(360, 112),
    IslandKind.timer => const Size(400, 128),
    IslandKind.recording => const Size(380, 128),
    IslandKind.progress => Size(
      400,
      32 +
          IslandProgressCard.row *
              _progressCount.clamp(1, _I.progressRows) +
          (_progressCount > 1 ? 0 : 14),
    ),
    IslandKind.home => const Size(420, 188),
    _ => const Size(420, 190),
  };
  IconData _hudIcon = BarIcons.volumeUp;
  double _hudLevel = 0;
  int _hudTurn = 1;
  int _hudStep = 0;
  IconData _statusIcon = BarIcons.bellFill;
  Color? _statusTint;
  String _statusLabel = '';
  String _statusDetail = '';
  DateTime? _recordingSince;
  DateTime? _timerSeen;
  DateTime? _wentBack;
  DateTime _openedAt = DateTime.fromMillisecondsSinceEpoch(0);

  bool _hovered = false;
  bool _pressed = false;

  /// The press was held long enough to open the panel; its release is not a
  /// tap.
  bool _held = false;

  /// The pointer has rested on the island long enough to fade it.
  bool _dwelt = false;

  /// Something arrived while the pointer was on the island; it shows in
  /// full until the pointer has left.
  bool _news = false;
  int _arrivals = 0;

  // Which way content last moved, for the swap that follows.
  int _pageTurn = 0;
  String _faceKey = '';
  IslandKind? _faceKind;
  Offset _faceFrom = Offset.zero;
  IslandKind? _cardShown;
  Offset _cardFrom = Offset.zero;

  // ── Motion ───────────────────────────────────────────────────────────────

  late final KitSpring _w = KitSpring(_I.rest, IslandFeel.liquid.reshape);
  late final KitSpring _h = KitSpring(0, IslandFeel.liquid.reshape);
  late final KitSpring _r = KitSpring(0, IslandFeel.liquid.reshape);

  /// 0 shows the pill's face, 1 the card's content.
  late final KitSpring _content = KitSpring(0, IslandFeel.liquid.content);

  /// A closing outline waits here for its card to leave; see [_release].
  bool _waiting = false;
  Size _aim = const Size(_I.rest, 0);
  double _aimRadius = 0;
  late final KitSprings _shape = KitSprings(this, <KitSpring>[
    _w,
    _h,
    _r,
    _content,
  ], tolerance: 0.01);
  _Shaping _shaping = _Shaping.reshape;
  bool _shaped = false;
  bool _wasOpen = false;
  bool _cardBuilt = false;
  double _compact = _I.rest;

  // How the pill answers the pointer and the engine: it swells under a
  // pointer, gives under a press, draws a breath when something arrives,
  // lets its bubble go, and, where the user asks, fades out of the way.
  late final KitSpring _hoverFeel = KitSpring(0, IslandFeel.liquid.hover);
  late final KitSpring _pressFeel = KitSpring(0, IslandFeel.liquid.press);
  late final KitSpring _veil = KitSpring(0, IslandFeel.liquid.veil);

  /// Where over the pill the pointer is, from -1 to 1 each way, and the
  /// lean towards it that follows. The pill is drawn a little towards the
  /// pointer, as something held by its middle would be.
  Offset _pull = Offset.zero;
  late final KitSpring _pullX = KitSpring(0, IslandFeel.liquid.hover);
  late final KitSpring _pullY = KitSpring(0, IslandFeel.liquid.hover);

  /// The bubble on the pill's right, and the one on its left.
  late final KitSpring _split = KitSpring(0, IslandFeel.liquid.split);
  late final KitSpring _splitLeft = KitSpring(0, IslandFeel.liquid.split);
  late final KitSpring _pop = KitSpring(0, IslandFeel.liquid.pop);

  /// Directional elastic bump when a HUD hits 0% (-1) or 100% (+1).
  late final KitSpring _hudEdge = KitSpring(0, IslandFeel.liquid.pop);

  /// A press being held: the pill gathers itself towards the panel it is
  /// about to open, and is there as the press has lasted long enough.
  late final KitSpring _charge = KitSpring(0, IslandFeel.liquid.press);
  late final KitSprings _feel = KitSprings(this, <KitSpring>[
    _hoverFeel,
    _pressFeel,
    _pullX,
    _pullY,
    _veil,
    _split,
    _splitLeft,
    _pop,
    _hudEdge,
    _charge,
  ]);

  void _kick(KitSprings group) {
    final moving = group.springs.any(
      (spring) => spring.value != spring.target || spring.velocity != 0,
    );
    if (moving) group.kick(reduceMotion: KitMotion.reduced(context));
  }

  KitSpringTuning _shapeTuning(IslandFeel feel) => switch (_shaping) {
    _Shaping.grow => feel.grow,
    _Shaping.shrink => feel.shrink,
    _Shaping.reshape => feel.reshape,
  };

  /// Points the outline at what the engine shows now. Called from build: a
  /// target that moves while the springs are under way bends the motion.
  double _cardRadius(IslandKind kind, Size size) => _skin.corner(
    kind == IslandKind.media || kind == IslandKind.track ? 38 : 32,
    size.shortestSide,
  );

  void _aimShape(double compact, IslandFeel feel) {
    final h = widget.height;
    _compact = compact;
    final open = _engine.card;
    final size = open == null ? Size(compact, h) : _cardSize(open);
    final radius = open == null
        ? _skin.pill(h)
        : _cardRadius(open, size);
    if ((open != null) != _wasOpen) {
      _wasOpen = open != null;
      _shaping = _wasOpen ? _Shaping.grow : _Shaping.shrink;
    } else if (open == null && size.width != _w.target) {
      _shaping = _Shaping.reshape;
    }
    // Width, height and corner share one tuning and start together, so the
    // outline is one move and never widens before it deepens.
    final tuning = _shapeTuning(feel);
    for (final spring in <KitSpring>[_w, _h, _r]) {
      spring.tune(tuning);
    }
    _content.tune(open == null ? feel.contentOut : feel.content);
    _aim = size;
    _aimRadius = radius;
    // A hand on the island has the outline.
    if (_dragFrom != null) return;
    _content.target = open == null ? 0 : 1;
    // The card leaves first. A closing outline keeps its size until most of
    // the card has gone; with no travel to wait for it goes at once.
    _waiting =
        open == null &&
        _shaped &&
        islandHoldsOutline(_content.value) &&
        !KitMotion.reduced(context);
    if (!_waiting) _release();
    if (!_shaped) {
      _shaped = true;
      for (final spring in _shape.springs) {
        spring.settle();
      }
      return;
    }
    _kick(_shape);
  }

  /// Lets the outline go to where it was last aimed.
  void _release() {
    _waiting = false;
    _w.target = _aim.width;
    _h.target = _aim.height;
    _r.target = _aimRadius;
  }

  bool get _yields => islandYields(
    fade: widget.settings.islandHoverFade,
    dwelt: _dwelt,
    expanded: _engine.expanded,
    arriving: _news,
    pressed: _pressed,
  );

  /// Points the smaller springs at what the pointer and the engine do now.
  void _aimFeel(IslandFeel feel, {required int bubbles}) {
    final fade = widget.settings.islandHoverFade;
    _hoverFeel
      ..tune(feel.hover)
      ..target = _hovered && !fade && !_engine.expanded ? 1 : 0;
    _pressFeel
      ..tune(feel.press)
      ..target = _pressed ? 1 : 0;
    _pullX.tune(feel.hover);
    _pullY.tune(feel.hover);
    _aimPull();
    // Held, the pill gathers over exactly the time the press has to last;
    // let go, it springs back as any press does.
    final charging = _pressed && _engine.canExpand && !_engine.expanded;
    _charge
      ..tune(
        charging
            ? KitSpringTuning(
                islandChargeStiffness(
                  widget.settings.islandLongPress.inMilliseconds / 1000,
                  KitMotion.speed,
                ),
                1,
              )
            : feel.press,
      )
      ..target = charging ? 1 : 0;
    _veil
      ..tune(feel.veil)
      ..target = _yields ? 1 : 0;
    _split
      ..tune(bubbles > 0 ? feel.split : feel.merge)
      ..target = bubbles > 0 ? 1 : 0;
    _splitLeft
      ..tune(bubbles > 1 ? feel.split : feel.merge)
      ..target = bubbles > 1 ? 1 : 0;
    _pop.tune(feel.pop);
    _hudEdge.tune(feel.pop);
    if (_engine.arrivals != _arrivals) {
      _arrivals = _engine.arrivals;
      // The breath: the pill draws in, then springs out past its size.
      _pop.velocity -= feel.gulp;
      // News shows in full, whatever the pointer has been doing.
      if (_hovered) _news = true;
      _veil.target = 0;
    }
    _kick(_feel);
  }

  /// Points the lean at where the pointer is. Called as the pointer moves,
  /// so it touches the two springs and nothing else.
  void _aimPull() {
    final leans =
        _hovered && !widget.settings.islandHoverFade && !_engine.expanded;
    _pullX.target = leans ? _pull.dx : 0;
    _pullY.target = leans ? _pull.dy : 0;
  }

  double? _dragFrom;
  double _dragged = 0;
  double _swiped = 0;

  ShellServices get _services => widget.services;
  DateTime get _now => DateTime.now();

  void _onNightLight() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    kitOpenPanel.addListener(_onPanel);
    islandHomeActions.addListener(_onHomeActions);
    NightLight.enabled.addListener(_onNightLight);
    _timerSeen = islandTimer.finishedAt;
    islandTimer.addListener(_onTimer);
    micWatch.addListener(_onMic);
    debugCommand.addListener(_debug);
    // The closing card's content is dropped once the outline is home.
    // It can come to rest inside a build (reduced motion settles at once),
    // so the redraw waits its turn.
    _shape.before = (_) {
      if (_waiting && !islandHoldsOutline(_content.value)) _release();
    };
    _shape.onRest = () {
      if (!_cardBuilt || _engine.expanded || _dragFrom != null) return;
      scheduleMicrotask(() {
        if (mounted && !_engine.expanded) setState(() {});
      });
    };
    GestureBinding.instance.pointerRouter.addGlobalRoute(_anyPointer);
    kitPressTargets.add(_pressTarget);
    _outside = ref
        .read(denialBridgeProvider)
        .shellActions
        .where((event) => event.action.name == 'clientPointerPressed')
        .listen((_) => _pressedOutside());
  }

  @override
  void dispose() {
    _lyrics.dispose();
    kitOpenPanel.removeListener(_onPanel);
    islandHomeActions.removeListener(_onHomeActions);
    NightLight.enabled.removeListener(_onNightLight);
    islandTimer.removeListener(_onTimer);
    micWatch.removeListener(_onMic);
    debugCommand.removeListener(_debug);
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_anyPointer);
    kitPressTargets.remove(_pressTarget);
    _clock?.cancel();
    _outside?.cancel();
    _cursor?.cancel();
    _absorbRelease?.cancel();
    for (final timer in <Timer?>[
      _deadline,
      _intent,
      _leave,
      _progress,
      _dwell,
      _long,
    ]) {
      timer?.cancel();
    }
    _focus.dispose();
    _shape.dispose();
    _feel.dispose();
    super.dispose();
  }

  void _onPanel() {
    if (kitOpenPanel.value != null) _setOpen(false);
  }

  void _onHomeActions() {
    if (mounted) setState(() {});
  }

  void _debug() {
    final words = debugWords();
    if (words.isEmpty || !mounted) return;
    final number = words.length > 1 ? int.tryParse(words[1]) ?? 0 : 0;
    switch (words.first) {
      case 'island':
        _setOpen(words.length < 2 || words[1] != 'close');
      case 'timer':
        number > 0
            ? islandTimer.start(Duration(seconds: number), _now)
            : islandTimer.cancel();
      case 'cycle':
        _turn(1);
      case 'hud':
        if (words.length >= 2) {
          final kind = words[1];
          final pct = words.length >= 3
              ? (double.tryParse(words[2]) ?? 50).clamp(0.0, 100.0) / 100.0
              : 0.0;
          if (kind == 'brightness') {
            _hud(BarIcons.sunMaxFill, pct);
          } else if (kind == 'mute') {
            _hud(BarIcons.speakerSlashFill, 0.0);
          } else {
            _hud(
              pct <= 0.001
                  ? BarIcons.speakerSlashFill
                  : (pct < 0.5 ? BarIcons.speaker1Fill : BarIcons.speaker3Fill),
              pct,
            );
          }
        }
    }
  }

  bool _micWas = false;

  void _onMic() {
    if (!mounted) return;
    final users = micWatch.value;
    final using = users.isNotEmpty;
    if (using != _micWas && widget.settings.activityStatus) {
      _status(
        BarIcons.circleFill,
        using ? users.first : context.tr('Microphone'),
        detail: context.tr(using ? 'Microphone in use' : 'Off'),
        tint: using ? macOrange : _skin.dim,
      );
    }
    _micWas = using;
  }

  void _onTimer() {
    if (!mounted) return;
    final done = islandTimer.finishedAt;
    if (done != null && done != _timerSeen) {
      _timerSeen = done;
      if (widget.settings.activityTimer) {
        _status(
          BarIcons.timer,
          context.tr('Timer'),
          detail: context.tr('Done'),
          tint: macOrange,
          hold: _I.settle,
        );
      }
    }
    setState(() {});
  }

  /// Brings the timers in line with the engine and draws again; the build
  /// points the springs.
  void _sync() {
    _deadline?.cancel();
    final next = _engine.nextDeadline;
    if (next != null) {
      final wait = next.difference(_now);
      _deadline = Timer(wait.isNegative ? Duration.zero : wait, () {
        _engine.tick(_now);
        _sync();
      });
    }
    final open = _engine.expanded;
    final needsProgress = open && _engine.card == IslandKind.media;
    if (needsProgress != (_progress != null)) {
      _progress?.cancel();
      _progress = needsProgress
          ? Timer.periodic(const Duration(seconds: 1), (_) {
              if (mounted) setState(() {});
            })
          : null;
    }
    if (!open && _focus.hasFocus) _focus.unfocus();
    if (mounted) setState(() {});
  }

  /// Opens the panel, or closes it. [pinned] is a panel the user asked for:
  /// it stays until it is dismissed. A preview closes when the pointer goes.
  ///
  /// A pinned panel closes the way the shell's other panels do: a press
  /// outside it, Escape, or a press on the pill's own place. Nothing closes
  /// it for the pointer having left or for time having passed.
  void _setOpen(bool open, {bool pinned = true}) {
    _intent?.cancel();
    _leave?.cancel();
    if (open) {
      if (kitOpenPanel.value != null || !_engine.canExpand) return;
      if (!_engine.expanded) _openedAt = _now;
      _pull = Offset.zero;
      _engine.expand(pinned: pinned);
      if (pinned) _takeKeys();
      // An open panel is not faded, and the wait to fade starts over when
      // it closes.
      _dwell?.cancel();
      _dwelt = false;
    } else {
      if (!_engine.expanded) return;
      _engine.collapse(_now);
      if (_hovered) _armDwell();
    }
    _sync();
  }

  /// Starts the wait after which a resting pointer fades the pill.
  void _armDwell() {
    _dwell?.cancel();
    final settings = widget.settings;
    if (!settings.islandHoverFade) return;
    _dwell = Timer(settings.islandFadeDwell, () {
      if (!mounted || !_hovered || _engine.expanded) return;
      _dwelt = true;
      // Once the island gives up its input region the pointer belongs to
      // whatever is underneath, and only the compositor knows where it is.
      _cursor ??= ref.read(denialBridgeProvider).cursorPositions.listen((at) {
        if (_hovered && !_within(at, slack: 4)) _left();
      });
      setState(() {});
    });
  }

  /// A press on the island while another panel of the shell is open: that
  /// panel closes and hands over, as one bar item does to the next.
  VoidCallback? _pressTarget(Offset position) =>
      mounted && !_yields && _engine.canExpand && _within(position)
      ? () => _setOpen(true)
      : null;

  /// A pinned panel takes the keyboard, for Escape and the arrow keys.
  void _takeKeys() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _engine.pinned) _focus.requestFocus();
    });
  }

  void _show(IslandKind kind, String id, Duration hold) {
    _engine.show(kind, id, hold, _now);
    _sync();
  }

  void _hud(IconData icon, double level) {
    if (kitOpenPanel.value != null) return;
    final next = level.clamp(0.0, 1.0);
    if (icon != _hudIcon ||
        next != _hudLevel ||
        next <= 0.001 ||
        next >= 0.999) {
      _hudStep++;
    }
    if (icon == _hudIcon && next != _hudLevel) {
      _hudTurn = next > _hudLevel ? 1 : -1;
    }
    _hudIcon = icon;
    _hudLevel = next;
    if (next <= 0.001) {
      // Elastic left-edge squash/bounce when volume/brightness hits 0% or mute.
      _hudEdge.velocity -= 18;
      _pullX.velocity -= 6;
      _w.velocity += 110;
      _kick(_shape);
      _kick(_feel);
    } else if (next >= 0.999) {
      // Elastic right-edge stretch/bounce when hitting 100%.
      _hudEdge.velocity += 18;
      _pullX.velocity += 6;
      _w.velocity += 110;
      _kick(_shape);
      _kick(_feel);
    }
    _show(IslandKind.hud, 'level', _I.hudHold);
  }

  /// Scroll wheel over the collapsed pill adjusts master volume, or display
  /// brightness while Shift is held. Yields to in-island workspace scrolling
  /// when the resting pill is displaying workspace dots.
  void _onScroll(PointerScrollEvent event) {
    if (_engine.expanded || _yields || !widget.settings.activityHud) return;
    final dy = event.scrollDelta.dy;
    if (dy.abs() < 0.1) return;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    if (!shift &&
        _engine.kind == IslandKind.home &&
        widget.workspace != null &&
        widget.settings.workspaceScroll) {
      return;
    }
    final step = dy < 0 ? 0.05 : -0.05;
    if (shift) {
      final layout = ref.read(displayLayoutProvider);
      final output = layout?.outputs
          .where((o) => o.monitorId == widget.monitorId)
          .firstOrNull;
      if (output == null) return;
      final cur =
          ref.read(displayBrightnessProvider).levels[widget.monitorId];
      if (cur == null) return;
      final next = (cur + step).clamp(0.05, 1.0);
      final notifier = ref.read(displayBrightnessProvider.notifier);
      notifier.setLevel(output, next);
      notifier.commitLevel(output, next);
      _hud(BarIcons.sunMaxFill, next);
    } else {
      if (!ref.read(_services.volumeAvailable)) return;
      final cur = ref.read(_services.volume);
      final next = (cur + step).clamp(0.0, 1.0);
      _services.beginVolumeInteraction();
      _services.setVolume(next);
      _services.commitVolume(next);
      _hud(
        next <= 0.001
            ? BarIcons.speakerSlashFill
            : (next < 0.5 ? BarIcons.speaker1Fill : BarIcons.speaker3Fill),
        next,
      );
    }
  }

  /// A one-line change of state: an icon, what changed, and how.
  void _status(
    IconData icon,
    String label, {
    String detail = '',
    Color? tint,
    Duration hold = _I.statusHold,
  }) {
    // Sources report their first state as a change while the shell starts.
    if (_now.difference(_born) < _I.settle) return;
    if (kitOpenPanel.value != null) return;
    _statusIcon = icon;
    _statusTint = tint;
    _statusLabel = label;
    _statusDetail = detail;
    _show(IslandKind.status, '$label $detail', hold);
  }

  /// Turns to the next activity or page, or the previous one.
  void _turn(int step) {
    if (step == 0 || !_engine.cycle(step)) return;
    _pageTurn = step;
    _sync();
  }

  void _listen() {
    final settings = widget.settings;
    ref.listen<BluetoothState>(bluetoothProvider, (previous, next) {
      if (!settings.activityStatus || previous == null) return;
      if (previous.initializing || !previous.available) return;
      final before = <String>{
        for (final device in previous.devices)
          if (device.connected) device.address,
      };
      for (final device in next.devices) {
        if (device.connected == before.contains(device.address)) continue;
        _status(
          BarIcons.bluetooth,
          device.name.isEmpty ? context.tr('Bluetooth') : device.name,
          detail: context.tr(device.connected ? 'Connected' : 'Disconnected'),
          tint: device.connected ? macBlue : _skin.dim,
        );
        break;
      }
    });
    ref.listen<String?>(_services.connectedWifi.select((wifi) => wifi?.ssid), (
      previous,
      next,
    ) {
      if (!settings.activityStatus) return;
      if (next != null) {
        _status(
          BarIcons.wifi,
          next,
          detail: context.tr('Connected'),
          tint: macBlue,
        );
      } else if (previous != null) {
        _status(
          BarIcons.wifiSlash,
          previous,
          detail: context.tr('Disconnected'),
          tint: _skin.dim,
        );
      }
    });
    ref.listen<bool>(
      desktopNotificationsProvider.select((state) => state.doNotDisturb),
      (previous, next) {
        if (!settings.activityStatus || previous == null) return;
        _status(
          next ? BarIcons.moonFill : BarIcons.moon,
          context.tr('Focus'),
          detail: context.tr(next ? 'On' : 'Off'),
          tint: next ? macPurple : _skin.dim,
        );
      },
    );
    ref.listen<bool>(
      screenRecordingProvider.select((state) => state.recording),
      (previous, next) {
        if (!settings.activityRecording || previous != true || next) return;
        _status(
          BarIcons.circleFill,
          context.tr('Screen Recording'),
          detail: context.tr('Stopped'),
          tint: macRed,
        );
      },
    );
    ref.listen<MprisPlaybackState?>(
      _services.media.select((value) => value.value),
      (previous, next) {
        final playing = settings.activityMedia && (next?.playing ?? false);
        final title = next?.title ?? '';
        if (playing &&
            previous != null &&
            previous.title.isNotEmpty &&
            title.isNotEmpty &&
            previous.title != title) {
          _show(IslandKind.track, title, _I.trackHold);
        }
      },
    );
    ref.listen<DesktopNotification?>(
      desktopNotificationsProvider.select((state) => state.bannerNotification),
      (previous, next) {
        if (!settings.activityNotifications) return;
        if (next == null) {
          _engine.end(IslandKind.notice, _now);
          _sync();
        } else if (next.id != previous?.id) {
          _show(IslandKind.notice, '${next.id}', settings.islandNoticeHold);
        }
      },
    );
    // Both levels go through a gate, fed even while the HUD is off so it
    // always knows the last real level. A source's first value, and what it
    // reports while it starts over, is not a change the user made.
    // While no audio service has reported, the level is a placeholder 0;
    // the gate is told there is none, so the first real one is not news.
    ref.listen<bool>(_services.volumeAvailable, (previous, next) {
      if (!next) _volumeGate.feed(null, _now);
    });
    ref.listen<double>(_services.volume, (previous, next) {
      if (!ref.read(_services.volumeAvailable)) {
        _volumeGate.feed(null, _now);
        return;
      }
      final changed = _volumeGate.feed(next, _now, from: previous);
      if (!changed || !settings.activityHud) return;
      _hud(
        next <= 0.001
            ? BarIcons.speakerSlashFill
            : (next < 0.5 ? BarIcons.speaker1Fill : BarIcons.speaker3Fill),
        next,
      );
    });
    // The brightness provider starts over at a placeholder level whenever
    // the display layout changes, a workspace switch included, then reads
    // the backlight again, and the compositor may echo the level once more
    // after that, rounded differently. The gate keeps the level it trusted
    // before the reload and stays quiet until the source has settled.
    ref.listen<({double? level, bool loading})>(
      displayBrightnessProvider.select(
        (state) => (
          level: state.levels[widget.monitorId],
          loading: state.loading.contains(widget.monitorId),
        ),
      ),
      (previous, next) {
        final changed = _brightnessGate.feed(
          next.level,
          _now,
          from: previous == null || previous.loading ? null : previous.level,
          loading: next.loading,
        );
        final level = next.level;
        if (!changed || level == null || !settings.activityHud) return;
        _hud(BarIcons.sunMaxFill, level);
      },
    );
  }

  bool _isPlugged(WidgetRef ref) {
    final battery = ref.watch(_services.battery);
    final onBattery = ref.watch(
      upowerProvider.select((state) => state.snapshot?.onBattery),
    );
    return battery.charging || onBattery == false;
  }

  bool? _wasPlugged;
  int? _wasCharge;

  /// Whether the battery is low enough, and unplugged, to say so in red.
  static bool _low(bool plugged, int? charge) =>
      !plugged && charge != null && charge <= 20;

  /// The resting pill's width in the look in force.
  double get _rest =>
      _skin.rest(widget.height) * widget.settings.islandWidth / 100;

  double _measure(String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 1,
      textDirection: Directionality.of(context),
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  double _compactWidth(IslandKind kind, String label) => switch (kind) {
    IslandKind.home =>
      widget.workspace == null
          ? _rest
          : math.max(_rest, widget.workspaceWidth + 24),
    // An activity never makes the pill narrower than it rests: on a long
    // pill it shows at the two ends, as beside a camera housing.
    IslandKind.media => math.max(_rest, _I.media),
    IslandKind.hud => math.max(_rest, _I.hud),
    IslandKind.charging => math.max(_rest, _I.charging),
    IslandKind.timer || IslandKind.recording => math.max(
      _rest,
      _I.timer + (label.length > 5 ? 18 : 0),
    ),
    IslandKind.progress => math.max(_rest, _I.progress),
    IslandKind.status =>
      (_measure(label, BarType.islandLabel) +
              _measure(_statusDetail, BarType.islandLabel) +
              58)
          .clamp(_I.textMin, _I.textMax + 40),
    IslandKind.track || IslandKind.notice =>
      (_measure(label, BarType.islandLabel) + 74).clamp(_I.textMin, _I.textMax),
  };

  // ── Pointer ──────────────────────────────────────────────────────────────

  /// Whether a point on the screen is on the island's body.
  bool _within(Offset global, {double slack = 0}) {
    final box = _bodyKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return false;
    return MatrixUtils.transformRect(
      box.getTransformTo(null),
      Offset.zero & box.size,
    ).inflate(slack).contains(global);
  }

  void _enter(PointerEnterEvent event) {
    _leave?.cancel();
    // Coming back into a region the island had given up is not a new visit.
    if (_hovered) return;
    _hovered = true;
    _engine.hold(_now);
    final settings = widget.settings;
    if (!settings.islandHoverFade && !_engine.expanded) {
      // Suction bulge: pull the pill briefly toward the side the cursor entered.
      final w = math.max(widget.height, _w.value);
      final h = math.max(1.0, widget.height);
      final dx = (event.localPosition.dx / w * 2 - 1).clamp(-1.0, 1.0);
      final dy = (event.localPosition.dy / h * 2 - 1).clamp(-1.0, 1.0);
      _pull = Offset(dx, dy);
      if (settings.islandCursorAbsorb && KitStyle.of(context).liquid) {
        _pullX.velocity += dx * 12;
        _pullY.velocity += dy * 6;
        _pop.velocity += 0.95;
        _w.velocity += 55;
        _kick(_shape);
      }
      _aimPull();
      _kick(_feel);
    }
    if (settings.islandHoverFade) {
      if (!_engine.expanded) _armDwell();
    } else if (settings.islandHoverPeek &&
        !_engine.expanded &&
        _engine.tap == IslandTap.open &&
        _engine.opens != IslandKind.home) {
      _intent?.cancel();
      _intent = Timer(BarTokens.islandHoverIntent, () {
        if (mounted && _hovered) _setOpen(true, pinned: false);
      });
    }
    _sync();
  }

  Timer? _absorbRelease;

  void _exit(PointerExitEvent event) {
    // Faded, the island has handed its region to the window underneath, and
    // the compositor ends the shell's pointer there without the pointer
    // having moved. It has left only once it is somewhere else.
    if (_yields && _within(event.position)) return;
    // Cursor absorption: require a tiny extra bit of travel (~5 px) beyond
    // the pill edge before releasing the absorbed state — without mutating
    // hit-region Padding or shifting layout.
    final absorb =
        !_engine.expanded &&
        !_yields &&
        !widget.settings.islandHoverFade &&
        widget.settings.islandCursorAbsorb;
    if (absorb && _within(event.position, slack: 5.5)) {
      _cursor ??= ref.read(denialBridgeProvider).cursorPositions.listen((at) {
        if (_hovered && !_within(at, slack: 5.5)) _left();
      });
      _absorbRelease?.cancel();
      _absorbRelease = Timer(const Duration(milliseconds: 240), () {
        if (mounted && _hovered) _left();
      });
      return;
    }
    _left();
  }

  void _left() {
    _absorbRelease?.cancel();
    _absorbRelease = null;
    if (!_hovered) return;
    final lastPull = _pull;
    _hovered = false;
    _pull = Offset.zero;
    if (!widget.settings.islandHoverFade &&
        widget.settings.islandCursorAbsorb &&
        !_engine.expanded &&
        KitStyle.of(context).liquid) {
      // Elastic release rebound as the cursor emerges from the pill.
      _pullX.velocity -= lastPull.dx * 14;
      _pop.velocity -= 0.7;
      _aimPull();
      _kick(_feel);
    }
    _dwelt = false;
    _news = false;
    _dwell?.cancel();
    _intent?.cancel();
    _cursor?.cancel();
    _cursor = null;
    _engine.release(_now);
    if (_engine.expanded && !_engine.pinned) {
      _leave?.cancel();
      _leave = Timer(BarTokens.islandLeaveGrace, () {
        if (mounted && !_hovered) _setOpen(false);
      });
    }
    _sync();
  }

  /// Every press the shell sees. One outside an open panel closes it.
  void _anyPointer(PointerEvent event) {
    if (event is! PointerDownEvent || !_engine.expanded) return;
    if (_within(event.position)) return;
    _pressedOutside();
  }

  void _pressedOutside() {
    if (!_engine.expanded) return;
    if (_now.difference(_openedAt) < IslandDefaults.outsideGuard) return;
    _setOpen(false);
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (!_engine.pinned || event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      _setOpen(false);
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      _turn(-1);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _turn(1);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  void _pressDown() {
    _pressed = true;
    _held = false;
    _long?.cancel();
    _long = Timer(widget.settings.islandLongPress, () {
      if (!mounted || !_pressed) return;
      // The open panel takes no taps of its own, so the release that ends
      // this press would never be reported.
      _held = true;
      _pressed = false;
      _setOpen(true);
    });
    setState(() {});
  }

  void _pressUp() {
    _pressed = false;
    _long?.cancel();
    setState(() {});
  }

  /// A light tap does what the pill is for: it opens the panel, or sends
  /// away an item that has nothing more to show.
  void _tap() {
    if (_held) return;
    switch (_engine.tap) {
      case IslandTap.open:
        _setOpen(true);
      case IslandTap.dismiss:
        _engine.dismiss(_now);
        _sync();
    }
  }

  double get _travel => _cardSize(_card).height - widget.height;

  void _dragStart(DragStartDetails details) {
    _long?.cancel();
    _dragged = 0;
    if (!_engine.expanded && !_engine.canExpand) return;
    _waiting = false;
    _card = _engine.card ?? _engine.opens;
    _dragFrom = islandOpenShare(
      _h.value,
      widget.height,
      _cardSize(_card).height,
    );
    setState(() {});
  }

  void _dragUpdate(DragUpdateDetails details) {
    _dragged += details.primaryDelta ?? 0;
    final from = _dragFrom;
    if (from == null) return;
    final share = islandRubber(from + _dragged / _travel);
    final card = _cardSize(_card);
    final h = widget.height;
    void hold(KitSpring spring, double value) {
      spring
        ..value = value
        ..target = value
        ..velocity = 0;
    }

    hold(_w, lerpDouble(_compact, card.width, share)!);
    hold(_h, lerpDouble(h, card.height, share)!);
    hold(
      _r,
      lerpDouble(
        _skin.pill(h),
        _cardRadius(_card, card),
        share.clamp(0.0, 1.0),
      )!,
    );
    hold(_content, share.clamp(0.0, 1.0));
    // One tick draws the held values.
    _shape.kick(reduceMotion: KitMotion.reduced(context));
  }

  void _dragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final from = _dragFrom;
    _dragFrom = null;
    if (from == null) {
      // Nothing to pull open: a flick up sends a passing item away.
      if (velocity < -250 || _dragged < -14) {
        _engine.dismiss(_now);
        _sync();
      }
      return;
    }
    final share = islandOpenShare(
      _h.value,
      widget.height,
      _cardSize(_card).height,
    );
    final open = velocity.abs() > 250 ? velocity > 0 : share > 0.45;
    // The outline leaves the hand at the hand's speed.
    _h.velocity = velocity.clamp(-3000.0, 3000.0);
    if (open) {
      if (!_engine.expanded) _openedAt = _now;
      _engine.expand();
      _takeKeys();
      _dwell?.cancel();
      _dwelt = false;
    } else if (_engine.expanded) {
      _engine.collapse(_now);
    } else if (from <= 0 && (velocity < -250 || _dragged < -14)) {
      _engine.dismiss(_now);
    }
    _sync();
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    _listen();
    final plugged = _isPlugged(ref);
    if (_wasPlugged != null &&
        _wasPlugged != plugged &&
        widget.settings.activityCharging) {
      final now = plugged;
      scheduleMicrotask(() {
        if (mounted) _show(IslandKind.charging, '$now', _I.chargeHold);
      });
    }
    _wasPlugged = plugged;
    // On battery, falling to a fifth and then to a tenth says so once each.
    // While plugged in, reaching 100% notifies Battery Full once.
    final charge = ref.watch(_services.battery).capacity;
    final before = _wasCharge;
    _wasCharge = charge;
    if (charge != null && before != null && widget.settings.activityCharging) {
      if (!plugged) {
        for (final mark in const <int>[20, 10]) {
          if (before > mark && charge <= mark) {
            scheduleMicrotask(() {
              if (mounted) _show(IslandKind.charging, 'low$mark', _I.lowHold);
            });
            break;
          }
        }
      } else if (before < 100 && charge >= 100) {
        scheduleMicrotask(() {
          if (mounted) _show(IslandKind.charging, 'full', _I.chargeHold);
        });
      }
    }

    final settings = widget.settings;
    final style = KitStyle.of(context);
    final feel = IslandFeel.of(style);
    _skin = IslandSkin.of(context);
    final playback = ref.watch(_services.media).value;
    // Lyrics are looked for only while the playback card can show them.
    _lyrics.follow(
      settings.activityMedia && widget.subline == null ? playback : null,
    );
    final recording = ref.watch(
      screenRecordingProvider.select((state) => state.recording),
    );
    _recordingSince = recording ? (_recordingSince ?? _now) : null;
    final progress = _launcherProgress();
    if (progress.isNotEmpty) _progressCount = progress.length;
    // Paused playback keeps its place while its card is open: pausing from
    // the card must not take the card away.
    final playing = playback?.playing ?? false;
    final mediaOpen =
        _engine.card == IslandKind.media && (playback?.available ?? false);
    _engine
      ..homeCard = settings.islandHome
      ..setMedia(settings.activityMedia && (playing || mediaOpen))
      ..setLive(
        IslandKind.progress,
        settings.activityProgress && progress.isNotEmpty,
      )
      ..setLive(IslandKind.timer, settings.activityTimer && islandTimer.active)
      ..setLive(IslandKind.recording, settings.activityRecording && recording);
    final ticking = recording || (islandTimer.active && !islandTimer.paused);
    if (ticking != (_clock != null)) {
      _clock?.cancel();
      _clock = ticking
          ? Timer.periodic(const Duration(seconds: 1), (_) {
              if (mounted) setState(() {});
            })
          : null;
    }
    final note = ref.watch(
      desktopNotificationsProvider.select((state) => state.bannerNotification),
    );
    if (note != null) _noticeAnswers = _answers(note).isNotEmpty;
    final battery = ref.watch(_services.battery);
    final kind = _engine.kind;
    final h = widget.height;
    final label = switch (kind) {
      IslandKind.track => playback?.title ?? '',
      IslandKind.notice => (note?.summary ?? '').replaceAll('\n', ' '),
      IslandKind.status => _statusLabel,
      IslandKind.timer => clockSpan(islandTimer.remaining(_now)),
      IslandKind.recording => clockSpan(
        _now.difference(_recordingSince ?? _now),
      ),
      _ => '',
    };
    final compact = _compactWidth(kind, label);
    final beside = settings.islandSplit
        ? _engine.bubbles
        : const <IslandKind>[];
    if (beside.isNotEmpty) _bubble = beside.first;
    if (beside.length > 1) _bubbleLeft = beside[1];
    // Room is kept on both sides whenever a bubble stands on either, so the
    // pill stays in the middle.
    final reserve = compact + (beside.isEmpty ? 0 : (h + _I.gap) * 2);
    if (widget.reserved.value != reserve) {
      scheduleMicrotask(() => widget.reserved.value = reserve);
    }

    final open = _engine.card;
    if (open != null) _card = open;
    _aimShape(compact, feel);
    _aimFeel(feel, bubbles: beside.length);

    // Which way the new face and the new card come from: a turn of the page
    // moves sideways, a passing item rises over what it interrupts and sinks
    // away again, a new track follows the transport button that asked for it.
    final faceKey = switch (kind) {
      IslandKind.track => 'track/$label',
      _ => '${kind.name}/${_engine.transient?.id ?? ''}',
    };
    if (faceKey != _faceKey) {
      final before = _faceKind;
      _faceFrom = _pageTurn != 0
          ? Offset(_pageTurn.toDouble(), 0)
          : kind == IslandKind.track && before == IslandKind.track
          ? Offset(_trackTurn.toDouble(), 0)
          : Offset(0, before == null || kind.index >= before.index ? 1 : -1);
      _faceKey = faceKey;
      _faceKind = kind;
    }
    final pages = _engine.pages;
    if (_card != _cardShown) {
      final before = _cardShown;
      final step = _pageTurn != 0
          ? _pageTurn
          : before == null || !pages.contains(before) || !pages.contains(_card)
          ? 0
          : pages.indexOf(_card) > pages.indexOf(before)
          ? 1
          : -1;
      _cardFrom = Offset(step.toDouble(), 0);
      _cardShown = _card;
    }
    _pageTurn = 0;

    // The content is built here, once per change of state, and handed to the
    // frame below as it is: while the outline moves, only its clip, opacity
    // and transform change.
    final faceLayer = RepaintBoundary(
      child: IslandSwap(
        from: _faceFrom,
        child: KeyedSubtree(
          key: ValueKey<String>(faceKey),
          child: _face(kind, label, playback, note, battery),
        ),
      ),
    );
    final showCard =
        _engine.expanded || _dragFrom != null || _content.value > 0.001;
    _cardBuilt = showCard;
    final cardLayer = !showCard
        ? null
        : RepaintBoundary(
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                IslandSwap(
                  from: _cardFrom,
                  distance: 28,
                  child: KeyedSubtree(
                    key: ValueKey<IslandKind>(_card),
                    child: _cardBody(playback, note, battery, plugged, progress),
                  ),
                ),
                if (pages.length > 1 && pages.contains(_card))
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 2,
                    child: Center(
                      child: IslandPageDots(
                        count: pages.length,
                        index: pages.indexOf(_card),
                        onPick: (index) {
                          _engine.showPage(pages[index]);
                          _sync();
                        },
                      ),
                    ),
                  ),
              ],
            ),
          );
    Widget bubbleLayer(IslandKind bubble) => RepaintBoundary(
      child: IslandSwap(
        shrink: 0.4,
        child: KeyedSubtree(
          key: ValueKey<IslandKind>(bubble),
          child: _bubbleFor(bubble, playback, progress),
        ),
      ),
    );
    final rightBubble = bubbleLayer(_bubble);
    final leftBubble = bubbleLayer(_bubbleLeft);
    final coverUrl = playback?.artUrl ?? '';
    final swipes =
        settings.islandSwipe &&
        (_engine.expanded ? pages.length > 1 : _engine.live.length > 1);
    final yields = _yields;
    final expanded = _engine.expanded;
    final pinned = _engine.pinned;
    final cardSize = _cardSize(_card);

    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[_shape, _feel]),
      builder: (context, _) {
        // A held press reaches a little towards the panel: wider, and
        // deeper from the pill's own top edge, which is how it will open.
        // Absorbing the cursor adds a very subtle +6 px width elongation to
        // mimic swallowing the pointer mass.
        final charge = _charge.value.clamp(-0.2, 1.2) * (1 - _content.value);
        final tc = islandOpenShare(_h.value, h, cardSize.height);
        final absorbActive =
            !expanded &&
            !yields &&
            !settings.islandHoverFade &&
            settings.islandCursorAbsorb;
        final hover = _hoverFeel.value * (1 - tc);
        final absorbElongation = absorbActive
            ? 4.0 * hover.clamp(0.0, 1.2)
            : 0.0;
        final width = math.max(h, _w.value + 14 * charge + absorbElongation);
        final height = math.max(h * 0.9, _h.value + 5 * charge);
        final radius = math.max(0.0, _r.value);
        final shown = _content.value;
        final faceShown = islandFaceShare(shown, tc);
        final cardShown = islandCardShare(shown, tc);
        final split = _split.value;
        final splitLeft = _splitLeft.value;
        final reach =
            math.max(0.0, math.max(split, splitLeft)) * (h + _I.gap);
        final bubbleAt = reach + width + islandBubbleOffset(split, h, _I.gap);
        final bubbleLeftAt =
            reach - h - islandBubbleOffset(splitLeft, h, _I.gap);
        final hasBubble = split > 0.002;
        final hasBubbleLeft = splitLeft > 0.002;
        final veil = _veil.value.clamp(0.0, 1.0);
        final press = _pressFeel.value;
        final coverSize = lerpDouble(_I.cover, _I.bigCover, tc)!;
        final coverInset = (h - _I.cover) / 2;
        final blur = _skin.blurs
            ? BarTokens.islandContentBlur * (1 - cardShown)
            : 0.0;

        final content = ClipPath(
          clipper: widget.notch
              ? _NotchClipper(radius: radius)
              : ContinuousCornersClipper(radius: radius),
          child: Stack(
            children: <Widget>[
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: h,
                child: IgnorePointer(
                  ignoring: faceShown < 0.5,
                  child: Opacity(
                    opacity: faceShown,
                    child: Transform.scale(
                      scale: 0.9 + 0.1 * faceShown,
                      child: OverflowBox(
                        minWidth: compact,
                        maxWidth: compact,
                        child: faceLayer,
                      ),
                    ),
                  ),
                ),
              ),
              if (cardLayer != null && cardShown > 0)
                Positioned.fill(
                  child: IgnorePointer(
                    ignoring: cardShown < 0.5,
                    child: Opacity(
                      opacity: cardShown,
                      child: Transform.scale(
                        alignment: Alignment.topCenter,
                        scale:
                            BarTokens.islandContentScale +
                            (1 - BarTokens.islandContentScale) * cardShown,
                        child: ImageFiltered(
                          enabled: blur > 0.3,
                          imageFilter: ImageFilter.blur(
                            sigmaX: blur,
                            sigmaY: blur,
                          ),
                          child: OverflowBox(
                            alignment: Alignment.topCenter,
                            minWidth: cardSize.width,
                            maxWidth: cardSize.width,
                            minHeight: cardSize.height,
                            maxHeight: cardSize.height,
                            child: cardLayer,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              if (_hasCover(tc > 0 ? _card : kind))
                Positioned(
                  left: lerpDouble(coverInset + 1, _I.pad, tc)!,
                  top: lerpDouble(coverInset, _I.pad, tc)!,
                  child: IgnorePointer(
                    child: IslandCover(
                      url: coverUrl,
                      size: coverSize,
                      radius: _skin.corner(lerpDouble(5, 14, tc)!, coverSize),
                    ),
                  ),
                ),
              if (!expanded &&
                  !yields &&
                  !settings.islandHoverFade &&
                  settings.islandCursorAbsorb &&
                  hover > 0.01)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _CursorSheenPainter(
                        center: Offset(
                          width * (0.5 + _pullX.value.clamp(-1.1, 1.1) * 0.48),
                          h * (0.5 + _pullY.value.clamp(-1.1, 1.1) * 0.45),
                        ),
                        color: _skin.ink.withValues(
                          alpha: 0.13 * hover.clamp(0.0, 1.0),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );

        // Hide the OS cursor inside the resting pill only when it isn't
        // showing interactive workspace dots (so dot selection is never blind).
        // Keep hit-region geometry constant across hover transitions (no
        // dynamic Padding relayout or bubble-gap overlap).
        final overWorkspaces =
            _engine.kind == IslandKind.home && widget.workspace != null;
        final hideCursor = absorbActive && !overWorkspaces;
        final body = ShellInputRegion(
          debugLabel: 'denial_topbar.island',
          // Faded, the island gives its place up: the window underneath
          // takes the pointer there.
          active: !yields,
          keyboardPolicy: pinned
              ? ShellKeyboardPolicy.capture
              : ShellKeyboardPolicy.none,
          observeClientPointerPresses: expanded,
          child: MouseRegion(
            // Not opaque while faded, so the bar under the island is hit
            // too; the region itself still sees the pointer come and go.
            opaque: !yields,
            cursor: hideCursor
                ? SystemMouseCursors.none
                : !expanded && _engine.canExpand
                ? SystemMouseCursors.click
                : MouseCursor.defer,
            onEnter: _enter,
            onExit: _exit,
            onHover: expanded
                ? null
                : (event) {
                    final at = event.localPosition;
                    final pull = Offset(
                      (at.dx / width * 2 - 1).clamp(-1.15, 1.15),
                      (at.dy / h * 2 - 1).clamp(-1.15, 1.15),
                    );
                    // Small moves are not worth a frame.
                    if ((pull - _pull).distance < 0.015) return;
                    _pull = pull;
                    _aimPull();
                    _kick(_feel);
                  },
            child: IgnorePointer(
              ignoring: yields,
              child: Focus(
                focusNode: _focus,
                canRequestFocus: pinned,
                skipTraversal: true,
                onKeyEvent: _key,
                child: Listener(
                  onPointerSignal: (signal) {
                    if (signal is PointerScrollEvent) _onScroll(signal);
                  },
                  onPointerDown: (_) {
                    if (!_engine.expanded) return;
                    // A press inside a preview keeps it.
                    if (!_engine.pinned) {
                      _engine.pin();
                      _takeKeys();
                      _sync();
                    }
                  },
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: expanded ? null : (_) => _pressDown(),
                    // Open, a press where the pill was puts it back.
                    onTapUp: expanded
                        ? (details) {
                            final at = details.localPosition;
                            if (at.dy <= h &&
                                (at.dx - width / 2).abs() <= compact / 2) {
                              _setOpen(false);
                            }
                          }
                        : (_) => _pressUp(),
                    onTapCancel: expanded ? null : _pressUp,
                    onTap: expanded ? null : _tap,
                    onVerticalDragStart: _dragStart,
                    onVerticalDragUpdate: _dragUpdate,
                    onVerticalDragEnd: _dragEnd,
                    onHorizontalDragStart: swipes ? (_) => _swiped = 0 : null,
                    onHorizontalDragUpdate: swipes
                        ? (details) => _swiped += details.primaryDelta ?? 0
                        : null,
                    onHorizontalDragEnd: swipes
                        ? (details) => _turn(
                            islandSwipeStep(
                              _swiped,
                              details.primaryVelocity ?? 0,
                            ),
                          )
                        : null,
                    child: KeyedSubtree(key: _bodyKey, child: content),
                  ),
                ),
              ),
            ),
          ),
        );

        Widget bubbleAtop(double left, double share, Widget layer) {
          final bubbleShown = kitPhase(share, 0.5, 0.95);
          return Positioned(
            left: left,
            top: 0,
            width: h,
            height: h,
            child: IgnorePointer(
              ignoring: yields || bubbleShown < 0.5,
              child: Opacity(
                opacity: bubbleShown,
                child: Transform.scale(
                  scale: 0.6 + 0.4 * bubbleShown,
                  child: layer,
                ),
              ),
            ),
          );
        }

        final island = SizedBox(
          width: width + reach * 2,
          height: height,
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              Positioned.fill(
                child: CustomPaint(
                  painter: IslandBlobPainter(
                    body: Rect.fromLTWH(reach, 0, width, height),
                    radius: radius,
                    drops: <IslandDrop>[
                      if (hasBubble)
                        IslandDrop(
                          Rect.fromLTWH(bubbleAt, 0, h, h),
                          islandNeck(split),
                        ),
                      if (hasBubbleLeft)
                        IslandDrop(
                          Rect.fromLTWH(bubbleLeftAt, 0, h, h),
                          islandNeck(splitLeft),
                        ),
                    ],
                    bubbleRadius: _skin.pill(h),
                    shadow: tc,
                    skin: _skin,
                    notch: widget.notch,
                  ),
                ),
              ),
              Positioned(
                left: reach,
                top: 0,
                width: width,
                height: height,
                child: body,
              ),
              if (hasBubble) bubbleAtop(bubbleAt, split, rightBubble),
              if (hasBubbleLeft)
                bubbleAtop(bubbleLeftAt, splitLeft, leftBubble),
            ],
          ),
        );

        // Under a pointer the pill swells; under a press it flattens more
        // than it narrows, like something soft; an arrival is one breath.
        // All of it turns about the middle of the pill's own row.
        final lean = Offset(_pullX.value, _pullY.value) * (1 - tc);
        final hudBump = _hudEdge.value * (1 - tc);
        return Transform.translate(
          offset: Offset(
            lean.dx * _I.leanX + hudBump * 5.0,
            lean.dy * _I.leanY,
          ),
          child: Transform(
            alignment: Alignment(0, h / height - 1),
            transform: Matrix4.diagonal3Values(
              1 + 0.05 * hover - 0.03 * press + _pop.value + hudBump.abs() * 0.035,
              1 + 0.09 * hover - 0.09 * press + _pop.value - hudBump.abs() * 0.025,
              1,
            ),
            child: veil <= 0.001
                ? island
                : Opacity(opacity: 1 - veil, child: island),
          ),
        );
      },
    );
  }

  // Which way the track last changed. Going back is remembered for a
  // moment, long enough for the player to answer; anything else is forward.
  int get _trackTurn {
    final back = _wentBack;
    return back != null && _now.difference(back) < const Duration(seconds: 3)
        ? -1
        : 1;
  }

  bool _hasCover(IslandKind? kind) =>
      kind == IslandKind.media || kind == IslandKind.track;

  /// Applications publishing a progress, by desktop id as they spell it.
  Map<String, double> _launcherProgress() {
    final bus = ref.read(launcherEntriesProvider.notifier);
    return <String, double>{
      for (final entry in ref.watch(launcherEntriesProvider).entries)
        bus.desktopId(entry.key): ?entry.value.shownProgress,
    };
  }

  Widget _progressIcon(Map<String, double> progress) => progress.isEmpty
      ? BarGlyph(BarIcons.arrowDown, size: 12, color: _skin.ink)
      : _services.buildApplicationIcon(context, progress.keys.first);

  /// The second live activity, as a disc beside the pill.
  Widget _bubbleFor(
    IslandKind kind,
    MprisPlaybackState? playback,
    Map<String, double> progress,
  ) {
    final h = widget.height;
    final Widget content = switch (kind) {
      IslandKind.timer => IslandRing(
        value: _timerFraction,
        colour: _skin.tone(macOrange),
        size: h - 12,
        child: BarGlyph(
          BarIcons.timer,
          size: 9,
          color: _skin.tone(macOrange),
        ),
      ),
      IslandKind.recording => const IslandPulse(),
      IslandKind.progress => IslandRing(
        value: progress.values.firstOrNull ?? 0,
        colour: _skin.tone(macBlue),
        size: h - 12,
      ),
      _ => IslandCover(
        url: playback?.artUrl ?? '',
        size: h - 10,
        radius: _skin.corner(5, h - 10),
      ),
    };
    return ShellInputRegion(
      debugLabel: 'denial_topbar.island.second',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          _engine.pick(kind);
          _sync();
        },
        // The island's body paints the bubble's plate, joined to the pill.
        child: SizedBox.square(
          dimension: h,
          child: Center(child: content),
        ),
      ),
    );
  }

  double get _timerFraction {
    final total = islandTimer.total.inMilliseconds;
    if (total <= 0) return 0;
    return islandTimer.remaining(_now).inMilliseconds / total;
  }

  String _appLabel(String id) {
    for (final application in ref.read(_services.applications)) {
      final match = application.id == id || application.appId == id;
      if (match && application.name.isNotEmpty) return application.name;
    }
    return id.split('.').last;
  }

  Widget _face(
    IslandKind? kind,
    String label,
    MprisPlaybackState? playback,
    DesktopNotification? note,
    BatteryStatus battery,
  ) {
    final h = widget.height;
    final edge = (h - _I.cover) / 2 + 1;
    const gap = SizedBox(width: _I.cover + 8);
    switch (kind) {
      case null || IslandKind.home:
        return widget.workspace == null
            ? const SizedBox.expand()
            : Center(child: widget.workspace);
      case IslandKind.media:
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: edge),
          child: Row(
            children: <Widget>[
              gap,
              const Spacer(),
              IslandEqualizer(
                playing: playback?.playing ?? false,
                colour: _skin.tone(_skin.ink),
              ),
              const SizedBox(width: 3),
            ],
          ),
        );
      case IslandKind.track:
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: edge),
          child: Row(
            children: <Widget>[
              gap,
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: BarType.islandLabel.copyWith(color: _skin.ink),
                ),
              ),
              const SizedBox(width: 8),
              IslandEqualizer(
                playing: playback?.playing ?? false,
                colour: _skin.tone(_skin.ink),
              ),
              const SizedBox(width: 3),
            ],
          ),
        );
      case IslandKind.timer:
        final colour = islandTimer.paused
            ? _skin.dim
            : _skin.tone(macOrange);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: <Widget>[
              BarGlyph(BarIcons.timer, size: 14, color: colour),
              const Spacer(),
              Text(
                label,
                style: BarType.islandLabel.copyWith(
                  color: colour,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ],
          ),
        );
      case IslandKind.recording:
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13),
          child: Row(
            children: <Widget>[
              const IslandPulse(),
              const Spacer(),
              Text(
                label,
                style: BarType.islandLabel.copyWith(
                  color: macRed,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ],
          ),
        );
      case IslandKind.progress:
        final progress = _launcherProgress();
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9),
          child: Row(
            children: <Widget>[
              SizedBox.square(dimension: 18, child: _progressIcon(progress)),
              const Spacer(),
              IslandRing(
                value: progress.values.firstOrNull ?? 0,
                colour: _skin.tone(macBlue),
              ),
            ],
          ),
        );
      case IslandKind.status:
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: <Widget>[
              BarGlyph(_statusIcon, size: 14, color: _statusTint ?? _skin.ink),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: BarType.islandLabel.copyWith(color: _skin.ink),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _statusDetail,
                style: BarType.islandLabel.copyWith(color: _skin.dim),
              ),
            ],
          ),
        );
      case IslandKind.hud:
        final isMute = _hudIcon == BarIcons.speakerSlashFill;
        final isSun = _hudIcon == BarIcons.sunMaxFill;
        final Widget baseGlyph = IslandSwap(
          child: BarGlyph(
            _hudIcon,
            key: ValueKey<int>(_hudIcon.codePoint),
            size: 15,
            color: _skin.ink,
          ),
        );
        final Widget animatedGlyph;
        if (isMute) {
          animatedGlyph = TweenAnimationBuilder<double>(
            key: ValueKey<String>('mute-$_hudStep'),
            tween: Tween<double>(begin: 0, end: 1),
            duration: KitMotion.duration(
              context,
              const Duration(milliseconds: 300),
            ),
            builder: (context, t, child) => Transform.translate(
              offset: Offset(math.sin(t * math.pi * 4) * (1 - t) * 4.5, 0),
              child: child,
            ),
            child: baseGlyph,
          );
        } else if (isSun) {
          animatedGlyph = Sprung(
            target: _hudLevel,
            tuning: IslandFeel.of(KitStyle.of(context)).level,
            builder: (context, v, child) => Transform.rotate(
              angle: v * math.pi * 0.75,
              child: Transform.scale(
                scale: 0.86 + v.clamp(0.0, 1.0) * 0.24,
                child: child,
              ),
            ),
            child: baseGlyph,
          );
        } else {
          // Keep IslandSwap identity stable across volume ticks so crossing
          // mute/low/high thresholds morphs smoothly instead of unmounting.
          animatedGlyph = Sprung(
            target: _hudLevel,
            tuning: IslandFeel.of(KitStyle.of(context)).level,
            builder: (context, _, child) => child!,
            child: baseGlyph,
          );
        }
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13),
          child: Row(
            children: <Widget>[
              SizedBox(width: 20, child: animatedGlyph),
              const SizedBox(width: 9),
              Expanded(
                child: IslandLevel(
                  level: _hudLevel,
                  edgeRepaint: _feel,
                  edgeBumpOf: () => _hudEdge.value,
                ),
              ),
              const SizedBox(width: 9),
              // The number rolls the way the level went.
              SizedBox(
                width: 26,
                child: IslandSwap(
                  from: Offset(0, _hudTurn.toDouble()),
                  distance: 7,
                  alignment: Alignment.centerRight,
                  child: Text(
                    '${(_hudLevel * 100).round()}',
                    key: ValueKey<int>((_hudLevel * 100).round()),
                    textAlign: TextAlign.right,
                    style: BarType.islandLabel.copyWith(
                      color: _skin.dim,
                      fontFeatures: const <FontFeature>[
                        FontFeature.tabularFigures(),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      case IslandKind.charging:
        final plugged = _wasPlugged ?? false;
        final full = plugged && (battery.capacity ?? 0) >= 100;
        final low = _low(plugged, battery.capacity);
        final colour = plugged
            ? const Color(0xff30d158)
            : low
            ? const Color(0xffff453a)
            : _skin.ink;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  context.tr(
                    full
                        ? 'Battery Full'
                        : plugged
                        ? 'Charging'
                        : low
                        ? 'Low Battery'
                        : 'On Battery',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: BarType.islandLabel.copyWith(color: _skin.ink),
                ),
              ),
              Text(
                '${battery.capacity ?? 0}%',
                style: BarType.islandLabel.copyWith(color: colour),
              ),
              const SizedBox(width: 6),
              BatteryGlyph(
                level: (battery.capacity ?? 0) / 100,
                colour: colour,
                charging: plugged,
                width: 24,
              ),
            ],
          ),
        );
      case IslandKind.notice:
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: <Widget>[
              SizedBox(width: 18, height: 18, child: _noticeIcon(note, 12)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: BarType.islandLabel.copyWith(color: _skin.ink),
                ),
              ),
            ],
          ),
        );
    }
  }

  Widget _noticeIcon(DesktopNotification? note, double glyph) {
    final id = note == null
        ? ''
        : (note.desktopEntry.isNotEmpty ? note.desktopEntry : note.appName);
    if (id.isEmpty) {
      return BarGlyph(BarIcons.bellFill, size: glyph, color: _skin.ink);
    }
    return _services.buildApplicationIcon(context, id);
  }

  /// The answers a notification offers, apart from the one a press on the
  /// card itself gives.
  List<DesktopNotificationAction> _answers(DesktopNotification note) =>
      <DesktopNotificationAction>[
        for (final action in note.actions)
          if (action.key != 'default' && action.label.trim().isNotEmpty)
            action,
      ].take(3).toList();

  String _span(Duration span) {
    final hours = span.inHours, minutes = span.inMinutes % 60;
    final short = context.tr('{} min', minutes);
    return hours > 0 ? '${context.tr('{} h', hours)} $short' : short;
  }

  Widget _cardBody(
    MprisPlaybackState? playback,
    DesktopNotification? note,
    BatteryStatus battery,
    bool plugged,
    Map<String, double> progress,
  ) {
    switch (_card) {
      case IslandKind.timer:
        return IslandTimerCard(
          remaining: clockSpan(islandTimer.remaining(_now)),
          fraction: _timerFraction,
          paused: islandTimer.paused,
          caption: context.tr(islandTimer.paused ? 'Paused' : 'Timer'),
          detail: context.tr('of {}', clockSpan(islandTimer.total)),
          onToggle: () => islandTimer.toggle(_now),
          onAdd: () => islandTimer.add(const Duration(minutes: 1), _now),
          onCancel: islandTimer.cancel,
        );
      case IslandKind.recording:
        final speakers = micWatch.value;
        return IslandRecordingCard(
          elapsed: clockSpan(_now.difference(_recordingSince ?? _now)),
          caption: context.tr('Screen Recording'),
          detail: speakers.isEmpty
              ? ''
              : context.tr('Microphone: {}', speakers.first),
          onStop: () => ref.read(screenRecordingProvider.notifier).toggle(),
        );
      case IslandKind.progress:
        return IslandProgressCard(
          entries: <IslandProgressEntry>[
            for (final entry in progress.entries.take(_I.progressRows))
              IslandProgressEntry(
                icon: _services.buildApplicationIcon(context, entry.key),
                name: _appLabel(entry.key),
                value: entry.value,
              ),
          ],
        );
      case IslandKind.home:
        void start(int minutes) {
          islandTimer.start(Duration(minutes: minutes), _now);
          _setOpen(false);
        }
        void go(VoidCallback? action) {
          _setOpen(false);
          action?.call();
        }
        final notices = ref.watch(desktopNotificationsProvider);
        final latest = widget.settings.activityNotifications
            ? notices.groups.firstOrNull?.members.firstOrNull?.notification
            : null;
        final homeNow = widget.timeLabel.isEmpty
            ? (ref.watch(_services.clock).value ?? DateTime.now())
            : null;
        final timeText = widget.timeLabel.isNotEmpty
            ? widget.timeLabel
            : _services.strings(context).time(homeNow!);
        final dateText = widget.dateLabel.isNotEmpty
            ? widget.dateLabel
            : (widget.dateLabelFor != null && homeNow != null
                  ? widget.dateLabelFor!(context, homeNow)
                  : '');
        return IslandHomeCard(
          time: timeText,
          date: dateText,
          workspace: widget.workspace,
          nothing: context.tr('No Notifications'),
          digest: latest == null
              ? null
              : IslandDigest(
                  icon: _noticeIcon(latest, 16),
                  title: latest.summary.isEmpty
                      ? latest.appName
                      : latest.summary.replaceAll('\n', ' '),
                  body: latest.body.replaceAll('\n', ' '),
                  unread: notices.unreadCount,
                ),
          onDigest: () => go(widget.onNotifications),
          trailing: battery.capacity == null
              ? null
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      '${battery.capacity}%',
                      style: BarType.islandLabel.copyWith(color: _skin.dim),
                    ),
                    const SizedBox(width: 6),
                    BatteryGlyph(
                      level: battery.capacity! / 100,
                      colour: plugged ? macGreen : _skin.ink,
                      charging: plugged,
                      width: 24,
                    ),
                  ],
                ),
          actions: <IslandHomeAction>[
            if (widget.settings.activityTimer)
              for (final minutes in widget.settings.islandTimers)
                IslandHomeAction(
                  icon: BarIcons.timer,
                  label: context.tr('{}m', minutes),
                  onTap: () => start(minutes),
                ),
            ...() {
              ensureIslandHomeActionsLoaded();
              final recording = ref.watch(
                screenRecordingProvider.select((s) => s.recording),
              );
              final isDark = ref.watch(
                shellSettingsProvider.select(kitSystemIsDark),
              );
              final built = <IslandHomeAction>[];
              for (final id in islandHomeActions.value) {
                switch (id) {
                  case 'dnd':
                    built.add(
                      IslandHomeAction(
                        icon: notices.doNotDisturb
                            ? BarIcons.moonFill
                            : BarIcons.moon,
                        on: notices.doNotDisturb,
                        onTap: ref
                            .read(desktopNotificationsProvider.notifier)
                            .toggleDoNotDisturb,
                      ),
                    );
                  case 'cc':
                    built.add(
                      IslandHomeAction(
                        icon: BarIcons.sliderHorizontal3,
                        onTap: () => go(widget.onControlCenter),
                      ),
                    );
                  case 'nc':
                    built.add(
                      IslandHomeAction(
                        icon: BarIcons.bell,
                        onTap: () => go(widget.onNotifications),
                      ),
                    );
                  case 'search':
                    built.add(
                      IslandHomeAction(
                        icon: BarIcons.search,
                        onTap: () => go(
                          () => KitRequests.triggerSearch(
                            fallback: _services.toggleLauncher,
                            monitorId: widget.monitorId,
                          ),
                        ),
                      ),
                    );
                  case 'screenshot':
                    built.add(
                      IslandHomeAction(
                        icon: BarIcons.camera,
                        onTap: () => go(
                          () => ref
                              .read(systemActionsServiceProvider)
                              .takeScreenshot(),
                        ),
                      ),
                    );
                  case 'recording':
                    built.add(
                      IslandHomeAction(
                        icon: BarIcons.circleFill,
                        on: recording,
                        onTap: () => go(
                          () => ref
                              .read(screenRecordingProvider.notifier)
                              .toggle(),
                        ),
                      ),
                    );
                  case 'night':
                    built.add(
                      IslandHomeAction(
                        icon: NightLight.enabled.value
                            ? BarIcons.sunMaxFill
                            : BarIcons.sunMax,
                        on: NightLight.enabled.value,
                        onTap: () {
                          unawaited(
                            NightLight.toggle().whenComplete(() {
                              if (mounted) setState(() {});
                            }),
                          );
                          setState(() {});
                        },
                      ),
                    );
                  case 'dark':
                    built.add(
                      IslandHomeAction(
                        icon: BarIcons.circleHalf,
                        on: isDark,
                        onTap: () => setKitSystemDarkMode(ref, !isDark),
                      ),
                    );
                  case 'lock':
                    built.add(
                      IslandHomeAction(
                        icon: BarIcons.lockFill,
                        onTap: () => go(
                          () => ref
                              .read(sessionPowerProvider.notifier)
                              .request(SessionPowerAction.lock),
                        ),
                      ),
                    );
                }
              }
              return built;
            }(),
          ],
        );
      case IslandKind.notice:
        final notifications = ref.read(desktopNotificationsProvider.notifier);
        return IslandNoticeCard(
          icon: _noticeIcon(note, 22),
          app: note == null
              ? ''
              : (note.appName.isEmpty ? note.sender : note.appName),
          summary: (note?.summary ?? '').replaceAll('\n', ' '),
          body: (note?.body ?? '').replaceAll('\n', ' '),
          actions: <(String, VoidCallback)>[
            if (note != null)
              for (final action in _answers(note))
                (
                  action.label,
                  () {
                    notifications.invokeAction(note.id, action.key);
                    _setOpen(false);
                  },
                ),
          ],
          onOpen: note == null
              ? null
              : () {
                  notifications.invokeDefaultAction(note.id);
                  _setOpen(false);
                },
          onDismiss: note == null
              ? null
              : () {
                  notifications.hideBanner(note.id);
                  _setOpen(false);
                },
        );
      case IslandKind.charging:
        final cell = ref.watch(
          upowerProvider.select(
            (state) => state.snapshot?.batteries.firstOrNull,
          ),
        );
        final left = plugged ? cell?.timeToFull : cell?.timeToEmpty;
        final full = plugged && (battery.capacity ?? 0) >= 100;
        return IslandChargeCard(
          percent: battery.capacity ?? 0,
          plugged: plugged,
          label: context.tr(
            full
                ? 'Battery Full'
                : plugged
                ? 'Charging'
                : _low(plugged, battery.capacity)
                ? 'Low Battery'
                : 'On Battery',
          ),
          detail: left != null && left > Duration.zero
              ? context.tr(
                  plugged ? '{} until full' : '{} remaining',
                  _span(left),
                )
              : '',
        );
      default:
        final commands = ref.watch(_services.mediaCommands);
        // Where the sound goes, when the shell lists its outputs.
        final audioState = ref.watch(audioDevicesProvider);
        final availableOutputs = audioState.devices
            .where((d) => d.available || d.active)
            .toList();
        final output = availableOutputs.where((d) => d.active).firstOrNull;
        return IslandMediaCard(
          playback: playback,
          onPrevious: () {
            _wentBack = _now;
            commands.previous();
          },
          onPlayPause: commands.playPause,
          onNext: () {
            _wentBack = null;
            commands.next();
          },
          turn: _trackTurn,
          subline: (widget.subline ?? _lyrics).line,
          output: output == null
              ? ''
              : (output.description.isEmpty
                    ? output.name
                    : output.description),
          outputIcon: output == null ? null : outputDeviceIcon(output),
          onSwitchOutput: availableOutputs.length > 1
              ? () {
                  final idx = availableOutputs.indexWhere((d) => d.active);
                  final next =
                      availableOutputs[(idx + 1) % availableOutputs.length];
                  ref.read(audioDevicesProvider.notifier).select(next.name);
                }
              : null,
          coverSlot: _I.bigCover,
          padding: _I.pad,
          nothing: context.tr('Not Playing'),
        );
    }
  }
}

class _NotchClipper extends CustomClipper<Path> {
  const _NotchClipper({required this.radius});

  final double radius;

  @override
  Path getClip(Size size) {
    final r = radius.clamp(0.0, math.min(size.width, size.height) / 2);
    return Path()..addRRect(
      RRect.fromRectAndCorners(
        Offset.zero & size,
        bottomLeft: Radius.circular(r),
        bottomRight: Radius.circular(r),
      ),
    );
  }

  @override
  bool shouldReclip(_NotchClipper old) => old.radius != radius;
}

class _CursorSheenPainter extends CustomPainter {
  const _CursorSheenPainter({required this.center, required this.color});

  final Offset center;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || color.a <= 0.001) return;
    const radius = 44.0;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final shader = RadialGradient(
      colors: <Color>[color, color.withValues(alpha: 0)],
    ).createShader(rect);
    canvas.drawRect(rect, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_CursorSheenPainter old) =>
      old.center != center || old.color != color;
}
