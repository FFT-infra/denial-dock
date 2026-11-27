import 'dart:async';
import 'dart:math' as math;

import 'package:denial_flutter_sdk/input.dart';
import 'package:denial_flutter_sdk/models.dart' show DisplayLayout;
import 'package:denial_flutter_sdk/panels.dart';
import 'package:denial_flutter_sdk/popups.dart';
import 'package:denial_flutter_sdk/rendering.dart' show translationOnPixelGrid;
import 'package:denial_flutter_sdk/state.dart'
    show denialBridgeProvider, displayLayoutProvider;
import 'package:denial_flutter_sdk/surfaces.dart' show ShellScaleViewport;
import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'glass_card.dart';
import 'kit_material.dart';
import 'kit_motion.dart';
import 'kit_panel_place.dart';
import 'kit_springs.dart';
import 'kit_style.dart';

export 'kit_panel_place.dart';

/// The popup slot every panel and menu of the shell shares, so opening one
/// closes the other whichever plugin it belongs to.
const String kitPanelKey = 'denial_shell_kit.panel';
const String kitDialogKey = 'denial_shell_kit.dialog';

/// Id of the panel that is open, or null. The items that open panels light
/// up from this.
final ValueNotifier<String?> kitOpenPanel = ValueNotifier<String?>(null);

/// Answers a press outside an open panel: the action of the shell item under
/// the pointer, or null where there is none. A plugin adds one for the items
/// it draws, so a press on another item switches straight to it, the way a
/// menu bar hands over between titles.
typedef KitPressTarget = VoidCallback? Function(Offset position);

final Set<KitPressTarget> kitPressTargets = <KitPressTarget>{};

_KitLayerState? _currentPanel;

/// The rectangle of [key]'s widget on the screen, once it is laid out.
Rect? kitSceneRect(GlobalKey key) {
  final render = key.currentContext?.findRenderObject();
  if (render is! RenderBox || !render.hasSize) return null;
  return kitScreenRect(render);
}

/// Where [box] is drawn, in the screen's units. The shell may lay a surface
/// out in units of its own and draw it larger, so the size a box has for
/// itself is not the size it takes on the screen.
Rect kitScreenRect(RenderBox box) => MatrixUtils.transformRect(
  box.getTransformTo(null),
  Offset.zero & box.size,
);

/// The units a layer is laid out in. The shell draws itself larger than the
/// screen's scale on some outputs, and a layer follows the output it opens
/// on: it covers that output alone, its origin is the output's corner and one
/// of its units takes [scale] of the screen's.
///
/// Everything that reaches a layer from outside it, an anchor or a pointer
/// position, arrives in the screen's units and is brought over here.
class KitLayerSpace extends InheritedWidget {
  const KitLayerSpace({
    required this.origin,
    required this.scale,
    required super.child,
    super.key,
  });

  /// The output's corner on the screen.
  final Offset origin;
  final double scale;

  static KitLayerSpace? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<KitLayerSpace>();

  /// [screen] in the layer of [context]. Outside a layer it stays as it is.
  static Rect rectIn(BuildContext context, Rect screen) =>
      maybeOf(context)?.rect(screen) ?? screen;

  /// The rectangle [box] takes in the layer of [context].
  static Rect boxIn(BuildContext context, RenderBox box) =>
      rectIn(context, kitScreenRect(box));

  Offset point(Offset screen) => (screen - origin) / scale;

  Rect rect(Rect screen) => point(screen.topLeft) & (screen.size / scale);

  @override
  bool updateShouldNotify(KitLayerSpace old) =>
      origin != old.origin || scale != old.scale;
}

/// The output of [layout] a layer near [near] opens on, the main one when
/// that is nowhere: its rectangle on [canvas], in the screen's units, and the
/// shell's scale there.
({Rect rect, double scale}) kitOutputAt(
  DisplayLayout? layout,
  Offset? near,
  Rect canvas,
) {
  if (layout == null) return (rect: canvas, scale: 1.0);
  var output = layout.mainOutput;
  if (near != null) {
    for (final candidate in layout.outputs) {
      if (candidate.logicalRect.contains(near)) {
        output = candidate;
        break;
      }
    }
  }
  final rect = output?.logicalRect.intersect(canvas);
  if (output == null || rect == null || rect.isEmpty) {
    return (rect: canvas, scale: 1.0);
  }
  return (rect: rect, scale: layout.shellScaleOf(output.monitorId));
}

