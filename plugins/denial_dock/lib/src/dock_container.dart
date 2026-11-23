import 'dart:async';
import 'dart:math' as math;

import 'package:denial_flutter_sdk/applications.dart'
    show applicationRecentsProvider;
import 'package:denial_flutter_sdk/effects.dart';
import 'package:denial_flutter_sdk/input.dart';
import 'package:denial_flutter_sdk/popups.dart';
import 'package:denial_flutter_sdk/services.dart';
import 'package:denial_flutter_sdk/shell.dart';
import 'package:denial_flutter_sdk/state.dart'
    show
        appAudioProvider,
        desktopNotificationsProvider,
        shellControllerProvider;
import 'package:denial_flutter_sdk/surfaces.dart';
import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/gestures.dart'
    show GestureBinding, PointerScrollEvent, PointerSignalEvent, kPrimaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dock_autohide.dart';
import 'dock_badges.dart';
import 'dock_recents.dart';
import 'dock_drag.dart';
import 'dock_extras.dart';
import 'dock_extras_item.dart';
import 'dock_icon.dart';
import 'dock_mac_icons.dart';
import 'dock_debug.dart';
import 'dock_hotkeys.dart';
import 'dock_item.dart';
import 'dock_launcher_entry.dart';
import 'dock_launcher_entry_bus.dart';
import 'dock_layout.dart';
import 'dock_math.dart';
import 'dock_menu.dart';
import 'dock_preferences.dart';
import 'dock_scroll.dart';
import 'dock_sections.dart';
import 'dock_settings_panel.dart';
import 'dock_stack_thumbs.dart';
import 'dock_windows.dart';

/// The floating dock. Icons are laid out by [DockLayout] along the dock's main
/// axis, so the same kernel serves a bottom dock and a side dock.
///
/// Drag offsets are deltas of absolute scene positions: Denial starts a button
/// pointer at the scene origin, so gesture-local deltas cannot be trusted.
class DockContainer extends ConsumerStatefulWidget {
  const DockContainer({
    required this.monitorId,
    required this.services,
    required this.environment,
    super.key,
  });

  final int monitorId;
  final ShellServices services;
  final ShellSurfaceEnvironment environment;

  @override
  ConsumerState<DockContainer> createState() => _DockContainerState();
}

