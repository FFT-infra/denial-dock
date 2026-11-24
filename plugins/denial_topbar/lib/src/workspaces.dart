import 'dart:async';
import 'dart:math' as math;

import 'package:denial_flutter_sdk/models.dart';
import 'package:denial_flutter_sdk/services.dart';
import 'package:denial_flutter_sdk/settings.dart';
import 'package:denial_flutter_sdk/state.dart';
import 'package:denial_flutter_sdk/theme.dart';
import 'package:denial_shell_kit/kit_motion.dart';
import 'package:denial_shell_kit/kit_style.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'bar_icons.dart';
import 'bar_panel.dart';
import 'bar_settings.dart';
import 'bar_type.dart';
import 'l10n.dart';
import 'panels/mac_kit.dart';

abstract final class _W {
  static const double dot = 6;
  static const double active = 18;
  static const double gap = 7;
  static const double number = 20;
  static const double thumb = 168;
}

/// Length of the indicator along the bar, so a host can size itself first.
double workspacesExtent(int count, BarWorkspaceStyle style) {
  if (count <= 0) return 0;
  return switch (style) {
    BarWorkspaceStyle.dots =>
      (count - 1) * (_W.dot + _W.gap) + _W.active + _W.gap,
    BarWorkspaceStyle.numbers => count * _W.number,
  };
}

/// The workspace indicator. The current space is a capsule, spaces with
/// windows are solid dots, empty ones are faint. Tap a dot to go there,
/// scroll or swipe across to step, hold or right-click for the overview.
class BarWorkspaces extends ConsumerStatefulWidget {
  const BarWorkspaces({
    required this.services,
    required this.monitorId,
    required this.ink,
    required this.settings,
    this.vertical = false,
    this.side = PanelEdge.top,
    this.barHeight = 28,
    super.key,
  });

  final ShellServices services;
  final int monitorId;
  final Color ink;
  final BarSettings settings;
  final bool vertical;
  final PanelEdge side;
  final double barHeight;

  @override
  ConsumerState<BarWorkspaces> createState() => _BarWorkspacesState();
}

class _BarWorkspacesState extends ConsumerState<BarWorkspaces> {
  final GlobalKey _key = GlobalKey();
  Timer? _intent;
  DateTime _lastStep = DateTime(0);
  double _swiped = 0;

  @override
  void dispose() {
    _intent?.cancel();
    super.dispose();
  }

  void _go(int workspace) => widget.services.switchWorkspace(
    monitorId: widget.monitorId,
    workspaceId: workspace,
  );

  void _step(int by) {
    final status = ref.read(widget.services.workspace(widget.monitorId));
    final next = status.active + by;
    if (next < 1 || next > status.count) return;
    _go(next);
  }

  void _scroll(PointerSignalEvent event) {
    if (!widget.settings.workspaceScroll || event is! PointerScrollEvent) {
      return;
    }
    final delta = event.scrollDelta.dy.abs() >= event.scrollDelta.dx.abs()
        ? event.scrollDelta.dy
        : event.scrollDelta.dx;
    final now = DateTime.now();
    if (delta == 0 || now.difference(_lastStep).inMilliseconds < 140) return;
    _lastStep = now;
    _step(delta > 0 ? 1 : -1);
  }

  void _swipe(DragUpdateDetails details) {
    if (!widget.settings.workspaceScroll) return;
    _swiped += details.primaryDelta ?? 0;
    if (_swiped.abs() < 22) return;
    _step(_swiped > 0 ? 1 : -1);
    _swiped = 0;
  }