/// The rectangle [box] takes in the overlay that entries opened from
/// [context] go to, and that overlay's size. A surface's overlay is laid out
/// in the shell's units like the surface, so a position on the screen is not
/// one in it.
({Rect rect, Size size})? kitOverlayRect(BuildContext context, RenderBox box) {
  final overlay = Overlay.maybeOf(context)?.context.findRenderObject();
  if (overlay is! RenderBox || !overlay.hasSize || !box.hasSize) return null;
  return (
    rect: MatrixUtils.transformRect(
      box.getTransformTo(overlay),
      Offset.zero & box.size,
    ),
    size: overlay.size,
  );
}

/// Lays a layer's content out on one output, in the shell's units there: the
/// output [near] is on, or the main one.
class _KitLayerOutput extends ConsumerWidget {
  const _KitLayerOutput({required this.near, required this.child});

  final Offset? near;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (:rect, :scale) = kitOutputAt(
      ref.watch(displayLayoutProvider),
      near,
      Offset.zero & MediaQuery.sizeOf(context),
    );
    return ValueListenableBuilder<double?>(
      valueListenable: kitShellScale,
      builder: (context, override, _) {
        final effectiveScale = resolveKitScale(scale, override);
        final space = KitLayerSpace(
          origin: rect.topLeft,
          scale: effectiveScale,
          child: KitScaleScope(effectiveScale: effectiveScale, child: child),
        );
        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Positioned.fromRect(
              rect: rect,
              // The viewport tells its child the size it has; at a scale of 1 it
              // steps aside, and the size of one output among several is told
              // here.
              child: (effectiveScale - 1.0).abs() <= 1e-4
                  ? MediaQuery(
                      data: MediaQuery.of(context).copyWith(size: rect.size),
                      child: space,
                    )
                  : ShellScaleViewport(scale: effectiveScale, child: space),
            ),
          ],
        );
      },
    );
  }
}

extension KitEdgeOfPanelEdge on PanelEdge {
  /// The edge a panel opens away from. A hidden bar counts as the top.
  KitEdge get kitEdge => switch (this) {
    PanelEdge.bottom => KitEdge.bottom,
    PanelEdge.left => KitEdge.left,
    PanelEdge.right => KitEdge.right,
    _ => KitEdge.top,
  };
}

/// What a popup's content can reach: its open/close progress and a way to
/// close with the exit animation.
class KitLayer extends InheritedWidget {
  const KitLayer({
    required this.animation,
    required this.dismiss,
    required super.child,
    this.interceptBack,
    this.finish,
    super.key,
  });

  final Animation<double> animation;
  final VoidCallback dismiss;

  /// Hands the layer a question it asks before Escape or a press outside
  /// closes it: answering true means the content stepped back a level itself
  /// (left a detail page, ended an edit) and the layer stays. Null clears it.
  final ValueChanged<bool Function()?>? interceptBack;

  /// Set only on a layer shown with `contentEndsClose`: the content calls it
  /// once its own exit has come to rest, and the layer goes away then.
  final VoidCallback? finish;

  static KitLayer of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<KitLayer>()!;

  @override
  bool updateShouldNotify(KitLayer oldWidget) =>
      animation != oldWidget.animation;
}

