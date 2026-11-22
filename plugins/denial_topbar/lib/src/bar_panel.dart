import 'dart:math' as math;

import 'package:denial_flutter_sdk/effects.dart';
import 'package:denial_flutter_sdk/panels.dart';
import 'package:denial_flutter_sdk/popups.dart';
import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'bar_tokens.dart';

const String barPanelKey = 'denial_topbar.panel';

String? _openId;
int? _openPopup;

/// Scene rectangle of a bar item, used to hang a panel under its edge.
Rect? barSceneRect(GlobalKey key) {
  final render = key.currentContext?.findRenderObject();
  if (render is! RenderBox || !render.hasSize) return null;
  return render.localToGlobal(Offset.zero) & render.size;
}

/// Opens one bar panel at a time.
///
/// Ports NextKDE `BarStatusArea.qml`'s single-open rule: opening a second
/// module closes the first, and clicking the open module's own button closes
/// it again.
void showBarPanel({
  required WidgetRef ref,
  required String panelId,
  required GlobalKey anchor,
  required Widget Function(BuildContext context, VoidCallback close) builder,
  PanelEdge side = PanelEdge.top,
  double width = BarTokens.panelMaxWidth,
  String keyName = barPanelKey,
  bool glass = true,
}) {
  final controller = ref.read(shellPopupControllerProvider.notifier);
  final previous = _openPopup;
  final previousOpen =
      previous != null &&
      ref
          .read(shellPopupControllerProvider)
          .any((popup) => popup.id == previous && !popup.closing);
  if (_openId == panelId && previousOpen) {
    controller.close(previous);
    _openId = null;
    _openPopup = null;
    return;
  }
  for (final popup in ref.read(shellPopupControllerProvider)) {
    if (popup.keyName == keyName) controller.close(popup.id);
  }
  final rect = barSceneRect(anchor);
  final handle = controller.show(
    keyName: keyName,
    debugLabel: 'Top bar $panelId',
    dismissPolicy: ShellDismissPolicy.outsideTapAndEscape,
    transitionDuration: Motion.cardSettle,
    barrierColor: Colors.transparent,
    builder: (context, popup) => BarPanelFrame(
      anchor: rect,
      side: side,
      width: width,
      glass: glass,
      child: builder(context, popup.close),
    ),
  );
  _openId = panelId;
  _openPopup = handle.id;
}

/// The glass card every bar panel is drawn in.
///
/// Ports revo-shell's popup anchor (`barHeight + 6`) and NextKDE's panel
/// material: one blur region, one plate, a hairline and a soft shadow.
class BarPanelFrame extends StatelessWidget {
  const BarPanelFrame({
    required this.anchor,
    required this.side,
    required this.width,
    required this.child,
    this.glass = true,
    super.key,
  });

  final Rect? anchor;
  final PanelEdge side;
  final double width;
  final Widget child;

  /// Menus are opaque cards on macOS; panels are glass. The bar's own
  /// dropdowns pass false so their plate does not shimmer over a wallpaper.
  final bool glass;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final scene = MediaQuery.sizeOf(context);
    final rect = anchor;
    final centre = rect?.center.dx ?? scene.width / 2;
    final left = (centre - width / 2)
        .clamp(8.0, math.max(8.0, scene.width - width - 8))
        .toDouble();
    final below = side != PanelEdge.bottom;
    final top = below ? (rect?.bottom ?? 0) + BarTokens.panelGap : null;
    final bottom = below
        ? null
        : scene.height - (rect?.top ?? 0) + BarTokens.panelGap;
    final available = below
        ? scene.height - (top ?? 0) - 8
        : scene.height - (bottom ?? 0) - 8;

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        Positioned(
          left: left,
          width: width,
          top: top,
          bottom: bottom,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: available.clamp(120.0, scene.height),
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: theme.borderRadius(BarTokens.panelRadius),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: theme.colors.shadow.withValues(alpha: 0.28),
                    blurRadius: 30,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: ShellBackdropBlur(
                borderRadius: theme.borderRadius(BarTokens.panelRadius),
                blendMode: BlendMode.srcOver,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    // A menu is the opaque material macOS draws behind a
                    // dropdown; a panel is the translucent glass card.
                    color: glass
                        ? theme.panelColor(theme.colors.panelBackground)
                        : theme.colors.panelBackground,
                    borderRadius: theme.borderRadius(BarTokens.panelRadius),
                    border: Border.all(
                      color: theme.colors.hairline,
                      width: 0.8,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: theme.borderRadius(BarTokens.panelRadius - 1),
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
