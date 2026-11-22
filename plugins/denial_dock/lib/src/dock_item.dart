import 'dart:async';
import 'dart:math' as math;

import 'package:denial_flutter_sdk/effects.dart';
import 'package:denial_flutter_sdk/input.dart';
import 'package:denial_flutter_sdk/services.dart';
import 'package:denial_flutter_sdk/surfaces.dart';
import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/gestures.dart'
    show
        GestureBinding,
        PointerDeviceKind,
        PointerScrollEvent,
        PointerSignalEvent,
        kPrimaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'dock_click.dart';
import 'dock_icon.dart';
import 'dock_launch.dart';
import 'dock_menu.dart';
import 'dock_scroll.dart';
import 'dock_settings.dart';

/// Windows waits this long before showing a taskbar thumbnail
/// (`MouseHoverTime`, 400 ms by default). The dock matches it so a pointer
/// passing over an icon on its way somewhere else never opens a tray.
const int previewHoverDelayMs = 400;

/// Omarchy's dock waits this long before its vertical stack of previews.
const int stackPreviewHoverDelayMs = 300;

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
    required this.launchFeedback,
    required this.indicatorStyle,
    required this.previewStyle,
    required this.hoverFocusPreview,
    required this.dimInactivePinned,
    required this.badge,
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

  final DockLaunchFeedback launchFeedback;
  final DockIndicatorStyle indicatorStyle;
  final DockPreviewStyle previewStyle;

  /// Focuses a previewed window when the pointer moves onto its row.
  final bool hoverFocusPreview;

  /// Fades a pinned icon that has no window.
  final bool dimInactivePinned;

  /// Unread notifications for this application; zero hides the badge.
  final int badge;

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

  @override
  State<DockItemWidget> createState() => _DockItemWidgetState();
}