/// Shows [builder] on its own full-scene layer. The layer runs its own enter
/// and exit animation, so the host's fade is switched off.
///
/// This is the one place the shell's plugins reach the host's popups.
///
/// With [contentEndsClose] the layer outlives its own exit animation and
/// leaves when the content calls [KitLayer.finish]: for content that goes out
/// on a spring, whose length the layer cannot know in advance. A layer whose
/// content never answers still leaves after a moment.
///
/// The content is laid out on one output, the one [near] is on (a point on
/// the screen, usually the middle of what opened the layer) or the main one,
/// and in the shell's units there; see [KitLayerSpace].
void showKitLayer({
  required WidgetRef ref,
  required String keyName,
  required Widget Function(BuildContext context, VoidCallback close) builder,
  String? panelId,
  String? debugLabel,
  Duration open = KitMotion.travel,
  Duration close = KitMotion.layerExit,
  bool dismissOnOutsideTap = true,
  bool passthrough = false,
  bool contentEndsClose = false,
  Color? scrim,
  Offset? near,
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
    debugLabel: debugLabel ?? 'Shell ${panelId ?? keyName}',
    dismissPolicy: ShellDismissPolicy.none,
    transitionDuration: Duration.zero,
    barrierColor: Colors.transparent,
    pointerPolicy: passthrough
        ? ShellPointerPolicy.none
        : ShellPointerPolicy.fullScene,
    keyboardPolicy: passthrough
        ? ShellKeyboardPolicy.none
        : ShellKeyboardPolicy.capture,
    builder: (context, popup) => KitThemed(
      child: _KitLayerHost(
        outside: outside,
        panelId: panelId,
        open: open,
        close: close,
        dismissOnOutsideTap: dismissOnOutsideTap,
        contentEndsClose: contentEndsClose,
        scrim: scrim,
        near: near,
        onClosed: popup.close,
        builder: builder,
      ),
    ),
  );
}

class _KitLayerHost extends StatefulWidget {
  const _KitLayerHost({
    required this.panelId,
    required this.outside,
    required this.open,
    required this.close,
    required this.dismissOnOutsideTap,
    required this.contentEndsClose,
    required this.scrim,
    required this.near,
    required this.onClosed,
    required this.builder,
  });

  final Offset? near;
  final String? panelId;
  final Stream<Object?>? outside;
  final Duration open;
  final Duration close;
  final bool dismissOnOutsideTap;
  final bool contentEndsClose;
  final Color? scrim;
  final VoidCallback onClosed;
  final Widget Function(BuildContext context, VoidCallback close) builder;

  @override
  State<_KitLayerHost> createState() => _KitLayerState();
}