  void _openSpaces() {
    _intent?.cancel();
    if (barOpenPanel.value == 'spaces') return;
    showBarPanel(
      ref: ref,
      panelId: 'spaces',
      anchor: _key,
      side: widget.side,
      barHeight: widget.barHeight,
      placement: BarPanelAnchor.centred,
      width: math.min(
        MediaQuery.sizeOf(context).width - 24,
        ref.read(widget.services.workspace(widget.monitorId)).count *
                (_W.thumb + 12) +
            12 +
            46,
      ),
      builder: (context, close) => SpacesStrip(
        services: widget.services,
        monitorId: widget.monitorId,
        onClose: close,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final services = widget.services;
    if (!ref.watch(services.workspacesEnabled)) return const SizedBox.shrink();
    final status = ref.watch(services.workspace(widget.monitorId));
    if (status.count <= 0) return const SizedBox.shrink();
    final ink = widget.ink;
    final numbers = widget.settings.workspaceStyle == BarWorkspaceStyle.numbers;

    Widget item(int workspace) {
      final active = workspace == status.active;
      final occupied = status.occupied.contains(workspace);
      final Widget mark;
      if (numbers) {
        mark = AnimatedContainer(
          duration: KitMotion.duration(context, KitMotion.swap),
          curve: KitMotion.outCubic,
          width: _W.number - 3,
          height: _W.number - 3,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: ink.withValues(alpha: active ? 0.22 : 0),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '$workspace',
            style: BarType.caption.copyWith(
              fontSize: 12,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              color: ink.withValues(alpha: active ? 1 : (occupied ? 0.8 : 0.4)),
            ),
          ),
        );
      } else {
        final long = active ? _W.active : _W.dot;
        mark = AnimatedContainer(
          duration: KitMotion.duration(context, KitMotion.unfold),
          curve: KitMotion.spring,
          width: widget.vertical ? _W.dot : long,
          height: widget.vertical ? long : _W.dot,
          decoration: BoxDecoration(
            color: ink.withValues(alpha: active ? 1 : (occupied ? 0.72 : 0.28)),
            borderRadius: BorderRadius.circular(_W.dot / 2),
          ),
        );
      }
      final pad = numbers ? 1.5 : _W.gap / 2;
      return Pressable(
        onTap: active ? null : () => _go(workspace),
        scale: 0.8,
        child: Padding(
          padding: widget.vertical
              ? EdgeInsets.symmetric(vertical: pad, horizontal: 6)
              : EdgeInsets.symmetric(horizontal: pad, vertical: 6),
          child: mark,
        ),
      );
    }

    return MouseRegion(
      onEnter: (_) {
        if (!widget.settings.workspacePreview) return;
        _intent?.cancel();
        _intent = Timer(const Duration(milliseconds: 450), () {
          if (mounted) _openSpaces();
        });
      },
      onExit: (_) => _intent?.cancel(),
      child: Listener(
        onPointerSignal: _scroll,
        onPointerDown: (_) => _intent?.cancel(),
        child: GestureDetector(
          key: _key,
          behavior: HitTestBehavior.opaque,
          onLongPress: _openSpaces,
          onSecondaryTap: _openSpaces,
          onHorizontalDragStart: widget.vertical ? null : (_) => _swiped = 0,
          onHorizontalDragUpdate: widget.vertical ? null : _swipe,
          onVerticalDragStart: widget.vertical ? (_) => _swiped = 0 : null,
          onVerticalDragUpdate: widget.vertical ? _swipe : null,
          child: Flex(
            direction: widget.vertical ? Axis.vertical : Axis.horizontal,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[for (var w = 1; w <= status.count; w++) item(w)],
          ),
        ),
      ),
    );
  }
}

/// Every space as a miniature of the screen, with its windows where they
/// are. Tap a space to go there; drag a window onto another space to move
/// it; add or remove a space at the end.
class SpacesStrip extends ConsumerStatefulWidget {
  const SpacesStrip({
    required this.services,
    required this.monitorId,
    required this.onClose,
    super.key,
  });

  final ShellServices services;
  final int monitorId;
  final VoidCallback onClose;

  @override
  ConsumerState<SpacesStrip> createState() => _SpacesStripState();
}

class _SpacesStripState extends ConsumerState<SpacesStrip> {
  final Map<int, GlobalKey> _cards = <int, GlobalKey>{};
  DenialWindow? _dragged;
  Offset _dragAt = Offset.zero;
  int? _target;

  int? _spaceAt(Offset global) {
    for (final entry in _cards.entries) {
      final rect = barSceneRect(entry.value);
      if (rect != null && rect.inflate(6).contains(global)) return entry.key;
    }
    return null;
  }

