import 'dart:async';

import 'package:denial_flutter_sdk/panels.dart';
import 'package:denial_flutter_sdk/services.dart';
import 'package:denial_shell_kit/kit_motion.dart';
import 'package:denial_shell_kit/kit_springs.dart';
import 'package:denial_shell_kit/kit_style.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'bar_panel.dart';
import 'bar_settings.dart';
import 'bar_type.dart';
import 'debug_remote.dart';
import 'workspace_overview.dart';
import 'workspace_overview_layout.dart';

IndicatorMetrics _metrics(BarWorkspaceStyle style) => switch (style) {
  BarWorkspaceStyle.dots => const IndicatorMetrics.dots(),
  BarWorkspaceStyle.numbers => const IndicatorMetrics.numbers(),
};

/// Length of the indicator along the bar, so a host can size itself first.
double workspacesExtent(int count, BarWorkspaceStyle style) =>
    _metrics(style).extent(count);

/// The workspace indicator. The current space is a droplet that slides
/// between the marks and stretches on the way; spaces with windows are
/// solid, empty ones are hollow. Tap a mark to go there, tap the current
/// one, hold or right-click for the overview, scroll or swipe to step.
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

class _BarWorkspacesState extends ConsumerState<BarWorkspaces>
    with SingleTickerProviderStateMixin {
  // The droplet's front runs ahead and its back follows, so it stretches
  // while it travels. A look that is not liquid moves both ends as one.
  static const KitSpringTuning _lead = KitSpringTuning(560, 0.82);
  static const KitSpringTuning _follow = KitSpringTuning(200, 0.78);

  final GlobalKey _key = GlobalKey();
  late final KitSpring _head = KitSpring(0, _lead);
  late final KitSpring _tail = KitSpring(0, _follow);
  late final KitSprings _springs = KitSprings(this, <KitSpring>[
    _head,
    _tail,
  ], tolerance: 0.002);
  Timer? _intent;
  DateTime _lastStep = DateTime(0);
  double _swiped = 0;

  @override
  void initState() {
    super.initState();
    debugCommand.addListener(_debug);
  }

  void _debug() {
    if (mounted && debugWords().firstOrNull == 'spaces') _openSpaces();
  }

  @override
  void dispose() {
    debugCommand.removeListener(_debug);
    _intent?.cancel();
    _springs.dispose();
    super.dispose();
  }

  void _follows(int active, KitStyle style, bool reduced) {
    final target = active.toDouble();
    if (_head.target == 0) {
      // First sight of the workspace: the droplet is simply there.
      _head
        ..value = target
        ..target = target;
      _tail
        ..value = target
        ..target = target;
      return;
    }
    _head.tune(style.liquid ? _lead : style.panelGrow);
    _tail.tune(style.liquid ? _follow : style.panelGrow);
    if (_head.target == target) return;
    _head.target = target;
    _tail.target = target;
    _springs.kick(reduceMotion: reduced);
  }

  void _tapped(TapUpDetails details) {
    final status = ref.read(widget.services.workspace(widget.monitorId));
    final at = widget.vertical
        ? details.localPosition.dy
        : details.localPosition.dx;
    final workspace = _metrics(
      widget.settings.workspaceStyle,
    ).workspaceAt(at, status.count, status.active);
    if (workspace != status.active) {
      _go(workspace);
    } else if (widget.settings.workspacePreview) {
      _openSpaces();
    }
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
    if (kitOpenPanel.value == OverviewTuning.panelId) return;
    showWorkspaceOverview(
      ref: ref,
      context: context,
      anchor: _key,
      services: widget.services,
      monitorId: widget.monitorId,
      side: widget.side,
      barHeight: widget.barHeight,
    );
  }

  @override
  Widget build(BuildContext context) {
    final services = widget.services;
    if (!ref.watch(services.workspacesEnabled)) return const SizedBox.shrink();
    final status = ref.watch(services.workspace(widget.monitorId));
    if (status.count <= 0) return const SizedBox.shrink();
    final style = KitStyle.of(context);
    final numbers = widget.settings.workspaceStyle == BarWorkspaceStyle.numbers;
    final metrics = _metrics(widget.settings.workspaceStyle);
    _follows(status.active, style, KitMotion.reduced(context));
    final along = metrics.extent(status.count);
    final across = metrics.dot + 12;

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
          onTapUp: _tapped,
          onLongPress: _openSpaces,
          onSecondaryTap: _openSpaces,
          onHorizontalDragStart: widget.vertical ? null : (_) => _swiped = 0,
          onHorizontalDragUpdate: widget.vertical ? null : _swipe,
          onVerticalDragStart: widget.vertical ? (_) => _swiped = 0 : null,
          onVerticalDragUpdate: widget.vertical ? _swipe : null,
          child: CustomPaint(
            size: widget.vertical ? Size(across, along) : Size(along, across),
            painter: _IndicatorPainter(
              springs: _springs,
              head: _head,
              tail: _tail,
              metrics: metrics,
              count: status.count,
              active: status.active,
              occupied: status.occupied,
              ink: widget.ink,
              vertical: widget.vertical,
              numbers: numbers,
              corner: style.corner(numbers ? 6 : metrics.dot / 2),
              type: BarType.caption.copyWith(fontSize: 12),
            ),
          ),
        ),
      ),
    );
  }
}