class _DockContainerState extends ConsumerState<DockContainer>
    with SingleTickerProviderStateMixin {
  static const Duration _labelDwell = Duration(milliseconds: 250);

  /// One gate for the whole dock: icons and the capsule share it, so a swipe
  /// that crosses icons still steps once.
  final DockScrollGate _scrollGate = DockScrollGate();
  static const double _baseInset = 10;

  /// Distance from the screen edge to the capsule. A bar that reserves the
  /// dock's own edge adds its thickness, so the two never share pixels.
  double _reserved = 0;
  double get _edgeInset => _baseInset + _reserved;

  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;

  /// Pointer position along the dock's main axis, in surface coordinates.
  /// Storing surface coordinates keeps the target valid while the capsule
  /// changes length under a still pointer.
  double _pointer = 0;
  double _pointerTarget = 0;
  double _hover = 0;
  double _hoverTarget = 0;
  double _reveal = 1;
  double _revealTarget = 1;

  bool _insideCapsule = false;
  bool _edgeHover = false;

  /// Counted, because two icons hold an overlay during a hand-over.
  int _overlayHolds = 0;
  bool get _overlayHold => _overlayHolds > 0;
  bool _settingsOpen = false;
  bool _menuOpen = false;
  bool _tickerScheduled = false;
  bool _conflict = false;

  /// A dock that starts retracted must not paint one revealed frame first.
  bool _bootResolved = false;

  Timer? _hideTimer;
  Timer? _revealTimer;

  bool _edgeTapHold = false;
  Timer? _edgeTapTimer;

  final OverlayPortalController _menuPortal = OverlayPortalController();
  double _menuAnchor = 0;

  /// One dwell timer gates the first name label; moving between icons keeps the
  /// visible label continuous instead of restarting the delay.
  Timer? _labelTimer;
  String? _labelKey;
  bool _labelShown = false;

  DockSettings _settings = DockSettings.defaults;
  WorkspaceStatus _workspaceStatus = WorkspaceStatus(
    count: 1,
    active: 1,
    occupied: const {},
  );

  DockLayoutFrame? _frame;

  /// The trash icon's rectangle in scene coordinates, or null when the dock
  /// hides the trash. A folder stack uses it as its drop target.
  Rect? _trashRect;
  Map<int, int> _entrySlots = const {};
  List<_LabelTarget?> _labels = const [];
  double _capsuleStart = 0;
  double _capsuleCross = _baseInset;
  double _capsuleFar = _baseInset;
  double _surfaceWidth = 0;
  double _surfaceHeight = 0;

  /// Application drag: the dragged entry key, its rest centre and the candidate
  /// insertion slot. A running, unpinned entry carries [_dragNewPin] and can be
  /// dropped among the pins. The dragged icon follows the pointer while
  /// neighbours make room, mirroring NextKDE's reorder delegate.
  String? _dragKey;
  DockPin? _dragNewPin;

  /// The entries of the last build. The drop rule reads them so it sees the
  /// application's state as it is when the pointer is released, not as it was
  /// when the drag began.
  List<_DockEntry> _builtEntries = const [];

  /// The recents section and the ids parked outside it, from the last build.
  /// Saved when they differ from the stored ones, so a slot survives a
  /// restart.
  List<String> _recentsOrder = const [];
  List<String> _parkedRecents = const [];
  bool _recentsSaveScheduled = false;
  int _dragFrom = -1;
  int _dragTo = -1;
  double _dragDx = 0;
  double _dragDy = 0;
  double _dragOriginX = 0;
  double _dragOriginY = 0;

  /// Scene position where the grab started, used to turn absolute pointer
  /// positions into a drag offset.
  double _dragStartX = 0;
  double _dragStartY = 0;
  List<double> _pinCenters = const [];

  /// Where a new pin appended after the last pinned icon would land.
  double _appendCenter = 0;

  /// After release the icon keeps following the pointer while it glides into
  /// its new slot, then the row takes over (NextKDE's settling phase).
  bool _settling = false;
  double _settleT = 0;
  Offset _settleFrom = Offset.zero;
  Offset _settleTo = Offset.zero;

  /// Icon size while a divider drag is in progress, before the write lands.
  double? _dragIconSize;
  bool _resizing = false;

  double get _iconSize => _dragIconSize ?? _settings.iconSize;
  double get _capsuleHeight => _iconSize + DockSettings.padding * 2;
  double get _halfIcon => _iconSize / 2;

  DockPosition get _position => _settings.position;
  bool get _vertical => _position != DockPosition.bottom;
  Rect get _output => widget.environment.output.logicalRect;

  bool get _held =>
      _insideCapsule ||
      _edgeHover ||
      _overlayHold ||
      _settingsOpen ||
      _menuOpen ||
      _edgeTapHold ||
      _dragKey != null;

  double get _dragCenterX => _dragOriginX + _dragDx;
  double get _dragCenterY => _dragOriginY + _dragDy;
  double get _dragLocalX => _dragCenterX - _output.left;
  double get _dragLocalY => _dragCenterY - _output.top;
  double get _dragLocalMain => _vertical ? _dragLocalY : _dragLocalX;

  bool get _dragOutside => switch (_position) {
    DockPosition.bottom =>
      _dragLocalY < _surfaceHeight - _capsuleFar - _iconSize,
    DockPosition.left => _dragLocalX > _capsuleFar + _iconSize,
    DockPosition.right => _dragLocalX < _surfaceWidth - _capsuleFar - _iconSize,
  };

  /// A running entry only joins the pins when it is dragged past the last
  /// pinned slot (plus three quarters of an icon of slack). Dragging it within
  /// the running section leaves the order alone.
  bool get _dragInPinRegion {
    final lastPin = _pinCenters.isNotEmpty ? _pinCenters.last : _appendCenter;
    return _dragLocalMain <= lastPin + _iconSize * 0.75;
  }

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    // The thumbnail index is built before a folder is opened, so the fan shows
    // previews on its first frame instead of a column of type icons, and stale
    // generated previews are dropped so the cache cannot grow without bound.
    DockStackThumbs.warm();
    DockStackThumbs.sweepCache();
    _hotkeys = DockHotkeys.requests.listen(_onHotkey);
    _debug = DockDebug.commands.listen(_onDebug);
  }

  StreamSubscription<List<String>>? _debug;

  void _onDebug(List<String> words) {
    if (!mounted || !widget.environment.isMainOutput) return;
    final number = words.length > 1 ? int.tryParse(words[1]) ?? 0 : 0;
    switch (words.first) {
      case 'settings':
        _openSettings(page: number);
      case 'click':
        _onHotkey((slot: number, monitorId: widget.monitorId));
    }
  }

  StreamSubscription<DockHotkey>? _hotkeys;

  /// The application a shortcut asked for, with a serial so the same slot can
  /// be asked for twice in a row.
  final ValueNotifier<({String key, int serial})?> _activation = ValueNotifier(
    null,
  );

  void _onHotkey(DockHotkey request) {
    final monitor = request.monitorId;
    if (monitor == null
        ? !widget.environment.isMainOutput
        : monitor != widget.monitorId) {
      return;
    }
    final entries = _builtEntries;
    if (request.slot < 1 || request.slot > entries.length) return;
    _activation.value = (
      key: appIdentity(entries[request.slot - 1].appId),
      serial: (_activation.value?.serial ?? 0) + 1,
    );
  }

  Timer? _audioTimer;

  /// The mixer answers a request and never pushes, so the speaker badge asks
  /// again every few seconds for as long as it is switched on.
  void _syncAudioPolling(bool enabled) {
    if (!enabled) {
      _audioTimer?.cancel();
      _audioTimer = null;
      return;
    }
    if (_audioTimer != null) return;
    void ask() {
      if (mounted) ref.read(appAudioProvider.notifier).refresh();
    }

    _audioTimer = Timer.periodic(const Duration(seconds: 3), (_) => ask());
    // Asking changes the provider, which a build may not do.
    SchedulerBinding.instance.addPostFrameCallback((_) => ask());
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _revealTimer?.cancel();
    _labelTimer?.cancel();
    _edgeTapTimer?.cancel();
    _audioTimer?.cancel();
    unawaited(_hotkeys?.cancel());
    unawaited(_debug?.cancel());
    _activation.dispose();
    _ticker.dispose();
    super.dispose();
  }

  void _ensureTicker() {
    if (_ticker.isActive) return;
    _lastTick = Duration.zero;
    _ticker.start();
  }

  /// Called from build, so the ticker start is deferred one frame.
  void _requestReveal(double target) {
    if ((_revealTarget - target).abs() < 0.001) return;
    _revealTarget = target;
    if (_ticker.isActive || _tickerScheduled) return;
    _tickerScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _tickerScheduled = false;
      if (mounted) _ensureTicker();
    });
    SchedulerBinding.instance.scheduleFrame();
  }

  void _onTick(Duration elapsed) {
    if (_lastTick == Duration.zero) {
      _lastTick = elapsed;
      return;
    }
    final dt = (elapsed - _lastTick).inMicroseconds / 1000000.0;
    _lastTick = elapsed;
    final pointer = DockMath.advance(
      _pointer,
      _pointerTarget,
      dt,
      // NextKDE's magnification response: the wave follows the pointer within
      // a few frames instead of trailing it.
      responseSeconds: 0.026,
    );
    final hover = DockMath.advance(
      _hover,
      _hoverTarget,
      dt,
      responseSeconds: 0.055,
    );
    final reveal = DockMath.advance(
      _reveal,
      _revealTarget,
      dt,
      responseSeconds: 0.10,
    );
    var dragDx = _dragDx;
    var dragDy = _dragDy;
    var settleFinished = false;
    if (_settling) {
      _settleT += dt / DockSettings.dragSettleSeconds;
      final t = _settleT.clamp(0.0, 1.0);
      final eased = Curves.easeOutCubic.transform(t);
      dragDx = _settleFrom.dx + (_settleTo.dx - _settleFrom.dx) * eased;
      dragDy = _settleFrom.dy + (_settleTo.dy - _settleFrom.dy) * eased;
      settleFinished = t >= 1;
    }
    final settled =
        (pointer - _pointer).abs() < 0.001 &&
        (hover - _hover).abs() < 0.001 &&
        (reveal - _reveal).abs() < 0.001 &&
        !_settling;
    setState(() {
      _pointer = pointer;
      _hover = hover;
      _reveal = reveal;
      _dragDx = dragDx;
      _dragDy = dragDy;
    });
    _syncLabel();
    if (settleFinished) _finishDrag();
    if (settled) {
      _ticker.stop();
      _lastTick = Duration.zero;
    }
  }

  void _tapEdge() {
    if (_reveal > 0.5) return;
    _revealTimer?.cancel();
    _revealTimer = null;
    _requestReveal(1);
    _ensureTicker();
    _edgeTapHold = true;
    _edgeTapTimer?.cancel();
    _edgeTapTimer = Timer(const Duration(seconds: 4), () {
      _edgeTapTimer = null;
      if (!mounted) return;
      _edgeTapHold = false;
      _evaluateHide();
    });
    _evaluateHide();
  }

  /// Hide only after a short, stable overlap; reveal as soon as the space is
  /// free. A window parked on the boundary must not make the dock flap.
  /// [ready] is false until the saved settings are in, so a dock saved as
  /// retracted opens retracted instead of flashing out and sliding back.
  void _syncConflict(bool conflict, {required bool ready}) {
    if (!_bootResolved) {
      if (!ready) return;
      _bootResolved = true;
      _conflict = conflict;
      _reveal = conflict ? 0 : 1;
      _revealTarget = _reveal;
      return;
    }
    if (_conflict == conflict) return;
    _conflict = conflict;
    _evaluateHide();
  }

  void _evaluateHide() {
    _hideTimer?.cancel();
    _hideTimer = null;
    if (!_conflict || _held) {
      // A cursor parked on the screen edge pulls the dock out only after a
      // short pause (reference: smartHideHoverShowDelay), so brushing past the
      // edge does not flash the capsule.
      if (_conflict && _edgeHover && !_insideCapsule && _revealTarget < 0.5) {
        _revealTimer ??= Timer(
          Duration(milliseconds: _settings.revealDelayMs),
          () {
            _revealTimer = null;
            if (!mounted) return;
            _requestReveal(1);
            _evaluateHide();
          },
        );
        return;
      }
      _revealTimer?.cancel();
      _revealTimer = null;
      _requestReveal(1);
      return;
    }
    _hideTimer = Timer(Duration(milliseconds: _settings.hideDelayMs), () {
      if (!mounted) return;
      if (_conflict && !_held) {
        _revealTarget = 0;
        _ensureTicker();
      }
    });
  }

  void _onHover(PointerHoverEvent event) {
    final local = _vertical ? event.localPosition.dy : event.localPosition.dx;
    _pointerTarget = _capsuleStart + local;
    _hoverTarget = 1;
    _insideCapsule = true;
    _revealTarget = 1;
    _ensureTicker();
    _syncLabel();
    _evaluateHide();
  }

  /// Wheel over the capsule background, which only sees events the icons did
  /// not claim. Switching workspaces is the only capsule-level action.
  void _onCapsuleScroll(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final settings = _settings;
    if (settings.scrollAction != DockScrollAction.switchWorkspace) return;
    final status = _workspaceStatus;
    if (status.count <= 1) return;
    final step = _scrollGate.feed(
      event.scrollDelta.dy,
      event.timeStamp.inMilliseconds,
    );
    if (step == null) return;
    final direction = settings.scrollReversed ? -step : step;
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      final target = nextWorkspace(
        count: status.count,
        active: status.active,
        step: direction,
        wrap: settings.scrollWraps,
      );
      if (target == null) return;
      widget.services.switchWorkspace(
        monitorId: widget.monitorId,
        workspaceId: target,
      );
    });
  }

  void _onExit(PointerExitEvent event) {
    _insideCapsule = false;
    _hoverTarget = 0;
    _ensureTicker();
    _syncLabel();
    _evaluateHide();
  }

  void _onEdgeEnter(PointerEnterEvent event) {
    if (_edgeHover) return;
    _edgeHover = true;
    _evaluateHide();
  }

  void _onEdgeExit(PointerExitEvent event) {
    _revealTimer?.cancel();
    _revealTimer = null;
    if (!_edgeHover) return;
    _edgeHover = false;
    _evaluateHide();
  }

  void _setOverlayHold(bool hold) {
    final was = _overlayHold;
    _overlayHolds = math.max(0, _overlayHolds + (hold ? 1 : -1));
    if (was == _overlayHold) return;
    _syncLabel();
    _evaluateHide();
  }

  /// The icon whose preview stack is open. Only the stack style follows the
  /// pointer, so only it needs an owner.
  String? _previewOwner;

  void _setPreviewOwner(String? appId) {
    if (_previewOwner == appId) return;
    setState(() => _previewOwner = appId);
  }

  /// The label appears after a 250 ms dwell on the same slot. Once visible it
  /// follows the pointer between icons without restarting the delay, which is
  /// what makes sliding along the row readable.
  void _syncLabel() {
    // A name bubble under a menu or a window preview only repeats what the
    // overlay already says, and it sits between the icon and the panel.
    final key = _dragKey == null && !_overlayHold && _hover >= 0.2
        ? _currentLabelKey()
        : null;
    if (key == _labelKey) {
      if (key == null && _labelShown) {
        setState(() => _labelShown = false);
      }
      return;
    }
    _labelKey = key;
    _labelTimer?.cancel();
    _labelTimer = null;
    if (key == null) {
      if (_labelShown) setState(() => _labelShown = false);
      return;
    }
    if (_labelShown) return;
    final expected = key;
    _labelTimer = Timer(_labelDwell, () {
      _labelTimer = null;
      if (!mounted || _labelKey != expected) return;
      setState(() => _labelShown = true);
    });
  }

  String? _currentLabelKey() {
    final frame = _frame;
    if (frame == null) return null;
    final nearest = frame.nearest(_pointer);
    if (nearest == null) return null;
    final (index, slot, distance) = nearest;
    if (distance > slot.half + 20) return null;
    final label = index < _labels.length ? _labels[index] : null;
    return label?.key;
  }

  void _openDockMenu(double surfaceMain) {
    if (_menuOpen) {
      _closeDockMenu();
      return;
    }
    _menuAnchor = surfaceMain;
    _menuOpen = true;
    _menuPortal.show();
    setState(() {});
    _evaluateHide();
  }

  void _closeDockMenu() {
    if (!_menuOpen) return;
    _menuPortal.hide();
    _menuOpen = false;
    setState(() {});
    _evaluateHide();
  }

  /// The settings sheet is a managed shell popup, not an OverlayPortal menu, so
  /// it keeps its own hold: without it the capsule retracts behind the sheet
  /// when a window is parked on the dock strip.
  void _openSettings({int page = 0}) {
    if (_settingsOpen) return;
    _closeDockMenu();
    _settingsOpen = true;
    _evaluateHide();
    ref
        .read(shellPopupControllerProvider.notifier)
        .show(
          keyName: 'denial_dock.settings',
          debugLabel: 'Dock settings',
          dismissPolicy: ShellDismissPolicy.outsideTapAndEscape,
          builder: (context, handle) =>
              DockSettingsPanel(onClose: handle.close, initialPage: page),
        );
    // The handle has no completion callback; poll the popup list so the hold is
    // released once the sheet has finished its closing transition.
    Timer.periodic(const Duration(milliseconds: 120), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final open = ref
          .read(shellPopupControllerProvider)
          .any((popup) => popup.keyName == 'denial_dock.settings');
      if (open) return;
      timer.cancel();
      if (!mounted) return;
      _settingsOpen = false;
      _evaluateHide();
    });
  }

  void _startDrag(
    _DockEntry entry,
    int entryIndex,
    int pinIndex,
    Offset pointer,
  ) {
    if (_dragKey != null) return;
    final slotIndex = _entrySlots[entryIndex];
    final slot = slotIndex == null ? null : _frame?.slots[slotIndex];
    _dragKey = appIdentity(entry.appId);
    _dragNewPin = entry.pin == null
        ? DockPin(
            id: entry.launchId ?? entry.appId,
            appId: entry.appId,
            name: entry.name,
          )
        : null;
    _dragFrom = entry.pin == null ? -1 : pinIndex;
    _dragTo = _dragFrom;
    _dragDx = 0;
    _dragDy = 0;
    final mainCenter = slot?.center ?? _capsuleStart;
    final crossCenter = _capsuleCross + DockSettings.padding + _halfIcon;
    _dragOriginX = switch (_position) {
      DockPosition.bottom => _output.left + mainCenter,
      DockPosition.left => _output.left + crossCenter,
      DockPosition.right => _output.right - crossCenter,
    };
    _dragOriginY = switch (_position) {
      DockPosition.bottom => _output.top + _surfaceHeight - crossCenter,
      _ => _output.top + mainCenter,
    };
    // Denial starts the button pointer at the scene origin, so a grab that
    // reports (0,0) is anchored on the icon instead of the screen corner.
    final grabIsPlausible = _output.contains(pointer);
    _dragStartX = grabIsPlausible ? pointer.dx : _dragOriginX;
    _dragStartY = grabIsPlausible ? pointer.dy : _dragOriginY;
    _hoverTarget = 0;
    _hover = 0;
    _pointerTarget = -10000;
    _pointer = -10000;
    _insideCapsule = false;
    _syncLabel();
    setState(() {});
    _ensureTicker();
    _evaluateHide();
  }

  void _updateDrag(Offset pointer) {
    if (_dragKey == null) return;
    if (!pointer.dx.isFinite || !pointer.dy.isFinite) return;
    // The button pointer emits a stray move at the scene origin; a real dock
    // drag never visits that corner.
    if (pointer.dx == 0 && pointer.dy == 0) return;
    setState(() {
      _dragDx = pointer.dx - _dragStartX;
      _dragDy = pointer.dy - _dragStartY;
      _refreshDragTarget();
    });
  }

  /// Omarchy waits for 6 px of travel along the dock before a drag starts
  /// reordering, so a press that wobbles keeps the icon where it is.
  static const double _reorderSlop = 6.0;

  void _refreshDragTarget() {
    if (_dragKey == null || _pinCenters.isEmpty) return;
    final travel = _vertical ? _dragDy : _dragDx;
    if (travel.abs() < _reorderSlop) {
      _dragTo = _dragFrom;
      return;
    }
    final centers = [..._pinCenters, _appendCenter];
    final index = DockDrag.insertionIndex(
      centers: centers,
      pointerX: _dragLocalMain,
      fallback: _dragFrom < 0 ? 0 : _dragFrom,
    );
    _dragTo = _dragFrom < 0 && !_dragInPinRegion ? -1 : index;
  }

  /// Pins as they would look at the current drop position. A pinned source is
  /// moved; a running source is shown inserted at the drop slot.
  List<DockPin> _displayPins(List<DockPin> pins) {
    final to = _dragTo;
    if (to < 0) return pins;
    if (_dragFrom >= 0) return DockDrag.moved(pins, _dragFrom, to);
    final newPin = _dragNewPin;
    return newPin == null ? pins : DockDrag.inserted(pins, newPin, to);
  }

  void _endDrag() {
    if (_dragKey == null || _settling) return;
    final key = _dragKey!;
    final from = _dragFrom;
    final to = _dragTo;
    final outside = _dragOutside;
    if (!outside) {
      // The pointer is still over the capsule after release, but no new enter
      // event will arrive; keep the dock awake under it.
      _insideCapsule = true;
      _pointerTarget = _dragLocalMain;
      _pointer = _dragLocalMain;
      _ensureTicker();
    }

    DockPin? pin;
    final pins = _settings.pinned;
    for (final candidate in pins) {
      if (appIdentity(candidate.appId) == key) {
        pin = candidate;
        break;
      }
    }
    final notifier = ref.read(dockSettingsProvider.notifier);

    final newPin = _dragNewPin;
    if (outside) {
      _DockEntry? entry;
      for (final candidate in _builtEntries) {
        if (appIdentity(candidate.appId) == key) {
          entry = candidate;
          break;
        }
      }
      // Dragging out drops a pin, or dismisses a suggestion whose app is not
      // running. A running app stays: the dock is the only way back to its
      // windows, so dropping it here must not lose them. The entry is read
      // here, at release, so a launch that happened mid-drag counts.
      switch (DockDrag.removalFor(
        pinned: pin != null,
        suggestion: entry?.suggestion ?? false,
        running: entry?.windows.isNotEmpty ?? false,
        outside: true,
      )) {
        case DockRemoval.unpin:
          unawaited(notifier.togglePin(pin!, pinned: false));
        case DockRemoval.dismissRecent:
          unawaited(notifier.removeRecent(key));
        case DockRemoval.none:
          break;
      }
      _finishDrag();
      return;
    }
    if (newPin != null) {
      if (to < 0) {
        _finishDrag();
        return;
      }
      unawaited(notifier.insertPin(newPin, to));
      _beginSettle(to);
      return;
    }
    if (pin == null || to < 0 || to == from) {
      _finishDrag();
      return;
    }
    unawaited(notifier.movePin(from, to));
    _beginSettle(to);
  }

  /// Commit the order, then glide the source from its release position into the
  /// slot it now occupies; the row keeps a gap there until the glide lands, so
  /// the icon never jumps back to its old slot.
  void _beginSettle(int to) {
    final target = to < _pinCenters.length ? _pinCenters[to] : _appendCenter;
    _settleFrom = Offset(_dragDx, _dragDy);
    _settleTo = _vertical
        ? Offset(0, _output.top + target - _dragOriginY)
        : Offset(_output.left + target - _dragOriginX, 0);
    _settleT = 0;
    _settling = true;
    setState(() {});
    _ensureTicker();
    _evaluateHide();
  }

  void _finishDrag() {
    if (_dragKey == null) return;
    _settling = false;
    _settleT = 0;
    _dragKey = null;
    _dragNewPin = null;
    _dragFrom = -1;
    _dragTo = -1;
    _dragDx = 0;
    _dragDy = 0;
    _hoverTarget = _insideCapsule ? 1 : 0;
    setState(() {});
    _ensureTicker();
    _evaluateHide();
  }

  /// Closes windows through the compositor's close request. The dock lists
  /// [ApplicationWindow]s, whose `id` is the compositor's `objectId`, so the
  /// matching shell window is what the controller accepts.
  void _closeWindows(List<int> objectIds) {
    final wanted = objectIds.toSet();
    final windows = ref.read(userAppWindowsProvider);
    final controller = ref.read(shellControllerProvider.notifier);
    for (final window in windows) {
      if (wanted.contains(window.objectId)) controller.closeWindow(window);
    }
  }

  void _togglePin(_DockEntry entry) {
    final notifier = ref.read(dockSettingsProvider.notifier);
    final pin = entry.pin;
    if (pin != null) {
      unawaited(notifier.togglePin(pin, pinned: false));
    } else {
      unawaited(
        notifier.togglePin(
          DockPin(
            id: entry.launchId ?? entry.appId,
            appId: entry.appId,
            name: entry.name,
          ),
          pinned: true,
        ),
      );
    }
  }

  List<_DockEntry> _entries(
    DockSettings settings,
    List<LaunchableApplication> catalog,
    List<ApplicationWindow> windows,
    List<DockPin>? pinnedOrder,
    List<String> recents,
  ) {
    final byId = <String, LaunchableApplication>{};
    for (final app in catalog) {
      byId[appIdentity(app.id)] = app;
      byId[appIdentity(app.appId)] = app;
      for (final windowId in app.windowAppIds) {
        byId[appIdentity(windowId)] = app;
      }
    }

    final windowsByApp = <String, List<ApplicationWindow>>{};
    final appByGroup = <String, LaunchableApplication?>{};
    for (final window in windows) {
      final app = byId[appIdentity(window.appId)];
      final key = app == null ? appIdentity(window.appId) : appIdentity(app.id);
      windowsByApp.putIfAbsent(key, () => []).add(window);
      appByGroup[key] ??= app;
    }

    final entries = <_DockEntry>[];
    final seen = <String>{};
    for (final pin in pinnedOrder ?? settings.pinned) {
      final app = byId[appIdentity(pin.appId)] ?? byId[appIdentity(pin.id)];
      final key = app == null ? appIdentity(pin.appId) : appIdentity(app.id);
      if (!seen.add(key)) continue;
      entries.add(
        _DockEntry(
          appId: app?.appId ?? pin.appId,
          launchId: app?.id ?? (pin.id.isEmpty ? null : pin.id),
          name: app?.name ?? pin.name,
          windows: windowsByApp[key] ?? const [],
          pin: pin,
        ),
      );
    }
    // The unpinned section keeps its own membership, oldest first. A new app
    // joins at the end and holds that slot after it quits, so the row only
    // moves when a launch outgrows the limit and the oldest closed slot leaves.
    final running = <String>{};
    for (final key in windowsByApp.keys) {
      if (seen.contains(key)) continue;
      final app = byId[key];
      running.add(app == null ? key : appIdentity(app.id));
    }
    final removed = settings.dismissedSuggestions.toSet();
    final count = settings.showSuggestions ? settings.recentCount : 0;
    final resolved = DockRecents.resolve(
      order: settings.recentsOrder,
      parked: settings.parkedRecents,
      running: running,
      recent: recents.reversed.map(_recentAppId),
      count: count,
      removed: removed,
    );
    _recentsOrder = resolved.members;
    _parkedRecents = resolved.parked;

    for (final key in resolved.shown) {
      if (!seen.add(key)) continue;
      final group = windowsByApp[key];
      final app = byId[key] ?? appByGroup[key];
      final windowsHere = group ?? const <ApplicationWindow>[];
      if (windowsHere.isEmpty && app == null) continue;
      entries.add(
        _DockEntry(
          appId: app?.appId ?? windowsHere.first.appId,
          launchId: app?.id ?? windowsHere.firstOrNull?.appId,
          name: app?.name ?? windowsHere.first.title,
          windows: windowsHere,
          pin: null,
          suggestion: windowsHere.isEmpty,
        ),
      );
    }
    return entries;
  }

  /// `desktop:foo.desktop` and `local:foo` both reduce to the app id the
  /// catalog is keyed by.
  static String _recentAppId(String recent) => appIdentity(recent);

  List<_SlotSpec> _specsFor(List<_DockEntry> entries, DockSettings settings) {
    final sections = DockSections.build(
      entryCount: entries.length,
      isPinned: (index) => entries[index].pinned,
      settings: settings,
    );
    return [
      for (final section in sections)
        _SlotSpec(
          kind: switch (section.kind) {
            DockSlotKind.app => _SlotKind.app,
            DockSlotKind.launcher => _SlotKind.launcher,
            DockSlotKind.folder => _SlotKind.folder,
            DockSlotKind.file => _SlotKind.file,
            DockSlotKind.trash => _SlotKind.trash,
            DockSlotKind.divider => _SlotKind.divider,
          },
          half: section.kind == DockSlotKind.divider ? 0.5 : _iconSize / 2,
          entry: section.index,
          folder: section.folder,
          file: section.file,
          dividerKey: section.dividerKey,
        ),
    ];
  }

  /// Persists a recents section that changed this build. The write is skipped
  /// when the stored lists already match, so an idle dock never touches the
  /// file.
  void _saveRecentsOrder(DockSettings settings, {required bool ready}) {
    final order = _recentsOrder;
    final parked = _parkedRecents;
    // Before the file is read, `settings` is the default value and its empty
    // order would look like a change worth saving.
    if (!ready) return;
    if (_sameOrder(settings.recentsOrder, order) &&
        _sameOrder(settings.parkedRecents, parked)) {
      return;
    }
    if (_recentsSaveScheduled) return;
    _recentsSaveScheduled = true;
    // Deferred out of build: the notifier's state change would rebuild the
    // dock mid-frame.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _recentsSaveScheduled = false;
      if (!mounted) return;
      unawaited(
        ref
            .read(dockSettingsProvider.notifier)
            .setRecentsOrder(_recentsOrder, _parkedRecents),
      );
    });
  }

  static bool _sameOrder(List<String> first, List<String> second) {
    if (first.length != second.length) return false;
    for (var i = 0; i < first.length; i++) {
      if (first[i] != second[i]) return false;
    }
    return true;
  }

  DockLayoutFrame _layout(
    double surfaceExtent,
    List<_SlotSpec> specs, {
    required double hover,
  }) => DockLayout.compute(
    surfaceExtent: surfaceExtent,
    slots: [
      for (final spec in specs)
        DockSlot(half: spec.half, growable: spec.growable),
    ],
    padding: DockSettings.edgePadding,
    gap: DockSettings.gap,
    pointer: _pointer,
    hover: hover,
    maxScale: _settings.effectiveMaxScale,
    radius: DockSettings.magnificationRadius,
  );

  @override
  Widget build(BuildContext context) {
    final storedSettings = ref.watch(dockSettingsProvider);
    final settings = storedSettings.value ?? DockSettings.defaults;
    _settings = settings;
    if (_dragIconSize != null &&
        (_dragIconSize! - settings.iconSize).abs() < 0.5) {
      _dragIconSize = null;
    }
    final catalog = ref.watch(widget.services.applications);
    final allWindows = ref.watch(widget.services.windows(widget.monitorId));
    final denialWindows = ref.watch(userAppWindowsProvider);
    final windows = settings.currentWorkspaceOnly
        ? DockWindows.onWorkspace(
            allWindows,
            idOf: (window) => window.id,
            workspaceById: {
              for (final window in denialWindows)
                window.objectId: window.workspaceId,
            },
            workspace: widget.environment.workspaceId,
          )
        : allWindows;
    _reserved = settings.avoidReservedEdge
        ? DockAutoHide.reservedEdge(
            output: _output,
            workArea: widget.environment.workArea,
            position: settings.position,
          )
        : 0;
    final launcherEntries =
        settings.showBadges || settings.showProgress || settings.showAttention
        ? ref.watch(launcherEntriesProvider)
        : const <String, LauncherEntry>{};
    _syncAudioPolling(settings.showAudioIndicator);
    // A line per stream, so a poll that changes nothing rebuilds nothing.
    final audio = settings.showAudioIndicator
        ? ref.watch(
            appAudioProvider.select(
              (state) => [
                for (final stream in state.streams)
                  '${stream.muted || stream.level <= 0 ? 1 : 0}${stream.name}',
              ].join('\n'),
            ),
          )
        : '';
    final recents = ref.watch(applicationRecentsProvider);
    _workspaceStatus = ref.watch(widget.services.workspace(widget.monitorId));
    final environment = widget.environment;
    final theme = context.shellTheme;
    final colors = theme.colors;
    final chinese = Localizations.localeOf(context).languageCode == 'zh';
    final launcherLabel = chinese ? '启动台' : 'Launcher';

    final baseEntries = _entries(settings, catalog, windows, null, recents);
    final baseSpecs = _specsFor(baseEntries, settings);
    final badges = settings.showBadges
        ? DockBadges.counts(
            ref
                .watch(desktopNotificationsProvider)
                .history
                .map(
                  (record) => (
                    desktopEntry: record.notification.desktopEntry,
                    appName: record.notification.appName,
                    unread: record.unread,
                  ),
                ),
            baseEntries.map(
              (entry) => (
                key: appIdentity(entry.appId),
                appId: entry.appId,
                launchId: entry.launchId,
                name: entry.name,
              ),
            ),
          )
        : const <String, int>{};

    return LayoutBuilder(
      builder: (context, constraints) {
        _surfaceWidth = constraints.maxWidth;
        _surfaceHeight = constraints.maxHeight;
        final surfaceMain = _vertical ? _surfaceHeight : _surfaceWidth;
        var entries = baseEntries;
        var specs = baseSpecs;
        if (_dragKey != null && !_settling && _dragTo >= 0) {
          final displayPins = _displayPins(settings.pinned);
          entries = _entries(settings, catalog, windows, displayPins, recents);
          specs = _specsFor(entries, settings);
        }
        _builtEntries = entries;
        _saveRecentsOrder(settings, ready: !storedSettings.isLoading);

        final frame = _layout(
          surfaceMain,
          specs,
          hover: _dragKey == null ? _hover : 0,
        );
        _frame = frame;
        _capsuleStart = frame.capsuleStart;
        _entrySlots = {
          for (var i = 0; i < specs.length; i++) ?specs[i].entry: i,
        };
        _labels = [
          for (var i = 0; i < specs.length; i++)
            _labelForSlot(specs, i, entries, launcherLabel, chinese),
        ];
        final hideOffset = (1 - _reveal) * (_capsuleHeight + 14 + _edgeInset);
        _capsuleCross = _edgeInset - hideOffset;
        _capsuleFar = _capsuleCross + _capsuleHeight;
        _trashRect = _trashSlotRect(specs, frame);

        // Collision uses the rectangle the dock would occupy at full reveal,
        // never the animated one, so a retracted dock still reports the space
        // it claims and a window parked there does not make it flap.
        final dockRect = DockAutoHide.visibleDockRect(
          output: _output,
          position: _position,
          extent: frame.extent,
          thickness: _capsuleHeight,
          inset: _edgeInset,
        );
        final conflict = DockAutoHide.hasConflict(
          windows: denialWindows,
          trigger: DockAutoHide.intentionalOverlap(
            dockRect,
            position: _position,
          ),
          release: dockRect,
          previousConflict: _conflict,
          monitorId: widget.monitorId,
          workspaceId: environment.workspaceId,
          output: environment.output,
          desktopVisible: environment.desktopVisible,
          scope: settings.hideScope,
          activeIds: {
            for (final window in allWindows)
              if (window.active) window.id,
          },
        );
        _syncConflict(
          DockVisibility.wantsHidden(
            mode: settings.visibility,
            conflict: conflict,
          ),
          ready: !storedSettings.isLoading,
        );

        if (_dragKey != null) {
          final baseFrame = _layout(surfaceMain, baseSpecs, hover: 0);
          final pinCenters = [
            for (var i = 0; i < baseSpecs.length; i++)
              if (baseSpecs[i].kind == _SlotKind.app &&
                  baseEntries[baseSpecs[i].entry!].pinned)
                baseFrame.slots[i].center,
          ];
          // The last centre is where a new pin at the end would land, so a
          // running entry can be dropped after every existing pin.
          final firstApp = _firstAppCenter(baseFrame, baseSpecs);
          final appendCenter = pinCenters.isNotEmpty
              ? pinCenters.last + _iconSize + DockSettings.gap
              : firstApp ??
                    baseFrame.capsuleStart +
                        DockSettings.edgePadding +
                        _halfIcon;
          _pinCenters = pinCenters;
          _appendCenter = appendCenter;
          _refreshDragTarget();
        }

        final labelIndex = _labelShown ? _indexForKey(_labelKey) : null;
        final label = labelIndex == null ? null : _labels[labelIndex];
        final labelSlot = labelIndex == null ? null : frame.slots[labelIndex];
        final labelLift = labelSlot == null
            ? 0.0
            : (labelSlot.scale - 1.0) * _iconSize * DockSettings.liftRatio;
        final bubble = label == null
            ? null
            : _DockLabelBubble(
                text: label.name,
                iconSize: _iconSize * (labelSlot?.scale ?? 1.0),
                // A caption over a bright wallpaper needs a solid ground; the
                // panel's own translucency leaves the text fighting whatever
                // is behind it.
                background: theme
                    .panelColor(colors.surfaceContainer)
                    .withValues(alpha: 0.94),
                border: colors.hairline,
                foreground: colors.textPrimary,
                horizontal: _vertical,
                tailLeading: _position == DockPosition.left,
              );
        final nameLabel = bubble == null
            ? null
            : switch (_position) {
                DockPosition.bottom => Positioned(
                  left: (label!.center - 110).clamp(
                    12.0,
                    math.max(12.0, _surfaceWidth - 232.0),
                  ),
                  bottom:
                      _capsuleCross +
                      DockSettings.padding +
                      (labelSlot?.half ?? _halfIcon) * 2 +
                      labelLift +
                      6,
                  width: 220,
                  child: IgnorePointer(child: Center(child: bubble)),
                ),
                DockPosition.left => Positioned(
                  left: _capsuleFar + 10,
                  top: (label!.center - 14).clamp(
                    8.0,
                    math.max(8.0, _surfaceHeight - 36.0),
                  ),
                  width: 220,
                  child: IgnorePointer(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: bubble,
                    ),
                  ),
                ),
                DockPosition.right => Positioned(
                  right: _capsuleFar + 10,
                  top: (label!.center - 14).clamp(
                    8.0,
                    math.max(8.0, _surfaceHeight - 36.0),
                  ),
                  width: 220,
                  child: IgnorePointer(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: bubble,
                    ),
                  ),
                ),
              };

        _DockEntry? dragEntry;
        for (final entry in entries) {
          if (appIdentity(entry.appId) == _dragKey) {
            dragEntry = entry;
            break;
          }
        }
        final willRemove =
            DockDrag.removalFor(
              pinned: dragEntry?.pinned ?? false,
              suggestion: dragEntry?.suggestion ?? false,
              running: dragEntry?.windows.isNotEmpty ?? false,
              outside: _dragOutside,
            ) !=
            DockRemoval.none;

        return OverlayPortal.overlayChildLayoutBuilder(
          controller: _menuPortal,
          overlayChildBuilder: (context, layout) => _menuOpen
              ? _buildDockMenu(context, layout)
              : const SizedBox.shrink(),
          child: Stack(
            fit: StackFit.expand,
            clipBehavior: Clip.none,
            children: [
              _placeInSurface(
                main: _capsuleStart,
                cross: _capsuleCross,
                mainExtent: frame.extent,
                crossExtent: _capsuleHeight,
                child: ShellInputRegion(
                  debugLabel: 'Dock capsule',
                  active: _reveal > 0.5,
                  child: MouseRegion(
                    onHover: _onHover,
                    onExit: _onExit,
                    child: Listener(
                      onPointerSignal: _onCapsuleScroll,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned.fill(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onSecondaryTapDown: (details) => _openDockMenu(
                                _capsuleStart +
                                    (_vertical
                                        ? details.localPosition.dy
                                        : details.localPosition.dx),
                              ),
                              child: _capsuleSurface(context, theme),
                            ),
                          ),
                          for (var i = 0; i < specs.length; i++)
                            if (_slotChild(
                                  context,
                                  spec: specs[i],
                                  slot: frame.slots[i],
                                  entries: entries,
                                  badges: badges,
                                  launcherEntries: launcherEntries,
                                  audio: audio,
                                  dragging: _dragKey != null,
                                  launcherLabel: launcherLabel,
                                  settings: settings,
                                  tintColor: dockTintColor(
                                    settings.tintColor,
                                    theme.accent,
                                  ),
                                  chinese: chinese,
                                )
                                case final Widget child)
                              child,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (dragEntry != null)
                Positioned(
                  left: _dragLocalX - _iconSize * 0.55,
                  top: _dragLocalY - _iconSize * 0.55,
                  width: _iconSize * 1.1,
                  height: _iconSize * 1.1,
                  child: IgnorePointer(
                    // The dragged source lifts off the dock: it grows slightly
                    // and turns translucent while held, as in the reference.
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.0, end: 1.0),
                      duration: const Duration(milliseconds: 120),
                      curve: Curves.easeOutCubic,
                      builder: (context, t, child) => Transform.scale(
                        scale: 1 + 0.10 * t,
                        child: Opacity(
                          opacity: (1 - 0.12 * t) * (willRemove ? 0.55 : 1),
                          child: child,
                        ),
                      ),
                      child: DockIcon(
                        mode: settings.iconMode,
                        opacity: settings.iconOpacity,
                        accent: dockTintColor(settings.tintColor, theme.accent),
                        child: widget.services.buildApplicationIcon(
                          context,
                          dragEntry.appId,
                        ),
                      ),
                    ),
                  ),
                ),
              if (dragEntry != null && willRemove)
                // The icon has left the row and letting go will drop it, so
                // the dock says so instead of leaving the user to guess.
                Positioned(
                  left: (_dragLocalX - 60).clamp(
                    8.0,
                    math.max(8.0, _surfaceWidth - 128.0),
                  ),
                  top: _vertical
                      ? (_dragLocalY + _iconSize * 0.75).clamp(
                          8.0,
                          math.max(8.0, _surfaceHeight - 48.0),
                        )
                      : (_dragLocalY - _iconSize * 1.15).clamp(
                          8.0,
                          math.max(8.0, _surfaceHeight - 48.0),
                        ),
                  width: 120,
                  child: IgnorePointer(
                    child: Center(
                      child: _DockLabelBubble(
                        text: chinese ? '移除' : 'Remove',
                        iconSize: _iconSize,
                        background: theme.panelColor(
                          colors.performanceWarning.withValues(alpha: 0.92),
                        ),
                        border: colors.hairline,
                        foreground: colors.textPrimary,
                        horizontal: _vertical,
                        tailLeading: _position == DockPosition.left,
                      ),
                    ),
                  ),
                ),
              ?nameLabel,
              _placeInSurface(
                main: 0,
                cross: _reserved,
                mainExtent: surfaceMain,
                // Beside a bar the pointer cannot rest on the screen edge, so
                // the strip is thick enough to stop on.
                crossExtent: math.max(
                  _reserved > 0 ? 10 : 4,
                  _capsuleCross - _reserved,
                ),
                child: ShellInputRegion(
                  debugLabel: 'Dock reveal edge',
                  child: MouseRegion(
                    onEnter: _onEdgeEnter,
                    onExit: _onEdgeExit,
                    child: Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: (_) => _tapEdge(),
                      child: ColoredBox(
                        color: const Color(0x00000000),
                        child: settings.revealIndicator && _reveal < 0.5
                            ? _revealHandle(theme)
                            : const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// A short bar on the screen edge while the dock is retracted, so a hidden
  /// dock still shows where it lives.
  Widget _revealHandle(ShellThemeData theme) => Align(
    alignment: switch (_position) {
      DockPosition.bottom => Alignment.bottomCenter,
      DockPosition.left => Alignment.centerLeft,
      DockPosition.right => Alignment.centerRight,
    },
    child: Padding(
      padding: const EdgeInsets.all(2),
      child: SizedBox(
        width: _vertical ? 4 : _iconSize * 1.6,
        height: _vertical ? _iconSize * 1.6 : 4,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colors.textPrimary.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    ),
  );

  /// Places a box on the dock's axis: [main] runs along the row, [cross] is
  /// the distance from the screen edge the dock is attached to.
  Widget _placeInSurface({
    required double main,
    required double cross,
    required double mainExtent,
    required double crossExtent,
    required Widget child,
  }) => switch (_position) {
    DockPosition.bottom => Positioned(
      left: main,
      bottom: cross,
      width: mainExtent,
      height: crossExtent,
      child: child,
    ),
    DockPosition.left => Positioned(
      left: cross,
      top: main,
      width: crossExtent,
      height: mainExtent,
      child: child,
    ),
    DockPosition.right => Positioned(
      right: cross,
      top: main,
      width: crossExtent,
      height: mainExtent,
      child: child,
    ),
  };

  Widget _buildDockMenu(BuildContext context, OverlayChildLayoutInfo layout) {
    final theme = context.shellTheme;
    final chinese = Localizations.localeOf(context).languageCode == 'zh';
    final anchor = MatrixUtils.transformRect(
      layout.childPaintTransform,
      Offset.zero & layout.childSize,
    );
    final scene = Offset.zero & layout.overlaySize;
    final onOutput = anchor.intersect(scene);
    final visible = onOutput.isEmpty ? scene : onOutput;
    final width = math.min(248.0, math.max(0.0, visible.width - 16));
    final capsuleTopScene = anchor.top + _surfaceHeight - _capsuleFar;
    final capsuleLeftScene = _position == DockPosition.right
        ? anchor.left + _surfaceWidth - _capsuleFar
        : anchor.left + _capsuleCross;
    final capsuleRightScene = _position == DockPosition.right
        ? anchor.left + _surfaceWidth - _capsuleCross
        : anchor.left + _capsuleFar;
    final menuAnchorRect = switch (_position) {
      DockPosition.bottom => Rect.fromLTWH(
        anchor.left + _menuAnchor,
        capsuleTopScene,
        1,
        1,
      ),
      DockPosition.left => Rect.fromLTWH(
        capsuleRightScene,
        anchor.top + _menuAnchor,
        0,
        0,
      ),
      DockPosition.right => Rect.fromLTWH(
        capsuleLeftScene,
        anchor.top + _menuAnchor,
        0,
        0,
      ),
    };
    final placement = dockMenuAnchor(
      anchor: menuAnchorRect,
      output: visible,
      width: width,
      position: _position,
    );
    if (placement == null) return const SizedBox.shrink();
    final smart = _settings.visibility == DockVisibilityMode.smart;
    final magnifies = _settings.magnification;
    final maxHeight = _position == DockPosition.bottom
        ? math.max(0.0, capsuleTopScene - visible.top - 16)
        : math.max(0.0, visible.height - 16);
    return ShellInputRegion(
      debugLabel: 'Dock menu',
      pointerPolicy: ShellPointerPolicy.fullScene,
      keyboardPolicy: ShellKeyboardPolicy.capture,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): _closeDockMenu,
        },
        child: Focus(
          autofocus: true,
          child: Stack(
            children: [
              Positioned.fill(
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (_) => _closeDockMenu(),
                  child: const ColoredBox(color: Color(0x00000000)),
                ),
              ),
              DockMenuLayer(
                anchor: placement,
                overlaySize: layout.overlaySize,
                child: DockMenuPanel(
                  radius: theme.borderRadius(14),
                  maxHeight: maxHeight,
                  tail: placement.tail,
                  tailAlignment: placement.tailAlignment,
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          DockMenuRow(
                            icon: smart
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            label: smart
                                ? (chinese ? '关闭隐藏' : 'Turn Hiding Off')
                                : (chinese ? '启用隐藏' : 'Turn Hiding On'),
                            onTap: () {
                              _closeDockMenu();
                              unawaited(
                                ref
                                    .read(dockSettingsProvider.notifier)
                                    .setVisibility(
                                      smart
                                          ? DockVisibilityMode.always
                                          : DockVisibilityMode.smart,
                                    ),
                              );
                            },
                          ),
                          DockMenuRow(
                            icon: magnifies ? Icons.zoom_out : Icons.zoom_in,
                            label: magnifies
                                ? (chinese ? '关闭放大' : 'Turn Magnification Off')
                                : (chinese ? '开启放大' : 'Turn Magnification On'),
                            onTap: () {
                              _closeDockMenu();
                              unawaited(
                                ref
                                    .read(dockSettingsProvider.notifier)
                                    .setMagnification(
                                      magnification: !magnifies,
                                    ),
                              );
                            },
                          ),
                          const DockMenuSeparator(),
                          DockMenuSubmenuRow(
                            icon: Icons.open_with,
                            label: chinese ? '置于屏幕上的位置' : 'Position on Screen',
                            submenu: (context) => Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (final option in DockPosition.values)
                                  DockMenuRow(
                                    icon: switch (option) {
                                      DockPosition.left =>
                                        Icons.align_horizontal_left,
                                      DockPosition.bottom =>
                                        Icons.vertical_align_bottom,
                                      DockPosition.right =>
                                        Icons.align_horizontal_right,
                                    },
                                    label: switch (option) {
                                      DockPosition.left =>
                                        chinese ? '左边' : 'Left',
                                      DockPosition.bottom =>
                                        chinese ? '底部' : 'Bottom',
                                      DockPosition.right =>
                                        chinese ? '右边' : 'Right',
                                    },
                                    selected: _position == option,
                                    onTap: () {
                                      _closeDockMenu();
                                      unawaited(
                                        ref
                                            .read(dockSettingsProvider.notifier)
                                            .setPosition(option),
                                      );
                                    },
                                  ),
                              ],
                            ),
                          ),
                          const DockMenuSeparator(),
                          DockMenuRow(
                            icon: Icons.tune,
                            label: chinese ? '程序坞设置…' : 'Dock Settings…',
                            onTap: _openSettings,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Where the trash icon sits on screen, for the folder stack's drop target.
  /// A hidden trash returns null rather than a stale rectangle.
  Rect? _trashSlotRect(List<_SlotSpec> specs, DockLayoutFrame frame) {
    for (var i = 0; i < specs.length; i++) {
      if (specs[i].kind != _SlotKind.trash) continue;
      final slot = frame.slots[i];
      final extent = slot.half * 2;
      // The slot's near edge, measured from the dock's own edge inward.
      final near = _capsuleCross + DockSettings.padding;
      return switch (_position) {
        DockPosition.bottom => Rect.fromLTWH(
          _output.left + slot.center - slot.half,
          _output.top + _surfaceHeight - near - extent,
          extent,
          extent,
        ),
        DockPosition.left => Rect.fromLTWH(
          _output.left + near,
          _output.top + slot.center - slot.half,
          extent,
          extent,
        ),
        DockPosition.right => Rect.fromLTWH(
          _output.right - near - extent,
          _output.top + slot.center - slot.half,
          extent,
          extent,
        ),
      };
    }
    return null;
  }

  double? _firstAppCenter(DockLayoutFrame frame, List<_SlotSpec> specs) {
    for (var i = 0; i < specs.length; i++) {
      if (specs[i].kind == _SlotKind.app) return frame.slots[i].center;
    }
    return null;
  }

  int? _indexForKey(String? key) {
    if (key == null) return null;
    for (var i = 0; i < _labels.length; i++) {
      if (_labels[i]?.key == key) return i;
    }
    return null;
  }

  Widget _capsuleSurface(BuildContext context, ShellThemeData theme) {
    final radius = theme.borderRadius(20);
    // Mixed from the theme's own surface, not the glass backing: that backing
    // is a flat white or black chosen by the glass appearance setting, so on a
    // dark wallpaper it turned the dock into a pale bar nothing else on screen
    // shared. The surface colour already follows the light or dark appearance.
    final alpha = theme.effectivePanelOpacity.clamp(0.55, 0.86).toDouble();
    return ShellBackdropBlur(
      blur: theme.effectivePanelOpacity < 1,
      separateChild: true,
      // A glass surface owns the fade so the backdrop and foreground can fade
      // independently instead of being isolated in one opacity group.
      opacity: ShellSurfacePresentation.opacityOf(context),
      borderRadius: radius,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          color: theme.colors.surfaceContainer.withValues(alpha: alpha),
          border: Border.all(
            color: theme.colors.hairline.withValues(alpha: 0.7),
          ),
        ),
      ),
    );
  }

  /// Half width of a divider's hit area. Slots sit 8 px apart, so the handle
  /// never reaches into an icon's own region.
  static const double _dividerReach = 6;

  Widget _dividerHandle(Color color) {
    final vertical = _position == DockPosition.bottom;
    return MouseRegion(
      cursor: vertical
          ? SystemMouseCursors.resizeUpDown
          : SystemMouseCursors.resizeLeftRight,
      // A raw pointer listener, not a pan recogniser: the handle takes the
      // drag on the first pixel instead of waiting out the pan slop.
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (event) {
          if (event.buttons != kPrimaryButton || _settings.lockItems) return;
          _resizing = true;
          _dragIconSize = _iconSize;
        },
        onPointerMove: (event) {
          if (_resizing) _resizeFromDivider(event.delta);
        },
        onPointerUp: (_) => _commitIconSize(),
        onPointerCancel: (_) => _commitIconSize(),
        child: Center(
          child: SizedBox(
            width: vertical ? 1 : double.infinity,
            height: vertical ? double.infinity : 1,
            child: ColoredBox(color: color),
          ),
        ),
      ),
    );
  }

  /// A divider drag away from the screen edge grows the icons, the way the
  /// Dock's own separator resizes it.
  void _resizeFromDivider(Offset delta) {
    final step = switch (_position) {
      DockPosition.bottom => -delta.dy,
      DockPosition.left => delta.dx,
      DockPosition.right => -delta.dx,
    };
    // Whole pixels: a sub-pixel drag would otherwise rebuild the dock and
    // resize every icon texture on every pointer event.
    final next = DockSettings.clampIconSize((_iconSize + step).roundToDouble());
    if (next == _iconSize) return;
    setState(() => _dragIconSize = next);
  }

  void _commitIconSize() {
    _resizing = false;
    final size = _dragIconSize;
    if (size == null) return;
    unawaited(ref.read(dockSettingsProvider.notifier).setIconSize(size));
  }

  Widget? _slotChild(
    BuildContext context, {
    required _SlotSpec spec,
    required DockSlotLayout slot,
    required List<_DockEntry> entries,
    required Map<String, int> badges,
    required Map<String, LauncherEntry> launcherEntries,
    required String audio,
    required bool dragging,
    required String launcherLabel,
    required DockSettings settings,
    required Color tintColor,
    required bool chinese,
  }) {
    final main = slot.center - _capsuleStart - slot.half;
    final extent = slot.half * 2;
    final lift = (slot.scale - 1.0) * _iconSize * DockSettings.liftRatio;
    // Neighbours ease into their new slot while an icon is being dragged,
    // matching the reorder animation in the reference docks.
    Widget slotAt({
      required double cross,
      required double mainExtent,
      required double crossExtent,
      required Widget child,
      Key? key,
    }) => switch (_position) {
      DockPosition.bottom => AnimatedPositioned(
        key: key,
        duration: dragging ? const Duration(milliseconds: 180) : Duration.zero,
        curve: Curves.easeOutCubic,
        left: main,
        bottom: cross,
        width: mainExtent,
        height: crossExtent,
        child: child,
      ),
      DockPosition.left => AnimatedPositioned(
        key: key,
        duration: dragging ? const Duration(milliseconds: 180) : Duration.zero,
        curve: Curves.easeOutCubic,
        top: main,
        left: cross,
        height: mainExtent,
        width: crossExtent,
        child: child,
      ),
      DockPosition.right => AnimatedPositioned(
        key: key,
        duration: dragging ? const Duration(milliseconds: 180) : Duration.zero,
        curve: Curves.easeOutCubic,
        top: main,
        right: cross,
        height: mainExtent,
        width: crossExtent,
        child: child,
      ),
    };

    switch (spec.kind) {
      case _SlotKind.divider:
        final line = _iconSize * 0.52;
        final inset = DockSettings.padding + _iconSize * 0.24;
        final handle = _dividerHandle(context.shellTheme.colors.hairline);
        return switch (_position) {
          DockPosition.bottom => AnimatedPositioned(
            key: ValueKey('dock-divider-${spec.dividerKey ?? 'default'}'),
            duration: Duration.zero,
            left: main + slot.half - _dividerReach,
            bottom: inset,
            width: _dividerReach * 2,
            height: line,
            child: handle,
          ),
          DockPosition.left => AnimatedPositioned(
            key: ValueKey('dock-divider-${spec.dividerKey ?? 'default'}'),
            duration: Duration.zero,
            top: main + slot.half - _dividerReach,
            left: inset,
            height: _dividerReach * 2,
            width: line,
            child: handle,
          ),
          DockPosition.right => AnimatedPositioned(
            key: ValueKey('dock-divider-${spec.dividerKey ?? 'default'}'),
            duration: Duration.zero,
            top: main + slot.half - _dividerReach,
            right: inset,
            height: _dividerReach * 2,
            width: line,
            child: handle,
          ),
        };
      case _SlotKind.launcher:
        // A stable key keeps the launcher's menu state when a drag adds or
        // removes the divider and shifts this slot's index.
        return slotAt(
          key: const ValueKey('dock-launcher'),
          cross: DockSettings.padding,
          mainExtent: extent,
          crossExtent: extent,
          child: _LauncherItem(
            size: extent,
            lift: lift,
            position: _position,
            appearance: _settings.appearance,
            label: launcherLabel,
            onTap: widget.services.toggleLauncher,
            onOpenMenu: () => _openDockMenu(slot.center),
          ),
        );
      case _SlotKind.folder:
        final folder = spec.folder;
        if (folder == null) return null;
        return slotAt(
          key: ValueKey('dock-folder-${folder.path}'),
          cross: DockSettings.padding,
          mainExtent: extent,
          crossExtent: extent,
          child: DockFolderItem(
            folder: folder,
            size: extent,
            lift: lift,
            position: _position,
            zh: chinese,
            onRemove: () => unawaited(
              ref.read(dockSettingsProvider.notifier).removeFolder(folder.path),
            ),
            onOverlayChanged: _setOverlayHold,
            monitorBounds: _output,
            workArea: widget.environment.workArea,
            appearance: _settings.appearance,
            onOpenSettings: _openSettings,
            onSetView: (view) => unawaited(
              ref
                  .read(dockSettingsProvider.notifier)
                  .setFolderView(folder.path, view),
            ),
            onSetSort: (sort) => unawaited(
              ref
                  .read(dockSettingsProvider.notifier)
                  .setFolderSort(folder.path, sort),
            ),
            onSetStacked: (stacked) => unawaited(
              ref
                  .read(dockSettingsProvider.notifier)
                  .setFolderStacked(folder.path, stacked),
            ),
            onReorder: (order) => unawaited(
              ref
                  .read(dockSettingsProvider.notifier)
                  .setFolderOrder(folder.path, order),
            ),
            trashRect: _trashRect,
          ),
        );
      case _SlotKind.file:
        final file = spec.file;
        if (file == null) return null;
        return slotAt(
          key: ValueKey('dock-file-${file.path}'),
          cross: DockSettings.padding,
          mainExtent: extent,
          crossExtent: extent,
          child: DockFileItem(
            file: file,
            size: extent,
            lift: lift,
            position: _position,
            zh: chinese,
            appearance: _settings.appearance,
            monitorBounds: _output,
            onOpen: () => unawaited(DockExtras.openPath(file.path)),
            onReveal: () => unawaited(DockExtras.revealPath(file.path)),
            onRemove: () => unawaited(
              ref.read(dockSettingsProvider.notifier).removeFile(file.path),
            ),
            onOpenSettings: _openSettings,
            onOverlayChanged: _setOverlayHold,
          ),
        );
      case _SlotKind.trash:
        return slotAt(
          key: const ValueKey('dock-trash'),
          cross: DockSettings.padding,
          mainExtent: extent,
          crossExtent: extent,
          child: DockTrashItem(
            size: extent,
            lift: lift,
            position: _position,
            zh: chinese,
            onOverlayChanged: _setOverlayHold,
            monitorBounds: _output,
            onOpenSettings: _openSettings,
            appearance: _settings.appearance,
          ),
        );
      case _SlotKind.app:
        final entryIndex = spec.entry!;
        final entry = entries[entryIndex];
        // The dragged source stays mounted but invisible: it owns the pan
        // recognizer, and unmounting it mid-gesture would kill the drag.
        final isSource = dragging && appIdentity(entry.appId) == _dragKey;
        final pinIndex = entries
            .take(entryIndex)
            .where((candidate) => candidate.pinned)
            .length;
        final identity = appIdentity(entry.appId);
        final launchIdentity = entry.launchId == null
            ? identity
            : appIdentity(entry.launchId!);
        final published =
            launcherEntries[identity] ?? launcherEntries[launchIdentity];
        final publishedCount = settings.showBadges
            ? published?.shownCount ?? 0
            : 0;
        bool? muted;
        if (audio.isNotEmpty && entry.windows.isNotEmpty) {
          for (final line in audio.split('\n')) {
            if (line.length < 2) continue;
            if (!DockWindows.ownsStream(
              line.substring(1),
              appId: entry.appId,
              name: entry.name,
            )) {
              continue;
            }
            // One audible stream is enough to call the application audible.
            muted = (muted ?? true) && line.startsWith('1');
          }
        }
        return slotAt(
          key: ValueKey('dock-${entry.appId}'),
          cross: DockSettings.padding,
          mainExtent: extent,
          crossExtent: extent,
          child: Opacity(
            opacity: isSource ? 0 : 1,
            child: DockItemWidget(
              appId: entry.appId,
              launchId: entry.launchId,
              name: entry.name,
              windows: entry.windows,
              pinned: entry.pin != null,
              dragging: dragging,
              services: widget.services,
              monitorId: widget.monitorId,
              monitorBounds: _output,
              position: _position,
              size: extent,
              lift: lift,
              clickAction: settings.clickAction,
              scrollAction: settings.scrollAction,
              workspaceStatus: _workspaceStatus,
              scrollGate: _scrollGate,
              scrollReversed: settings.scrollReversed,
              scrollWraps: settings.scrollWraps,
              launchFeedback: settings.launchFeedback,
              indicatorStyle: settings.indicatorStyle,
              previewStyle: settings.previewStyle,
              hoverFocusPreview: settings.hoverFocusPreview,
              dimInactivePinned: settings.dimInactivePinned,
              badge: publishedCount > 0
                  ? publishedCount
                  : badges[identity] ?? 0,
              progress: settings.showProgress ? published?.shownProgress : null,
              attention: settings.showAttention && (published?.urgent ?? false),
              audioMuted: muted,
              middleClickAction: settings.middleClickAction,
              showDesktopActions: settings.showDesktopActions,
              previewMiddleClose: settings.previewMiddleClose,
              activation: _activation,
              iconMode: settings.iconMode,
              iconOpacity: settings.iconOpacity,
              tintColor: tintColor,
              onTogglePin: () => _togglePin(entry),
              onCloseWindows: _closeWindows,
              onOverlayChanged: _setOverlayHold,
              previewOwner: _previewOwner,
              onPreviewOwnerChanged: _setPreviewOwner,
              onDragStart: settings.lockItems
                  ? null
                  : (pointer) =>
                        _startDrag(entry, entryIndex, pinIndex, pointer),
              onDragUpdate: settings.lockItems ? null : _updateDrag,
              onDragEnd: settings.lockItems ? null : _endDrag,
            ),
          ),
        );
    }
  }

  _LabelTarget? _labelForSlot(
    List<_SlotSpec> specs,
    int index,
    List<_DockEntry> entries,
    String launcherLabel,
    bool chinese,
  ) {
    final spec = specs[index];
    final center = _frame?.slots[index].center ?? 0;
    return switch (spec.kind) {
      _SlotKind.app => _LabelTarget(
        // Keyed by application identity, not slot index: pinning or closing an
        // app shifts indices, and the label must not jump to a different name.
        key: 'app-${appIdentity(entries[spec.entry!].appId)}',
        name: entries[spec.entry!].name,
        center: center,
      ),
      _SlotKind.launcher => _LabelTarget(
        key: 'launcher',
        name: launcherLabel,
        center: center,
      ),
      _SlotKind.folder =>
        spec.folder == null
            ? null
            : _LabelTarget(
                key: 'folder-${spec.folder!.path}',
                name: spec.folder!.label,
                center: center,
              ),
      _SlotKind.file =>
        spec.file == null
            ? null
            : _LabelTarget(
                key: 'file-${spec.file!.path}',
                name: spec.file!.label,
                center: center,
              ),
      _SlotKind.trash => _LabelTarget(
        key: 'trash',
        name: chinese ? '回收站' : 'Trash',
        center: center,
      ),
      _SlotKind.divider => null,
    };
  }
}

enum _SlotKind { app, launcher, folder, file, trash, divider }

class _SlotSpec {
  const _SlotSpec({
    required this.kind,
    required this.half,
    this.entry,
    this.folder,
    this.file,
    this.dividerKey,
  });

  final _SlotKind kind;
  final double half;
  final int? entry;
  final DockFolder? folder;
  final DockFile? file;
  final String? dividerKey;

  bool get growable => kind != _SlotKind.divider;
}

class _DockEntry {
  const _DockEntry({
    required this.appId,
    required this.launchId,
    required this.name,
    required this.windows,
    required this.pin,
    this.suggestion = false,
  });

  final String appId;
  final String? launchId;
  final String name;
  final List<ApplicationWindow> windows;
  final DockPin? pin;

  /// True for an entry the dock only shows because the launcher recorded a
  /// launch, so dragging it out can dismiss it without touching a pin.
  final bool suggestion;

  bool get pinned => pin != null;
}

class _LabelTarget {
  const _LabelTarget({
    required this.key,
    required this.name,
    required this.center,
  });

  final String key;
  final String name;
  final double center;
}

class _LauncherItem extends StatefulWidget {
  const _LauncherItem({
    required this.size,
    required this.lift,
    required this.position,
    required this.label,
    required this.onTap,
    required this.onOpenMenu,
    this.appearance = DockAppearance.macos,
  });

  final double size;
  final double lift;
  final DockPosition position;
  final String label;
  final DockAppearance appearance;
  final VoidCallback onTap;
  final VoidCallback onOpenMenu;

  @override
  State<_LauncherItem> createState() => _LauncherItemState();
}

class _LauncherItemState extends State<_LauncherItem> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    return Transform.translate(
      offset: switch (widget.position) {
        DockPosition.bottom => Offset(0, -widget.lift),
        DockPosition.left => Offset(widget.lift, 0),
        DockPosition.right => Offset(-widget.lift, 0),
      },
      child: Semantics(
        label: widget.label,
        button: true,
        child: Listener(
          onPointerDown: (_) => _setPressed(true),
          onPointerUp: (_) => _setPressed(false),
          onPointerCancel: (_) => _setPressed(false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            onSecondaryTapDown: (_) => widget.onOpenMenu(),
            child: widget.appearance == DockAppearance.macos
                ? DockLaunchpadIcon(size: widget.size, pressed: _pressed)
                : DockTile(
                    size: widget.size,
                    accent: theme.accent,
                    pressed: _pressed,
                    child: SizedBox.square(
                      dimension: widget.size * 0.42,
                      child: CustomPaint(
                        painter: _LauncherGlyphPainter(theme.accent),
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _DockLabelBubble extends StatelessWidget {
  const _DockLabelBubble({
    required this.text,
    required this.iconSize,
    required this.background,
    required this.border,
    required this.foreground,
    this.horizontal = false,
    this.tailLeading = true,
  });

  final String text;

  /// The bubble scales with the icon it belongs to: a fixed 11 px caption
  /// reads as a speck next to a magnified 76 px icon.
  final double iconSize;

  final Color background;
  final Color border;
  final Color foreground;

  /// Side docks point their tail sideways so the bubble stays readable.
  final bool horizontal;
  final bool tailLeading;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final fontSize = (iconSize * 0.26).clamp(11.0, 13.0);
    final padV = (iconSize * 0.10).clamp(4.0, 6.0);
    final padH = (iconSize * 0.24).clamp(10.0, 14.0);
    final height = fontSize * 1.25 + padV * 2;
    final tailSize = (iconSize * 0.13).clamp(6.0, 9.0);
    return CustomPaint(
      painter: _BubblePainter(
        color: background,
        border: border,
        radius: height / 2,
        tail: tailSize,
        horizontal: horizontal,
        tailLeading: tailLeading,
      ),
      child: Padding(
        padding: EdgeInsets.only(
          left: padH + (horizontal && tailLeading ? tailSize : 0),
          right: padH + (horizontal && !tailLeading ? tailSize : 0),
          top: padV,
          bottom: padV + (horizontal ? 0 : tailSize),
        ),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.text.systemBarCaption.copyWith(
            color: foreground,
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
            height: 1.25,
            letterSpacing: 0.1,
          ),
        ),
      ),
    );
  }
}

/// The bubble and its tail as one shape, so the hairline runs around the tail
/// instead of across its base.
class _BubblePainter extends CustomPainter {
  const _BubblePainter({
    required this.color,
    required this.border,
    required this.radius,
    required this.tail,
    required this.horizontal,
    required this.tailLeading,
  });

  final Color color;
  final Color border;
  final double radius;
  final double tail;
  final bool horizontal;
  final bool tailLeading;

  @override
  void paint(Canvas canvas, Size size) {
    final depth = tail * 2.1;
    final Path body;
    final Path point;
    if (horizontal) {
      final rect = tailLeading
          ? Rect.fromLTWH(tail, 0, size.width - tail, size.height)
          : Rect.fromLTWH(0, 0, size.width - tail, size.height);
      final edge = tailLeading ? rect.left + 1 : rect.right - 1;
      final apex = tailLeading ? 0.0 : size.width;
      body = Path()
        ..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
      point = Path()
        ..moveTo(edge, rect.center.dy - depth / 2)
        ..lineTo(apex, rect.center.dy)
        ..lineTo(edge, rect.center.dy + depth / 2)
        ..close();
    } else {
      final rect = Rect.fromLTWH(0, 0, size.width, size.height - tail);
      body = Path()
        ..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
      point = Path()
        ..moveTo(rect.center.dx - depth / 2, rect.bottom - 1)
        ..lineTo(rect.center.dx, size.height)
        ..lineTo(rect.center.dx + depth / 2, rect.bottom - 1)
        ..close();
    }
    final shape = Path.combine(PathOperation.union, body, point);
    canvas.drawPath(shape, Paint()..color = color);
    canvas.drawPath(
      shape,
      Paint()
        ..color = border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _BubblePainter old) =>
      old.color != color ||
      old.border != border ||
      old.radius != radius ||
      old.tail != tail ||
      old.horizontal != horizontal ||
      old.tailLeading != tailLeading;
}

class _LauncherGlyphPainter extends CustomPainter {
  const _LauncherGlyphPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final cell = size.width / 4.2;
    final radius = Radius.circular(cell * 0.32);
    for (var row = 0; row < 3; row++) {
      for (var column = 0; column < 3; column++) {
        final left = column * cell * 1.55;
        final top = row * cell * 1.55;
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(left, top, cell, cell), radius),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LauncherGlyphPainter oldDelegate) =>
      oldDelegate.color != color;
}