class _KitLayerState extends State<_KitLayerHost>
    with SingleTickerProviderStateMixin {
  // The first values apply to the forward() below, before any build. The
  // build method refreshes them from the pace, and the speed setting rebuilds
  // the tree, so a later forward or reverse uses the new multiplier without
  // this state being recreated.
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: KitMotion.timedNow.duration(widget.open),
    reverseDuration: KitMotion.timedNow.duration(widget.close),
  );
  bool _closing = false;
  bool Function()? _back;
  bool _closed = false;
  Timer? _closeGuard;
  StreamSubscription<Object?>? _outsideSub;

  bool _steppedBack() => !_closing && (_back?.call() ?? false);

  @override
  void initState() {
    super.initState();
    _outsideSub = widget.outside?.listen((_) => dismiss());
    if (widget.panelId != null) {
      _currentPanel = this;
      // The notifier feeds widgets that may be mid-build right now.
      scheduleMicrotask(() {
        if (_currentPanel == this) kitOpenPanel.value = widget.panelId;
      });
    }
    _controller.forward();
  }

  @override
  void dispose() {
    _outsideSub?.cancel();
    _closeGuard?.cancel();
    _release();
    _controller.dispose();
    super.dispose();
  }

  void _release() {
    if (_currentPanel != this) return;
    _currentPanel = null;
    scheduleMicrotask(() {
      if (_currentPanel == null) kitOpenPanel.value = null;
    });
  }

  void dismiss() {
    if (_closing) return;
    _closing = true;
    _release();
    if (widget.contentEndsClose) {
      // The content's exit decides; the guard only covers content that never
      // reports back.
      _closeGuard = Timer(const Duration(seconds: 3), _finish);
      _controller.reverse();
      return;
    }
    _controller.reverse().whenCompleteOrCancel(_finish);
  }

  void _finish() {
    if (!_closing || _closed || !mounted) return;
    _closed = true;
    _closeGuard?.cancel();
    widget.onClosed();
  }

  void _outside(Offset position) {
    VoidCallback? target;
    for (final resolve in kitPressTargets) {
      target = resolve(position);
      if (target != null) break;
    }
    if (target == null && _steppedBack()) return;
    dismiss();
    target?.call();
  }

  @override
  Widget build(BuildContext context) {
    final pace = KitMotion.timed(context);
    _controller
      ..duration = pace.duration(widget.open)
      ..reverseDuration = pace.duration(widget.close);
    if (widget.outside != null) {
      return KitLayer(
        animation: _controller,
        dismiss: dismiss,
        finish: widget.contentEndsClose ? _finish : null,
        child: _KitLayerOutput(
          near: widget.near,
          child: Builder(
            builder: (context) => widget.builder(context, dismiss),
          ),
        ),
      );
    }
    final scrim = widget.scrim;
    return Focus(
      autofocus: true,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          if (!_steppedBack()) dismiss();
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
          KitLayer(
            animation: _controller,
            dismiss: dismiss,
            interceptBack: (handler) => _back = handler,
            finish: widget.contentEndsClose ? _finish : null,
            child: _KitLayerOutput(
              near: widget.near,
              child: Builder(
                builder: (context) => widget.builder(context, dismiss),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// How a panel is drawn: a menu is the lighter kind, fading in place, and a
/// popover grows out of the item that opened it.
enum KitPanelKind { menu, popover }

/// Opens one panel at a time, placed from the item that opened it and the
/// edge its host sits on; see [kitPanelPlace]. Asking for the panel that is
/// open closes it.
///
/// [anchor] is where the item is on the screen, as [kitSceneRect] gives it.
void showKitPanel({
  required WidgetRef ref,
  required String panelId,
  required Rect? anchor,
  required KitEdge edge,
  required double hostExtent,
  required double gap,
  required double radius,
  required double width,
  required Widget Function(BuildContext context, VoidCallback close) builder,
  KitPanelKind kind = KitPanelKind.popover,
  KitPanelAlign align = KitPanelAlign.anchorCenter,
  double alignOffset = 0,
  bool glass = true,
  Color? fill,
  String? debugLabel,
  Size? bead,
  bool cornerOrigin = false,
}) {
  if (closeKitPanel(panelId)) return;
  final menu = kind == KitPanelKind.menu;
  showKitLayer(
    ref: ref,
    keyName: kitPanelKey,
    panelId: panelId,
    debugLabel: debugLabel,
    open: menu ? KitMotion.tap : KitMotion.enter,
    close: menu ? KitMotion.ease : KitMotion.fill,
    near: anchor?.center,
    builder: (context, close) => KitPanelFrame(
      anchor: anchor,
      edge: edge,
      hostExtent: hostExtent,
      gap: gap,
      radius: radius,
      width: width,
      kind: kind,
      align: align,
      alignOffset: alignOffset,
      glass: glass,
      fill: fill,
      bead: bead,
      cornerOrigin: cornerOrigin,
      child: builder(context, close),
    ),
  );
}

/// Closes the open panel with its exit animation. With [panelId], only when
/// that is the panel open. Answers whether a panel was closed.
bool closeKitPanel([String? panelId]) {
  final current = _currentPanel;
  if (current == null) return false;
  if (panelId != null && current.widget.panelId != panelId) return false;
  current.dismiss();
  return true;
}

/// A window in the middle of the screen: an about box, a password prompt, a
/// plugin's settings.
void showKitDialog({
  required WidgetRef ref,
  required Widget Function(BuildContext context, VoidCallback close) builder,
  double width = 420,
  String keyName = kitDialogKey,
  String? debugLabel,
  bool dismissOnOutsideTap = true,
}) {
  closeKitPanel();
  showKitLayer(
    ref: ref,
    keyName: keyName,
    debugLabel: debugLabel,
    open: KitMotion.enterLarge,
    close: KitMotion.fill,
    dismissOnOutsideTap: dismissOnOutsideTap,
    builder: (context, close) =>
        KitWindow(width: width, child: builder(context, close)),
  );
}

/// The enter/exit motion shared by popovers and windows: the card grows out
/// of [alignment] on the look's spring and goes back the same way. A new
/// direction keeps the velocity, so a popup closed while it opens turns round
/// without a jump. The fade belongs to [KitCard], because a backdrop blur has
/// to be faded by the blur itself.
class KitSwell extends StatefulWidget {
  const KitSwell({
    required this.alignment,
    required this.child,
    this.fadeOnly = false,
    this.bead,
    super.key,
  });

  final Alignment alignment;
  final bool fadeOnly;

  /// The share of its size the card starts from, in place of the look's.
  final Size? bead;
  final Widget child;

  @override
  State<KitSwell> createState() => _KitSwellState();
}

class _KitSwellState extends State<KitSwell>
    with SingleTickerProviderStateMixin {
  late final KitSpring _grow = KitSpring(0, KitStyle.denial.panelGrow);
  late final KitSprings _springs = KitSprings(this, <KitSpring>[_grow]);
  Animation<double>? _layer;
  bool _started = false;

  /// How far a card travels under a look whose panels slide in.
  static const double _slide = 18;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final layer = KitLayer.of(context).animation;
    if (layer != _layer) {
      _layer?.removeStatusListener(_onStatus);
      _layer = layer..addStatusListener(_onStatus);
    }
    if (!_started) {
      _started = true;
      _head(layer.status != AnimationStatus.reverse);
    }
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.reverse) _head(false);
    if (status == AnimationStatus.forward) _head(true);
  }

  void _head(bool open) {
    final style = KitStyle.of(context);
    _grow
      ..tune(open ? style.panelGrow : style.panelShrink)
      ..target = open ? 1 : 0;
    _springs.kick(reduceMotion: KitMotion.reduced(context));
  }

  @override
  void dispose() {
    _layer?.removeStatusListener(_onStatus);
    _springs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.fadeOnly) return widget.child;
    final style = KitStyle.of(context);
    final bead = widget.bead ?? style.panelBead;
    // A card that names its own bead grows from it whatever the look.
    final entry = widget.bead != null ? KitPanelEntry.grow : style.entry;
    if (entry == KitPanelEntry.fade) return widget.child;
    return AnimatedBuilder(
      animation: _springs,
      builder: (context, child) {
        final grown = _grow.value;
        switch (entry) {
          case KitPanelEntry.slide:
            // From the side the card hangs by, the way it opens.
            return Transform.translate(
              offset: Offset(
                widget.alignment.x * _slide * (1 - grown),
                widget.alignment.y * _slide * (1 - grown),
              ),
              child: child,
            );
          case KitPanelEntry.zoom:
            final least = math.min(bead.width, bead.height);
            return Transform.scale(
              scale: least + (1 - least) * grown,
              child: child,
            );
          case KitPanelEntry.grow || KitPanelEntry.fade:
            return Transform.scale(
              alignment: widget.alignment,
              scaleX: bead.width + (1 - bead.width) * grown,
              scaleY: bead.height + (1 - bead.height) * grown,
              child: child,
            );
        }
      },
      child: widget.child,
    );
  }
}

/// The card every popup draws on: continuous corners, backdrop blur, a
/// hairline and a soft shadow. Inside a [KitLayer] it fades with the layer.
class KitCard extends StatelessWidget {
  const KitCard({
    required this.radius,
    required this.child,
    this.fill,
    this.elevation = 1,
    this.minOpacity = 0,
    this.tier = KitTier.popover,
    super.key,
  });

  final double radius;
  final Color? fill;
  final double elevation;

  /// See [GlassCard.minOpacity] and [GlassCard.tier].
  final double minOpacity;
  final KitTier tier;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final layer = context.dependOnInheritedWidgetOfExactType<KitLayer>();
    final together =
        context.dependOnInheritedWidgetOfExactType<_KitCardGroupMarker>() !=
        null;
    return GlassCard(
      radius: radius,
      fill: fill,
      elevation: elevation,
      minOpacity: minOpacity,
      tier: tier,
      grouped: together,
      fade: together
          ? null
          : layer?.animation.drive(CurveTween(curve: KitMotion.out)),
      child: child,
    );
  }
}

/// Cards below move as one body, the way a column of notifications slides
/// in. They share a single backdrop and skip their own fade: a column of
/// cards that each read the screen back and fade on their own costs a frame's
/// budget several times over.
class KitCardGroup extends StatelessWidget {
  const KitCardGroup({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return BackdropGroup(child: _KitCardGroupMarker(child: child));
  }
}

class _KitCardGroupMarker extends InheritedWidget {
  const _KitCardGroupMarker({required super.child});

  @override
  bool updateShouldNotify(_KitCardGroupMarker old) => false;
}

/// A centred window. Drag it by a [KitWindowHandle], or anywhere while the
/// Super key is held.
class KitWindow extends StatefulWidget {
  const KitWindow({required this.width, required this.child, super.key});

  final double width;
  final Widget child;

  @override
  State<KitWindow> createState() => KitWindowState();
}

class KitWindowState extends State<KitWindow> {
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
        offset: translationOnPixelGrid(
          _offset,
          devicePixelRatio: MediaQuery.maybeDevicePixelRatioOf(context),
        ),
        child: KitSwell(
          alignment: Alignment.center,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: math.min(widget.width, scene.width - 32),
              maxHeight: scene.height - 64,
            ),
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerMove: _super
                  ? (event) => moveBy(event.localDelta)
                  : null,
              child: MouseRegion(
                cursor: _super ? SystemMouseCursors.move : MouseCursor.defer,
                child: KitCard(
                  radius: 22,
                  elevation: 1.25,
                  // Windows hold text over whatever is behind them, so
                  // they stay denser than a popup.
                  minOpacity: 0.94,
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

/// A strip of a [KitWindow] that drags the window.
class KitWindowHandle extends StatelessWidget {
  const KitWindowHandle({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanUpdate: (details) => context
          .findAncestorStateOfType<KitWindowState>()
          ?.moveBy(
            // The pointer moves in screen units, the window in the layer's.
            details.delta / (KitLayerSpace.maybeOf(context)?.scale ?? 1),
          ),
      child: child,
    );
  }
}

/// Draws a panel's card where [kitPanelPlace] puts it.
class KitPanelFrame extends StatelessWidget {
  const KitPanelFrame({
    required this.anchor,
    required this.edge,
    required this.hostExtent,
    required this.gap,
    required this.radius,
    required this.width,
    required this.child,
    this.kind = KitPanelKind.popover,
    this.align = KitPanelAlign.anchorCenter,
    this.alignOffset = 0,
    this.glass = true,
    this.fill,
    this.bead,
    this.cornerOrigin = false,
    super.key,
  });

  /// See [KitSwell.bead].
  final Size? bead;

  /// Grows out of the panel's corner on the anchor's side, not out of the
  /// anchor's own position along the edge.
  final bool cornerOrigin;

  /// Where the item that opened the panel is on the screen.
  final Rect? anchor;
  final KitEdge edge;
  final double hostExtent;
  final double gap;
  final double radius;
  final double width;
  final KitPanelKind kind;
  final KitPanelAlign align;
  final double alignOffset;
  final bool glass;
  final Color? fill;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final scene = MediaQuery.sizeOf(context);
    final menu = kind == KitPanelKind.menu;
    final screenAnchor = this.anchor;
    final anchor = screenAnchor == null
        ? null
        : KitLayerSpace.rectIn(context, screenAnchor);
    final place = kitPanelPlace(
      sceneWidth: scene.width,
      sceneHeight: scene.height,
      edge: edge,
      hostExtent: hostExtent,
      gap: gap,
      width: width,
      align: align,
      alignOffset: alignOffset,
      anchorLeft: anchor?.left,
      anchorTop: anchor?.top,
      anchorRight: anchor?.right,
      anchorBottom: anchor?.bottom,
    );
    final cardColor =
        fill ??
        (glass
            ? theme.panelColor(theme.colors.panelBackground)
            : theme.panelColor(theme.colors.surfaceContainer));

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        Positioned(
          left: place.left,
          right: place.right,
          width: width,
          top: place.top,
          bottom: place.bottom,
          child: Align(
            alignment: place.bottom != null
                ? Alignment.bottomCenter
                : Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: place.maxHeight.clamp(120.0, scene.height),
              ),
              child: KitSwell(
                alignment: Alignment(
                  cornerOrigin ? (place.originX < 0 ? -1 : 1) : place.originX,
                  place.originY,
                ),
                fadeOnly: menu,
                bead: bead,
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  child: KitCard(
                    radius: radius,
                    fill: cardColor,
                    elevation: menu ? 0.7 : 1,
                    tier: menu ? KitTier.menu : KitTier.popover,
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
