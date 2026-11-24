import 'dart:async';
import 'dart:math' as math;

import 'package:denial_flutter_sdk/input.dart';
import 'package:denial_flutter_sdk/panels.dart';
import 'package:denial_flutter_sdk/popups.dart';
import 'package:denial_flutter_sdk/state.dart' show denialBridgeProvider;
import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'bar_button.dart';
import 'bar_tokens.dart';
import 'package:denial_shell_kit/glass_card.dart';

const String barPanelKey = 'denial_topbar.panel';
const String barDialogKey = 'denial_topbar.dialog';

/// Id of the bar panel that is open, or null. Bar items light up from this.
final ValueNotifier<String?> barOpenPanel = ValueNotifier<String?>(null);

_BarLayerState? _currentPanel;

enum BarPanelAnchor { dropdown, centred, clock, trailing }

Rect? barSceneRect(GlobalKey key) {
  final render = key.currentContext?.findRenderObject();
  if (render is! RenderBox || !render.hasSize) return null;
  return render.localToGlobal(Offset.zero) & render.size;
}

/// What a popup's content can reach: its open/close progress and a way to
/// close with the exit animation.
class BarLayer extends InheritedWidget {
  const BarLayer({
    required this.animation,
    required this.dismiss,
    required super.child,
    super.key,
  });

  final Animation<double> animation;
  final VoidCallback dismiss;

  static BarLayer of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BarLayer>()!;

  @override
  bool updateShouldNotify(BarLayer oldWidget) =>
      animation != oldWidget.animation;
}

bool get _reduceMotion => WidgetsBinding
    .instance
    .platformDispatcher
    .accessibilityFeatures
    .disableAnimations;

/// Shows [builder] on its own full-scene layer. The layer runs its own enter
/// and exit animation, so the host's fade is switched off.
void showBarLayer({
  required WidgetRef ref,
  required String keyName,
  required Widget Function(BuildContext context, VoidCallback close) builder,
  String? panelId,
  Duration open = const Duration(milliseconds: 320),
  Duration close = const Duration(milliseconds: 170),
  bool dismissOnOutsideTap = true,
  bool passthrough = false,
  Color? scrim,
}) {
  final controller = ref.read(shellPopupControllerProvider.notifier);
  // A passthrough layer takes no input of its own; what it shows claims its
  // own region, and a press on any application window dismisses it.
  final outside = passthrough
      ? ref
            .read(denialBridgeProvider)
            .shellActions
            .where((event) => event.action.name == 'clientPointerPressed')
      : null;
  for (final popup in ref.read(shellPopupControllerProvider)) {
    if (popup.keyName == keyName) controller.close(popup.id);
  }
  controller.show(
    keyName: keyName,
    debugLabel: 'Top bar ${panelId ?? keyName}',
    dismissPolicy: ShellDismissPolicy.none,
    transitionDuration: Duration.zero,
    barrierColor: Colors.transparent,
    pointerPolicy: passthrough
        ? ShellPointerPolicy.none
        : ShellPointerPolicy.fullScene,
    keyboardPolicy: passthrough
        ? ShellKeyboardPolicy.none
        : ShellKeyboardPolicy.capture,
    builder: (context, popup) => _BarLayerHost(
      outside: outside,
      panelId: panelId,
      open: open,
      close: close,
      dismissOnOutsideTap: dismissOnOutsideTap,
      scrim: scrim,
      onClosed: popup.close,
      builder: builder,
    ),
  );
}

class _BarLayerHost extends StatefulWidget {
  const _BarLayerHost({
    required this.panelId,
    required this.outside,
    required this.open,
    required this.close,
    required this.dismissOnOutsideTap,
    required this.scrim,
    required this.onClosed,
    required this.builder,
  });

  final String? panelId;
  final Stream<Object?>? outside;
  final Duration open;
  final Duration close;
  final bool dismissOnOutsideTap;
  final Color? scrim;
  final VoidCallback onClosed;
  final Widget Function(BuildContext context, VoidCallback close) builder;

  @override
  State<_BarLayerHost> createState() => _BarLayerState();
}

