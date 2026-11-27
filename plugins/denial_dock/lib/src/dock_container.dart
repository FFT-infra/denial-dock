import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show PointerDeviceKind;

import 'package:denial_shell_kit/glass_card.dart';
import 'package:denial_shell_kit/kit_dock_link.dart';
import 'package:denial_shell_kit/kit_host.dart';
import 'package:denial_shell_kit/kit_layer.dart' show kitOpenPanel;
import 'package:denial_shell_kit/kit_glass.dart';
import 'package:denial_shell_kit/kit_material.dart';
import 'package:denial_shell_kit/kit_motion.dart';
import 'package:denial_shell_kit/kit_panel_place.dart' show KitEdge;
import 'package:denial_shell_kit/kit_part.dart';
import 'package:denial_shell_kit/kit_requests.dart';
import 'package:denial_shell_kit/kit_settings.dart';
import 'package:denial_shell_kit/kit_style.dart';
import 'package:denial_flutter_sdk/applications.dart'
    show applicationRecentsProvider;
import 'package:denial_flutter_sdk/input.dart';
import 'package:denial_flutter_sdk/models.dart' show DenialWindow;
import 'package:denial_flutter_sdk/popups.dart';
import 'package:denial_flutter_sdk/services.dart';
import 'package:denial_flutter_sdk/settings.dart' show ShellScale;
import 'package:denial_flutter_sdk/shell.dart';
import 'package:denial_flutter_sdk/state.dart'
    show
        appAudioProvider,
        desktopNotificationsProvider,
        shellControllerProvider;
import 'package:denial_flutter_sdk/surfaces.dart';
import 'package:denial_flutter_sdk/theme.dart';
import 'package:denial_flutter_sdk/wallpaper.dart';
import 'package:flutter/gestures.dart'
    show GestureBinding, PointerScrollEvent, PointerSignalEvent, kPrimaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dock_autohide.dart';
import 'dock_badges.dart';
import 'dock_cell.dart';
import 'dock_recents.dart';
import 'dock_drag.dart';
import 'dock_extras.dart';
import 'dock_extras_item.dart';
import 'dock_icon.dart';
import 'dock_mac_icons.dart';
import 'dock_debug.dart';
import 'dock_hotkeys.dart';
import 'dock_ink.dart';
import 'dock_item.dart';

import 'package:denial_shell_kit/launcher_entry.dart';
import 'package:denial_shell_kit/launcher_entry_bus.dart';

