import 'dart:async';
import 'dart:math' as math;

import 'package:denial_shell_kit/kit_style.dart';
import 'package:denial_flutter_sdk/input.dart';
import 'package:denial_flutter_sdk/services.dart';
import 'package:denial_flutter_sdk/surfaces.dart';
import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/gestures.dart'
    show
        GestureBinding,
        PointerDeviceKind,
        PointerScrollEvent,
        PointerSignalEvent,
        kLongPressTimeout,
        kPrimaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'package:denial_shell_kit/glass_card.dart';

import 'dock_click.dart';
import 'dock_debug.dart';
import 'dock_desktop_actions.dart';
import 'dock_drag.dart';
import 'dock_icon.dart';
import 'dock_launch.dart';
import 'dock_menu.dart';
import 'dock_motion.dart';
import 'dock_scroll.dart';
import 'dock_settings.dart';

/// Windows `MouseHoverTime`, 400 ms.
const int previewHoverDelayMs = 400;

/// The stack keeps the same wait as Windows' flyout.
const int stackPreviewHoverDelayMs = 400;

/// Windows `MouseHoverSize`, 4 px.
const double _hoverRestExtent = 4;

/// Opacity of a pinned application that has no window, when dimming is on.
const double _inactivePinOpacity = 0.62;

/// A single application icon in the dock. Menus and window previews live in the
/// shell overlay; a shell surface has no Navigator or Scaffold of its own.
class DockItemWidget extends StatefulWidget {
  const DockItemWidget({
    required this.appId,
    required this.launchId,
    required this.name,
    required this.windows,
    required this.pinned,
    required this.dragging,
    required this.services,
    required this.monitorId,
    required this.monitorBounds,
    required this.position,
    required this.size,
    required this.lift,
    required this.clickAction,
    required this.scrollAction,
    required this.workspaceStatus,
    required this.scrollGate,
    required this.scrollReversed,
    required this.scrollWraps,
    required this.motion,
    required this.launchFeedback,
    required this.indicatorStyle,
    required this.previewStyle,
    required this.previewHover,
    required this.dimInactivePinned,
    required this.badge,
    required this.progress,
    required this.attention,
    required this.audioMuted,
    required this.middleClickAction,
    required this.showDesktopActions,
    required this.previewMiddleClose,
    required this.activation,
    required this.iconMode,
    required this.iconOpacity,
    required this.tintColor,
    required this.onTogglePin,
    required this.onCloseWindows,
    required this.onOverlayChanged,
    required this.previewOwner,
    required this.onPreviewOwnerChanged,
    this.onDragStart,
    this.onDragUpdate,
    this.onDragEnd,
    this.onDragCancel,
    super.key,
  });

  /// Icon identity.
  final String appId;

  /// Persistent launch identity from [LaunchableApplication.id].
  final String? launchId;

  final String name;
  final List<ApplicationWindow> windows;
  final bool pinned;

  /// True while another pinned icon is being dragged; hover previews stay shut.
  final bool dragging;

  final ShellServices services;
  final int monitorId;
  final Rect? monitorBounds;

  /// Which screen edge the dock is attached to.
  final DockPosition position;

  /// Painted edge length for the current magnification.
  final double size;

  /// Extra offset away from the screen edge for the magnified icon.
  final double lift;

  /// What a click on the front-most application does.
  final DockClickAction clickAction;

  /// What a wheel turn over this icon does.
  final DockScrollAction scrollAction;

  /// Workspace count and active workspace, resolved by the container so the
  /// wheel handler does not need to listen to a provider itself.
  final WorkspaceStatus workspaceStatus;

  /// The dock's single wheel gate. Shared by every icon and the capsule, so
  /// crossing icons mid-swipe cannot step twice.
  final DockScrollGate scrollGate;

  /// Inverts the wheel direction, and lets the last workspace wrap.
  final bool scrollReversed;
  final bool scrollWraps;

  /// The dock's motion policy; it decides how attention shows.
  final DockMotion motion;

  /// The launch feedback in effect, which with reduced motion is never the
  /// hop.
  final DockLaunchFeedback launchFeedback;
  final DockIndicatorStyle indicatorStyle;
  final DockPreviewStyle previewStyle;

  /// Focuses a previewed window when the pointer moves onto its row.
  final DockPreviewHover previewHover;

  /// Fades a pinned icon that has no window.
  final bool dimInactivePinned;

  /// Unread notifications for this application; zero hides the badge.
  final int badge;

  /// Progress the application publishes, from zero to one; null hides the bar.
  final double? progress;

  /// The application is asking for attention.
  final bool attention;

  /// Null while the application plays nothing, otherwise whether every stream
  /// of it is silent.
  final bool? audioMuted;

  final DockMiddleClickAction middleClickAction;

  /// Lists the desktop file's own actions in the menu.
  final bool showDesktopActions;

  /// A middle click on a window preview closes that window.
  final bool previewMiddleClose;

  /// A shortcut's request to act as if this icon had been clicked.
  final ValueListenable<({String key, int serial})?> activation;

  final DockIconMode iconMode;
  final double iconOpacity;

  /// Resolved tinted-mode colour.
  final Color tintColor;

  final VoidCallback onTogglePin;

  /// Closes every listed window through the compositor's close request. Denial
  /// has no app-level quit, so this is what "quit" means here: the application
  /// exits once its last window closes, unless it keeps running in the tray.
  final ValueChanged<List<int>> onCloseWindows;

  /// Which icon owns the preview overlay. The container keeps one owner at a
  /// time so a stack open on one icon closes as the pointer moves to another.
  final String? previewOwner;

  /// Asks the container to hand the overlay to [appId], or to no icon.
  final ValueChanged<String?> onPreviewOwnerChanged;

  /// Keeps the dock expanded while a menu or preview tray is open.
  final ValueChanged<bool> onOverlayChanged;

  /// Pinned icons can be dragged along the dock to reorder, or away from the
  /// screen edge to remove them. Null on unpinned running entries. The
  /// callbacks carry the pointer's scene position: the shell's button pointer
  /// can start at the scene origin, so the dock tracks absolute positions
  /// instead of deltas.
  final ValueChanged<Offset>? onDragStart;
  final ValueChanged<Offset>? onDragUpdate;
  final VoidCallback? onDragEnd;

  /// Puts a picked-up icon back without dropping it anywhere: a finger that
  /// held the icon and let go where it was, or a touch the system took away.
  final VoidCallback? onDragCancel;

  @override
  State<DockItemWidget> createState() => _DockItemWidgetState();
}

