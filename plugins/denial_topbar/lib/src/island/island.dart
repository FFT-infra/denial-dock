import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:denial_flutter_sdk/input.dart';
import 'package:denial_flutter_sdk/models.dart';
import 'package:denial_flutter_sdk/services.dart';
import 'package:denial_flutter_sdk/state.dart';
import 'package:denial_sdk/system.dart' show BatteryStatus;
import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bar_icons.dart';
import '../bar_panel.dart';
import '../bar_settings.dart';
import '../bar_tokens.dart';
import '../bar_type.dart';
import '../continuous_corners.dart';
import '../debug_remote.dart';
import '../l10n.dart';
import '../mic_watch.dart';
import '../panels/mac_kit.dart';
import 'island_cards.dart';
import 'island_engine.dart';
import 'island_parts.dart';
import 'island_timer.dart';
import 'launcher_progress.dart';

/// How far below the bar the island may grow; the bar's surface reserves it.
const double islandReach = 220;

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
  static const double bigCover = 56;
  static const double pad = 16;
  static const Duration hudHold = Duration(seconds: 2);
  static const Duration chargeHold = Duration(seconds: 3);
  static const Duration trackHold = Duration(seconds: 3);
  static const Duration statusHold = Duration(milliseconds: 2600);
  static const Duration settle = Duration(seconds: 6);
  static const Duration touchIdle = Duration(seconds: 10);
  static const Color ink = Color(0xffffffff);
  static const Color dim = Color(0x99ffffff);
}

Size _cardSize(IslandKind kind) => switch (kind) {
  IslandKind.notice => const Size(360, 88),
  IslandKind.charging => const Size(300, 78),
  IslandKind.timer => const Size(370, 86),
  IslandKind.recording => const Size(320, 86),
  IslandKind.progress => const Size(340, 86),
  IslandKind.home => const Size(380, 148),
  _ => const Size(380, 172),
};

double _cardRadius(IslandKind kind) => switch (kind) {
  IslandKind.media || IslandKind.track => 36,
  _ => 30,
};

/// The island. It lives in the bar and grows in place: the same black shape
/// is the resting pill, the compact activity, and the open card.
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
    this.onControlCenter,
    this.onNotifications,
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

  /// What the home card shows and opens.
  final String timeLabel;
  final String dateLabel;
  final VoidCallback? onControlCenter;
  final VoidCallback? onNotifications;

  @override
  ConsumerState<Island> createState() => _IslandState();
}