class _BarLayerState extends State<_BarLayerHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _reduceMotion ? Duration.zero : widget.open,
    reverseDuration: _reduceMotion ? Duration.zero : widget.close,
  );
  bool _closing = false;
  StreamSubscription<Object?>? _outsideSub;

  @override
  void initState() {
    super.initState();
    _outsideSub = widget.outside?.listen((_) => dismiss());
    if (widget.panelId != null) {
      _currentPanel = this;
      // The notifier feeds widgets that may be mid-build right now.
      scheduleMicrotask(() {
        if (_currentPanel == this) barOpenPanel.value = widget.panelId;
      });
    }
    _controller.forward();
  }

  @override
  void dispose() {
    _outsideSub?.cancel();
    _release();
    _controller.dispose();
    super.dispose();
  }

  void _release() {
    if (_currentPanel != this) return;
    _currentPanel = null;
    scheduleMicrotask(() {
      if (_currentPanel == null) barOpenPanel.value = null;
    });
  }

  void dismiss() {
    if (_closing) return;
    _closing = true;
    _release();
    _controller.reverse().whenCompleteOrCancel(() {
      if (mounted) widget.onClosed();
    });
  }

  void _outside(Offset position) {
    final target = BarButton.targetAt(position);
    dismiss();
    // A press on another bar item switches straight to it, the way a menu
    // bar hands over between titles.
    target?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.outside != null) {
      return BarLayer(
        animation: _controller,
        dismiss: dismiss,
        child: Builder(builder: (context) => widget.builder(context, dismiss)),
      );
    }
    final scrim = widget.scrim;
    return Focus(
      autofocus: true,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          dismiss();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: widget.dismissOnOutsideTap
                ? (event) => _outside(event.position)
                : null,
            child: scrim == null
                ? const SizedBox.expand()
                : FadeTransition(
                    opacity: _controller,
                    child: ColoredBox(color: scrim),
                  ),
          ),
          BarLayer(
            animation: _controller,
            dismiss: dismiss,
            child: Builder(
              builder: (context) => widget.builder(context, dismiss),
            ),
          ),
        ],
      ),
    );
  }
}

/// Opens one bar panel at a time; the open panel's own item closes it.
void showBarPanel({
  required WidgetRef ref,
  required String panelId,
  required GlobalKey anchor,
  required Widget Function(BuildContext context, VoidCallback close) builder,
  PanelEdge side = PanelEdge.top,
  double width = BarTokens.panelMaxWidth,
  bool glass = true,
  BarPanelAnchor placement = BarPanelAnchor.dropdown,
  Color? fill,
  double barHeight = BarTokens.height,
  double? height,
}) {
  final current = _currentPanel;
  if (current != null && current.widget.panelId == panelId) {
    current.dismiss();
    return;
  }
  final rect = barSceneRect(anchor);
  final menu = placement == BarPanelAnchor.dropdown;
  showBarLayer(
    ref: ref,
    keyName: barPanelKey,
    panelId: panelId,
    open: Duration(milliseconds: menu ? 90 : 200),
    close: Duration(milliseconds: menu ? 140 : 160),
    builder: (context, close) => BarPanelFrame(
      anchor: rect,
      side: side,
      width: width,
      glass: glass,
      placement: placement,
      fill: fill,
      barHeight: barHeight,
      height: height,
      child: builder(context, close),
    ),
  );
}

void closeBarPanel() => _currentPanel?.dismiss();

/// A window in the middle of the screen: About, Force Quit, the Wi-Fi
/// password, the bar's settings.
void showBarDialog({
  required WidgetRef ref,
  required Widget Function(BuildContext context, VoidCallback close) builder,
  double width = 420,
  String keyName = barDialogKey,
  bool dismissOnOutsideTap = true,
}) {
  _currentPanel?.dismiss();
  showBarLayer(
    ref: ref,
    keyName: keyName,
    open: const Duration(milliseconds: 240),
    close: const Duration(milliseconds: 160),
    dismissOnOutsideTap: dismissOnOutsideTap,
    builder: (context, close) =>
        BarWindow(width: width, child: builder(context, close)),
  );
}

/// The enter/exit motion shared by popovers and windows: a small settle out
/// of [alignment]. The fade belongs to [BarCard], because a backdrop blur has
/// to be faded by the blur itself.
class BarSwell extends StatelessWidget {
  const BarSwell({
    required this.alignment,
    required this.child,
    this.from = 0.96,
    this.fadeOnly = false,
    super.key,
  });

  final Alignment alignment;
  final double from;
  final bool fadeOnly;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (fadeOnly) return child;
    final animation = BarLayer.of(context).animation;
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final forward = animation.status != AnimationStatus.reverse;
        final scale = forward
            ? from + (1 - from) * Curves.easeOutCubic.transform(animation.value)
            : 0.985 + 0.015 * animation.value;
        return Transform.scale(
          alignment: alignment,
          scale: scale,
          child: child,
        );
      },
      child: child,
    );
  }
}

/// The card every popup draws on: continuous corners, backdrop blur, a
/// hairline and a soft shadow. Inside a [BarLayer] it fades with the layer.
class BarCard extends StatelessWidget {
  const BarCard({
    required this.radius,
    required this.child,
    this.fill,
    this.elevation = 1,
    super.key,
  });

  final double radius;
  final Color? fill;
  final double elevation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final layer = context.dependOnInheritedWidgetOfExactType<BarLayer>();
    return GlassCard(
      radius: radius,
      fill: fill,
      elevation: elevation,
      fade: layer?.animation.drive(CurveTween(curve: Curves.easeOut)),
      child: child,
    );
  }
}

/// A centred window. Drag it by a [BarWindowHandle], or anywhere while the
/// Super key is held.
class BarWindow extends StatefulWidget {
  const BarWindow({required this.width, required this.child, super.key});

  final double width;
  final Widget child;

  @override
  State<BarWindow> createState() => BarWindowState();
}