class _DockItemWidgetState extends State<DockItemWidget>
    with TickerProviderStateMixin {
  final OverlayPortalController _portal = OverlayPortalController();
  final FocusNode _focus = FocusNode(debugLabel: 'Dock application');

  /// One ticker drives both the hop and its landing glide. The hop runs until
  /// a window appears (with a 500 ms floor and a 15 s ceiling); the glide then
  /// eases the icon back to the row instead of dropping it.
  late final Ticker _launchTicker;
  Duration _launchLastTick = Duration.zero;
  DateTime? _launchStartedAt;
  bool _launchHopping = false;
  double _launchPhase = 0;
  double _launchLift = 0;
  double _launchPulse = 1;
  double _landingProgress = 1;
  double _landingStartLift = 0;
  bool _launchFailed = false;

  /// The press under way, or null between presses and for any button but the
  /// primary one. A mouse picks the icon up by travelling; a finger or pen has
  /// to rest on it first, so a swipe across the dock leaves the row alone.
  DockPress? _press;
  DockPointerKind _pressKind = DockPointerKind.precise;

  /// The pointer that owns [_press], so a second finger cannot end it.
  int _pressPointer = -1;

  /// Touch and pen have no right button, so resting on the icon is their long
  /// press. It lifts the icon; letting go without moving opens the menu the
  /// secondary button opens. The flag keeps that release from also counting
  /// as a click.
  Timer? _longPressTimer;
  bool _longPressFired = false;

  /// Press feedback: a light wash that appears on press and fades out, as in
  /// the reference docks.
  Timer? _pressTimer;
  bool _pressed = false;

  Timer? _showPreviewTimer;
  Timer? _hidePreviewTimer;
  Offset? _hoverRestPoint;
  Timer? _emphasisTimer;
  Timer? _hoverSwitchTimer;
  VoidCallback? _emphasisRelease;
  int? _emphasisWindow;

  /// The window whose preview the pointer is on. It gets the accent ring,
  /// whether or not the previews switch focus.
  int? _hoverPreview;

  Offset? _downPosition;
  int _downButtons = 0;

  bool _menuOpen = false;
  bool _previewsOpen = false;

  /// The windows the panel was built from, in the order it showed them.
  ///
  /// The host reports windows by stacking order, so activating one reorders
  /// the list and swaps the rows under the pointer; the row that slid into
  /// place then activates too, and the panel oscillates. The order is taken
  /// once when the panel opens and kept until it closes.
  List<ApplicationWindow> _previewWindows = const [];
  bool _launching = false;
  String? _launchError;

  /// Hops the icon for as long as the application asks for attention.
  late final AnimationController _attention;

  /// The desktop file's actions, read when the menu first opens.
  List<DesktopAction>? _desktopActions;

  bool get _overlayOpen => _menuOpen || _previewsOpen;

  /// Unit vector pointing away from the screen edge the dock is attached to.
  Offset get _away => switch (widget.position) {
    DockPosition.bottom => const Offset(0, -1),
    DockPosition.left => const Offset(1, 0),
    DockPosition.right => const Offset(-1, 0),
  };

  @override
  void initState() {
    super.initState();
    _launchTicker = createTicker(_onLaunchTick);
    _attention = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    if (widget.attention) unawaited(_attention.repeat());
    widget.activation.addListener(_onActivation);
    _debug = DockDebug.commands.listen(_onDebug);
  }

  StreamSubscription<List<String>>? _debug;

  void _onDebug(List<String> words) {
    if (!mounted) return;
    if (words.first == 'close') return _closeOverlay();
    if (words.length < 2 || !appIdentity(widget.appId).contains(words[1])) {
      return;
    }
    switch (words.first) {
      case 'preview':
        _showPreviews();
      case 'menu':
        _openMenu();
    }
  }

  void _onActivation() {
    final request = widget.activation.value;
    if (request == null || !mounted) return;
    final launch = widget.launchId;
    if (request.key != appIdentity(widget.appId) &&
        (launch == null || request.key != appIdentity(launch))) {
      return;
    }
    _activate();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!ShellSurfacePresentation.visibleOf(context) && _portal.isShowing) {
      _hideImmediately();
    }
  }

  @override
  void didUpdateWidget(covariant DockItemWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.activation != oldWidget.activation) {
      oldWidget.activation.removeListener(_onActivation);
      widget.activation.addListener(_onActivation);
    }
    if (widget.attention != oldWidget.attention) {
      if (widget.attention) {
        unawaited(_attention.repeat());
      } else {
        _attention
          ..stop()
          ..value = 0;
      }
    }
    if (widget.launchId != oldWidget.launchId ||
        widget.appId != oldWidget.appId) {
      _desktopActions = null;
    }
    if (widget.windows.isEmpty &&
        oldWidget.windows.isNotEmpty &&
        _overlayOpen) {
      _closeOverlay();
    }
    final ids = widget.windows.map((window) => window.id).toSet();
    if (_emphasisWindow != null && !ids.contains(_emphasisWindow)) {
      _clearEmphasis();
    }
    // Only the stack style hands its overlay to a neighbouring icon; the cards
    // style keeps the owner null, so comparing against it unconditionally
    // closed every cards preview on the rebuild its own open had just asked
    // for.
    if (widget.previewStyle == DockPreviewStyle.stack &&
        _previewsOpen &&
        widget.previewOwner != widget.appId) {
      // Give the counted hold back, or the dock stays held for good.
      _previewsOpen = false;
      _previewWindows = const [];
      _previewHoverDepth = 0;
      _clearEmphasis();
      _portal.hide();
      widget.onOverlayChanged(false);
    }
  }

  @override
  void dispose() {
    _showPreviewTimer?.cancel();
    _hidePreviewTimer?.cancel();
    _longPressTimer?.cancel();
    _pressTimer?.cancel();
    _hoverSwitchTimer?.cancel();
    _clearEmphasis();
    widget.activation.removeListener(_onActivation);
    unawaited(_debug?.cancel());
    _attention.dispose();
    // Give the counted hold back, or the dock never retracts again.
    if (_overlayOpen) widget.onOverlayChanged(false);
    _focus.dispose();
    _launchTicker.dispose();
    super.dispose();
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final action = widget.scrollAction;
    if (action == DockScrollAction.nothing) return;
    if (action == DockScrollAction.cycleWindows && widget.windows.isEmpty) {
      return;
    }
    if (action == DockScrollAction.switchWorkspace &&
        widget.workspaceStatus.count <= 1) {
      return;
    }
    final step = widget.scrollGate.feed(
      event.scrollDelta.dy,
      event.timeStamp.inMilliseconds,
    );
    if (step == null) return;
    final direction = widget.scrollReversed ? -step : step;
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      switch (action) {
        case DockScrollAction.nothing:
          return;
        case DockScrollAction.cycleWindows:
          final windows = widget.windows;
          final next = DockClick.scrollIndex(
            count: windows.length,
            activeIndex: DockClick.activeIndex(
              windows.map((window) => window.active),
            ),
            down: direction > 0,
          );
          if (next != null) widget.services.activateWindow(windows[next].id);
        case DockScrollAction.switchWorkspace:
          final status = widget.workspaceStatus;
          final target = nextWorkspace(
            count: status.count,
            active: status.active,
            step: direction,
            wrap: widget.scrollWraps,
          );
          if (target == null) return;
          widget.services.switchWorkspace(
            monitorId: widget.monitorId,
            workspaceId: target,
          );
      }
    });
  }

  /// Windows waits 400 ms before a thumbnail flyout, Omarchy's dock 300 ms
  /// before its stack. The card row needs two windows to be worth opening; the
  /// stack opens for a single window too, as Omarchy's does.
  int get _previewDelayMs => widget.previewStyle == DockPreviewStyle.stack
      ? stackPreviewHoverDelayMs
      : previewHoverDelayMs;

  bool get _wantsPreviews => widget.previewStyle == DockPreviewStyle.stack
      ? widget.windows.isNotEmpty
      : widget.windows.length > 1;

  void _enter() {
    _hidePreviewTimer?.cancel();
    _hidePreviewTimer = null;
    _hoverRestPoint = null;
    if (widget.dragging || _menuOpen || !_wantsPreviews) return;
    // Every icon waits out its own dwell; a neighbour that opened at once
    // flashed a panel for each icon the pointer crossed.
    if (_showPreviewTimer == null) _armPreviewTimer();
  }

  void _armPreviewTimer() {
    _showPreviewTimer?.cancel();
    _showPreviewTimer = Timer(Duration(milliseconds: _previewDelayMs), () {
      _showPreviewTimer = null;
      if (mounted && _wantsPreviews) _showPreviews();
    });
  }

  /// Restarts the dwell while the pointer is still travelling, so the clock
  /// measures rest instead of approach.
  void _restartPreviewOnMove(PointerHoverEvent event) {
    if (_showPreviewTimer == null || _previewsOpen) return;
    final last = _hoverRestPoint;
    _hoverRestPoint = event.position;
    if (last == null) return;
    if ((event.position - last).distance < _hoverRestExtent) return;
    _armPreviewTimer();
  }

  /// Regions holding the pointer: icon, gap, panel. A counter because a
  /// hand-over sends the exit before the enter.
  int _previewHoverDepth = 0;
  bool get _previewsHovered => _previewHoverDepth > 0;

  void _leave() {
    _showPreviewTimer?.cancel();
    _showPreviewTimer = null;
    if (!_previewsOpen) return;
    _scheduleHide();
  }

  /// Closes the panel shortly after the pointer leaves it, so the next icon's
  /// panel has to wait out its own dwell. Handing the open panel over instead
  /// left it on screen through that dwell and the swap read as no delay.
  void _scheduleHide() {
    _hidePreviewTimer?.cancel();
    _hidePreviewTimer = Timer(const Duration(milliseconds: 120), () {
      _hidePreviewTimer = null;
      if (!mounted || !_previewsOpen) return;
      if (_previewsHovered) return;
      _closeOverlay();
    });
  }

  void _setPreviewsHovered(bool inside) {
    final was = _previewsHovered;
    _previewHoverDepth = math.max(0, _previewHoverDepth + (inside ? 1 : -1));
    if (_previewsHovered) {
      _hidePreviewTimer?.cancel();
      _hidePreviewTimer = null;
    } else if (was) {
      _leave();
    }
  }

  void _showPreviews() {
    if (_previewsOpen || widget.windows.isEmpty) return;
    setState(() {
      _previewsOpen = true;
      _menuOpen = false;
      _previewWindows = widget.windows;
    });
    if (!_portal.isShowing) _portal.show();
    if (widget.previewStyle == DockPreviewStyle.stack) {
      widget.onPreviewOwnerChanged(widget.appId);
    }
    widget.onOverlayChanged(true);
  }

  void _openMenu() {
    _showPreviewTimer?.cancel();
    _showPreviewTimer = null;
    _hidePreviewTimer?.cancel();
    _clearEmphasis();
    setState(() {
      _menuOpen = true;
      _previewsOpen = false;
    });
    if (!_portal.isShowing) _portal.show();
    _focus.requestFocus();
    widget.onOverlayChanged(true);
    if (widget.showDesktopActions && _desktopActions == null) {
      unawaited(_loadDesktopActions());
    }
  }

  Future<void> _loadDesktopActions() async {
    final locale = Localizations.localeOf(context);
    final country = locale.countryCode;
    final actions = await DesktopActions.load(
      [?widget.launchId, widget.appId],
      locale: country == null || country.isEmpty
          ? locale.languageCode
          : '${locale.languageCode}_$country',
    );
    if (!mounted) return;
    setState(() => _desktopActions = actions);
  }

  void _closeOverlay() {
    _hidePreviewTimer?.cancel();
    _previewHoverDepth = 0;
    _previewWindows = const [];
    _clearEmphasis();
    if (!_overlayOpen) return;
    final gaveUpPreviews = _previewsOpen;
    setState(() {
      _menuOpen = false;
      _previewsOpen = false;
    });
    _portal.hide();
    widget.onOverlayChanged(false);
    if (gaveUpPreviews && widget.previewOwner == widget.appId) {
      widget.onPreviewOwnerChanged(null);
    }
  }

  void _hideImmediately() {
    _showPreviewTimer?.cancel();
    _hidePreviewTimer?.cancel();
    _previewHoverDepth = 0;
    _previewWindows = const [];
    _clearEmphasis();
    if (!_overlayOpen) return;
    final gaveUpPreviews = _previewsOpen;
    _menuOpen = false;
    _previewsOpen = false;
    _portal.hide();
    widget.onOverlayChanged(false);
    if (gaveUpPreviews && widget.previewOwner == widget.appId) {
      widget.onPreviewOwnerChanged(null);
    }
  }

  /// A mouse and a trackpad steer a cursor. Everything else lands on the
  /// icon directly, and may only be passing over it.
  static DockPointerKind _pointerKind(PointerDeviceKind kind) => switch (kind) {
    PointerDeviceKind.mouse ||
    PointerDeviceKind.trackpad => DockPointerKind.precise,
    _ => DockPointerKind.touch,
  };

  void _pointerDown(PointerDownEvent event) {
    // A second finger must not take over an icon another one already holds.
    if (_press == DockPress.lifted || _press == DockPress.dragging) return;
    // The pan's start position is unreliable in this shell (the button
    // pointer begins at the scene origin), but the down event carries the
    // real grab point.
    _downPosition = event.position;
    _downButtons = event.buttons;
    _longPressTimer?.cancel();
    _longPressTimer = null;
    _longPressFired = false;
    _press = null;
    if (event.buttons != kPrimaryButton) return;
    _pressDown();
    _press = DockPress.down;
    _pressKind = _pointerKind(event.kind);
    _pressPointer = event.pointer;
    if (_pressKind == DockPointerKind.touch) {
      // The SDK exposes no long-press time of its own, so this is Flutter's.
      _longPressTimer = Timer(kLongPressTimeout, _pointerRested);
    }
  }

  /// The finger or pen has stayed on the icon for the long-press time.
  void _pointerRested() {
    _longPressTimer = null;
    final press = _press;
    final origin = _downPosition;
    if (!mounted || press == null || origin == null) return;
    if (DockDrag.pressRested(press, _pressKind) != DockPress.lifted) return;
    // Whatever the release does now, it is not a click.
    _longPressFired = true;
    final start = widget.onDragStart;
    if (start == null) {
      // Locked items cannot be picked up, so there is nothing to tell apart
      // and the menu opens under the finger, as it does without the lock.
      _press = null;
      _openMenu();
      return;
    }
    if (widget.dragging) {
      // Another icon is already in the air; this hold must not steer it.
      _press = null;
      return;
    }
    _press = DockPress.lifted;
    // The container draws the icon raised off the row, exactly as it does for
    // a drag. That lift is the cue that the hold has armed.
    start(origin);
  }

  void _pointerMove(PointerMoveEvent event) {
    final press = _press;
    final origin = _downPosition;
    // A mouse is followed by the pan recogniser below.
    if (press == null ||
        origin == null ||
        _pressKind != DockPointerKind.touch ||
        event.pointer != _pressPointer) {
      return;
    }
    final next = DockDrag.leftRest((event.position - origin).distance)
        ? DockDrag.pressTravelled(press, _pressKind)
        : press;
    _press = next;
    switch (next) {
      case DockPress.swipe:
        _longPressTimer?.cancel();
        _longPressTimer = null;
      case DockPress.lifted || DockPress.dragging:
        // Fed from the raw pointer: the pan recogniser waits out its own,
        // wider touch slop, which would hold the lifted icon still and then
        // make it jump.
        widget.onDragUpdate?.call(event.position);
      case DockPress.down:
        break;
    }
  }

  void _pointerUp(PointerEvent event, {required bool cancelled}) {
    final press = _press;
    if (press != null &&
        _pressKind == DockPointerKind.touch &&
        event.pointer != _pressPointer) {
      return;
    }
    _pressUp();
    _longPressTimer?.cancel();
    _longPressTimer = null;
    _press = null;
    _downPosition = null;
    _downButtons = 0;
    // A mouse drag is ended by the pan recogniser below.
    if (press == null || _pressKind != DockPointerKind.touch) return;
    final end = DockDrag.pressReleased(press);
    if (end == DockPressEnd.none) return;
    if (cancelled) {
      // A touch the system took away decided nothing, so nothing is dropped.
      widget.onDragCancel?.call();
      return;
    }
    switch (end) {
      case DockPressEnd.menu:
        widget.onDragCancel?.call();
        _openMenu();
      case DockPressEnd.drop:
        widget.onDragEnd?.call();
      case DockPressEnd.none:
        break;
    }
  }

  void _pressDown() {
    _pressTimer?.cancel();
    if (!_pressed) setState(() => _pressed = true);
  }

  void _pressUp() {
    if (!_pressed) return;
    _pressTimer?.cancel();
    _pressTimer = Timer(const Duration(milliseconds: 45), () {
      if (mounted && _pressed) setState(() => _pressed = false);
    });
  }

  /// Clicking an application follows macOS: a stopped application starts, a
  /// front-most one minimizes or cycles to its next window, and one in the
  /// background comes forward.
  void _activate() {
    if (_menuOpen) {
      _closeOverlay();
      return;
    }
    if (widget.windows.isEmpty) {
      _launch();
      return;
    }
    final windows = widget.windows;
    final activeIndex = DockClick.activeIndex(
      windows.map((window) => window.active),
    );
    final click = DockClick.resolve(
      action: widget.clickAction,
      count: windows.length,
      activeIndex: activeIndex,
      minimized: windows.map((window) => window.minimized),
    );
    switch (click.kind) {
      case DockClickKind.previews:
        if (_previewsOpen) {
          _closeOverlay();
        } else {
          _showPreviewTimer?.cancel();
          _showPreviewTimer = null;
          _showPreviews();
        }
        return;
      case DockClickKind.activate:
        widget.services.activateWindow(windows[click.index].id);
      case DockClickKind.minimize:
        widget.services.minimizeWindow(windows[click.index].id);
      case DockClickKind.nothing:
        break;
    }
    _closeOverlay();
  }

  /// The middle button. With no window open every choice but "nothing" starts
  /// the application, since there is nothing to close or minimize.
  void _middleClick() {
    final action = widget.middleClickAction;
    if (action == DockMiddleClickAction.nothing) return;
    final windows = widget.windows;
    if (windows.isEmpty) {
      _activate();
      return;
    }
    final activeIndex = DockClick.activeIndex(
      windows.map((window) => window.active),
    );
    final target = windows[activeIndex < 0 ? 0 : activeIndex];
    switch (action) {
      case DockMiddleClickAction.newWindow:
        _launch();
      case DockMiddleClickAction.close:
        _closeOverlay();
        widget.onCloseWindows([target.id]);
      case DockMiddleClickAction.minimize:
        widget.services.minimizeWindow(target.id);
        _closeOverlay();
      case DockMiddleClickAction.nothing:
        break;
    }
  }

  Future<void> _launch() async {
    if (_launching) return;
    final chinese = Localizations.localeOf(context).languageCode == 'zh';
    final launchId = widget.launchId;
    if (launchId == null) {
      _launchError = chinese
          ? '这个窗口没有可用的启动项'
          : 'This window has no launch entry';
      _openMenu();
      return;
    }
    setState(() {
      _launching = true;
      _launchFailed = false;
      _launchError = null;
    });
    if (widget.launchFeedback != DockLaunchFeedback.none) {
      _startLaunchFeedback();
    }
    var launched = false;
    try {
      launched = await widget.services.launchApplication(
        launchId,
        monitorId: widget.monitorId,
      );
    } on Object {
      launched = false;
    }
    if (!mounted) return;
    setState(() {
      _launching = false;
      _launchFailed = !launched;
      if (!launched) {
        _launchError = chinese ? '无法启动应用' : 'Could not launch the application';
      }
    });
    if (!launched) _openMenu();
  }

  void _startLaunchFeedback() {
    _launchStartedAt = DateTime.now();
    _launchHopping = true;
    _launchPhase = 0;
    _launchLift = 0;
    _launchPulse = 1;
    _landingProgress = 1;
    _landingStartLift = 0;
    _launchLastTick = Duration.zero;
    if (!_launchTicker.isActive) _launchTicker.start();
  }

  /// Each frame asks the release rule whether the feedback may end. A window
  /// appearing ends it after the 500 ms floor; a failed launch ends it at once;
  /// a launch that never opens a window stops at the timeout.
  void _onLaunchTick(Duration elapsed) {
    if (_launchLastTick == Duration.zero) {
      _launchLastTick = elapsed;
      return;
    }
    final dt = (elapsed - _launchLastTick).inMicroseconds / 1000000.0;
    _launchLastTick = elapsed;

    if (_launchHopping) {
      final started = _launchStartedAt ?? DateTime.now();
      final sinceStart = DateTime.now().difference(started);
      final done = DockLaunch.release(
        elapsed: sinceStart,
        windowReady: widget.windows.isNotEmpty,
        failed: _launchFailed,
      );
      if (!done) {
        if (widget.launchFeedback == DockLaunchFeedback.pulse) {
          // The feedback can turn from a hop into a pulse while it runs (the
          // reduced-motion setting does that), and a pulse stays on the row.
          _launchLift = 0;
          _launchPulse = DockLaunch.pulseOpacity(
            sinceStart.inMilliseconds / 1000.0,
          );
          setState(() {});
          return;
        }
        _launchPhase = DockLaunch.advancePhase(_launchPhase, dt);
        _launchLift = DockLaunch.hopLift(_launchPhase, widget.size);
        setState(() {});
        return;
      }
      _launchHopping = false;
      _launchPulse = 1;
      if (widget.launchFeedback == DockLaunchFeedback.pulse) {
        _launchLift = 0;
        _launchStartedAt = null;
        _launchTicker.stop();
        _launchLastTick = Duration.zero;
        setState(() {});
        return;
      }
      _landingStartLift = _launchLift;
      _landingProgress = 0;
    }

    if (_landingProgress < 1) {
      _landingProgress = DockLaunch.advanceLanding(_landingProgress, dt);
      _launchLift = DockLaunch.landingLift(_landingStartLift, _landingProgress);
      setState(() {});
      return;
    }

    _launchLift = 0;
    _launchPulse = 1;
    _launchStartedAt = null;
    _launchTicker.stop();
    _launchLastTick = Duration.zero;
    setState(() {});
  }

  void _minimizeAll() {
    for (final window in widget.windows) {
      widget.services.minimizeWindow(window.id);
    }
    _closeOverlay();
  }

  void _closeWindows() {
    final ids = [for (final window in widget.windows) window.id];
    _closeOverlay();
    if (ids.isEmpty) return;
    widget.onCloseWindows(ids);
  }

  void _activateWindow(int id) {
    widget.services.activateWindow(id);
    _closeOverlay();
  }

  /// The pointer reaching a window's preview, in either preview style.
  ///
  /// The accent ring marks the preview under the pointer and always shows: it
  /// says where the pointer is, which is useful whether or not the window
  /// takes focus.
  ///
  /// [DockSettings.previewHover] decides the rest. Highlighting fades the
  /// other windows and leaves focus and stacking alone, so moving away puts
  /// everything back; focusing switches for good.
  void _previewHover(int id, {required bool inside}) {
    _hoverSwitchTimer?.cancel();
    _hoverSwitchTimer = null;
    if (inside) {
      if (_hoverPreview != id) setState(() => _hoverPreview = id);
      if (widget.previewHover == DockPreviewHover.nothing) return;
      if (widget.previewHover == DockPreviewHover.highlight) {
        _emphasisEnter(id);
        return;
      }
      // Windows and macOS never raise a window just because the pointer
      // crossed its thumbnail; a pointer sweeping the panel would otherwise
      // raise every window it passed. The ring follows at once, the switch
      // waits for the pointer to settle.
      _hoverSwitchTimer = Timer(const Duration(milliseconds: 250), () {
        _hoverSwitchTimer = null;
        if (!mounted || !_previewsOpen || _hoverPreview != id) return;
        _emphasisEnter(id);
        widget.services.activateWindow(id);
      });
      return;
    }
    if (_hoverPreview == id) setState(() => _hoverPreview = null);
    _emphasisLeave(id);
  }

  void _emphasisEnter(int id) {
    if (_emphasisWindow == id) return;
    _clearEmphasis();
    _emphasisWindow = id;
    _emphasisTimer = Timer(const Duration(milliseconds: 300), () {
      if (!mounted || _emphasisWindow != id) return;
      _emphasisRelease = widget.services.emphasizeWindow(
        id,
        monitorId: widget.monitorId,
      );
    });
  }

  void _emphasisLeave(int id) {
    if (_emphasisWindow == id) _clearEmphasis();
  }

  void _clearEmphasis() {
    _hoverSwitchTimer?.cancel();
    _hoverSwitchTimer = null;
    _emphasisTimer?.cancel();
    _emphasisTimer = null;
    _emphasisWindow = null;
    _hoverPreview = null;
    final release = _emphasisRelease;
    _emphasisRelease = null;
    release?.call();
  }

  /// The running marker. Dots count windows, up to three, as macOS does; a line
  /// is one bar the width of the icon, as GNOME and Plasma draw it.
  Widget _buildIndicator({
    required Color color,
    required int count,
    required DockIndicatorStyle style,
  }) {
    if (style == DockIndicatorStyle.line ||
        style == DockIndicatorStyle.segments) {
      final thickness = math.max(2.0, widget.size * 0.055);
      final pieces = style == DockIndicatorStyle.segments
          ? math.min(4, math.max(1, count))
          : 1;
      final piece = DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(thickness / 2),
          color: color,
        ),
      );
      // One piece per window, as Windows' taskbar splits its underline.
      final bar = pieces == 1
          ? piece
          : Flex(
              direction: widget.position == DockPosition.bottom
                  ? Axis.horizontal
                  : Axis.vertical,
              children: [
                for (var i = 0; i < pieces; i++) ...[
                  if (i > 0) SizedBox.square(dimension: thickness),
                  Expanded(child: piece),
                ],
              ],
            );
      return switch (widget.position) {
        DockPosition.bottom => Positioned(
          left: widget.size * 0.22,
          right: widget.size * 0.22,
          bottom: -thickness,
          height: thickness,
          child: bar,
        ),
        DockPosition.left => Positioned(
          top: widget.size * 0.22,
          bottom: widget.size * 0.22,
          left: -thickness,
          width: thickness,
          child: bar,
        ),
        DockPosition.right => Positioned(
          top: widget.size * 0.22,
          bottom: widget.size * 0.22,
          right: -thickness,
          width: thickness,
          child: bar,
        ),
      };
    }
    final dashes = style == DockIndicatorStyle.dashes;
    final dotCount = math.min(dashes ? 4 : 3, math.max(1, count));
    // The marker scales with the icon: a 4 px dot under a magnified 76 px
    // icon reads as a speck, and macOS keeps the dot in proportion.
    final dotSize = widget.size * (dotCount >= 3 ? 0.085 : 0.10);
    final spacing = dotSize * 0.45;
    final length = dashes ? dotSize * 2.2 : dotSize;
    return switch (widget.position) {
      DockPosition.bottom => Positioned(
        left: 0,
        right: 0,
        bottom: -dotSize,
        child: Center(
          child: SizedBox(
            height: dotSize,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < dotCount; i++) ...[
                  if (i > 0) SizedBox(width: spacing),
                  _Dot(width: length, height: dotSize, color: color),
                ],
              ],
            ),
          ),
        ),
      ),
      DockPosition.left || DockPosition.right => Positioned(
        top: 0,
        bottom: 0,
        left: widget.position == DockPosition.left ? -dotSize : null,
        right: widget.position == DockPosition.right ? -dotSize : null,
        child: Center(
          child: SizedBox(
            width: dotSize,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < dotCount; i++) ...[
                  if (i > 0) SizedBox(height: spacing),
                  _Dot(width: dotSize, height: length, color: color),
                ],
              ],
            ),
          ),
        ),
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = theme.colors;
    final running = widget.windows.isNotEmpty;
    final inactivePin = widget.dimInactivePinned && widget.pinned && !running;
    final active = widget.windows.any((window) => window.active);
    final size = widget.size;
    final indicator =
        running && widget.indicatorStyle != DockIndicatorStyle.none
        ? _buildIndicator(
            color: active
                ? theme.kitAccent
                : colors.textPrimary.withValues(alpha: 0.55),
            count: widget.windows.length,
            style: widget.indicatorStyle,
          )
        : null;

    final offset =
        _away *
        -(DockLaunch.iconOffset(
          hoverLift: widget.lift,
          launchLift: _launchLift,
        ));

    final progress = widget.progress;
    final muted = widget.audioMuted;

    return OverlayPortal.overlayChildLayoutBuilder(
      controller: _portal,
      overlayChildBuilder: (context, layout) => _menuOpen
          ? _buildMenu(context, layout)
          : _previewsOpen
          ? _buildPreviews(context, layout)
          : const SizedBox.shrink(),
      child: MouseRegion(
        onEnter: (_) {
          _setPreviewsHovered(true);
          _enter();
        },
        onExit: (_) => _setPreviewsHovered(false),
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.contextMenu): _openMenu,
            const SingleActivator(LogicalKeyboardKey.f10, shift: true):
                _openMenu,
            const SingleActivator(LogicalKeyboardKey.escape): _closeOverlay,
          },
          child: Focus(
            focusNode: _focus,
            child: Semantics(
              label: widget.name,
              value: '${widget.windows.length}',
              selected: active,
              button: true,
              child: Listener(
                onPointerSignal: _onPointerSignal,
                onPointerHover: _restartPreviewOnMove,
                onPointerDown: _pointerDown,
                onPointerMove: _pointerMove,
                onPointerUp: (event) => _pointerUp(event, cancelled: false),
                onPointerCancel: (event) => _pointerUp(event, cancelled: true),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (_longPressFired) {
                      _longPressFired = false;
                      return;
                    }
                    _activate();
                  },
                  onSecondaryTapDown: (_) =>
                      _menuOpen ? _closeOverlay() : _openMenu(),
                  // By default the middle button asks for another window of an
                  // application that is already running, as Omarchy and Plasma
                  // do.
                  onTertiaryTapDown: (_) => _middleClick(),
                  // Secondary-button drags must not reorder or pin anything; a
                  // right-drag is a menu gesture. The pan drives a mouse drag
                  // only: a finger or pen is followed by the listener above,
                  // which knows whether it rested on the icon first.
                  onPanStart: widget.onDragStart == null
                      ? null
                      : (details) {
                          if (_downButtons != kPrimaryButton) return;
                          if (_pressKind == DockPointerKind.touch) return;
                          _press = DockDrag.pressTravelled(
                            _press ?? DockPress.down,
                            _pressKind,
                          );
                          widget.onDragStart!(
                            _downPosition ?? details.globalPosition,
                          );
                        },
                  onPanUpdate: widget.onDragUpdate == null
                      ? null
                      : (details) {
                          if (_pressKind == DockPointerKind.touch) return;
                          widget.onDragUpdate!(details.globalPosition);
                        },
                  onPanEnd: widget.onDragEnd == null
                      ? null
                      : (_) {
                          if (_pressKind == DockPointerKind.touch) return;
                          widget.onDragEnd!();
                        },
                  onPanCancel: widget.onDragEnd == null
                      ? null
                      : () {
                          if (_pressKind == DockPointerKind.touch) return;
                          widget.onDragEnd!();
                        },
                  child: AnimatedBuilder(
                    animation: _attention,
                    builder: (context, child) => Transform.translate(
                      // One hop at the start of each period, then a rest.
                      offset:
                          offset +
                          _away *
                              widget.motion.attentionLift(
                                _attention.value,
                                size,
                              ),
                      // With reduced motion nothing hops, and the dock has no
                      // still marker for attention, so the icon dims in the
                      // same rhythm instead.
                      child: Opacity(
                        opacity: widget.motion.attentionOpacity(
                          _attention.value,
                        ),
                        child: child,
                      ),
                    ),
                    child: SizedBox(
                      width: size,
                      height: size,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned.fill(
                            child: AnimatedOpacity(
                              duration: const Duration(milliseconds: 180),
                              curve: Curves.easeOut,
                              opacity:
                                  (inactivePin ? _inactivePinOpacity : 1.0) *
                                  _launchPulse,
                              child: DockIcon(
                                mode: widget.iconMode,
                                opacity: widget.iconOpacity,
                                accent: widget.tintColor,
                                child: widget.services.buildApplicationIcon(
                                  context,
                                  widget.appId,
                                ),
                              ),
                            ),
                          ),
                          if (widget.badge > 0 && !widget.dragging)
                            Positioned(
                              top: -size * 0.06,
                              right: -size * 0.06,
                              child: _Badge(
                                count: widget.badge,
                                size: math.max(16, size * 0.36),
                                style: theme.text.systemBarCaption,
                              ),
                            ),
                          if (progress != null && !widget.dragging)
                            Positioned(
                              left: size * 0.12,
                              right: size * 0.12,
                              bottom: size * 0.07,
                              child: IgnorePointer(
                                child: _Progress(
                                  value: progress,
                                  height: math.max(3, size * 0.075),
                                  track: const Color(0xFF000000)
                                      .withValues(alpha: 0.45),
                                  fill: theme.kitAccent,
                                ),
                              ),
                            ),
                          if (muted != null && !widget.dragging)
                            Positioned(
                              left: -size * 0.06,
                              top: -size * 0.06,
                              child: IgnorePointer(
                                child: Container(
                                  width: math.max(14, size * 0.32),
                                  height: math.max(14, size * 0.32),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: colors.background.withValues(
                                      alpha: 0.78,
                                    ),
                                  ),
                                  child: Icon(
                                    muted
                                        ? Icons.volume_off_rounded
                                        : Icons.volume_up_rounded,
                                    size: math.max(9, size * 0.2),
                                    color: colors.textPrimary,
                                  ),
                                ),
                              ),
                            ),
                          ?indicator,
                          Positioned.fill(
                            child: IgnorePointer(
                              child: AnimatedOpacity(
                                duration: const Duration(milliseconds: 90),
                                curve: Curves.easeOut,
                                opacity: _pressed ? 1 : 0,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(
                                      size * 0.24,
                                    ),
                                    color: const Color(0xFF000000)
                                        .withValues(alpha: 0.16),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The gap between panel and dock, as an input region. Without it the
  /// pointer crossing to a preview reports a leave and a retracted dock slides
  /// away; it stops at the dock edge so it never takes the icon's hover.
  Rect _bridgeRect(Rect panel, Rect anchor, Rect output) {
    const reach = 12.0;
    final strip = switch (widget.position) {
      DockPosition.bottom => Rect.fromLTWH(
        panel.left,
        panel.bottom,
        panel.width,
        (anchor.top - panel.bottom).clamp(0.0, reach),
      ),
      DockPosition.left => Rect.fromLTWH(
        panel.right,
        panel.top,
        (anchor.left - panel.right).clamp(0.0, reach),
        panel.height,
      ),
      DockPosition.right => Rect.fromLTWH(
        anchor.right,
        panel.top,
        (panel.left - anchor.right).clamp(0.0, reach),
        panel.height,
      ),
    };
    if (strip.width <= 0 || strip.height <= 0) return Rect.zero;
    final clipped = strip.intersect(output);
    return clipped.isEmpty ? Rect.zero : clipped;
  }

  Widget _bridgeStrip(Rect rect) {
    if (rect.isEmpty) return const SizedBox.shrink();
    return Positioned.fromRect(
      rect: rect,
      child: ShellInputRegion(
        debugLabel: 'Dock preview bridge',
        child: MouseRegion(
          onEnter: (_) => _setPreviewsHovered(true),
          onExit: (_) => _setPreviewsHovered(false),
          child: const ColoredBox(color: Color(0x00000000)),
        ),
      ),
    );
  }

  ({Rect anchor, Rect output}) _geometry(OverlayChildLayoutInfo layout) {
    final anchor = MatrixUtils.transformRect(
      layout.childPaintTransform,
      Offset.zero & layout.childSize,
    );
    final scene = Offset.zero & layout.overlaySize;
    final bounds = widget.monitorBounds;
    final output = bounds == null ? scene : bounds.intersect(scene);
    return (anchor: anchor, output: output.isEmpty ? scene : output);
  }

  Widget _buildMenu(BuildContext context, OverlayChildLayoutInfo layout) {
    final geometry = _geometry(layout);
    final output = geometry.output;
    final theme = context.shellTheme;
    final colors = theme.colors;
    final chinese = Localizations.localeOf(context).languageCode == 'zh';
    final width = math.min(248.0, math.max(0.0, output.width - 16));
    final placement = dockMenuAnchor(
      anchor: geometry.anchor,
      output: output,
      width: width,
      position: widget.position,
    );
    if (placement == null) return const SizedBox.shrink();
    final maxHeight = widget.position == DockPosition.bottom
        ? math.max(0.0, geometry.anchor.top - output.top - 16)
        : math.max(0.0, output.height - 16);
    final radius = theme.borderRadius(13);
    return ShellInputRegion(
      debugLabel: 'Dock application menu',
      pointerPolicy: ShellPointerPolicy.fullScene,
      keyboardPolicy: ShellKeyboardPolicy.capture,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): _closeOverlay,
        },
        child: Focus(
          autofocus: true,
          child: Stack(
            children: [
              Positioned.fill(
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (_) => _closeOverlay(),
                  child: const ColoredBox(color: Color(0x00000000)),
                ),
              ),
              DockMenuLayer(
                anchor: placement,
                overlaySize: layout.overlaySize,
                child: DockMenuPanel(
                  radius: radius,
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
                          Padding(
                            padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
                            child: Text(
                              widget.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.text.systemBarCaption.copyWith(
                                color: colors.textTertiary,
                              ),
                            ),
                          ),
                          // macOS lists the app's windows first, by title, and
                          // a click brings that window forward. The list is the
                          // menu's whole point when an app has several, so it
                          // sits above everything else rather than behind a
                          // "show all windows" row.
                          for (final window in _shownWindows.take(8))
                            DockMenuRow(
                              icon: window.active
                                  ? Icons.check
                                  : Icons.crop_square,
                              label: window.title.trim().isEmpty
                                  ? (chinese ? '未命名窗口' : 'Untitled window')
                                  : window.title,
                              onTap: () {
                                _closeOverlay();
                                _activateWindow(window.id);
                              },
                            ),
                          if (widget.windows.length > 8)
                            DockMenuRow(
                              icon: Icons.window_outlined,
                              label: chinese ? '显示所有窗口' : 'Show all windows',
                              onTap: _showPreviews,
                            ),
                          if (widget.windows.isNotEmpty) DockMenuSeparator(),
                          DockMenuSubmenuRow(
                            icon: Icons.tune,
                            label: chinese ? '选项' : 'Options',
                            submenu: (context) => Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                DockMenuRow(
                                  icon: widget.pinned
                                      ? Icons.push_pin
                                      : Icons.push_pin_outlined,
                                  label: widget.pinned
                                      ? (chinese
                                            ? '从 Dock 中移除'
                                            : 'Remove from Dock')
                                      : (chinese ? '保留在 Dock' : 'Keep in Dock'),
                                  onTap: () {
                                    _closeOverlay();
                                    widget.onTogglePin();
                                  },
                                ),
                                if (widget.windows.isNotEmpty)
                                  DockMenuRow(
                                    icon: Icons.vertical_align_bottom,
                                    label: widget.windows.length > 1
                                        ? (chinese
                                              ? '最小化全部窗口'
                                              : 'Minimize all windows')
                                        : (chinese ? '最小化' : 'Minimize'),
                                    onTap: _minimizeAll,
                                  ),
                                // Closing sits last in the submenu, as in
                                // macOS: it is the only entry that can discard
                                // unsaved work.
                                if (widget.windows.isNotEmpty)
                                  DockMenuRow(
                                    icon: Icons.close,
                                    label: widget.windows.length > 1
                                        ? (chinese
                                              ? '关闭全部窗口'
                                              : 'Close all windows')
                                        : (chinese ? '关闭窗口' : 'Close window'),
                                    onTap: _closeWindows,
                                  ),
                              ],
                            ),
                          ),
                          DockMenuSeparator(),
                          DockMenuRow(
                            icon: Icons.open_in_new,
                            label: widget.windows.isEmpty
                                ? (chinese ? '打开' : 'Open')
                                : (chinese ? '新窗口' : 'New window'),
                            onTap: () {
                              _closeOverlay();
                              _launch();
                            },
                          ),
                          if (widget.showDesktopActions)
                            for (final action
                                in _desktopActions ?? const <DesktopAction>[])
                              DockMenuRow(
                                icon: Icons.bolt_outlined,
                                label: action.name,
                                onTap: () {
                                  _closeOverlay();
                                  unawaited(DesktopActions.run(action));
                                },
                              ),
                          if (_launchError case final error?)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
                              child: Text(
                                error,
                                style: theme.text.systemBarCaption.copyWith(
                                  color: colors.performanceWarning,
                                ),
                              ),
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

  /// The rows the panel shows. While it is open this is the list captured at
  /// open time, so a window coming forward cannot reshuffle the rows; a window
  /// that closed in the meantime drops out without moving the others.
  List<ApplicationWindow> get _shownWindows {
    if (!_previewsOpen) return widget.windows;
    final live = {for (final window in widget.windows) window.id};
    return [
      for (final window in _previewWindows)
        if (live.contains(window.id)) window,
    ];
  }

  Widget _buildPreviews(BuildContext context, OverlayChildLayoutInfo layout) {
    final windows = _shownWindows;
    if (windows.isEmpty) {
      _clearEmphasis();
      return const SizedBox.shrink();
    }
    return widget.previewStyle == DockPreviewStyle.stack
        ? _buildPreviewStack(context, layout, windows)
        : _buildPreviewCards(context, layout, windows);
  }

  Widget _buildPreviewCards(
    BuildContext context,
    OverlayChildLayoutInfo layout,
    List<ApplicationWindow> windows,
  ) {
    final geometry = _geometry(layout);
    final output = geometry.output;
    final theme = context.shellTheme;
    final side = widget.position != DockPosition.bottom;
    final available = math.max(0.0, output.width - 16);
    final maxHeight = math.min(
      200.0,
      side
          ? math.max(0.0, output.height - 16)
          : math.max(0.0, geometry.anchor.top - output.top - 40),
    );
    if (available <= 0 || maxHeight <= 0) {
      _clearEmphasis();
      return const SizedBox.shrink();
    }
    final sizes = [
      for (final window in windows)
        _previewSize(window.previewSize, math.min(240.0, available), maxHeight),
    ];
    final cardHeight = sizes.map((size) => size.height + 22).reduce(math.max);
    final contentWidth =
        sizes.fold<double>(0.0, (sum, size) => sum + size.width) +
        (sizes.length - 1) * 8;
    final width = math.min(available, contentWidth + 16);
    final height = cardHeight + 16;
    final left = switch (widget.position) {
      DockPosition.bottom => (geometry.anchor.center.dx - width / 2).clamp(
        output.left + 8,
        math.max(output.left + 8, output.right - width - 8),
      ),
      DockPosition.left => math.max(
        output.left + 8,
        geometry.anchor.right + 12,
      ),
      DockPosition.right => math.max(
        output.left + 8,
        geometry.anchor.left - width - 12,
      ),
    };
    final top =
        (widget.position == DockPosition.bottom
                ? geometry.anchor.top - height - 12
                : geometry.anchor.center.dy - height / 2)
            .clamp(
              output.top + 8,
              math.max(output.top + 8, output.bottom - height - 8),
            );
    final panel = Rect.fromLTWH(left.toDouble(), top.toDouble(), width, height);
    return Stack(
      children: [
        _bridgeStrip(_bridgeRect(panel, geometry.anchor, output)),
        Positioned.fromRect(
          rect: panel,
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: 1),
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            builder: (context, t, child) => Opacity(
              opacity: t,
              child: Transform.scale(
                scale: 0.96 + 0.04 * t,
                alignment: switch (widget.position) {
                  DockPosition.bottom => Alignment.bottomCenter,
                  DockPosition.left => Alignment.centerLeft,
                  DockPosition.right => Alignment.centerRight,
                },
                child: child,
              ),
            ),
            child: ShellInputRegion(
              debugLabel: 'Dock window previews',
              child: MouseRegion(
                onEnter: (_) => _setPreviewsHovered(true),
                onExit: (_) => _setPreviewsHovered(false),
                child: GlassCard(
                  radius: 16,
                  blurStrength: 0.65,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          for (final (index, window) in windows.indexed) ...[
                            if (index > 0) const SizedBox(width: 8),
                            SizedBox(
                              width: sizes[index].width,
                              height: cardHeight,
                              child: MouseRegion(
                                onEnter: (_) =>
                                    _previewHover(window.id, inside: true),
                                onExit: (_) =>
                                    _previewHover(window.id, inside: false),
                                child: Semantics(
                                  label: window.title,
                                  button: true,
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () => _activateWindow(window.id),
                                    onTertiaryTapUp: widget.previewMiddleClose
                                        ? (_) =>
                                              widget.onCloseWindows([window.id])
                                        : null,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Expanded(
                                          child: Stack(
                                            fit: StackFit.expand,
                                            children: [
                                              _PreviewFrame(
                                                radius: theme.borderRadius(10),
                                                hovered:
                                                    _hoverPreview == window.id,
                                                accent: theme.kitAccent,
                                                child: ColoredBox(
                                                  color: theme.cardColor(
                                                    theme
                                                        .colors
                                                        .surfaceContainerHigh,
                                                  ),
                                                  child: widget.services
                                                      .buildWindowPreview(
                                                        context,
                                                        window.id,
                                                      ),
                                                ),
                                              ),
                                              if (_hoverPreview == window.id)
                                                Positioned(
                                                  top: 4,
                                                  right: 4,
                                                  child: _PreviewCloseButton(
                                                    onTap: () =>
                                                        widget.onCloseWindows([
                                                          window.id,
                                                        ]),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(height: 5),
                                        Text(
                                          window.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.center,
                                          style: theme.text.systemBarCaption
                                              .copyWith(
                                                color: theme.colors.textPrimary,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// The vertical style: a narrow column of rows anchored to the icon, each
  /// row a thumbnail with its title underneath and a close badge on hover.
  /// Omarchy's dock opens it after 300 ms, grows it out of the dock edge over
  /// 140 ms, and keeps it open for a single window too.
  Widget _buildPreviewStack(
    BuildContext context,
    OverlayChildLayoutInfo layout,
    List<ApplicationWindow> windows,
  ) {
    final geometry = _geometry(layout);
    final output = geometry.output;
    final theme = context.shellTheme;
    final side = widget.position != DockPosition.bottom;
    const pad = 6.0;
    const gap = 6.0;
    const titleHeight = 15.0;
    final thumbWidth = math.min(230.0, math.max(120.0, output.width * 0.28));
    final maxThumbHeight = side
        ? math.max(
            0.0,
            (output.height - 48) / windows.length - titleHeight - gap,
          )
        : math.max(
            0.0,
            (geometry.anchor.top - output.top - 24) / windows.length -
                titleHeight -
                gap,
          );
    if (maxThumbHeight <= 0) {
      _clearEmphasis();
      return const SizedBox.shrink();
    }
    final sizes = [
      for (final window in windows)
        _previewSize(window.previewSize, thumbWidth, maxThumbHeight),
    ];
    final width = sizes.map((size) => size.width).reduce(math.max) + pad * 2;
    final height =
        sizes.fold<double>(
          0.0,
          (sum, size) => sum + size.height + titleHeight,
        ) +
        gap * (sizes.length - 1) +
        pad * 2;
    final left = switch (widget.position) {
      DockPosition.bottom => (geometry.anchor.center.dx - width / 2).clamp(
        output.left + 8,
        math.max(output.left + 8, output.right - width - 8),
      ),
      DockPosition.left => math.max(
        output.left + 8,
        geometry.anchor.right + 12,
      ),
      DockPosition.right => math.max(
        output.left + 8,
        geometry.anchor.left - width - 12,
      ),
    };
    final top =
        (side
                ? geometry.anchor.center.dy - height / 2
                : geometry.anchor.top - height - 12)
            .clamp(
              output.top + 8,
              math.max(output.top + 8, output.bottom - height - 8),
            );
    final panel = Rect.fromLTWH(left.toDouble(), top.toDouble(), width, height);
    return Stack(
      children: [
        _bridgeStrip(_bridgeRect(panel, geometry.anchor, output)),
        Positioned.fromRect(
          rect: panel,
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: 1),
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            builder: (context, t, child) => Opacity(
              opacity: t,
              child: Transform.scale(
                scale: 0.96 + 0.04 * t,
                alignment: switch (widget.position) {
                  DockPosition.bottom => Alignment.bottomCenter,
                  DockPosition.left => Alignment.centerLeft,
                  DockPosition.right => Alignment.centerRight,
                },
                child: child,
              ),
            ),
            child: ShellInputRegion(
              debugLabel: 'Dock window previews',
              child: MouseRegion(
                onEnter: (_) => _setPreviewsHovered(true),
                onExit: (_) => _setPreviewsHovered(false),
                child: GlassCard(
                  radius: 16,
                  blurStrength: 0.65,
                  child: Padding(
                    padding: const EdgeInsets.all(pad),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final (index, window) in windows.indexed) ...[
                          if (index > 0) const SizedBox(height: gap),
                          SizedBox(
                            height: sizes[index].height + titleHeight,
                            child: _PreviewRow(
                              window: window,
                              radius: theme.borderRadius(10),
                              titleStyle: theme.text.systemBarCaption.copyWith(
                                color: theme.colors.textPrimary,
                              ),
                              preview: widget.services.buildWindowPreview(
                                context,
                                window.id,
                              ),
                              onActivate: () => _activateWindow(window.id),
                              onClose: () => widget.onCloseWindows([window.id]),
                              middleClose: widget.previewMiddleClose,
                              hovered: _hoverPreview == window.id,
                              onHover: (inside) =>
                                  _previewHover(window.id, inside: inside),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// One row of the vertical preview style. The close badge only appears while
/// the row is hovered, so the column stays quiet.
class _PreviewRow extends StatelessWidget {
  const _PreviewRow({
    required this.window,
    required this.radius,
    required this.hovered,
    required this.titleStyle,
    required this.preview,
    required this.onActivate,
    required this.onClose,
    required this.middleClose,
    required this.onHover,
  });

  final bool middleClose;

  final ApplicationWindow window;
  final BorderRadius radius;
  final bool hovered;
  final Widget preview;
  final TextStyle titleStyle;
  final VoidCallback onActivate;
  final VoidCallback onClose;
  final ValueChanged<bool> onHover;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    return MouseRegion(
      onEnter: (_) => onHover(true),
      onExit: (_) => onHover(false),
      child: Semantics(
        label: window.title,
        button: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onActivate,
          onTertiaryTapUp: middleClose ? (_) => onClose() : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: _PreviewFrame(
                        radius: radius,
                        hovered: hovered,
                        accent: theme.kitAccent,
                        child: ColoredBox(
                          color: theme.cardColor(
                            theme.colors.surfaceContainerHigh,
                          ),
                          child: preview,
                        ),
                      ),
                    ),
                    if (hovered)
                      Positioned(
                        top: 4,
                        right: 4,
                        child: _PreviewCloseButton(onTap: onClose),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              SizedBox(
                height: 11,
                child: Text(
                  window.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: titleStyle.copyWith(fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One thumbnail; the pointer resting on it lifts it and draws an accent ring.
class _PreviewFrame extends StatelessWidget {
  const _PreviewFrame({
    required this.radius,
    required this.hovered,
    required this.accent,
    required this.child,
  });

  final BorderRadius radius;
  final bool hovered;
  final Color accent;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: hovered ? 1 : 0),
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Transform.scale(
        scale: 1 + 0.02 * t,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(borderRadius: radius, child: child),
            if (t > 0)
              IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: radius,
                    border: Border.all(
                      color: accent.withValues(alpha: 0.9 * t),
                      width: 1.5,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      child: child,
    );
  }
}

class _PreviewCloseButton extends StatelessWidget {
  const _PreviewCloseButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final chinese = Localizations.localeOf(context).languageCode == 'zh';
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Semantics(
        label: chinese ? '关闭窗口' : 'Close window',
        button: true,
        child: Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: theme.colors.background.withValues(alpha: 0.72),
            border: Border.all(color: theme.colors.hairline),
          ),
          child: Icon(
            Icons.close_rounded,
            size: 11,
            color: theme.colors.textPrimary,
          ),
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.width, required this.height, required this.color});

  final double width;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(math.min(width, height) / 2),
      color: color,
    ),
  );
}

/// The bar an application's own progress fills across the foot of its icon.
class _Progress extends StatelessWidget {
  const _Progress({
    required this.value,
    required this.height,
    required this.track,
    required this.fill,
  });

  final double value;
  final double height;
  final Color track;
  final Color fill;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(height / 2),
    child: SizedBox(
      height: height,
      child: ColoredBox(
        color: track,
        child: FractionallySizedBox(
          alignment: AlignmentDirectional.centerStart,
          widthFactor: value.clamp(0.0, 1.0),
          child: ColoredBox(color: fill),
        ),
      ),
    ),
  );
}

/// The unread count macOS paints on an icon's corner: a red pill that stays
/// round until the number needs room.
class _Badge extends StatelessWidget {
  const _Badge({required this.count, required this.size, required this.style});

  final int count;
  final double size;
  final TextStyle style;

  static const Color _red = Color(0xFFFF3B30);

  @override
  Widget build(BuildContext context) => Container(
    constraints: BoxConstraints(minWidth: size, minHeight: size),
    padding: EdgeInsets.symmetric(horizontal: size * 0.28),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: _red,
      borderRadius: BorderRadius.circular(size / 2),
    ),
    child: Text(
      count > 99 ? '99+' : '$count',
      maxLines: 1,
      style: style.copyWith(
        color: const Color(0xFFFFFFFF),
        fontSize: size * 0.52,
        fontWeight: FontWeight.w700,
        height: 1,
      ),
    ),
  );
}

Size _previewSize(Size source, double maxWidth, double maxHeight) {
  final ratio = !source.isEmpty && source.isFinite ? source.aspectRatio : 1.5;
  final height = math.min(maxHeight, maxWidth / ratio);
  return Size(height * ratio, height);
}