import 'dock_layout.dart';
import 'dock_look.dart';
import 'dock_look_style.dart';
import 'dock_menu.dart';
import 'dock_metrics.dart';
import 'dock_motion.dart';
import 'dock_part_cell.dart';
import 'dock_parts.dart';
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
  double get _effectiveEdgeMargin => _look.effectiveEdgeMargin * _floatFraction;
  double get _effectiveCorner => _look.effectiveRadius * _floatFraction;
  double get _edgeInset => _effectiveEdgeMargin + _reserved;

  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;

  /// How the dock's own animations advance: every value the ticker chases and
  /// every timed move of an icon goes through it, so the shell's speed and
  /// the system's reduced-motion setting are honoured in one place.
  DockMotion _motion = DockMotion(pace: KitMotion.now);

  /// Pointer position along the dock's main axis, in surface coordinates.
  /// Storing surface coordinates keeps the target valid while the capsule
  /// changes length under a still pointer.
  double _pointer = 0;
  double _pointerTarget = 0;
  double _hover = 0;
  double _hoverTarget = 0;
  double _reveal = 1;
  double _revealTarget = 1;
  double _floatFraction = 1;
  double _floatTarget = 1;

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

  /// True when the dock menu was opened from the launcher icon, which adds
  /// the system's own entries above the dock's.
  bool _menuFromLauncher = false;

  /// One dwell timer gates the first name label; moving between icons keeps the
  /// visible label continuous instead of restarting the delay.
  Timer? _labelTimer;
  String? _labelKey;
  bool _labelShown = false;

  DockSettings _settings = DockSettings.defaults;

  /// How the capsule is drawn and spaced: the preset of the shell look in
  /// force with the user's own changes on top. Resolved once per build.
  DockLook _look = DockLook.denial;

  /// [_look] as the settings give it, before its spacing follows the icons.
  DockLook _baseLook = DockLook.denial;

  /// The wallpaper's colour, which a translucent plate mostly shows.
  Color _backdrop = const Color(0xFF000000);

  /// How much larger than the look's own the spacing is drawn.
  double _spacing = 1;

  /// The metrics of the look in force, with what the user set over them.
  DockMetrics _fit = DockMetrics.denial;

  /// The icon size the row was shrunk to so it fits its edge; null while it
  /// fits at the size asked for.
  double? _fitIcon;

  /// How long a task button is on a bar that shows titles; zero when none
  /// does.
  double _taskExtent = 0;

  /// Cross width on a vertical taskbar when window titles sit beside icons.
  double _verticalTaskCross = 0;
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

  double get _iconSize => _fitIcon ?? _dragIconSize ?? _fit.iconSize;
  double get _crossExtent =>
      _vertical && _verticalTaskCross > _iconSize ? _verticalTaskCross : _iconSize;
  double get _capsuleHeight => _crossExtent + _look.padding * 2;
  double get _halfIcon => _iconSize / 2;

  DockPosition get _position => _settings.position;
  bool get _vertical => _position.isVertical;
  double get _effectiveScale =>
      resolveKitScale(widget.environment.shellScale, kitShellScale.value);
  double get _relativeScale {
    final hostScale = widget.environment.shellScale;
    return _effectiveScale / (hostScale > 0 ? hostScale : 1.0);
  }

  Rect _scaleByRelative(Rect rect) {
    final rel = _relativeScale;
    if ((rel - 1.0).abs() <= 1e-4) return rect;
    return ShellScale.toShell(
      rect,
      widget.environment.output.logicalRect.topLeft,
      rel,
    );
  }

  Rect get _output => _scaleByRelative(widget.environment.output.logicalRect);
  Rect get _workArea => _scaleByRelative(widget.environment.workArea);

  /// The output as the overlay the dock's menus open in has it. Where the
  /// shell draws itself at a scale of its own, each output has an overlay
  /// that starts at the output's corner; elsewhere the overlay is the scene.
  Rect get _overlayOutput =>
      widget.environment.shellScale == 1.0 &&
          (_relativeScale - 1.0).abs() <= 1e-4
      ? _output
      : Offset.zero & _output.size;

  Rect get _overlayWorkArea =>
      widget.environment.shellScale == 1.0 &&
          (_relativeScale - 1.0).abs() <= 1e-4
      ? _workArea
      : _workArea.shift(-_output.topLeft);

  bool get _held =>
      _insideCapsule ||
      _edgeHover ||
      _overlayHold ||
      _settingsOpen ||
      _menuOpen ||
      _edgeTapHold ||
      _dragKey != null ||
      // A part of the dock opened a panel: the dock it hangs from stays.
      (_hasParts && kitOpenPanel.value != null);

  /// Whether the row holds parts of another plugin.
  bool _hasParts = false;

  /// The length each such part takes along the row, as last measured.
  final Map<String, double> _partExtents = <String, double>{};

  /// The slots of the last build, for telling what the pointer is over.
  List<_SlotSpec> _builtSpecs = const [];

  KitEdge get _kitEdge => switch (_position) {
    DockPosition.bottom => KitEdge.bottom,
    DockPosition.top => KitEdge.top,
    DockPosition.left => KitEdge.left,
    DockPosition.right => KitEdge.right,
  };

  /// The dock that last told the shell about itself. One dock speaks for
  /// the plugin, the one on the main output, and only it takes it back.
  static _DockContainerState? _speaker;

  void _onShellState() {
    if (!mounted) return;
    setState(() {});
    _evaluateHide();
  }

  void _applyLayout(Map<String, Object?> changes) {
    if (!mounted) return;
    unawaited(ref.read(dockSettingsProvider.notifier).applyLayout(changes));
  }

  /// Tells the rest of the shell what this dock draws and how much of its
  /// edge it holds. Run after the frame: listeners rebuild.
  void _reportToShell(DockSettings settings) {
    if (!mounted || !widget.environment.isMainOutput) return;
    _speaker = this;
    kitDock.publish(settings.layoutJson(kitStyle.value.look.dockKin));
    kitHosts.report(
      KitHosts.dock,
      KitHostState(
        edge: _kitEdge,
        thickness: (_look.effectiveEdgeMargin + _capsuleHeight) * _relativeScale,
        pinned: settings.visibility == DockVisibilityMode.always,
      ),
    );
  }

  void _measuredPart(String id, double extent) {
    if (!mounted || !extent.isFinite) return;
    final known = _partExtents[id];
    if (known != null && (known - extent).abs() < 0.5) return;
    setState(() => _partExtents[id] = extent);
  }

  double get _dragCenterX => _dragOriginX + _dragDx;
  double get _dragCenterY => _dragOriginY + _dragDy;
  double get _dragLocalX => _dragCenterX - _output.left;
  double get _dragLocalY => _dragCenterY - _output.top;
  double get _dragLocalMain => _vertical ? _dragLocalY : _dragLocalX;

  bool get _dragOutside => switch (_position) {
    DockPosition.bottom =>
      _dragLocalY < _surfaceHeight - _capsuleFar - _iconSize,
    DockPosition.top => _dragLocalY > _capsuleFar + _iconSize,
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
    // The speed is a value, so a change of it reaches a running dock at once.
    kitSpeed.addListener(_onSpeed);
    // The thumbnail index is built before a folder is opened, so the fan shows
    // previews on its first frame instead of a column of type icons, and stale
    // generated previews are dropped so the cache cannot grow without bound.
    DockStackThumbs.warm();
    DockStackThumbs.sweepCache();
    _hotkeys = DockHotkeys.requests.listen(_onHotkey);
    _debug = DockDebug.commands.listen(_onDebug);
    kitOpenPanel.addListener(_onShellState);
    kitReservation.addListener(_onShellState);
    kitShellScale.addListener(_onShellState);
    if (widget.environment.isMainOutput) kitDock.attach(_applyLayout);
    registerDockSettingsPages();
    registerDockParts();
  }

  void _onSpeed() {
    if (!mounted) return;
    // The pace is held as a value, so a new speed has to be read into it here:
    // a change of the setting does not run didChangeDependencies.
    setState(() => _motion = DockMotion(pace: KitMotion.pace(context)));
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
      case 'dockmenu':
        _openDockMenu((_vertical ? _surfaceHeight : _surfaceWidth) / 2);
      case 'close':
        _closeDockMenu();
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The same signal the settings panel and the stack view read. Depending
    // on it here means a change of the setting reaches a running dock; a
    // change of the speed arrives through [_onSpeed].
    _motion = DockMotion(pace: KitMotion.pace(context));
  }

  @override
  void dispose() {
    kitSpeed.removeListener(_onSpeed);
    kitOpenPanel.removeListener(_onShellState);
    kitReservation.removeListener(_onShellState);
    kitShellScale.removeListener(_onShellState);
    // Listeners rebuild, which they may not do while the tree is torn down.
    scheduleMicrotask(() {
      kitDock.detach(_applyLayout);
      if (identical(_speaker, this)) {
        _speaker = null;
        kitHosts.report(KitHosts.dock, null);
      }
    });
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
    _scheduleTicker();
  }

  void _requestFloat(double target) {
    if ((_floatTarget - target).abs() < 0.001) return;
    _floatTarget = target;
    _scheduleTicker();
  }

  void _scheduleTicker() {
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
    final pointer = _motion.advance(
      _pointer,
      _pointerTarget,
      dt,
      // NextKDE's magnification response: the wave follows the pointer within
      // a few frames instead of trailing it.
      responseSeconds: 0.026,
    );
    final hover = _motion.advance(
      _hover,
      _hoverTarget,
      dt,
      responseSeconds: 0.055,
    );
    final reveal = _motion.advance(
      _reveal,
      _revealTarget,
      dt,
      responseSeconds: 0.10,
    );
    final floatFraction = _motion.advance(
      _floatFraction,
      _floatTarget,
      dt,
      responseSeconds: 0.10,
    );
    var dragDx = _dragDx;
    var dragDy = _dragDy;
    var settleFinished = false;
    if (_settling) {
      _settleT = _motion.glide(_settleT, dt, DockSettings.dragSettleSeconds);
      final t = _settleT.clamp(0.0, 1.0);
      final eased = KitMotion.outCubic.transform(t);
      dragDx = _settleFrom.dx + (_settleTo.dx - _settleFrom.dx) * eased;
      dragDy = _settleFrom.dy + (_settleTo.dy - _settleFrom.dy) * eased;
      settleFinished = t >= 1;
    }
    final settled =
        (pointer - _pointer).abs() < 0.001 &&
        (hover - _hover).abs() < 0.001 &&
        (reveal - _revealTarget).abs() < 1e-3 &&
        (floatFraction - _floatTarget).abs() < 1e-3 &&
        !_settling;
    setState(() {
      _pointer = pointer;
      _hover = hover;
      _reveal = settled ? _revealTarget : reveal;
      _floatFraction = settled ? _floatTarget : floatFraction;
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

  void _tapEdge(PointerDownEvent event) {
    if (event.kind == PointerDeviceKind.mouse) return;
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
    // A part is not an icon: over one the row stays at rest.
    _hoverTarget = _overPart(_pointerTarget) ? 0 : 1;
    _insideCapsule = true;
    _revealTarget = 1;
    _ensureTicker();
    _syncLabel();
    _evaluateHide();
  }

  bool _overPart(double pointer) {
    final nearest = _frame?.nearest(pointer);
    if (nearest == null) return false;
    final (index, slot, distance) = nearest;
    return index < _builtSpecs.length &&
        _builtSpecs[index].kind == _SlotKind.part &&
        distance <= slot.half;
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
    if (_reveal > 0.5 && !_look.shape.name.contains('bar')) {
      _insideCapsule = true;
    }
    if (_edgeHover) return;
    _edgeHover = true;
    _evaluateHide();
  }

  void _onEdgeExit(PointerExitEvent event) {
    _revealTimer?.cancel();
    _revealTimer = null;
    if (_reveal > 0.5) _insideCapsule = false;
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

  void _openDockMenu(double surfaceMain, {bool launcher = false}) {
    if (_menuOpen) {
      _closeDockMenu();
      return;
    }
    _menuAnchor = surfaceMain;
    _menuFromLauncher = launcher;
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

  /// Opens the shell's settings window: at one of the dock's pages, or at
  /// its first page when [page] is null.
  ///
  /// The window is a managed shell popup, not an OverlayPortal menu, so the
  /// dock keeps its own hold: without it the capsule retracts behind the
  /// window when a window is parked on the dock strip.
  void _openSettings({int? page = 0}) {
    _closeDockMenu();
    showKitSettings(
      ref: ref,
      page: page == null
          ? null
          : dockSettingsPageInfo[page.clamp(
              0,
              dockSettingsPageInfo.length - 1,
            )].id,
    );
    if (_settingsOpen) return;
    _settingsOpen = true;
    _evaluateHide();
    // The popup has no completion callback; poll the popup list so the hold
    // is released once the window has finished its closing transition.
    Timer.periodic(const Duration(milliseconds: 120), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final open = ref
          .read(shellPopupControllerProvider)
          .any((popup) => popup.keyName == kitSettingsKey);
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
    Offset screenPointer,
  ) {
    if (_dragKey != null) return;
    final pointer = _toShell(screenPointer);
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
    final crossCenter = _capsuleCross + _look.padding + _halfIcon;
    _dragOriginX = switch (_position) {
      DockPosition.bottom || DockPosition.top => _output.left + mainCenter,
      DockPosition.left => _output.left + crossCenter,
      DockPosition.right => _output.right - crossCenter,
    };
    _dragOriginY = switch (_position) {
      DockPosition.bottom => _output.top + _surfaceHeight - crossCenter,
      DockPosition.top => _output.top + crossCenter,
      DockPosition.left || DockPosition.right => _output.top + mainCenter,
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

  /// A point on the screen in the units the dock is laid out in, which the
  /// shell may draw larger than the screen's. The dock's surface covers its
  /// output, so its own corner is the output's.
  Offset _toShell(Offset screen) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return screen;
    return box.globalToLocal(screen) / _relativeScale + _output.topLeft;
  }

  void _updateDrag(Offset screenPointer) {
    if (_dragKey == null) return;
    if (!screenPointer.dx.isFinite || !screenPointer.dy.isFinite) return;
    // The button pointer emits a stray move at the scene origin; a real dock
    // drag never visits that corner.
    if (screenPointer.dx == 0 && screenPointer.dy == 0) return;
    final pointer = _toShell(screenPointer);
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

  /// Puts a picked-up icon back where it came from. [_endDrag] is for a
  /// pointer that let go over the dock: it keeps the dock awake under that
  /// pointer until it leaves. A finger that held an icon and lifted off is
  /// gone, and no leave event follows it, so the dock would stay awake for
  /// good.
  void _cancelDrag() {
    if (_settling) return;
    _finishDrag();
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

  List<_SlotSpec> _specsFor(
    List<_DockEntry> entries,
    DockSettings settings, {
    List<ApplicationWindow> minimized = const <ApplicationWindow>[],
  }) {
    final sections = DockSections.build(
      entryCount: entries.length,
      isPinned: (index) => entries[index].pinned,
      settings: settings,
    );
    final slots = <_SlotSpec>[
      for (final section in sections)
        _SlotSpec(
          kind: switch (section.kind) {
            DockSlotKind.app => _SlotKind.app,
            DockSlotKind.launcher => _SlotKind.launcher,
            DockSlotKind.folder => _SlotKind.folder,
            DockSlotKind.file => _SlotKind.file,
            DockSlotKind.trash => _SlotKind.trash,
            DockSlotKind.divider => _SlotKind.divider,
            DockSlotKind.part => _SlotKind.part,
          },
          titled:
              section.kind == DockSlotKind.app &&
              (_vertical ? _verticalTaskCross > _iconSize : _taskExtent > _iconSize) &&
              entries[section.index!].windows.isNotEmpty,
          half: switch (section.kind) {
            DockSlotKind.divider => _fit.dividerSpan * _spacing / 2,
            DockSlotKind.app
                when !_vertical &&
                    _taskExtent > _iconSize &&
                    entries[section.index!].windows.isNotEmpty =>
              _taskExtent / 2,
            // Until a part has been measured it holds one icon's room.
            DockSlotKind.part =>
              (_partExtents[section.partId] ?? _iconSize) / 2,
            _ => _iconSize / 2,
          },
          partId: section.partId,
          entry: section.index,
          folder: section.folder,
          file: section.file,
          dividerKey: section.dividerKey,
        ),
    ];
    if (settings.showMinimizedWindows && minimized.isNotEmpty) {
      // Insert minimized window thumbnail tiles right before the trash (or at
      // the trailing end), matching macOS Dock's minimized window section.
      var insertAt = slots.indexWhere((s) => s.kind == _SlotKind.trash);
      if (insertAt < 0) insertAt = slots.length;
      final minSlots = <_SlotSpec>[
        if (insertAt > 0 && slots[insertAt - 1].kind != _SlotKind.divider)
          _SlotSpec(
            kind: _SlotKind.divider,
            half: _fit.dividerSpan * _spacing / 2,
            dividerKey: 'minimized',
          ),
        for (final win in minimized.take(6))
          _SlotSpec(
            kind: _SlotKind.minimized,
            half: _iconSize / 2,
            minimizedWindow: win,
          ),
      ];
      slots.insertAll(insertAt, minSlots);
    }
    return slots;
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

  /// The slots for [entries] at a size the row fits its edge with. A row too
  /// long for the edge has its icons shrunk, the way the macOS Dock shrinks
  /// as it fills up; a bar that shows titles shares what room is left among
  /// the applications that have a window.
  List<_SlotSpec> _fitSpecs(
    double surfaceExtent,
    List<_DockEntry> entries,
    DockSettings settings, {
    List<ApplicationWindow> minimized = const <ApplicationWindow>[],
  }) {
    _fitIcon = null;
    _taskExtent = 0;
    _verticalTaskCross = 0;
    final asked = _iconSize;
    _spaceFor(asked);
    final specs = _specsFor(entries, settings, minimized: minimized);
    if (!surfaceExtent.isFinite || specs.isEmpty) return specs;
    final bar = _look.shape == DockShape.bar;
    // A floating capsule keeps clear of the screen's corners.
    final available = surfaceExtent - (bar ? 0 : 16);
    final icons = specs.where((spec) => spec.growable).length;
    var spacing = _look.endPadding * 2 + _look.gap * (specs.length - 1);
    var parts = 0.0;
    for (final spec in specs) {
      if (spec.kind == _SlotKind.divider) spacing += spec.half * 2;
      if (spec.kind == _SlotKind.part) parts += spec.half * 2;
    }
    final fixed = parts + spacing;
    final fitted = DockLayout.fitIconSize(
      available: available,
      iconSize: asked,
      icons: icons,
      fixed: _fit.scaleSpacing ? parts : fixed,
      scaled: _fit.scaleSpacing ? spacing : 0,
      floor: DockMetrics.fitFloor,
    );
    if (fitted < asked) {
      _fitIcon = fitted;
      _spaceFor(fitted);
      final shrunk = _specsFor(entries, settings, minimized: minimized);
      // If even at fitFloor the row overflows the monitor edge, fold trailing
      // app icons into an overflow button so nothing clips off-screen.
      double totalWidth(List<_SlotSpec> list) {
        if (list.isEmpty) return 0;
        var w = _look.endPadding * 2 + _look.gap * (list.length - 1);
        for (final s in list) {
          w += s.half * 2;
        }
        return w;
      }

      if (totalWidth(shrunk) > available) {
        final appIndices = <int>[
          for (var i = 0; i < shrunk.length; i++)
            if (shrunk[i].kind == _SlotKind.app) i,
        ];
        if (appIndices.length > 2) {
          final foldedEntries = <int>[];
          final mutable = List<_SlotSpec>.of(shrunk);
          while (totalWidth(mutable) + fitted + _look.gap > available &&
              appIndices.length > 1) {
            final dropAt = appIndices.removeLast();
            final removed = mutable.removeAt(dropAt);
            if (removed.entry != null) foldedEntries.insert(0, removed.entry!);
          }
          if (foldedEntries.isNotEmpty) {
            final insertPos = appIndices.last + 1;
            mutable.insert(
              insertPos,
              _SlotSpec(
                kind: _SlotKind.overflow,
                half: fitted / 2,
                overflowEntries: foldedEntries,
              ),
            );
            return mutable;
          }
        }
      }
      return shrunk;
    }
    if (!bar || !_fit.taskTitles) return specs;
    final tasks = specs
        .where(
          (spec) =>
              spec.kind == _SlotKind.app &&
              entries[spec.entry!].windows.isNotEmpty,
        )
        .length;
    if (_vertical) {
      if (tasks == 0) return specs;
      _verticalTaskCross = math.max(_iconSize, math.min(_fit.taskWidth, 152.0));
      return _specsFor(entries, settings, minimized: minimized);
    }
    final extent = DockLayout.taskExtent(
      available: available - fixed - (icons - tasks) * asked,
      tasks: tasks,
      icon: asked,
      widest: _fit.taskWidth,
    );
    if (extent <= asked) return specs;
    _taskExtent = extent;
    return _specsFor(entries, settings, minimized: minimized);
  }

  /// Spaces the row for icons of [size]: a look whose spacing follows its
  /// icons gets its plate, gaps and divider scaled with them.
  void _spaceFor(double size) {
    _spacing = _fit.spacingScale(size);
    _look = _spacing == 1
        ? _baseLook
        : DockLook.fitted(
            _baseLook,
            padding: _baseLook.padding * _spacing,
            gap: _baseLook.gap * _spacing,
            endInset: _baseLook.endInset * _spacing,
          );
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
    padding: _look.endPadding,
    gap: _look.gap,
    pointer: _pointer,
    hover: hover,
    maxScale: _fit.maxScale,
    radius: _look.magnifyRange,
    spread: _spreadFor(specs),
  );

  /// How a dock lying along its whole edge shares the edge out, or null for
  /// one centred group: a floating capsule, and a bar set to stay packed.
  DockSpread? _spreadFor(List<_SlotSpec> specs) {
    if (_look.shape != DockShape.bar || _settings.align == DockAlign.packed) {
      return null;
    }
    final ends = DockSections.ends(
      entryCount: specs.where((spec) => spec.kind == _SlotKind.app).length,
      settings: _settings,
    );
    return DockSpread(
      leading: ends.leading,
      trailing: ends.trailing,
      centered: _settings.align == DockAlign.center,
    );
  }

  @override
  Widget build(BuildContext context) {
    final storedSettings = ref.watch(dockSettingsProvider);
    final settings = storedSettings.value ?? DockSettings.defaults;
    if (!settings.allMonitors && !widget.environment.isMainOutput) {
      return const SizedBox.shrink();
    }
    _settings = settings;
    _baseLook = dockLookNow(settings);
    _look = _baseLook;
    _fit = dockMetricsNow(settings, _look.shape);
    if (_dragIconSize != null &&
        (_dragIconSize! - _fit.iconSize).abs() < 0.5) {
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
    // Room kept free on the dock's edge is a bar's, unless the shell says
    // the room is the dock's own or lies on another edge; then there is
    // nothing to step aside for.
    final held = kitReservation.value;
    final foreign =
        (held == null && kitBarModeInForce == KitBarMode.shown) ||
        (held != null && held.owner == KitReserver.bar && held.edge == _kitEdge);
    _reserved = settings.avoidReservedEdge && foreign
        ? DockAutoHide.reservedEdge(
            output: _output,
            workArea: _workArea,
            position: settings.position,
          )
        : 0;
    if (!storedSettings.isLoading) {
      SchedulerBinding.instance.addPostFrameCallback(
        (_) => _reportToShell(settings),
      );
    }
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
    _backdrop = ref.watch(wallpaperAccentProvider).color;
    final environment = widget.environment;
    final theme = context.shellTheme;
    final colors = theme.colors;
    final chinese = Localizations.localeOf(context).languageCode == 'zh';
    final launcherLabel = chinese ? '启动台' : 'Launcher';

    final minimizedWindows = <ApplicationWindow>[
      for (final w in windows)
        if (w.minimized) w,
    ];
    final baseEntries = _entries(settings, catalog, windows, null, recents);
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

    final viewport = LayoutBuilder(
      builder: (context, constraints) {
        _surfaceWidth = constraints.maxWidth;
        _surfaceHeight = constraints.maxHeight;
        final surfaceMain = _vertical ? _surfaceHeight : _surfaceWidth;
        final baseSpecs = _fitSpecs(
          surfaceMain,
          baseEntries,
          settings,
          minimized: minimizedWindows,
        );
        var entries = baseEntries;
        var specs = baseSpecs;
        if (_dragKey != null && !_settling && _dragTo >= 0) {
          final displayPins = _displayPins(settings.pinned);
          entries = _entries(settings, catalog, windows, displayPins, recents);
          specs = _specsFor(entries, settings, minimized: minimizedWindows);
        }
        _builtEntries = entries;
        _builtSpecs = specs;
        _hasParts = specs.any((spec) => spec.kind == _SlotKind.part);
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
          // A bar holds its whole edge, wherever its icons end.
          extent: _look.shape == DockShape.bar ? surfaceMain : frame.extent,
          thickness: _capsuleHeight,
          inset: _edgeInset,
        );
        final origin = widget.environment.output.logicalRect.topLeft;
        final effectiveScale = _effectiveScale;
        final conflict = DockAutoHide.hasConflict(
          windows: denialWindows,
          // Windows are where the screen has them; the dock's own rectangles
          // are in the shell's units and go over to the screen's.
          trigger: ShellScale.toScreen(
            DockAutoHide.intentionalOverlap(dockRect, position: _position),
            origin,
            effectiveScale,
          ),
          release: ShellScale.toScreen(dockRect, origin, effectiveScale),
          previousConflict: _conflict,
          monitorId: widget.monitorId,
          workspaceId: environment.workspaceId,
          outputScale: environment.output.scale / environment.shellScale,
          outputWidth: environment.screenRect.width,
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
        final defloatTouch = _look.defloatOnTouch &&
            settings.visibility == DockVisibilityMode.always &&
            (conflict ||
                _hasTouchingWindow(
                  windows: denialWindows,
                  dockRect: dockRect,
                  origin: origin,
                  effectiveScale: effectiveScale,
                  environment: environment,
                  activeIds: {
                    for (final window in allWindows)
                      if (window.active) window.id,
                  },
                ));
        _requestFloat(defloatTouch ? 0.0 : 1.0);

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
              ? pinCenters.last + _iconSize + _look.gap
              : firstApp ??
                    baseFrame.capsuleStart +
                        _look.endPadding +
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
                shape: _fit.label,
                fontSize: _fit.labelFontSize,
                weight: _fit.labelWeight,
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
                      _look.padding +
                      (labelSlot?.half ?? _halfIcon) * 2 +
                      labelLift +
                      _fit.labelGap,
                  width: 220,
                  child: IgnorePointer(child: Center(child: bubble)),
                ),
                DockPosition.top => Positioned(
                  left: (label!.center - 110).clamp(
                    12.0,
                    math.max(12.0, _surfaceWidth - 232.0),
                  ),
                  top:
                      _capsuleCross +
                      _look.padding +
                      (labelSlot?.half ?? _halfIcon) * 2 +
                      labelLift +
                      _fit.labelGap,
                  width: 220,
                  child: IgnorePointer(child: Center(child: bubble)),
                ),
                DockPosition.left => Positioned(
                  left: _capsuleFar + _fit.labelGap + 4,
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
                  right: _capsuleFar + _fit.labelGap + 4,
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
              // A bar lies along the whole edge, so its plate is drawn behind
              // the capsule at the surface's full length; the capsule keeps
              // its own extent and everything in it stays where it was.
              if (_look.shape == DockShape.bar)
                _placeInSurface(
                  main: _look.defloatOnTouch ? _effectiveEdgeMargin : 0,
                  cross: _capsuleCross,
                  mainExtent: _look.defloatOnTouch
                      ? math.max(0.0, surfaceMain - _effectiveEdgeMargin * 2)
                      : surfaceMain,
                  crossExtent: _capsuleHeight,
                  child: IgnorePointer(child: _capsuleSurface(context, theme)),
                ),
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
                    child: FocusScope(
                      onKeyEvent: (node, event) {
                        if (event is! KeyDownEvent) return KeyEventResult.ignored;
                        final key = event.logicalKey;
                        if ((!_vertical && key == LogicalKeyboardKey.arrowRight) ||
                            (_vertical && key == LogicalKeyboardKey.arrowDown)) {
                          node.nextFocus();
                          return KeyEventResult.handled;
                        }
                        if ((!_vertical && key == LogicalKeyboardKey.arrowLeft) ||
                            (_vertical && key == LogicalKeyboardKey.arrowUp)) {
                          node.previousFocus();
                          return KeyEventResult.handled;
                        }
                        return KeyEventResult.ignored;
                      },
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
                              child: _look.shape == DockShape.bar
                                  ? const SizedBox.expand()
                                  : _capsuleSurface(context, theme),
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
                                    theme.kitAccent,
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
                      duration: KitMotion.duration(context, KitMotion.fade),
                      curve: KitMotion.outCubic,
                      builder: (context, t, child) => Transform.scale(
                        scale: 1 + 0.10 * t,
                        child: Opacity(
                          opacity: (1 - 0.12 * t) * (willRemove ? 0.55 : 1),
                          child: child,
                        ),
                      ),
                      child: DockIcon(
                        mode: dockIconModeNow(settings),
                        opacity: settings.iconOpacity,
                        accent: dockTintColor(
                          settings.tintColor,
                          theme.kitAccent,
                        ),
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
                // Keep a 1 px translucent wake strip when retracted, and
                // bridge seamlessly to the capsule while revealed so cursor
                // motion into the bottom margin never flickers smart-hide.
                crossExtent: _reveal > 0.5
                    ? math.max(
                        _reserved > 0 ? 10.0 : 4.0,
                        _capsuleCross - _reserved + 2.0,
                      )
                    : (_reserved > 0 ? 10.0 : 1.0),
                child: ShellInputRegion(
                  debugLabel: 'Dock reveal edge',
                  child: MouseRegion(
                    onEnter: _onEdgeEnter,
                    onExit: _onEdgeExit,
                    child: Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: _tapEdge,
                      child: ColoredBox(
                        color: const Color(0x01000000),
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
    final rel = _relativeScale;
    final scoped = KitScaleScope(
      effectiveScale: _effectiveScale,
      child: viewport,
    );
    return (rel - 1.0).abs() <= 1e-4
        ? scoped
        : ShellScaleViewport(
            scale: rel,
            child: ShellOverlayHost(child: scoped),
          );
  }

  /// Whether any visible window on this workspace is maximized or touches the
  /// floating dock's inward margin (used by Plasma/COSMIC `defloatOnTouch`).
  bool _hasTouchingWindow({
    required List<DenialWindow> windows,
    required Rect dockRect,
    required Offset origin,
    required double effectiveScale,
    required ShellSurfaceEnvironment environment,
    required Set<int> activeIds,
  }) {
    if (environment.desktopVisible) return false;
    final pad = _look.edgeMargin + 4.0;
    final touchRect = switch (_position) {
      DockPosition.bottom => Rect.fromLTRB(
        dockRect.left,
        dockRect.top - pad,
        dockRect.right,
        dockRect.bottom,
      ),
      DockPosition.top => Rect.fromLTRB(
        dockRect.left,
        dockRect.top,
        dockRect.right,
        dockRect.bottom + pad,
      ),
      DockPosition.left => Rect.fromLTRB(
        dockRect.left,
        dockRect.top,
        dockRect.right + pad,
        dockRect.bottom,
      ),
      DockPosition.right => Rect.fromLTRB(
        dockRect.left - pad,
        dockRect.top,
        dockRect.right,
        dockRect.bottom,
      ),
    };
    final screenTouch = ShellScale.toScreen(touchRect, origin, effectiveScale);
    return DockAutoHide.hasConflict(
      windows: windows,
      trigger: screenTouch,
      release: screenTouch,
      previousConflict: _floatTarget < 0.5,
      monitorId: widget.monitorId,
      workspaceId: environment.workspaceId,
      outputScale: environment.output.scale / environment.shellScale,
      outputWidth: environment.screenRect.width,
      desktopVisible: environment.desktopVisible,
      scope: DockHideScope.all,
      activeIds: activeIds,
    );
  }

  /// A short bar on the screen edge while the dock is retracted, so a hidden
  /// dock still shows where it lives.
  Widget _revealHandle(ShellThemeData theme) => Align(
    alignment: switch (_position) {
      DockPosition.bottom => Alignment.bottomCenter,
      DockPosition.top => Alignment.topCenter,
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
            borderRadius: BorderRadius.circular(kitStyle.value.pill(4)),
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
    DockPosition.top => Positioned(
      left: main,
      top: cross,
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
    final chinese = Localizations.localeOf(context).languageCode == 'zh';
    final anchor = MatrixUtils.transformRect(
      layout.childPaintTransform,
      Offset.zero & layout.childSize,
    );
    final scene = Offset.zero & layout.overlaySize;
    final onOutput = anchor.intersect(scene);
    final visible = onOutput.isEmpty ? scene : onOutput;
    final width = math.min(
      dockLookMetrics.menuWidth,
      math.max(0.0, visible.width - 16),
    );
    final capsuleTopScene = anchor.top + _surfaceHeight - _capsuleFar;
    final capsuleBottomTopScene = anchor.top + _capsuleFar;
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
      DockPosition.top => Rect.fromLTWH(
        anchor.left + _menuAnchor,
        capsuleBottomTopScene,
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
    final magnifies = _fit.magnify;
    final maxHeight = switch (_position) {
      DockPosition.bottom => math.max(0.0, capsuleTopScene - visible.top - 16),
      DockPosition.top =>
        math.max(0.0, visible.bottom - capsuleBottomTopScene - 16),
      DockPosition.left || DockPosition.right =>
        math.max(0.0, visible.height - 16),
    };
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
                  radius: dockMenuRadius(context),
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
                          // The launcher's icon stands in for the system
                          // menu, so its menu leads with that menu's entries.
                          // The about box belongs to another plugin and is
                          // asked for by name; without a listener the row
                          // would do nothing, so it is left out.
                          if (_menuFromLauncher) ...[
                            if (KitRequests.answered)
                              DockMenuRow(
                                icon: Icons.info_outline,
                                label: chinese ? '关于本机' : 'About This System',
                                onTap: () {
                                  _closeDockMenu();
                                  KitRequests.send(
                                    KitRequests.about,
                                    monitorId: widget.monitorId,
                                  );
                                },
                              ),
                            DockMenuRow(
                              icon: Icons.settings_outlined,
                              label: chinese ? '系统设置…' : 'System Settings…',
                              onTap: () {
                                _closeDockMenu();
                                widget.services.openPowerSettings();
                              },
                            ),
                            DockMenuRow(
                              icon: Icons.dashboard_customize_outlined,
                              label: chinese ? '外壳设置…' : 'Shell Settings…',
                              onTap: () => _openSettings(page: 0),
                            ),
                            const DockMenuSeparator(),
                          ],
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
                                      DockPosition.top =>
                                        Icons.vertical_align_top,
                                      DockPosition.right =>
                                        Icons.align_horizontal_right,
                                    },
                                    label: switch (option) {
                                      DockPosition.left =>
                                        chinese ? '左边' : 'Left',
                                      DockPosition.bottom =>
                                        chinese ? '底部' : 'Bottom',
                                      DockPosition.top =>
                                        chinese ? '顶部' : 'Top',
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
      final near = _capsuleCross + _look.padding;
      return switch (_position) {
        DockPosition.bottom => Rect.fromLTWH(
          _output.left + slot.center - slot.half,
          _output.top + _surfaceHeight - near - extent,
          extent,
          extent,
        ),
        DockPosition.top => Rect.fromLTWH(
          _output.left + slot.center - slot.half,
          _output.top + near,
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

  /// The ink a part of another plugin is drawn in on the plate. The theme's
  /// own while it reads there; otherwise the opposite one, since a
  /// translucent plate over a dark wallpaper is dark in a light appearance
  /// too. The fill and its opacity are found the way [_capsuleSurface]
  /// finds them.
  Color _partInk(BuildContext context, ShellThemeData theme) {
    final chosen = _settings.look;
    final base = kitMaterialOf(context, KitTier.dock);
    final own = base.fill.fixed
        ? kitToneColor(base.fill, theme, KitStyle.of(context))
        : null;
    final surface = theme.colors.surfaceContainer;
    final fill = own != null && !chosen.containsKey(DockLook.tintKey)
        ? own
        : switch (_look.tint) {
            DockTint.theme => surface,
            DockTint.accent => Color.alphaBlend(
              theme.kitAccent.withValues(alpha: 0.30),
              surface,
            ),
            DockTint.custom => Color.lerp(
              const Color(0xFF000000),
              const Color(0xFFFFFFFF),
              _look.tintShade,
            )!,
          };
    final alpha = own != null && !chosen.containsKey(DockLook.opacityKey)
        ? own.a
        : _look.opacity ?? theme.effectivePanelOpacity;
    final dark = theme.brightness == Brightness.dark;
    final light = DockInk.lightInk(
      fill: DockInk.luminance(fill.r, fill.g, fill.b),
      opacity: alpha,
      backdrop: DockInk.luminance(_backdrop.r, _backdrop.g, _backdrop.b),
      themeDark: dark,
    );
    if (light == dark) return theme.colors.textPrimary;
    return light ? const Color(0xF2FFFFFF) : const Color(0xE6000000);
  }

  /// The capsule's plate: the dock material of the look in force, with what
  /// [_look] says laid over it. The preset's numbers and the user's own
  /// settings both arrive through [_look]; the material gives what the
  /// settings have no word for, such as the saturation and the shape of the
  /// rim, and a fill of its own until the user picks a tint or an opacity.
  Widget _capsuleSurface(BuildContext context, ShellThemeData theme) {
    final look = _look;
    final chosen = _settings.look;
    final corner = KitStyle.of(context).outer(theme, _effectiveCorner);
    final base = kitMaterialOf(context, KitTier.dock);
    final own = base.fill.fixed
        ? kitToneColor(base.fill, theme, KitStyle.of(context))
        : null;
    // The theme's fill is mixed from its own surface, not the glass backing:
    // that backing is a flat white or black chosen by the glass appearance
    // setting, so on a dark wallpaper it turned the dock into a pale bar
    // nothing else on screen shared. The surface colour already follows the
    // light or dark appearance.
    final surface = theme.colors.surfaceContainer;
    final fill = own != null && !chosen.containsKey(DockLook.tintKey)
        ? own
        : switch (look.tint) {
            DockTint.theme => surface,
            DockTint.accent => Color.alphaBlend(
              theme.kitAccent.withValues(alpha: 0.30),
              surface,
            ),
            DockTint.custom => Color.lerp(
              const Color(0xFF000000),
              const Color(0xFFFFFFFF),
              look.tintShade,
            )!,
          };
    // A look that names no opacity takes the system's panel opacity over its
    // whole range, so the dock is as clear or as solid as every other panel.
    final alpha = own != null && !chosen.containsKey(DockLook.opacityKey)
        ? own.a
        : look.opacity ?? theme.effectivePanelOpacity;
    if (alpha <= 0.001 && !look.border && look.shadow <= 0) {
      return const SizedBox.expand();
    }
    final inner = base.inner;
    final isBar = look.shape == DockShape.bar && !look.defloatOnTouch;
    final material = base.copyWith(
      // A preset that counts its blur in pixels has it drawn at that sigma;
      // any other is a share of the system's own blur.
      sigma: look.blurSigma,
      outer: !look.border || isBar ? () => null : null,
      inner: () => !look.border
          ? null
          : look.accentBorder
          ? KitLine(
              const KitTone.of(KitRole.border),
              width: look.borderWidth,
            )
          : inner == null
          ? null
          : KitLine(
              inner.tone,
              width: look.borderWidth,
              edges: isBar ? KitEdges.all : inner.edges,
              tail: isBar ? 0 : inner.tail,
              reach: isBar ? 0 : inner.reach,
            ),
    );
    // A glass surface owns the fade so the backdrop and foreground can fade
    // independently instead of being isolated in one opacity group.
    final fade = ShellSurfacePresentation.opacityOf(context);
    final plate = RepaintBoundary(
      child: KitGlass(
        material: material,
        radius: corner,
        fill: fill.withValues(alpha: alpha),
        blurScale: look.blurSigma == null ? look.blur : 1,
        separate: true,
        fade: fade,
        tier: KitTier.dock,
      ),
    );
    if (look.shadow <= 0) return plate;
    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: [
        IgnorePointer(
          child: FadeTransition(
            opacity: fade,
            child: CustomPaint(
              painter: _CapsuleShadowPainter(
                radius: corner,
                color: theme.colors.shadow,
                // A retracted dock keeps a strip of itself just past the
                // edge, and its shadow would reach back onto the screen.
                strength: look.shadow * _reveal.clamp(0.0, 1.0),
              ),
            ),
          ),
        ),
        plate,
      ],
    );
  }

  /// Half width of a divider's hit area. Slots sit 8 px apart, so the handle
  /// never reaches into an icon's own region.
  double get _dividerReach => math.max(6.0, _fit.dividerSpan * _spacing / 2);

  Widget _dividerHandle(Color color) {
    final vertical = !_position.isVertical;
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
      DockPosition.top => delta.dy,
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
    final shuffle = dragging
        ? KitMotion.duration(context, KitMotion.enter)
        : Duration.zero;
    // A liquid look lets a neighbour run a hair past its new slot and come
    // back; the other eases straight into it.
    final shuffleCurve = KitMotion.settleCurve(context);
    Widget slotAt({
      required double cross,
      required double mainExtent,
      required double crossExtent,
      required Widget child,
      Key? key,
    }) => switch (_position) {
      DockPosition.bottom => AnimatedPositioned(
        key: key,
        duration: shuffle,
        curve: shuffleCurve,
        left: main,
        bottom: cross,
        width: mainExtent,
        height: crossExtent,
        child: child,
      ),
      DockPosition.top => AnimatedPositioned(
        key: key,
        duration: shuffle,
        curve: shuffleCurve,
        left: main,
        top: cross,
        width: mainExtent,
        height: crossExtent,
        child: child,
      ),
      DockPosition.left => AnimatedPositioned(
        key: key,
        duration: shuffle,
        curve: shuffleCurve,
        top: main,
        left: cross,
        height: mainExtent,
        width: crossExtent,
        child: child,
      ),
      DockPosition.right => AnimatedPositioned(
        key: key,
        duration: shuffle,
        curve: shuffleCurve,
        top: main,
        right: cross,
        height: mainExtent,
        width: crossExtent,
        child: child,
      ),
    };

    // The plate behind an item reaches halfway into the gap along the row,
    // and across it either the whole plate, for a dock that keeps the cell
    // of the application in front lit, or as far as the marker leaves room.
    final markerOffset = _look.padding - _fit.markerInset * _spacing;
    final plateCross = _fit.activePlate
        ? _look.padding
        : math.max(
            0.0,
            math.min(_look.gap / 2, markerOffset - _fit.markerSize / 2 - 1),
          );
    Widget cell(Widget child, {bool active = false}) => DockCell(
      hover: _fit.highlight && !dragging,
      active: _fit.activePlate && active,
      outline: _fit.highlightOutline,
      main: _look.gap / 2,
      cross: plateCross,
      vertical: _vertical,
      child: child,
    );

    switch (spec.kind) {
      case _SlotKind.divider:
        // The line's length is a share of the plate, and it sits in the
        // middle of it.
        final line = _capsuleHeight * _fit.dividerLength;
        final inset = (_capsuleHeight - line) / 2;
        final dividerTheme = context.shellTheme;
        final dividerAlpha = _fit.dividerAlphaFor(
          dark: dividerTheme.brightness == Brightness.dark,
        );
        final handle = _dividerHandle(
          dividerAlpha == null
              ? dividerTheme.colors.hairline
              : dividerTheme.colors.textPrimary.withValues(
                  alpha: dividerAlpha,
                ),
        );
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
          DockPosition.top => AnimatedPositioned(
            key: ValueKey('dock-divider-${spec.dividerKey ?? 'default'}'),
            duration: Duration.zero,
            left: main + slot.half - _dividerReach,
            top: inset,
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
      case _SlotKind.part:
        final id = spec.partId;
        if (id == null) return null;
        final theme = context.shellTheme;
        return slotAt(
          key: ValueKey('dock-part-$id'),
          cross: _look.padding,
          mainExtent: extent,
          crossExtent: _iconSize,
          child: DockPartCell(
            id: id,
            vertical: _vertical,
            crossExtent: _iconSize,
            onExtent: (value) => _measuredPart(id, value),
            part: KitPartContext(
              edge: _kitEdge,
              axis: _vertical ? Axis.vertical : Axis.horizontal,
              crossExtent: _iconSize,
              ink: _partInk(context, theme),
              density: KitDensity.tile,
              host: KitHostKind.dock,
              // Where the capsule's far side rests, not where it is while
              // it slides: a panel hangs from the dock at rest.
              hostExtent: _edgeInset + _capsuleHeight,
              siblings: _settings.zones.parts.toList(growable: false),
              monitorId: widget.monitorId,
              services: widget.services,
              environment: widget.environment,
            ),
          ),
        );
      case _SlotKind.launcher:
        // A stable key keeps the launcher's menu state when a drag adds or
        // removes the divider and shifts this slot's index.
        return slotAt(
          key: const ValueKey('dock-launcher'),
          cross: _look.padding,
          mainExtent: extent,
          crossExtent: extent,
          child: cell(_LauncherItem(
            size: extent,
            lift: lift,
            position: _position,
            appearance: _settings.appearance,
            label: launcherLabel,
            onTap: widget.services.toggleLauncher,
            onOpenMenu: () => _openDockMenu(slot.center, launcher: true),
          )),
        );
      case _SlotKind.folder:
        final folder = spec.folder;
        if (folder == null) return null;
        return slotAt(
          key: ValueKey('dock-folder-${folder.path}'),
          cross: _look.padding,
          mainExtent: extent,
          crossExtent: extent,
          child: cell(DockFolderItem(
            folder: folder,
            size: extent,
            lift: lift,
            position: _position,
            zh: chinese,
            onRemove: () => unawaited(
              ref.read(dockSettingsProvider.notifier).removeFolder(folder.path),
            ),
            onOverlayChanged: _setOverlayHold,
            monitorBounds: _overlayOutput,
            workArea: _overlayWorkArea,
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
          )),
        );
      case _SlotKind.file:
        final file = spec.file;
        if (file == null) return null;
        return slotAt(
          key: ValueKey('dock-file-${file.path}'),
          cross: _look.padding,
          mainExtent: extent,
          crossExtent: extent,
          child: cell(DockFileItem(
            file: file,
            size: extent,
            lift: lift,
            position: _position,
            zh: chinese,
            appearance: _settings.appearance,
            monitorBounds: _overlayOutput,
            onOpen: () => unawaited(DockExtras.openPath(file.path)),
            onReveal: () => unawaited(DockExtras.revealPath(file.path)),
            onRemove: () => unawaited(
              ref.read(dockSettingsProvider.notifier).removeFile(file.path),
            ),
            onOpenSettings: _openSettings,
            onOverlayChanged: _setOverlayHold,
          )),
        );
      case _SlotKind.trash:
        return slotAt(
          key: const ValueKey('dock-trash'),
          cross: _look.padding,
          mainExtent: extent,
          crossExtent: extent,
          child: cell(DockTrashItem(
            size: extent,
            lift: lift,
            position: _position,
            zh: chinese,
            onOverlayChanged: _setOverlayHold,
            monitorBounds: _overlayOutput,
            onOpenSettings: _openSettings,
            appearance: _settings.appearance,
          )),
        );
      case _SlotKind.minimized:
        final win = spec.minimizedWindow;
        if (win == null) return null;
        return slotAt(
          key: ValueKey('dock-min-${win.id}'),
          cross: _look.padding,
          mainExtent: extent,
          crossExtent: extent,
          child: cell(_MinimizedWindowItem(
            window: win,
            size: extent,
            lift: lift,
            position: _position,
            services: widget.services,
            onRestore: () => widget.services.activateWindow(win.id),
          )),
        );
      case _SlotKind.overflow:
        final folded = <_DockEntry>[
          for (final idx in spec.overflowEntries)
            if (idx >= 0 && idx < entries.length) entries[idx],
        ];
        if (folded.isEmpty) return null;
        return slotAt(
          key: const ValueKey('dock-overflow'),
          cross: _look.padding,
          mainExtent: extent,
          crossExtent: extent,
          child: cell(_OverflowAppsItem(
            entries: folded,
            size: extent,
            lift: lift,
            position: _position,
            services: widget.services,
            monitorId: widget.monitorId,
            monitorBounds: _overlayOutput,
            onOverlayChanged: _setOverlayHold,
            zh: chinese,
          )),
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
        final taskCross = spec.titled && _vertical
            ? _verticalTaskCross
            : (spec.titled ? _iconSize : extent);
        return slotAt(
          key: ValueKey('dock-${entry.appId}'),
          cross: _look.padding,
          mainExtent: extent,
          crossExtent: taskCross,
          child: Opacity(
            opacity: isSource ? 0 : 1,
            child: cell(
              active: entry.windows.any((window) => window.active),
              DockItemWidget(
              appId: entry.appId,
              launchId: entry.launchId,
              name: entry.name,
              windows: entry.windows,
              pinned: entry.pin != null,
              dragging: dragging,
              services: widget.services,
              monitorId: widget.monitorId,
              monitorBounds: _overlayOutput,
              position: _position,
              size: spec.titled ? _iconSize : extent,
              cellExtent: spec.titled
                  ? (_vertical ? _verticalTaskCross : extent)
                  : null,
              title: spec.titled ? _taskTitle(entry) : null,
              metrics: _fit,
              markerOffset: markerOffset,
              lift: lift,
              clickAction: settings.clickAction,
              scrollAction: settings.scrollAction,
              workspaceStatus: _workspaceStatus,
              scrollGate: _scrollGate,
              scrollReversed: settings.scrollReversed,
              scrollWraps: settings.scrollWraps,
              motion: _motion,
              // A look that does not hop answers a launch with the pulse.
              launchFeedback:
                  !_fit.hop && settings.launchFeedback == DockLaunchFeedback.hop
                  ? DockLaunchFeedback.pulse
                  : _motion.launchFeedback(settings.launchFeedback),
              indicatorStyle: _fit.indicator,
              markerColor: _look.markerColor,
              previewStyle: settings.previewStyle,
              previewHover: settings.previewHover,
              previewDelayMs: settings.previewDelayMs,
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
              iconMode: dockIconModeNow(settings),
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
              onDragCancel: settings.lockItems ? null : _cancelDrag,
            )),
          ),
        );
    }
  }

  /// What a task button says: the title of the application's window in
  /// front, or of its first one, and the application's name when the window
  /// has none.
  static String _taskTitle(_DockEntry entry) {
    var window = entry.windows.first;
    for (final candidate in entry.windows) {
      if (candidate.active) {
        window = candidate;
        break;
      }
    }
    final title = window.title.trim();
    return title.isEmpty ? entry.name : title;
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
      _SlotKind.minimized =>
        spec.minimizedWindow == null
            ? null
            : _LabelTarget(
                key: 'min-${spec.minimizedWindow!.id}',
                name: spec.minimizedWindow!.title.trim().isEmpty
                    ? spec.minimizedWindow!.appId
                    : spec.minimizedWindow!.title,
                center: center,
              ),
      _SlotKind.overflow => _LabelTarget(
        key: 'overflow',
        name: chinese
            ? '更多应用 (${spec.overflowEntries.length})'
            : 'More Apps (${spec.overflowEntries.length})',
        center: center,
      ),
      _SlotKind.divider || _SlotKind.part => null,
    };
  }
}

enum _SlotKind {
  app,
  launcher,
  folder,
  file,
  trash,
  minimized,
  overflow,
  divider,
  part,
}

class _SlotSpec {
  const _SlotSpec({
    required this.kind,
    required this.half,
    this.entry,
    this.folder,
    this.file,
    this.dividerKey,
    this.partId,
    this.minimizedWindow,
    this.overflowEntries = const <int>[],
    this.titled = false,
  });

  /// Whether this is a task button: an application's icon with its
  /// window's title beside it.
  final bool titled;

  final _SlotKind kind;
  final double half;
  final int? entry;
  final DockFolder? folder;
  final DockFile? file;
  final String? dividerKey;
  final String? partId;
  final ApplicationWindow? minimizedWindow;
  final List<int> overflowEntries;

  /// Whether the slot is one icon: it grows under the pointer and shrinks
  /// with the row.
  bool get growable =>
      kind != _SlotKind.divider && kind != _SlotKind.part && !titled;
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
        DockPosition.top => Offset(0, widget.lift),
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
                    accent: theme.kitAccent,
                    pressed: _pressed,
                    child: SizedBox.square(
                      dimension: widget.size * 0.42,
                      child: CustomPaint(
                        painter: _LauncherGlyphPainter(theme.kitAccent),
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// A live thumbnail tile for a minimized window at the accessory end of the
/// dock, with a mini application icon badge in the corner.
class _MinimizedWindowItem extends StatelessWidget {
  const _MinimizedWindowItem({
    required this.window,
    required this.size,
    required this.lift,
    required this.position,
    required this.services,
    required this.onRestore,
  });

  final ApplicationWindow window;
  final double size;
  final double lift;
  final DockPosition position;
  final ShellServices services;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final radius = BorderRadius.circular(size * 0.18);
    return Transform.translate(
      offset: switch (position) {
        DockPosition.bottom => Offset(0, -lift),
        DockPosition.top => Offset(0, lift),
        DockPosition.left => Offset(lift, 0),
        DockPosition.right => Offset(-lift, 0),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onRestore,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: radius,
                  color: theme.panelColor(theme.colors.surfaceContainerHigh),
                  border: Border.all(color: theme.colors.hairline),
                ),
                child: ClipRRect(
                  borderRadius: radius,
                  child: services.buildWindowPreview(context, window.id),
                ),
              ),
            ),
            Positioned(
              right: -2,
              bottom: -2,
              width: size * 0.40,
              height: size * 0.40,
              child: services.buildApplicationIcon(context, window.appId),
            ),
          ],
        ),
      ),
    );
  }
}

/// Overflow collapse button shown when the dock still exceeds the monitor's
/// width even at minimum icon size; clicking opens a glass popover grid of
/// the overflowed applications.
class _OverflowAppsItem extends StatefulWidget {
  const _OverflowAppsItem({
    required this.entries,
    required this.size,
    required this.lift,
    required this.position,
    required this.services,
    required this.monitorId,
    required this.monitorBounds,
    required this.onOverlayChanged,
    required this.zh,
  });

  final List<_DockEntry> entries;
  final double size;
  final double lift;
  final DockPosition position;
  final ShellServices services;
  final int monitorId;
  final Rect monitorBounds;
  final ValueChanged<bool> onOverlayChanged;
  final bool zh;

  @override
  State<_OverflowAppsItem> createState() => _OverflowAppsItemState();
}

class _OverflowAppsItemState extends State<_OverflowAppsItem> {
  final OverlayPortalController _portal = OverlayPortalController();
  bool _open = false;

  void _toggle() {
    if (_open) {
      _close();
    } else {
      setState(() => _open = true);
      if (!_portal.isShowing) _portal.show();
      widget.onOverlayChanged(true);
    }
  }

  void _close() {
    if (!_open) return;
    setState(() => _open = false);
    _portal.hide();
    widget.onOverlayChanged(false);
  }

  @override
  void dispose() {
    if (_open) widget.onOverlayChanged(false);
    super.dispose();
  }

  void _activate(_DockEntry entry) {
    _close();
    if (entry.windows.isNotEmpty) {
      widget.services.activateWindow(entry.windows.first.id);
    } else if (entry.launchId != null) {
      unawaited(widget.services.launchApplication(entry.launchId!));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    return OverlayPortal.overlayChildLayoutBuilder(
      controller: _portal,
      overlayChildBuilder: (context, layout) {
        if (!_open) return const SizedBox.shrink();
        final anchor = MatrixUtils.transformRect(
          layout.childPaintTransform,
          Offset.zero & layout.childSize,
        );
        final scene = Offset.zero & layout.overlaySize;
        final bounds = widget.monitorBounds.intersect(scene);
        final out = bounds.isEmpty ? scene : bounds;
        final width = math.min(264.0, math.max(160.0, out.width - 24));
        final placement = dockMenuAnchor(
          anchor: anchor,
          output: out,
          width: width,
          position: widget.position,
        );
        if (placement == null) return const SizedBox.shrink();
        return ShellInputRegion(
          debugLabel: 'Dock overflow popover',
          pointerPolicy: ShellPointerPolicy.fullScene,
          keyboardPolicy: ShellKeyboardPolicy.capture,
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.escape): _close,
            },
            child: Focus(
              autofocus: true,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: (_) => _close(),
                      child: const ColoredBox(color: Color(0x00000000)),
                    ),
                  ),
                  DockMenuLayer(
                    anchor: placement,
                    overlaySize: layout.overlaySize,
                    child: GlassCard(
                      tier: KitTier.popover,
                      radius: 16,
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final entry in widget.entries)
                              GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => _activate(entry),
                                child: SizedBox(
                                  width: 56,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      SizedBox.square(
                                        dimension: 38,
                                        child: widget.services
                                            .buildApplicationIcon(
                                              context,
                                              entry.appId,
                                            ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        entry.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        textAlign: TextAlign.center,
                                        style: theme
                                            .text
                                            .systemBarCaption
                                            .inLook
                                            .copyWith(
                                              fontSize: 10,
                                              color: theme.colors.textPrimary,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
      child: Transform.translate(
        offset: switch (widget.position) {
          DockPosition.bottom => Offset(0, -widget.lift),
          DockPosition.top => Offset(0, widget.lift),
          DockPosition.left => Offset(widget.lift, 0),
          DockPosition.right => Offset(-widget.lift, 0),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggle,
          child: DockTile(
            size: widget.size,
            accent: theme.kitAccent,
            pressed: _open,
            child: Icon(
              Icons.more_horiz_rounded,
              size: widget.size * 0.5,
              color: theme.colors.textPrimary,
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
    this.shape = DockLabelShape.bubble,
    this.fontSize,
    this.weight = 600,
  });

  /// Whether the label is a pill with a tail, a pill, or a plate with the
  /// look's corners and line.
  final DockLabelShape shape;

  /// The type size; null scales it with the icon.
  final double? fontSize;

  /// The type's weight, as a CSS number.
  final int weight;

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
    final fontSize = this.fontSize ?? (iconSize * 0.26).clamp(11.0, 13.0);
    final padV = (iconSize * 0.10).clamp(4.0, 6.0);
    final padH = (iconSize * 0.24).clamp(10.0, 14.0);
    final height = fontSize * 1.25 + padV * 2;
    final tailSize = shape == DockLabelShape.bubble
        ? (iconSize * 0.13).clamp(6.0, 9.0)
        : 0.0;
    // The bubble grows out of its tail when it first appears. Sliding along
    // the row keeps the same bubble, so it does not replay between icons.
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: KitMotion.duration(context, KitMotion.fade),
      curve: KitMotion.outCubic,
      builder: (context, shown, child) => Opacity(
        opacity: shown,
        child: Transform.scale(
          scale: 0.9 + 0.1 * shown,
          alignment: !horizontal
              ? Alignment.bottomCenter
              : tailLeading
              ? Alignment.centerLeft
              : Alignment.centerRight,
          child: child,
        ),
      ),
      child: _bubble(theme, fontSize, padV, padH, tailSize, height),
    );
  }

  Widget _bubble(
    ShellThemeData theme,
    double fontSize,
    double padV,
    double padH,
    double tailSize,
    double height,
  ) {
    final style = kitStyle.value;
    final tag = shape == DockLabelShape.tag;
    return CustomPaint(
      painter: _BubblePainter(
        color: background,
        // A tag is one of the look's panels in small: its line and corners.
        border: tag ? style.border(theme) : border,
        borderWidth: tag ? style.borderWidth : 1,
        radius: tag ? style.corner(8) : style.pill(height),
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
          style: theme.text.systemBarCaption.inLook.copyWith(
            color: foreground,
            fontSize: fontSize,
            fontWeight: FontWeight.values[(weight ~/ 100 - 1).clamp(0, 8)],
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
    this.borderWidth = 1,
  });

  final double borderWidth;
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
    final shape = tail > 0
        ? Path.combine(PathOperation.union, body, point)
        : body;
    canvas.drawPath(shape, Paint()..color = color);
    canvas.drawPath(
      shape,
      Paint()
        ..color = border
        ..style = PaintingStyle.stroke
        ..strokeWidth = borderWidth
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _BubblePainter old) =>
      old.borderWidth != borderWidth ||
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

/// The shadow under the capsule, drawn only outside it. The plate is
/// translucent, so a plain box shadow would show through the fill and darken
/// the glass it is meant to lift.
class _CapsuleShadowPainter extends CustomPainter {
  const _CapsuleShadowPainter({
    required this.radius,
    required this.color,
    required this.strength,
  });

  final double radius;
  final Color color;

  /// From zero to one: how dark and how wide the shadow is.
  final double strength;

  @override
  void paint(Canvas canvas, Size size) {
    final plate = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final spread = 10 + 14 * strength;
    canvas
      ..save()
      ..clipPath(
        Path()
          ..fillType = PathFillType.evenOdd
          ..addRect((Offset.zero & size).inflate(spread * 3))
          ..addRRect(plate),
      )
      ..drawRRect(
        plate.shift(Offset(0, 3 + 5 * strength)),
        Paint()
          ..color = color.withValues(alpha: 0.5 * strength)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, spread),
      )
      ..restore();
  }

  @override
  bool shouldRepaint(covariant _CapsuleShadowPainter old) =>
      old.radius != radius || old.color != color || old.strength != strength;
}