class _IslandState extends ConsumerState<Island>
    with SingleTickerProviderStateMixin {
  final IslandEngine _engine = IslandEngine();
  late final AnimationController _open = AnimationController.unbounded(
    vsync: this,
  );

  Timer? _deadline;
  Timer? _intent;
  Timer? _leave;
  Timer? _idle;
  Timer? _progress;
  Timer? _clock;
  StreamSubscription<Object?>? _outside;
  final DateTime _born = DateTime.now();

  IslandKind _card = IslandKind.media;
  IconData _hudIcon = BarIcons.volumeUp;
  double _hudLevel = 0;
  IconData _statusIcon = BarIcons.bellFill;
  Color _statusTint = _I.ink;
  String _statusLabel = '';
  String _statusDetail = '';
  DateTime? _recordingSince;
  DateTime? _timerSeen;
  IslandKind _bubble = IslandKind.media;
  bool _hovered = false;
  bool _pressed = false;
  Offset _pull = Offset.zero;
  double? _dragFrom;
  double _dragged = 0;

  ShellServices get _services => widget.services;
  DateTime get _now => DateTime.now();

  @override
  void initState() {
    super.initState();
    barOpenPanel.addListener(_onPanel);
    _timerSeen = islandTimer.finishedAt;
    islandTimer.addListener(_onTimer);
    launcherProgress
      ..start()
      ..addListener(_onSource);
    micWatch.addListener(_onMic);
    debugCommand.addListener(_debug);
    _outside = ref
        .read(denialBridgeProvider)
        .shellActions
        .where((event) => event.action.name == 'clientPointerPressed')
        .listen((_) => _setOpen(false));
  }

  @override
  void dispose() {
    barOpenPanel.removeListener(_onPanel);
    islandTimer.removeListener(_onTimer);
    launcherProgress.removeListener(_onSource);
    micWatch.removeListener(_onMic);
    debugCommand.removeListener(_debug);
    _clock?.cancel();
    _outside?.cancel();
    for (final timer in <Timer?>[
      _deadline,
      _intent,
      _leave,
      _idle,
      _progress,
    ]) {
      timer?.cancel();
    }
    _open.dispose();
    super.dispose();
  }

  void _onPanel() {
    if (barOpenPanel.value != null) _setOpen(false);
  }

  void _onSource() {
    if (mounted) setState(() {});
  }

  void _debug() {
    final words = debugWords();
    if (words.isEmpty || !mounted) return;
    final number = words.length > 1 ? int.tryParse(words[1]) ?? 0 : 0;
    switch (words.first) {
      case 'island':
        _setOpen(words.length < 2 || words[1] != 'close', byTouch: true);
      case 'timer':
        number > 0
            ? islandTimer.start(Duration(seconds: number), _now)
            : islandTimer.cancel();
      case 'cycle':
        _engine.cycle(1);
        _sync();
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
        tint: using ? macOrange : _I.dim,
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

  /// Brings timers and the open animation in line with the engine.
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
    if (!_engine.expanded && _open.value > 0 && _dragFrom == null) {
      _animate(false);
    }
    if (mounted) setState(() {});
  }

  void _animate(bool open) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce) {
      _open.value = open ? 1 : 0;
      return;
    }
    final spring = SpringDescription.withDurationAndBounce(
      duration: open ? BarTokens.islandExpand : BarTokens.islandCollapse,
      bounce: open ? 0.24 : 0,
    );
    _open.animateWith(
      SpringSimulation(spring, _open.value, open ? 1 : 0, _open.velocity),
    );
  }

  void _setOpen(bool open, {bool byTouch = false}) {
    _intent?.cancel();
    _leave?.cancel();
    _idle?.cancel();
    if (open) {
      final kind = _engine.kind;
      if (kind == null || !kind.expandable) return;
      if (barOpenPanel.value != null) return;
      _card = kind;
      _engine.expand();
      _animate(true);
      if (byTouch) _armIdle();
    } else {
      if (!_engine.expanded && _open.value <= 0) return;
      _engine.collapse(_now);
      _animate(false);
    }
    _progress?.cancel();
    if (_engine.expanded) {
      _progress = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
    _sync();
  }

  void _armIdle() {
    _idle?.cancel();
    _idle = Timer(_I.touchIdle, () {
      if (!_hovered) _setOpen(false);
    });
  }

  void _show(IslandKind kind, String id, Duration hold) {
    _engine.show(kind, id, hold, _now);
    _sync();
  }

  void _hud(IconData icon, double level) {
    if (barOpenPanel.value != null) return;
    _hudIcon = icon;
    _hudLevel = level.clamp(0.0, 1.0);
    _show(IslandKind.hud, 'level', _I.hudHold);
  }

  /// A one-line change of state: an icon, what changed, and how.
  void _status(
    IconData icon,
    String label, {
    String detail = '',
    Color tint = _I.ink,
    Duration hold = _I.statusHold,
  }) {
    // Sources report their first state as a change while the shell starts.
    if (_now.difference(_born) < _I.settle) return;
    if (barOpenPanel.value != null) return;
    _statusIcon = icon;
    _statusTint = tint;
    _statusLabel = label;
    _statusDetail = detail;
    _show(IslandKind.status, '$label $detail', hold);
  }

  void _swipe(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity.abs() < 120) return;
    final open = _engine.expanded;
    _engine.cycle(velocity < 0 ? 1 : -1);
    final kind = _engine.kind;
    if (open && kind != null && kind.expandable) {
      _card = kind;
      _engine.expand();
    }
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
          tint: device.connected ? macBlue : _I.dim,
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
          tint: _I.dim,
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
          tint: next ? macPurple : _I.dim,
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
    ref.listen<double>(_services.volume, (previous, next) {
      if (!settings.activityHud) return;
      if (previous == null || (previous - next).abs() < 0.004) return;
      _hud(
        next <= 0.001
            ? BarIcons.speakerSlashFill
            : (next < 0.5 ? BarIcons.speaker1Fill : BarIcons.speaker3Fill),
        next,
      );
    });
    // The provider starts over at a placeholder level whenever the display
    // layout changes, a workspace switch included; a level that is still
    // loading, or has just finished, is not a change the user made.
    ref.listen<({double? level, bool loading})>(
      displayBrightnessProvider.select(
        (state) => (
          level: state.levels[widget.monitorId],
          loading: state.loading.contains(widget.monitorId),
        ),
      ),
      (previous, next) {
        final from = previous?.level;
        final to = next.level;
        if (!settings.activityHud || from == null || to == null) return;
        if (previous!.loading || next.loading) return;
        if ((from - to).abs() < 0.004) return;
        _hud(BarIcons.sunMaxFill, to);
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

  double _compactWidth(IslandKind? kind, String label) => switch (kind) {
    null || IslandKind.home =>
      widget.workspace == null
          ? _I.rest
          : math.max(_I.rest, widget.workspaceWidth + 24),
    IslandKind.media => _I.media,
    IslandKind.hud => _I.hud,
    IslandKind.charging => _I.charging,
    IslandKind.timer ||
    IslandKind.recording => _I.timer + (label.length > 5 ? 18 : 0),
    IslandKind.progress => _I.progress,
    IslandKind.status =>
      (_measure(label, BarType.islandLabel) +
              _measure(_statusDetail, BarType.islandLabel) +
              58)
          .clamp(_I.textMin, _I.textMax + 40),
    IslandKind.track || IslandKind.notice =>
      (_measure(label, BarType.islandLabel) + 74).clamp(_I.textMin, _I.textMax),
  };

  // ── Pointer ──────────────────────────────────────────────────────────────

  void _enter() {
    _hovered = true;
    _leave?.cancel();
    _idle?.cancel();
    final kind = _engine.kind;
    if (widget.settings.islandHoverPeek &&
        !_engine.expanded &&
        kind != null &&
        kind != IslandKind.home &&
        kind.expandable) {
      _intent?.cancel();
      _intent = Timer(BarTokens.islandHoverIntent, () {
        if (mounted && _hovered) _setOpen(true);
      });
    }
    setState(() {});
  }

  void _exit() {
    _hovered = false;
    _pull = Offset.zero;
    _intent?.cancel();
    if (_engine.expanded) {
      _leave?.cancel();
      _leave = Timer(BarTokens.islandLeaveGrace, () {
        if (mounted && !_hovered) _setOpen(false);
      });
    }
    setState(() {});
  }

  void _dragStart(DragStartDetails details) {
    final kind = _engine.kind;
    if (kind == null || !kind.expandable) return;
    if (!_engine.expanded) _card = kind;
    _open.stop();
    _dragFrom = _open.value;
    _dragged = 0;
  }

  void _dragUpdate(DragUpdateDetails details) {
    final from = _dragFrom;
    if (from == null) return;
    _dragged += details.primaryDelta ?? 0;
    final travel = _cardSize(_card).height - widget.height;
    var value = from + _dragged / travel;
    // Past either end the shape gives a little and resists.
    if (value > 1) value = 1 + (value - 1) / (1 + (value - 1) * 6) * 0.5;
    if (value < 0) value = value / (1 - value * 6) * 0.5;
    _open.value = value;
  }

  void _dragEnd(DragEndDetails details) {
    final from = _dragFrom;
    if (from == null) return;
    _dragFrom = null;
    final velocity = details.primaryVelocity ?? 0;
    final open = velocity.abs() > 250 ? velocity > 0 : _open.value > 0.45;
    if (open) {
      _engine.expand();
      _animate(true);
      _armIdle();
      _progress ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
      setState(() {});
    } else {
      _engine.collapse(_now);
      _animate(false);
      _sync();
    }
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

    final settings = widget.settings;
    final playback = ref.watch(_services.media).value;
    final recording = ref.watch(
      screenRecordingProvider.select((state) => state.recording),
    );
    _recordingSince = recording ? (_recordingSince ?? _now) : null;
    final progress = launcherProgress.value;
    _engine
      ..setLive(IslandKind.home, settings.islandHome)
      ..setMedia(settings.activityMedia && (playback?.playing ?? false))
      ..setLive(
        IslandKind.progress,
        settings.activityProgress && progress.isNotEmpty,
      )
      ..setLive(IslandKind.timer, settings.activityTimer && islandTimer.active)
      ..setLive(IslandKind.recording, settings.activityRecording && recording);
    if (!_engine.expanded &&
        _open.value > 0 &&
        _dragFrom == null &&
        !_open.isAnimating) {
      scheduleMicrotask(() {
        if (mounted && !_engine.expanded) _animate(false);
      });
    }
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
    final second = settings.islandSplit ? _engine.secondary : null;
    if (second != null) _bubble = second;
    final reserve = compact + (second == null ? 0 : (h + _I.gap) * 2);
    if (widget.reserved.value != reserve) {
      scheduleMicrotask(() => widget.reserved.value = reserve);
    }
    final lives = _engine.live
        .where((live) => live != IslandKind.home)
        .toList();
    final cardEnd = _cardSize(_card);

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: compact),
      duration: const Duration(milliseconds: 420),
      curve: BarTokens.spring,
      builder: (context, cw, _) => TweenAnimationBuilder<Size?>(
        tween: SizeTween(end: cardEnd),
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeOutCubic,
        builder: (context, cardNow, _) => AnimatedBuilder(
          animation: _open,
          builder: (context, _) {
            final card = cardNow ?? cardEnd;
            final t = _open.value;
            final tc = t.clamp(0.0, 1.0);
            final width = lerpDouble(cw, card.width, t)!;
            final height = math.max(h * 0.9, lerpDouble(h, card.height, t)!);
            final radius = lerpDouble(h / 2, _cardRadius(_card), tc)!;
            final faceOpacity = (1 - tc / 0.22).clamp(0.0, 1.0);
            final cardOpacity = ((tc - 0.32) / 0.5).clamp(0.0, 1.0);
            final swell = _pressed
                ? 0.96
                : (_hovered ? 1 + 0.07 * (1 - tc) : 1.0);
            final coverSize = lerpDouble(_I.cover, _I.bigCover, tc)!;
            final coverInset = (h - _I.cover) / 2;

            final shape = Container(
              width: width,
              height: height,
              decoration: ShapeDecoration(
                color: const Color(BarTokens.islandFill),
                shape: ContinuousCorners(
                  radius: radius,
                  side: BorderSide(
                    color: _I.ink.withValues(alpha: 0.12),
                    width: 0.6,
                  ),
                ),
                shadows: <BoxShadow>[
                  BoxShadow(
                    color: Color.fromRGBO(0, 0, 0, 0.36 * tc),
                    blurRadius: 30,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: ClipPath(
                clipper: ContinuousCornersClipper(radius: radius),
                child: Stack(
                  children: <Widget>[
                    if (faceOpacity > 0)
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        height: h,
                        child: Opacity(
                          opacity: faceOpacity,
                          child: OverflowBox(
                            minWidth: compact,
                            maxWidth: compact,
                            child: AnimatedSwitcher(
                              duration: BarTokens.islandContentIn,
                              reverseDuration: BarTokens.islandContentOut,
                              transitionBuilder: (child, animation) =>
                                  FadeTransition(
                                    opacity: animation,
                                    child: ScaleTransition(
                                      scale: Tween<double>(
                                        begin: 0.9,
                                        end: 1,
                                      ).animate(animation),
                                      child: child,
                                    ),
                                  ),
                              child: KeyedSubtree(
                                key: ValueKey<IslandKind?>(kind),
                                child: _face(
                                  kind,
                                  label,
                                  playback,
                                  note,
                                  battery,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (cardOpacity > 0)
                      Positioned.fill(
                        child: Opacity(
                          opacity: cardOpacity,
                          child: Transform.scale(
                            alignment: Alignment.topCenter,
                            scale: 0.94 + 0.06 * cardOpacity,
                            child: OverflowBox(
                              alignment: Alignment.topCenter,
                              minWidth: card.width,
                              maxWidth: card.width,
                              minHeight: card.height,
                              maxHeight: card.height,
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 220),
                                child: KeyedSubtree(
                                  key: ValueKey<IslandKind>(_card),
                                  child: _cardBody(
                                    playback,
                                    note,
                                    battery,
                                    plugged,
                                    progress,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (cardOpacity > 0 &&
                        lives.length > 1 &&
                        lives.contains(_card))
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 6,
                        child: Opacity(
                          opacity: cardOpacity,
                          child: Center(
                            child: IslandPageDots(
                              count: lives.length,
                              index: lives.indexOf(_card),
                            ),
                          ),
                        ),
                      ),
                    if (_hasCover(tc > 0 ? _card : kind))
                      Positioned(
                        left: lerpDouble(coverInset + 1, _I.pad, tc)!,
                        top: lerpDouble(coverInset, _I.pad, tc)!,
                        child: IslandCover(
                          url: playback?.artUrl ?? '',
                          size: coverSize,
                          radius: lerpDouble(5, 13, tc)!,
                        ),
                      ),
                  ],
                ),
              ),
            );

            final pill = Transform.translate(
              offset: _pull * (1 - tc),
              child: Transform.scale(
                scale: swell,
                alignment: Alignment.topCenter,
                child: ShellInputRegion(
                  debugLabel: 'denial_topbar.island',
                  observeClientPointerPresses: _engine.expanded,
                  child: MouseRegion(
                    cursor: kind != null && kind.expandable && !_engine.expanded
                        ? SystemMouseCursors.click
                        : MouseCursor.defer,
                    onEnter: (_) => _enter(),
                    onExit: (_) => _exit(),
                    onHover: (event) {
                      if (_engine.expanded) return;
                      final pull = Offset(
                        (event.localPosition.dx / width * 2 - 1).clamp(
                              -1.0,
                              1.0,
                            ) *
                            3,
                        (event.localPosition.dy / height * 2 - 1).clamp(
                              -1.0,
                              1.0,
                            ) *
                            1.5,
                      );
                      if ((pull - _pull).distance > 0.3) {
                        setState(() => _pull = pull);
                      }
                    },
                    child: Listener(
                      onPointerDown: (_) {
                        if (_engine.expanded && !_hovered) _armIdle();
                      },
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapDown: (_) {
                          if (!_engine.expanded) {
                            setState(() => _pressed = true);
                          }
                        },
                        onTapUp: (_) => setState(() => _pressed = false),
                        onTapCancel: () => setState(() => _pressed = false),
                        onTap: _engine.expanded
                            ? null
                            : () => _setOpen(true, byTouch: !_hovered),
                        onVerticalDragStart: _dragStart,
                        onVerticalDragUpdate: _dragUpdate,
                        onVerticalDragEnd: _dragEnd,
                        onHorizontalDragEnd:
                            settings.islandSwipe && lives.length > 1
                            ? _swipe
                            : null,
                        child: shape,
                      ),
                    ),
                  ),
                ),
              ),
            );
            return TweenAnimationBuilder<double>(
              tween: Tween<double>(end: second == null ? 0 : 1),
              duration: const Duration(milliseconds: 360),
              curve: Curves.easeOutCubic,
              builder: (context, split, _) {
                final slot = (h + _I.gap) * split;
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SizedBox(width: slot),
                    pill,
                    SizedBox(
                      width: slot,
                      height: h,
                      child: split <= 0.001
                          ? null
                          : OverflowBox(
                              alignment: Alignment.centerRight,
                              minWidth: h,
                              maxWidth: h,
                              child: Opacity(
                                opacity: split.clamp(0.0, 1.0),
                                child: Transform.scale(
                                  scale: 0.6 + 0.4 * split,
                                  child: _bubbleFor(
                                    _bubble,
                                    playback,
                                    progress,
                                  ),
                                ),
                              ),
                            ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  bool _hasCover(IslandKind? kind) =>
      kind == IslandKind.media || kind == IslandKind.track;

  Widget _progressIcon(Map<String, double> progress) => progress.isEmpty
      ? const BarGlyph(BarIcons.arrowDown, size: 12, color: _I.ink)
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
        colour: macOrange,
        size: h - 12,
        child: const BarGlyph(BarIcons.timer, size: 9, color: macOrange),
      ),
      IslandKind.recording => const IslandPulse(),
      IslandKind.progress => IslandRing(
        value: progress.values.firstOrNull ?? 0,
        colour: macBlue,
        size: h - 12,
      ),
      _ => IslandCover(url: playback?.artUrl ?? '', size: h - 10, radius: 5),
    };
    return ShellInputRegion(
      debugLabel: 'denial_topbar.island.second',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          _engine.pick(kind);
          _sync();
        },
        child: Container(
          width: h,
          height: h,
          alignment: Alignment.center,
          decoration: ShapeDecoration(
            color: const Color(BarTokens.islandFill),
            shape: CircleBorder(
              side: BorderSide(
                color: _I.ink.withValues(alpha: 0.12),
                width: 0.6,
              ),
            ),
          ),
          child: content,
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
              IslandEqualizer(playing: playback?.playing ?? false),
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
                  style: BarType.islandLabel.copyWith(color: _I.ink),
                ),
              ),
              const SizedBox(width: 8),
              IslandEqualizer(playing: playback?.playing ?? false),
              const SizedBox(width: 3),
            ],
          ),
        );
      case IslandKind.timer:
        final colour = islandTimer.paused ? _I.dim : macOrange;
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
        final progress = launcherProgress.value;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9),
          child: Row(
            children: <Widget>[
              SizedBox.square(dimension: 18, child: _progressIcon(progress)),
              const Spacer(),
              IslandRing(
                value: progress.values.firstOrNull ?? 0,
                colour: macBlue,
              ),
            ],
          ),
        );
      case IslandKind.status:
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: <Widget>[
              BarGlyph(_statusIcon, size: 14, color: _statusTint),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: BarType.islandLabel.copyWith(color: _I.ink),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _statusDetail,
                style: BarType.islandLabel.copyWith(color: _I.dim),
              ),
            ],
          ),
        );
      case IslandKind.hud:
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 20,
                child: BarGlyph(_hudIcon, size: 15, color: _I.ink),
              ),
              const SizedBox(width: 9),
              Expanded(child: IslandLevel(level: _hudLevel)),
              const SizedBox(width: 9),
              SizedBox(
                width: 26,
                child: Text(
                  '${(_hudLevel * 100).round()}',
                  textAlign: TextAlign.right,
                  style: BarType.islandLabel.copyWith(
                    color: _I.dim,
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      case IslandKind.charging:
        final plugged = _wasPlugged ?? false;
        final colour = plugged ? const Color(0xff30d158) : _I.ink;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  context.tr(plugged ? 'Charging' : 'On Battery'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: BarType.islandLabel.copyWith(color: _I.ink),
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
                  style: BarType.islandLabel.copyWith(color: _I.ink),
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
      return BarGlyph(BarIcons.bellFill, size: glyph, color: _I.ink);
    }
    return _services.buildApplicationIcon(context, id);
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
          onToggle: () => islandTimer.toggle(_now),
          onAdd: () => islandTimer.add(const Duration(minutes: 1), _now),
          onCancel: islandTimer.cancel,
        );
      case IslandKind.recording:
        return IslandRecordingCard(
          elapsed: clockSpan(_now.difference(_recordingSince ?? _now)),
          caption: context.tr('Screen Recording'),
          onStop: () => ref.read(screenRecordingProvider.notifier).toggle(),
        );
      case IslandKind.progress:
        final id = progress.keys.firstOrNull;
        return IslandProgressCard(
          icon: _progressIcon(progress),
          name: id == null ? '' : _appLabel(id),
          value: progress.values.firstOrNull ?? 0,
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
        return IslandHomeCard(
          time: widget.timeLabel,
          date: widget.dateLabel,
          trailing: battery.capacity == null
              ? null
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      '${battery.capacity}%',
                      style: BarType.islandLabel.copyWith(color: _I.dim),
                    ),
                    const SizedBox(width: 6),
                    BatteryGlyph(
                      level: battery.capacity! / 100,
                      colour: plugged ? macGreen : _I.ink,
                      charging: plugged,
                      width: 24,
                    ),
                  ],
                ),
          actions: <IslandHomeAction>[
            if (widget.settings.activityTimer)
              for (final minutes in const <int>[5, 15, 25])
                IslandHomeAction(
                  icon: BarIcons.timer,
                  label: context.tr('{}m', minutes),
                  onTap: () => start(minutes),
                ),
            IslandHomeAction(
              icon: BarIcons.sliderHorizontal3,
              onTap: () => go(widget.onControlCenter),
            ),
            IslandHomeAction(
              icon: BarIcons.bell,
              onTap: () => go(widget.onNotifications),
            ),
            IslandHomeAction(
              icon: BarIcons.search,
              onTap: () => go(_services.toggleLauncher),
            ),
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
        return IslandChargeCard(
          percent: battery.capacity ?? 0,
          plugged: plugged,
          label: context.tr(plugged ? 'Charging' : 'On Battery'),
        );
      default:
        return IslandMediaCard(
          playback: playback,
          commands: ref.watch(_services.mediaCommands),
          coverSlot: _I.bigCover,
          padding: _I.pad,
          nothing: context.tr('Not Playing'),
        );
    }
  }
}
