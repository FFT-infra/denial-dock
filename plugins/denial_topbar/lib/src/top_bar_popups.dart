import 'dart:math' as math;

import 'package:denial_flutter_sdk/effects.dart';
import 'package:denial_flutter_sdk/panels.dart';
import 'package:denial_flutter_sdk/popups.dart';
import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const String _panelKey = 'denial_topbar.panel';
const String _settingsKey = 'denial_topbar.settings';

String? _openPanelId;
int? _openPopupId;

/// Scene rectangle of a bar module, used to hang a panel off its edge.
Rect? sceneRectOf(GlobalKey key) {
  final render = key.currentContext?.findRenderObject();
  if (render is! RenderBox || !render.hasSize) return null;
  return render.localToGlobal(Offset.zero) & render.size;
}

/// Opens one bar panel at a time. Any other bar panel closes first so a click
/// on a second module never leaves two menus stacked.
void showTopBarPanel({
  required WidgetRef ref,
  required String panelId,
  required GlobalKey anchor,
  required PanelEdge side,
  required Widget Function(BuildContext context, VoidCallback close) builder,
  double width = 340,
  bool settings = false,
}) {
  final controller = ref.read(shellPopupControllerProvider.notifier);
  final previousId = _openPopupId;
  final previousOpen =
      previousId != null &&
      ref
          .read(shellPopupControllerProvider)
          .any((popup) => popup.id == previousId && !popup.closing);
  if (_openPanelId == panelId && previousOpen) {
    controller.close(previousId);
    _openPanelId = null;
    _openPopupId = null;
    return;
  }
  final keyName = settings ? _settingsKey : _panelKey;
  if (!settings) {
    for (final popup in ref.read(shellPopupControllerProvider)) {
      if (popup.keyName == _panelKey) controller.close(popup.id);
    }
  }
  final rect = sceneRectOf(anchor);
  final handle = controller.show(
    keyName: keyName,
    debugLabel: settings ? 'Top bar settings' : 'Top bar panel',
    dismissPolicy: ShellDismissPolicy.outsideTapAndEscape,
    transitionDuration: Motion.cardSettle,
    barrierColor: Colors.transparent,
    builder: (context, handle) => _AnchoredPanel(
      anchor: rect,
      side: side,
      width: width,
      settings: settings,
      child: builder(context, handle.close),
    ),
  );
  _openPanelId = panelId;
  _openPopupId = handle.id;
}

class _AnchoredPanel extends StatelessWidget {
  const _AnchoredPanel({
    required this.anchor,
    required this.side,
    required this.width,
    required this.settings,
    required this.child,
  });

  final Rect? anchor;
  final PanelEdge side;
  final double width;
  final bool settings;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final scene = MediaQuery.sizeOf(context);
    final rect = anchor;
    final centerX = rect?.center.dx ?? scene.width / 2;
    final left = (centerX - width / 2)
        .clamp(8.0, math.max(8.0, scene.width - width - 8.0))
        .toDouble();
    final top = side == PanelEdge.bottom ? null : (rect?.bottom ?? 0) + 6;
    final bottom = side == PanelEdge.bottom
        ? (rect == null ? 8.0 : scene.height - rect.top + 6)
        : null;
    final available = top == null
        ? (bottom == null ? scene.height : scene.height - bottom - 8)
        : scene.height - top - 8;
    final limit = math.min(
      available,
      settings ? scene.height * 0.72 : scene.height - 24,
    );
    final panel = ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: width,
        maxHeight: limit.clamp(120.0, scene.height),
      ),
      child: ShellBackdropBlur(
        borderRadius: theme.borderRadius(18),
        blendMode: BlendMode.srcOver,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.panelColor(theme.colors.panelBackground),
            borderRadius: theme.borderRadius(18),
            border: Border.all(color: theme.colors.hairline, width: 0.8),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: theme.colors.shadow.withValues(alpha: 0.24),
                blurRadius: 28,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(borderRadius: theme.borderRadius(17), child: child),
        ),
      ),
    );

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        if (rect != null)
          Positioned(
            left: left,
            width: width,
            top: top,
            bottom: bottom,
            child: panel,
          )
        else
          Positioned(
            left: left,
            width: width,
            top: scene.height * 0.12,
            child: panel,
          ),
      ],
    );
  }
}