  void _drop() {
    final window = _dragged;
    final target = _target;
    setState(() {
      _dragged = null;
      _target = null;
    });
    if (window == null || target == null || target == window.workspaceId) {
      return;
    }
    ref
        .read(denialBridgeProvider)
        .moveWindowToWorkspace(
          window,
          monitorId: widget.monitorId,
          workspaceId: target,
          follow: false,
        );
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final ink = theme.colors.textPrimary;
    final services = widget.services;
    final status = ref.watch(services.workspace(widget.monitorId));
    final bounds =
        ref.watch(services.monitorBounds(widget.monitorId)) ??
        (Offset.zero & MediaQuery.sizeOf(context));
    final windows = ref
        .watch(shellControllerProvider)
        .openAppWindows
        .where((w) => w.monitorId == widget.monitorId && !w.minimized)
        .toList();
    final settings = ref.read(shellSettingsProvider.notifier);
    final thumbH = _W.thumb * bounds.height / bounds.width;
    final scale = _W.thumb / bounds.width;

    Widget chip(DenialWindow window, {bool floating = false}) {
      final rect = window.presentationCoordinateRect.shift(-bounds.topLeft);
      final w = math.max(18.0, rect.width * scale);
      final h = math.max(14.0, rect.height * scale);
      final icon = math.min(26.0, math.min(w, h) * 0.62);
      final body = Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          color: Color.alphaBlend(
            ink.withValues(alpha: 0.16),
            theme.colors.surfaceContainer,
          ),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: ink.withValues(alpha: 0.18), width: 0.6),
          boxShadow: floating
              ? const <BoxShadow>[
                  BoxShadow(color: Color(0x55000000), blurRadius: 12),
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: SizedBox(
          width: icon,
          height: icon,
          child: services.buildApplicationIcon(context, window.appId),
        ),
      );
      if (floating) return body;
      return Positioned(
        left: (rect.left * scale).clamp(0.0, _W.thumb - w),
        top: (rect.top * scale).clamp(0.0, thumbH - h),
        child: Opacity(
          opacity: _dragged?.objectId == window.objectId ? 0.25 : 1,
          child: GestureDetector(
            onPanStart: (details) => setState(() {
              _dragged = window;
              _dragAt = details.globalPosition;
              _target = window.workspaceId;
            }),
            onPanUpdate: (details) => setState(() {
              _dragAt = details.globalPosition;
              _target = _spaceAt(_dragAt);
            }),
            onPanEnd: (_) => _drop(),
            onPanCancel: _drop,
            child: body,
          ),
        ),
      );
    }

    Widget card(int space) {
      final active = space == status.active;
      final hot = _dragged != null && _target == space;
      final mine = windows.where((w) => w.workspaceId == space).toList();
      return Pressable(
        scale: 0.97,
        onTap: () {
          services.switchWorkspace(
            monitorId: widget.monitorId,
            workspaceId: space,
          );
          widget.onClose();
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            AnimatedContainer(
              key: _cards.putIfAbsent(space, GlobalKey.new),
              duration: KitMotion.duration(context, KitMotion.fill),
              width: _W.thumb,
              height: thumbH,
              decoration: BoxDecoration(
                color: ink.withValues(alpha: hot ? 0.16 : 0.07),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: active || hot
                      ? KitStyle.of(context).accent(context.shellTheme)
                      : ink.withValues(alpha: 0.10),
                  width: active || hot ? 2 : 1,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(children: <Widget>[for (final w in mine) chip(w)]),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              context.tr('Desktop {}', space),
              style: BarType.caption.copyWith(
                fontSize: 12,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                color: active ? ink : theme.colors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    Widget countButton(IconData icon, int next) {
      final enabled =
          next >= minimumWorkspaceCount && next <= maximumWorkspaceCount;
      return Opacity(
        opacity: enabled ? 1 : 0.3,
        child: Pressable(
          scale: 0.85,
          onTap: enabled
              ? () => settings.setWorkspaceCount(next.toDouble())
              : null,
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: ink.withValues(alpha: 0.09),
            ),
            child: BarGlyph(icon, size: 13, color: ink),
          ),
        ),
      );
    }

    final dragged = _dragged;
    final origin = (context.findRenderObject() as RenderBox?)?.localToGlobal(
      Offset.zero,
    );
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                for (var space = 1; space <= status.count; space++) ...<Widget>[
                  card(space),
                  const SizedBox(width: 12),
                ],
                SizedBox(
                  height: thumbH,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      countButton(BarIcons.plus, status.count + 1),
                      const SizedBox(height: 8),
                      countButton(BarIcons.minus, status.count - 1),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (dragged != null && origin != null)
          Positioned(
            left: _dragAt.dx - origin.dx - 20,
            top: _dragAt.dy - origin.dy - 14,
            child: IgnorePointer(child: chip(dragged, floating: true)),
          ),
      ],
    );
  }
}