class BarWindowState extends State<BarWindow> {
  Offset _offset = Offset.zero;
  bool _super = false;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
    _super = HardwareKeyboard.instance.isMetaPressed;
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    final held = HardwareKeyboard.instance.isMetaPressed;
    if (held != _super && mounted) setState(() => _super = held);
    return false;
  }

  void moveBy(Offset delta) {
    final scene = MediaQuery.sizeOf(context);
    setState(() {
      _offset = Offset(
        (_offset.dx + delta.dx).clamp(-scene.width / 2, scene.width / 2),
        (_offset.dy + delta.dy).clamp(-scene.height / 2, scene.height / 2),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final scene = MediaQuery.sizeOf(context);
    return Center(
      child: Transform.translate(
        offset: _offset,
        child: BarSwell(
          alignment: Alignment.center,
          from: 0.96,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: math.min(widget.width, scene.width - 32),
              maxHeight: scene.height - 64,
            ),
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerMove: _super ? (event) => moveBy(event.delta) : null,
              child: MouseRegion(
                cursor: _super ? SystemMouseCursors.move : MouseCursor.defer,
                child: BarCard(
                  radius: 22,
                  elevation: 1.25,
                  fill: _windowFill(context),
                  child: IgnorePointer(ignoring: _super, child: widget.child),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Windows hold text over whatever is behind them, so they stay denser than
/// popovers however clear the theme's panels are.
Color _windowFill(BuildContext context) {
  final theme = context.shellTheme;
  final base = theme.panelColor(theme.colors.panelBackground);
  return base.withValues(alpha: math.max(base.a, 0.9));
}

/// A strip of a [BarWindow] that drags the window.
class BarWindowHandle extends StatelessWidget {
  const BarWindowHandle({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanUpdate: (details) => context
          .findAncestorStateOfType<BarWindowState>()
          ?.moveBy(details.delta),
      child: child,
    );
  }
}

class BarPanelFrame extends StatelessWidget {
  const BarPanelFrame({
    required this.anchor,
    required this.side,
    required this.width,
    required this.child,
    this.glass = true,
    this.placement = BarPanelAnchor.dropdown,
    this.fill,
    this.barHeight = BarTokens.height,
    this.height,
    super.key,
  });

  final Rect? anchor;
  final PanelEdge side;
  final double width;
  final Widget child;
  final double barHeight;
  final bool glass;
  final BarPanelAnchor placement;
  final Color? fill;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final scene = MediaQuery.sizeOf(context);
    final rect = anchor;
    final menu = placement == BarPanelAnchor.dropdown;
    final gap = switch (placement) {
      BarPanelAnchor.dropdown => BarTokens.menuDropOffsetY,
      _ => BarTokens.popoverGap,
    };
    final radius = switch (placement) {
      BarPanelAnchor.dropdown => BarTokens.menuRadius,
      _ => BarTokens.popoverRadius,
    };
    const margin = 6.0;
    final maxLeft = math.max(margin, scene.width - width - margin);

    double? left, top, right, bottom;
    Alignment origin;
    if (side.isHorizontal) {
      final double x = switch (placement) {
        BarPanelAnchor.dropdown =>
          ((rect?.left ?? 0) + BarTokens.menuDropOffsetX)
              .clamp(margin, maxLeft)
              .toDouble(),
        BarPanelAnchor.centred =>
          ((rect?.center.dx ?? scene.width / 2) - width / 2)
              .clamp(margin, maxLeft)
              .toDouble(),
        BarPanelAnchor.clock => math.max(margin, scene.width - width - 8),
        BarPanelAnchor.trailing => math.max(
          margin,
          scene.width - width - BarTokens.controlCenterInset,
        ),
      };
      left = x;
      if (side == PanelEdge.bottom) {
        bottom = barHeight + gap;
      } else {
        top = barHeight + gap;
      }
      final ax = rect == null
          ? 0.0
          : (((rect.center.dx - x) / width) * 2 - 1).clamp(-1.0, 1.0);
      origin = Alignment(ax, side == PanelEdge.bottom ? 1 : -1);
    } else {
      // A vertical bar hangs its panels beside the item that opened them.
      if (side == PanelEdge.left) {
        left = barHeight + gap;
      } else {
        right = barHeight + gap;
      }
      top = math.max(margin, (rect?.top ?? margin) - 4);
      origin = Alignment(side == PanelEdge.left ? -1 : 1, -1);
    }
    final available = scene.height - (top ?? 0) - (bottom ?? 0) - 8;

    final cardColor =
        fill ??
        (glass
            ? theme.panelColor(theme.colors.panelBackground)
            : theme.panelColor(theme.colors.surfaceContainer));

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        Positioned(
          left: left,
          right: right,
          width: width,
          top: top,
          bottom: bottom,
          child: Align(
            alignment: bottom != null
                ? Alignment.bottomCenter
                : Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: available.clamp(120.0, scene.height),
              ),
              child: BarSwell(
                alignment: origin,
                fadeOnly: menu,
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  child: BarCard(
                    radius: radius,
                    fill: cardColor,
                    elevation: menu ? 0.7 : 1,
                    child: child,
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
