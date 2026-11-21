import 'dart:async';
import 'dart:math' as math;

import 'package:denial_flutter_sdk/effects.dart';
import 'package:denial_flutter_sdk/input.dart';
import 'package:denial_flutter_sdk/services.dart';
import 'package:denial_flutter_sdk/surfaces.dart';
import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind, kPrimaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'dock_click.dart';
import 'dock_launch.dart';
import 'dock_menu.dart';
import 'dock_settings.dart';

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
    required this.bounceOnLaunch,
    required this.showIndicators,
    required this.onTogglePin,
    required this.onCloseWindows,
    required this.onOverlayChanged,
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

  final bool bounceOnLaunch;
  final bool showIndicators;

  final VoidCallback onTogglePin;

  /// Closes every listed window through the compositor's close request. Denial
  /// has no app-level quit, so this is what "quit" means here: the application
  /// exits once its last window closes, unless it keeps running in the tray.
  final ValueChanged<List<int>> onCloseWindows;

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

  void _enter() {
    _hidePreviewTimer?.cancel();
    if (widget.dragging || _menuOpen || widget.windows.length < 2) return;
    _showPreviewTimer ??= Timer(const Duration(milliseconds: 200), () {
      _showPreviewTimer = null;
      if (mounted && widget.windows.length > 1) _showPreviews();
    });
  }

  void _leave() {
    _showPreviewTimer?.cancel();
    _showPreviewTimer = null;
    if (!_previewsOpen) return;
    _hidePreviewTimer?.cancel();
    _hidePreviewTimer = Timer(const Duration(milliseconds: 180), () {
      if (mounted && _previewsOpen) _closeOverlay();
    });
  }

  void _showPreviews() {
    if (_previewsOpen || widget.windows.isEmpty) return;
    setState(() {
      _previewsOpen = true;
      _menuOpen = false;
    });
    if (!_portal.isShowing) _portal.show();
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
    _clearEmphasis();
    if (!_overlayOpen) return;
    setState(() {
      _menuOpen = false;
      _previewsOpen = false;
    });
    _portal.hide();
    widget.onOverlayChanged(false);
  }

  void _hideImmediately() {
    _showPreviewTimer?.cancel();
    _hidePreviewTimer?.cancel();
    _clearEmphasis();
    if (!_overlayOpen) return;
    _menuOpen = false;
    _previewsOpen = false;
    _portal.hide();
    widget.onOverlayChanged(false);
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
    if (widget.bounceOnLaunch) _startLaunchFeedback();
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
    _landingProgress = 1;
    _landingStartLift = 0;
    _launchLastTick = Duration.zero;
    if (!_launchTicker.isActive) _launchTicker.start();
  }

  /// Each frame asks the release rule whether the hop may end. A window
  /// appearing ends it after the 500 ms floor; a failed launch ends it at once;
  /// a launch that never opens a window stops at 15 s.
  void _onLaunchTick(Duration elapsed) {
    if (_launchLastTick == Duration.zero) {
      _launchLastTick = elapsed;
      return;
    }
    final dt = (elapsed - _launchLastTick).inMicroseconds / 1000000.0;
    _launchLastTick = elapsed;

    if (_launchHopping) {
      final started = _launchStartedAt;
      final done =
          started != null &&
          DockLaunch.release(
            elapsed: DateTime.now().difference(started),
            windowReady: widget.windows.isNotEmpty,
            failed: _launchFailed,
          );
      if (!done) {
        _launchPhase = DockLaunch.advancePhase(_launchPhase, dt);
        _launchLift = DockLaunch.hopLift(_launchPhase, widget.size);
        setState(() {});
        return;
      }
      _launchHopping = false;
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
    final release = _emphasisRelease;
    _emphasisRelease = null;
    release?.call();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = theme.colors;
    final running = widget.windows.isNotEmpty;
    final active = widget.windows.any((window) => window.active);
    final size = widget.size;
    // macOS shows one dot per open window up to three; more windows keep the
    // three-dot row.
    final dotCount = math.min(3, math.max(1, widget.windows.length));
    final dotSize = dotCount >= 3 ? 4.0 : 5.0;
    const dotSpacing = 2.0;
    final indicator = running && widget.showIndicators
        ? switch (widget.position) {
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
                        if (i > 0) const SizedBox(width: dotSpacing),
                        _Dot(
                          size: dotSize,
                          color: active
                              ? theme.accent
                              : colors.textPrimary.withValues(alpha: 0.55),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            DockPosition.left => Positioned(
              top: 0,
              bottom: 0,
              left: -5,
              child: Center(
                child: SizedBox(
                  width: 4,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < dotCount; i++) ...[
                        if (i > 0) const SizedBox(height: dotSpacing),
                        _Dot(
                          size: dotSize,
                          color: active
                              ? theme.accent
                              : colors.textPrimary.withValues(alpha: 0.55),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            DockPosition.right => Positioned(
              top: 0,
              bottom: 0,
              right: -5,
              child: Center(
                child: SizedBox(
                  width: 4,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < dotCount; i++) ...[
                        if (i > 0) const SizedBox(height: dotSpacing),
                        _Dot(
                          size: dotSize,
                          color: active
                              ? theme.accent
                              : colors.textPrimary.withValues(alpha: 0.55),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          }
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
        onEnter: (_) => _enter(),
        onExit: (_) => _leave(),
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
                            child: widget.services.buildApplicationIcon(
                              context,
                              widget.appId,
                            ),
                          ),
                          if (indicator != null) indicator,
                          IgnorePointer(
                            child: AnimatedOpacity(
                              duration: const Duration(milliseconds: 45),
                              curve: Curves.easeOut,
                              opacity: _pressed ? 1 : 0,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(
                                    size * 0.24,
                                  ),
                                  color: const Color(0xFFFFFFFF)
                                      .withValues(alpha: 0.12),
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
        _previewSize(window.previewSize, math.min(300.0, available), maxHeight),
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
    return Stack(
      children: [
        Positioned(
          left: left.toDouble(),
          top: top.toDouble(),
          width: width,
          height: height,
          child: ShellInputRegion(
            debugLabel: 'Dock window previews',
            child: MouseRegion(
              onEnter: (_) => _enter(),
              onExit: (_) => _leave(),
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
                                onEnter: (_) => _emphasisEnter(window.id),
                                onExit: (_) => _emphasisLeave(window.id),
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
                                          child: ClipRRect(
                                            borderRadius: theme.borderRadius(
                                              10,
                                            ),
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

Size _previewSize(Size source, double maxWidth, double maxHeight) {
  final ratio = !source.isEmpty && source.isFinite ? source.aspectRatio : 1.5;
  final height = math.min(maxHeight, maxWidth / ratio);
  return Size(height * ratio, height);
}