class _DockItemWidgetState extends State<DockItemWidget>
    with SingleTickerProviderStateMixin {
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

  /// Touch and pen have no right button; a long press opens the same menu.
  Timer? _longPressTimer;
  bool _longPressFired = false;

  /// Press feedback: a light wash that appears on press and fades out, as in
  /// the reference docks.
  Timer? _pressTimer;
  bool _pressed = false;

  Timer? _showPreviewTimer;
  Timer? _hidePreviewTimer;
  Timer? _emphasisTimer;
  VoidCallback? _emphasisRelease;
  int? _emphasisWindow;

  /// The window whose preview the pointer is on. It gets the accent ring,
  /// whether or not the previews switch focus.
  int? _hoverPreview;

  Offset? _downPosition;
  int _downButtons = 0;

  bool _menuOpen = false;
  bool _previewsOpen = false;
  bool _launching = false;
  String? _launchError;

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
    if (widget.windows.isEmpty &&
        oldWidget.windows.isNotEmpty &&
        _overlayOpen) {
      _closeOverlay();
    }
    final ids = widget.windows.map((window) => window.id).toSet();
    if (_emphasisWindow != null && !ids.contains(_emphasisWindow)) {
      _clearEmphasis();
    }
    if (_previewsOpen && widget.previewOwner != widget.appId) {
      // Another icon took the overlay; this one just folds away. It does not
      // report the overlay closed: the icon that took it already reported it
      // open, and a false here would drop the dock's hold while the new panel
      // is still on screen.
      _previewsOpen = false;
      _clearEmphasis();
      _portal.hide();
    }
  }

  @override
  void dispose() {
    _showPreviewTimer?.cancel();
    _hidePreviewTimer?.cancel();
    _longPressTimer?.cancel();
    _pressTimer?.cancel();
    _clearEmphasis();
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
    if (widget.dragging || _menuOpen || !_wantsPreviews) return;
    // Every icon waits out its own dwell, including the one next to an open
    // panel. Sliding along the dock is how a pointer passes an icon it did not
    // mean to open, so a neighbour that opens at once would flash a panel the
    // user never asked for.
    _showPreviewTimer ??= Timer(Duration(milliseconds: _previewDelayMs), () {
      _showPreviewTimer = null;
      if (mounted && _wantsPreviews) _showPreviews();
    });
  }

  /// How many of the regions that own the previews hold the pointer: the
  /// icon, the panel and the gap between them. Crossing from one to the next
  /// sends an exit before the enter, so a counter is what tells a real leave
  /// from a hand-over.
  int _previewHoverDepth = 0;
  bool get _previewsHovered => _previewHoverDepth > 0;

  void _leave() {
    _showPreviewTimer?.cancel();
    _showPreviewTimer = null;
    if (!_previewsOpen) return;
    _hidePreviewTimer?.cancel();
    // Moving along the dock to another icon is not leaving: that icon claims
    // the overlay before this timer runs.
    _hidePreviewTimer = Timer(const Duration(milliseconds: 180), () {
      if (!mounted || !_previewsOpen) return;
      if (_previewsHovered) return;
      if (widget.previewOwner != null && widget.previewOwner != widget.appId) {
        return;
      }
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
    });
    if (!_portal.isShowing) _portal.show();
    // The stack follows the pointer along the dock, so the container hands the
    // overlay to whichever icon the pointer is on.
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
  }

  void _closeOverlay() {
    _hidePreviewTimer?.cancel();
    _previewHoverDepth = 0;
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
    final next = DockClick.nextIndex(
      action: widget.clickAction,
      count: windows.length,
      activeIndex: activeIndex,
      minimized: windows.map((window) => window.minimized),
    );
    if (next == null) {
      if (activeIndex >= 0 && activeIndex < windows.length) {
        widget.services.minimizeWindow(windows[activeIndex].id);
      }
    } else {
      widget.services.activateWindow(windows[next].id);
    }
    _closeOverlay();
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
  /// [DockSettings.hoverFocusPreview] decides whether the window takes focus;
  /// the dimming of the other windows is part of the same gesture, so it
  /// follows the same switch. A disabled toggle that still faded the
  /// neighbours would read as focus by another name.
  void _previewHover(int id, {required bool inside}) {
    if (inside) {
      if (_hoverPreview != id) setState(() => _hoverPreview = id);
    } else if (_hoverPreview == id) {
      setState(() => _hoverPreview = null);
    }
    if (!inside) {
      _emphasisLeave(id);
      return;
    }
    if (!widget.hoverFocusPreview) return;
    _emphasisEnter(id);
    widget.services.activateWindow(id);
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
    if (style == DockIndicatorStyle.line) {
      final bar = DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(1.5),
          color: color,
        ),
      );
      return switch (widget.position) {
        DockPosition.bottom => Positioned(
          left: widget.size * 0.22,
          right: widget.size * 0.22,
          bottom: -5,
          height: 3,
          child: bar,
        ),
        DockPosition.left => Positioned(
          top: widget.size * 0.22,
          bottom: widget.size * 0.22,
          left: -5,
          width: 3,
          child: bar,
        ),
        DockPosition.right => Positioned(
          top: widget.size * 0.22,
          bottom: widget.size * 0.22,
          right: -5,
          width: 3,
          child: bar,
        ),
      };
    }
    final dotCount = math.min(3, math.max(1, count));
    final dotSize = dotCount >= 3 ? 4.0 : 5.0;
    const spacing = 2.0;
    return switch (widget.position) {
      DockPosition.bottom => Positioned(
        left: 0,
        right: 0,
        bottom: -5,
        child: Center(
          child: SizedBox(
            height: 4,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < dotCount; i++) ...[
                  if (i > 0) const SizedBox(width: spacing),
                  _Dot(size: dotSize, color: color),
                ],
              ],
            ),
          ),
        ),
      ),
      DockPosition.left || DockPosition.right => Positioned(
        top: 0,
        bottom: 0,
        left: widget.position == DockPosition.left ? -5 : null,
        right: widget.position == DockPosition.right ? -5 : null,
        child: Center(
          child: SizedBox(
            width: 4,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < dotCount; i++) ...[
                  if (i > 0) const SizedBox(height: spacing),
                  _Dot(size: dotSize, color: color),
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
                ? theme.accent
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
                // The pan's start position is unreliable in this shell (the
                // button pointer begins at the scene origin), but the down
                // event carries the real grab point.
                onPointerDown: (event) {
                  _downPosition = event.position;
                  _downButtons = event.buttons;
                  if (event.buttons == kPrimaryButton) _pressDown();
                  // A touch or pen has no secondary button; a long press opens
                  // the same menu. The timer is cancelled as soon as the
                  // pointer moves, so a drag never turns into a menu.
                  if (event.kind != PointerDeviceKind.mouse &&
                      event.buttons == kPrimaryButton) {
                    _longPressFired = false;
                    _longPressTimer?.cancel();
                    _longPressTimer = Timer(
                      const Duration(milliseconds: 550),
                      () {
                        _longPressTimer = null;
                        if (!mounted) return;
                        _longPressFired = true;
                        _openMenu();
                      },
                    );
                  }
                },
                onPointerMove: (event) {
                  if (_longPressTimer != null &&
                      (_downPosition != null) &&
                      (event.position - _downPosition!).distance > 6) {
                    _longPressTimer?.cancel();
                    _longPressTimer = null;
                  }
                },
                onPointerUp: (event) {
                  _pressUp();
                  _longPressTimer?.cancel();
                  _longPressTimer = null;
                  _downPosition = null;
                  _downButtons = 0;
                },
                onPointerCancel: (event) {
                  _pressUp();
                  _longPressTimer?.cancel();
                  _longPressTimer = null;
                  _downPosition = null;
                  _downButtons = 0;
                },
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
                  // The middle button asks for another window of an application
                  // that is already running, as Omarchy and Plasma do. Without
                  // a launch entry there is nothing to start, so it falls
                  // through to the normal click.
                  onTertiaryTapDown: (_) {
                    if (widget.windows.isEmpty) {
                      _activate();
                    } else {
                      _launch();
                    }
                  },
                  // Secondary-button drags must not reorder or pin anything; a
                  // right-drag is a menu gesture.
                  onPanStart: widget.onDragStart == null
                      ? null
                      : (details) {
                          if (_downButtons != kPrimaryButton) return;
                          widget.onDragStart!(
                            _downPosition ?? details.globalPosition,
                          );
                        },
                  onPanUpdate: widget.onDragUpdate == null
                      ? null
                      : (details) =>
                            widget.onDragUpdate!(details.globalPosition),
                  onPanEnd: widget.onDragEnd == null
                      ? null
                      : (_) => widget.onDragEnd!(),
                  onPanCancel: widget.onDragEnd,
                  child: Transform.translate(
                    offset: offset,
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
                          if (indicator != null) indicator,
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

  /// The empty scene between the panel and the dock.
  ///
  /// The pointer crosses it on the way to a preview, and with no input region
  /// there the surface reports a leave: the previews close, the overlay hold
  /// drops and a retracted dock slides away from under the pointer. The strip
  /// covers only that gap — it starts where the panel ends and stops at the
  /// dock's edge, so it never takes the icon's own hover.
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

  /// A transparent input region over [rect] that keeps the previews hovered.
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
    final radius = theme.borderRadius(14);
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
                          if (widget.windows.length > 1)
                            DockMenuRow(
                              icon: Icons.window_outlined,
                              label: chinese ? '显示所有窗口' : 'Show all windows',
                              onTap: _showPreviews,
                            ),
                          DockMenuRow(
                            icon: widget.pinned
                                ? Icons.push_pin
                                : Icons.push_pin_outlined,
                            label: widget.pinned
                                ? (chinese ? '从 Dock 中移除' : 'Remove from Dock')
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
                          // Closing sits last, as in macOS, KDE and GNOME: it is
                          // the only item here that can discard unsaved work.
                          if (widget.windows.isNotEmpty)
                            DockMenuRow(
                              icon: Icons.close,
                              label: widget.windows.length > 1
                                  ? (chinese ? '关闭全部窗口' : 'Close all windows')
                                  : (chinese ? '关闭窗口' : 'Close window'),
                              onTap: _closeWindows,
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

  Widget _buildPreviews(BuildContext context, OverlayChildLayoutInfo layout) {
    if (widget.windows.isEmpty) {
      _clearEmphasis();
      return const SizedBox.shrink();
    }
    return widget.previewStyle == DockPreviewStyle.stack
        ? _buildPreviewStack(context, layout)
        : _buildPreviewCards(context, layout);
  }

  Widget _buildPreviewCards(
    BuildContext context,
    OverlayChildLayoutInfo layout,
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
      for (final window in widget.windows)
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
    final radius = theme.borderRadius(16);
    final panel = Rect.fromLTWH(left.toDouble(), top.toDouble(), width, height);
    return Stack(
      children: [
        _bridgeStrip(_bridgeRect(panel, geometry.anchor, output)),
        Positioned.fromRect(
          rect: panel,
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: 1),
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            builder: (context, t, child) => Opacity(
              opacity: t,
              child: Transform.scale(
                scale: 0.97 + 0.03 * t,
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
                child: ShellBackdropBlur(
                  blur: theme.effectivePanelOpacity < 1,
                  strength: 0.65,
                  separateChild: true,
                  borderRadius: radius,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: theme.panelColor(theme.colors.surfaceContainer),
                      borderRadius: radius,
                      border: Border.all(color: theme.colors.hairline),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            for (final (index, window)
                                in widget.windows.indexed) ...[
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
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          Expanded(
                                            child: _PreviewFrame(
                                              radius: theme.borderRadius(10),
                                              hovered:
                                                  _hoverPreview == window.id,
                                              accent: theme.accent,
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
                                          ),
                                          const SizedBox(height: 5),
                                          Text(
                                            window.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            textAlign: TextAlign.center,
                                            style: theme.text.systemBarCaption
                                                .copyWith(
                                                  color:
                                                      theme.colors.textPrimary,
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
            (output.height - 48) / widget.windows.length - titleHeight - gap,
          )
        : math.max(
            0.0,
            (geometry.anchor.top - output.top - 24) / widget.windows.length -
                titleHeight -
                gap,
          );
    if (maxThumbHeight <= 0) {
      _clearEmphasis();
      return const SizedBox.shrink();
    }
    final sizes = [
      for (final window in widget.windows)
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
    final radius = theme.borderRadius(16);
    final panel = Rect.fromLTWH(left.toDouble(), top.toDouble(), width, height);
    return Stack(
      children: [
        _bridgeStrip(_bridgeRect(panel, geometry.anchor, output)),
        Positioned.fromRect(
          rect: panel,
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: 1),
            duration: const Duration(milliseconds: 140),
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
                child: ShellBackdropBlur(
                  blur: theme.effectivePanelOpacity < 1,
                  strength: 0.65,
                  separateChild: true,
                  borderRadius: radius,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: theme.panelColor(theme.colors.surfaceContainer),
                      borderRadius: radius,
                      border: Border.all(color: theme.colors.hairline),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(pad),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final (index, window)
                              in widget.windows.indexed) ...[
                            if (index > 0) const SizedBox(height: gap),
                            SizedBox(
                              height: sizes[index].height + titleHeight,
                              child: _PreviewRow(
                                window: window,
                                radius: theme.borderRadius(10),
                                titleStyle: theme.text.systemBarCaption
                                    .copyWith(color: theme.colors.textPrimary),
                                preview: widget.services.buildWindowPreview(
                                  context,
                                  window.id,
                                ),
                                onActivate: () => _activateWindow(window.id),
                                onClose: () =>
                                    widget.onCloseWindows([window.id]),
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
    required this.onHover,
  });

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
                        accent: theme.accent,
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

/// One window's thumbnail. The pointer resting on it lifts it a little and
/// draws an accent ring: Windows 11 marks the thumbnail under the pointer with
/// a highlight, and Omarchy grows the icon under it to 1.15 over 120 ms.
/// The lift here is smaller because a thumbnail is larger than an icon.
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
  const _Dot({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(shape: BoxShape.circle, color: color),
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