class _IndicatorPainter extends CustomPainter {
  _IndicatorPainter({
    required this.springs,
    required this.head,
    required this.tail,
    required this.metrics,
    required this.count,
    required this.active,
    required this.occupied,
    required this.ink,
    required this.vertical,
    required this.numbers,
    required this.corner,
    required this.type,
  }) : super(repaint: springs);

  final KitSprings springs;
  final KitSpring head;
  final KitSpring tail;
  final IndicatorMetrics metrics;
  final int count;
  final int active;
  final Set<int> occupied;
  final Color ink;
  final bool vertical;
  final bool numbers;
  final double corner;
  final TextStyle type;

  /// A rectangle given along and across the bar, whichever way it runs.
  Rect _rect(double along, double across, double length, double thickness) =>
      vertical
      ? Rect.fromLTWH(across, along, thickness, length)
      : Rect.fromLTWH(along, across, length, thickness);

  Offset _point(double along, double across) =>
      vertical ? Offset(across, along) : Offset(along, across);

  @override
  void paint(Canvas canvas, Size size) {
    final across = vertical ? size.width : size.height;
    final thick = metrics.dot;
    final top = (across - thick) / 2;
    final radius = Radius.circular(corner);
    final at = (head.value + tail.value) / 2;
    final drop = metrics.droplet(head.value, tail.value);
    final body = RRect.fromRectAndRadius(
      _rect(drop.start, top, drop.length, thick),
      radius,
    );

    if (numbers) {
      canvas.drawRRect(body, Paint()..color = ink.withValues(alpha: 0.22));
      for (var i = 1; i <= count; i++) {
        final near = metrics.weight(i, at);
        final full = occupied.contains(i);
        final rest = full ? 0.8 : 0.4;
        final painter = TextPainter(
          text: TextSpan(
            text: '$i',
            style: type.copyWith(
              fontWeight: near > 0.5
                  ? FontWeight.w700
                  : (full ? FontWeight.w500 : FontWeight.w400),
              color: ink.withValues(alpha: rest + (1 - rest) * near),
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final centre = _point(metrics.centre(i, at, count), across / 2);
        painter.paint(
          canvas,
          centre - Offset(painter.width / 2, painter.height / 2),
        );
        painter.dispose();
        // A workspace with windows carries a pip beside its number.
        if (full && near < 0.5) {
          canvas.drawCircle(
            _point(metrics.centre(i, at, count), top + thick + 2.5),
            1.2,
            Paint()..color = ink.withValues(alpha: 0.7),
          );
        }
      }
      return;
    }

    for (var i = 1; i <= count; i++) {
      final mark = RRect.fromRectAndRadius(
        _rect(metrics.centre(i, at, count) - thick / 2, top, thick, thick),
        radius,
      );
      if (occupied.contains(i)) {
        canvas.drawRRect(mark, Paint()..color = ink.withValues(alpha: 0.72));
      } else {
        // An empty workspace is a ring, so it differs in shape and not only
        // in strength.
        canvas.drawRRect(
          mark.deflate(0.6),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2
            ..color = ink.withValues(alpha: 0.45),
        );
      }
    }
    canvas.drawRRect(body, Paint()..color = ink);
  }

  @override
  bool shouldRepaint(_IndicatorPainter old) =>
      old.metrics != metrics ||
      old.count != count ||
      old.active != active ||
      old.occupied.length != occupied.length ||
      !old.occupied.containsAll(occupied) ||
      old.ink != ink ||
      old.vertical != vertical ||
      old.numbers != numbers ||
      old.corner != corner ||
      old.type != type;
}
