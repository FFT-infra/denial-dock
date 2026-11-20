import 'dart:async';
import 'dart:math' as math;

import 'package:denial_flutter_sdk/effects.dart';
import 'package:denial_flutter_sdk/input.dart';
import 'package:denial_flutter_sdk/services.dart';
import 'package:denial_flutter_sdk/shell.dart';
import 'package:denial_flutter_sdk/surfaces.dart';
import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dock_autohide.dart';
import 'dock_drag.dart';
import 'dock_item.dart';
import 'dock_layout.dart';
import 'dock_math.dart';
import 'dock_preferences.dart';

/// The floating dock. Icons are laid out by [DockLayout] rather than a Row so
/// magnification changes real widths and pushes neighbours aside.
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
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;

  /// Pointer position in surface coordinates. Storing surface coordinates keeps
  /// the target valid while the capsule changes width under a still pointer.
  double _pointer = 0;
  double _pointerTarget = 0;
  double _hover = 0;
  double _hoverTarget = 0;
  double _reveal = 1;
  double _revealTarget = 1;

  bool _insideCapsule = false;
  bool _edgeHover = false;
  bool _overlayHold = false;
  bool _tickerScheduled = false;
  bool _conflict = false;
  Timer? _hideTimer;
  Timer? _revealTimer;

  DockLayoutFrame? _frame;
  Map<int, int> _entrySlots = const {};
  double _capsuleLeft = 0;
  double _capsuleBottom = 10;
  double _capsuleTop = 74;

  /// Pinned-app drag: the dragged entry key, its rest centre and the candidate
  /// insertion slot. The dragged icon follows the pointer while neighbours make
  /// room, mirroring NextKDE's reorder delegate.
  String? _dragKey;
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

  /// After release the icon keeps following the pointer while it glides into
  /// its new slot, then the row takes over (NextKDE's settling phase).
  bool _settling = false;
  double _settleT = 0;
  Offset _settleFrom = Offset.zero;
  Offset _settleTo = Offset.zero;

  bool get _held =>
      _insideCapsule || _edgeHover || _overlayHold || _dragKey != null;

  double get _dragCenterX => _dragOriginX + _dragDx;
  double get _dragCenterY => _dragOriginY + _dragDy;

  /// Scene-space top edge of the dock surface.
  double get _surfaceTop =>
      widget.environment.output.logicalRect.bottom - dockSurfaceHeight;

  /// Surface-space top edge of the capsule; [_capsuleTop] is bottom-relative.
  double get _capsuleTopY => dockSurfaceHeight - _capsuleTop;

  /// Removing a pinned icon means dragging it clear of the dock: the icon
  /// centre has to rise more than one icon height above the capsule, so a
  /// sideways reorder never drops the pin by accident.
  bool get _dragOutside => _dragCenterY < _capsuleTopY - DockSettings.iconSize;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _revealTimer?.cancel();
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
    if (_ticker.isActive || _tickerScheduled) return;
    _tickerScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _tickerScheduled = false;
      if (mounted) _ensureTicker();
    });
  }

  void _onTick(Duration elapsed) {
    if (_lastTick == Duration.zero) {
      _lastTick = elapsed;
      return;
    }
    final dt = (elapsed - _lastTick).inMicroseconds / 1000000.0;
    _lastTick = elapsed;
    final pointer = DockMath.advance(
      _pointer,
      _pointerTarget,
      dt,
      responseSeconds: 0.035,
    );
    final hover = DockMath.advance(
      _hover,
      _hoverTarget,
      dt,
      responseSeconds: 0.055,
    );
    final reveal = DockMath.advance(
      _reveal,
      _revealTarget,
      dt,
      responseSeconds: 0.10,
    );
    var dragDx = _dragDx;
    var dragDy = _dragDy;
    var settleFinished = false;
    if (_settling) {
      _settleT += dt / DockSettings.dragSettleSeconds;
      final t = _settleT.clamp(0.0, 1.0);
      final eased = Curves.easeOutCubic.transform(t);
      dragDx = _settleFrom.dx + (_settleTo.dx - _settleFrom.dx) * eased;
      dragDy = _settleFrom.dy + (_settleTo.dy - _settleFrom.dy) * eased;
      settleFinished = t >= 1;
    }
    final settled =
        (pointer - _pointer).abs() < 0.001 &&
        (hover - _hover).abs() < 0.001 &&
        (reveal - _reveal).abs() < 0.001 &&
        !_settling;
    setState(() {
      _pointer = pointer;
      _hover = hover;
      _reveal = reveal;
      _dragDx = dragDx;
      _dragDy = dragDy;
    });
    if (settleFinished) _finishDrag();
    if (settled) {
      _ticker.stop();
      _lastTick = Duration.zero;
    }
  }

  /// Hide only after a short, stable overlap; reveal as soon as the space is
  /// free. A window parked on the boundary must not make the dock flap.
  void _syncConflict(bool conflict) {
    if (_conflict == conflict) return;
    _conflict = conflict;
    _evaluateHide();
  }

  void _evaluateHide() {
    _hideTimer?.cancel();
    _hideTimer = null;
    if (!_conflict || _held) {
      // A cursor parked on the bottom edge pulls the dock out only after a
      // short pause (reference: smartHideHoverShowDelay), so brushing past the
      // edge does not flash the capsule.
      if (_conflict && _edgeHover && !_insideCapsule && _revealTarget < 0.5) {
        _revealTimer ??= Timer(const Duration(milliseconds: 90), () {
          _revealTimer = null;
          if (!mounted) return;
          _requestReveal(1);
          _evaluateHide();
        });
        return;
      }
      _revealTimer?.cancel();
      _revealTimer = null;
      _requestReveal(1);
      return;
    }
    _hideTimer = Timer(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      if (_conflict && !_held) {
        _revealTarget = 0;
        _ensureTicker();
      }
    });
  }

  void _onHover(PointerHoverEvent event) {
    _pointerTarget = _capsuleLeft + event.localPosition.dx;
    _hoverTarget = 1;
    _insideCapsule = true;
    _revealTarget = 1;
    _ensureTicker();
    _evaluateHide();
  }

  void _onExit(PointerExitEvent event) {
    _insideCapsule = false;
    _hoverTarget = 0;
    _ensureTicker();
    _evaluateHide();
  }

  void _onEdgeEnter(PointerEnterEvent event) {
    if (_edgeHover) return;
    _edgeHover = true;
    _evaluateHide();
  }

  void _onEdgeExit(PointerExitEvent event) {
    _revealTimer?.cancel();
    _revealTimer = null;
    if (!_edgeHover) return;
    _edgeHover = false;
    _evaluateHide();
  }

  void _setOverlayHold(bool hold) {
    if (_overlayHold == hold) return;
    _overlayHold = hold;
    _evaluateHide();
  }

  void _startDrag(
    _DockEntry entry,
    int entryIndex,
    int pinIndex,
    Offset pointer,
  ) {
    if (entry.pin == null || _dragKey != null) return;
    final slotIndex = _entrySlots[entryIndex];
    final slot = slotIndex == null ? null : _frame?.slots[slotIndex];
    _dragKey = normalizeAppId(entry.pin!.appId);
    _dragFrom = pinIndex;
    _dragTo = pinIndex;
    _dragDx = 0;
    _dragDy = 0;
    _dragOriginX = slot?.center ?? _capsuleLeft;
    _dragOriginY =
        dockSurfaceHeight -
        (_capsuleBottom + DockSettings.padding + DockSettings.iconSize / 2);
    // Denial starts the button pointer at the scene origin, so a grab that
    // reports (0,0) is anchored on the icon instead of the screen corner.
    final grabIsPlausible =
        pointer.dy > _surfaceTop &&
        pointer.dy <= _surfaceTop + dockSurfaceHeight;
    _dragStartX = grabIsPlausible ? pointer.dx : _dragOriginX;
    _dragStartY = grabIsPlausible ? pointer.dy : _surfaceTop + _dragOriginY;
    _hoverTarget = 0;
    _hover = 0;
    _pointerTarget = -10000;
    _pointer = -10000;
    _insideCapsule = false;
    setState(() {});
    _ensureTicker();
    _evaluateHide();
  }

  void _updateDrag(Offset pointer) {
    if (_dragKey == null) return;
    if (!pointer.dx.isFinite || !pointer.dy.isFinite) return;
    // The button pointer emits a stray move at the scene origin; a real dock
    // drag never visits that corner.
    if (pointer.dx == 0 && pointer.dy == 0) return;
    setState(() {
      _dragDx = pointer.dx - _dragStartX;
      _dragDy = pointer.dy - _dragStartY;
      _refreshDragTarget();
    });
  }

  void _refreshDragTarget() {
    if (_dragKey == null || _pinCenters.isEmpty) return;
    _dragTo = DockDrag.insertionIndex(
      centers: _pinCenters,
      pointerX: _dragCenterX,
      fallback: _dragFrom,
    );
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
      _pointerTarget = _dragCenterX;
      _pointer = _dragCenterX;
      _ensureTicker();
    }

    DockPin? pin;
    final pins =
        ref.read(dockSettingsProvider).value?.pinned ??
        DockSettings.defaults.pinned;
    for (final candidate in pins) {
      if (normalizeAppId(candidate.appId) == key) {
        pin = candidate;
        break;
      }
    }
    final notifier = ref.read(dockSettingsProvider.notifier);

    if (outside) {
      if (pin != null) unawaited(notifier.togglePin(pin, pinned: false));
      _finishDrag();
      return;
    }
    if (pin == null || to < 0 || to == from) {
      _finishDrag();
      return;
    }
    // Commit the order, then glide the source from its release position into
    // the slot it now occupies; the row keeps a gap there until the glide
    // lands, so the icon never jumps back to its old slot.
    unawaited(notifier.movePin(from, to));
    final targetX = to < _pinCenters.length ? _pinCenters[to] : _dragOriginX;
    _settleFrom = Offset(_dragDx, _dragDy);
    _settleTo = Offset(targetX - _dragOriginX, 0);
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
    _dragFrom = -1;
    _dragTo = -1;
    _dragDx = 0;
    _dragDy = 0;
    _hoverTarget = _insideCapsule ? 1 : 0;
    setState(() {});
    _ensureTicker();
    _evaluateHide();
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
  ) {
    final byId = <String, LaunchableApplication>{};
    for (final app in catalog) {
      byId[normalizeAppId(app.id)] = app;
      byId[normalizeAppId(app.appId)] = app;
      for (final windowId in app.windowAppIds) {
        byId[normalizeAppId(windowId)] = app;
      }
    }

    final windowsByApp = <String, List<ApplicationWindow>>{};
    final appByGroup = <String, LaunchableApplication?>{};
    for (final window in windows) {
      final app = byId[normalizeAppId(window.appId)];
      final key = app == null
          ? normalizeAppId(window.appId)
          : normalizeAppId(app.id);
      windowsByApp.putIfAbsent(key, () => []).add(window);
      appByGroup[key] ??= app;
    }

    final entries = <_DockEntry>[];
    final seen = <String>{};
    for (final pin in pinnedOrder ?? settings.pinned) {
      final app =
          byId[normalizeAppId(pin.appId)] ?? byId[normalizeAppId(pin.id)];
      final key = app == null
          ? normalizeAppId(pin.appId)
          : normalizeAppId(app.id);
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
    for (final group in windowsByApp.entries) {
      if (seen.contains(group.key)) continue;
      final app = appByGroup[group.key];
      final first = group.value.first;
      entries.add(
        _DockEntry(
          appId: app?.appId ?? first.appId,
          launchId: app?.id ?? first.appId,
          name: app?.name ?? first.title,
          windows: group.value,
          pin: null,
        ),
      );
    }
    return entries;
  }

  List<_SlotSpec> _specsFor(List<_DockEntry> entries) {
    final specs = <_SlotSpec>[];
    var entryIndex = 0;
    var pinnedCount = 0;
    for (final entry in entries) {
      if (!entry.pinned) continue;
      specs.add(
        _SlotSpec(
          kind: _SlotKind.app,
          entry: entryIndex++,
          half: DockSettings.iconSize / 2,
        ),
      );
      pinnedCount++;
    }
    final runningCount = entries.length - pinnedCount;
    if (runningCount > 0) {
      specs.add(const _SlotSpec(kind: _SlotKind.divider, half: 0.5));
    }
    for (var i = 0; i < runningCount; i++) {
      specs.add(
        _SlotSpec(
          kind: _SlotKind.app,
          entry: entryIndex++,
          half: DockSettings.iconSize / 2,
        ),
      );
    }
    specs.add(
      const _SlotSpec(
        kind: _SlotKind.launcher,
        half: DockSettings.iconSize / 2,
      ),
    );
    return specs;
  }

  DockLayoutFrame _layout(
    double surfaceWidth,
    List<_SlotSpec> specs, {
    required double hover,
  }) => DockLayout.compute(
    surfaceWidth: surfaceWidth,
    slots: [
      for (final spec in specs)
        DockSlot(half: spec.half, growable: spec.growable),
    ],
    padding: DockSettings.padding,
    gap: DockSettings.gap,
    pointerX: _pointer,
    hover: hover,
    maxScale: DockSettings.maxScale,
    radius: DockSettings.magnificationRadius,
  );

  @override
  Widget build(BuildContext context) {
    final settings =
        ref.watch(dockSettingsProvider).value ?? DockSettings.defaults;
    final catalog = ref.watch(widget.services.applications);
    final windows = ref.watch(widget.services.windows(widget.monitorId));
    final denialWindows = ref.watch(userAppWindowsProvider);
    final environment = widget.environment;
    final theme = context.shellTheme;
    final colors = theme.colors;

    final baseEntries = _entries(settings, catalog, windows, null);
    final baseSpecs = _specsFor(baseEntries);

    return LayoutBuilder(
      builder: (context, constraints) {
        final surfaceWidth = constraints.maxWidth;
        var entries = baseEntries;
        var specs = baseSpecs;
        if (_dragKey != null &&
            !_settling &&
            _dragFrom >= 0 &&
            _dragTo >= 0 &&
            _dragFrom < settings.pinned.length) {
          final displayPins = DockDrag.moved(
            settings.pinned,
            _dragFrom,
            _dragTo,
          );
          entries = _entries(settings, catalog, windows, displayPins);
          specs = _specsFor(entries);
        }

        final frame = _layout(
          surfaceWidth,
          specs,
          hover: _dragKey == null ? _hover : 0,
        );
        _frame = frame;
        _capsuleLeft = frame.capsuleLeft;
        _entrySlots = {
          for (var i = 0; i < specs.length; i++)
            if (specs[i].entry case final entry?) entry: i,
        };

        final hideOffset = (1 - _reveal) * (DockSettings.capsuleHeight + 24);
        final capsuleBottom = 10.0 - hideOffset;
        final capsuleTop = capsuleBottom + DockSettings.capsuleHeight;
        _capsuleBottom = capsuleBottom;
        _capsuleTop = capsuleTop;

        final dockRect = DockAutoHide.visibleDockRect(
          output: environment.output.logicalRect,
          width: frame.restWidth,
          height: DockSettings.capsuleHeight,
        );
        final conflict = DockAutoHide.hasConflict(
          windows: denialWindows,
          trigger: DockAutoHide.intentionalOverlap(dockRect),
          release: DockAutoHide.release(dockRect),
          previousConflict: _conflict,
          monitorId: widget.monitorId,
          workspaceId: environment.workspaceId,
          output: environment.output,
          desktopVisible: environment.desktopVisible,
        );
        _syncConflict(
          settings.visibility == DockVisibilityMode.smart && conflict,
        );

        if (_dragKey != null) {
          final baseFrame = _layout(surfaceWidth, baseSpecs, hover: 0);
          _pinCenters = [
            for (var i = 0; i < baseSpecs.length; i++)
              if (baseSpecs[i].kind == _SlotKind.app &&
                  baseEntries[baseSpecs[i].entry!].pinned)
                baseFrame.slots[i].center,
          ];
          _refreshDragTarget();
        }

        final label = _dragKey == null
            ? _labelFor(frame, specs, entries)
            : null;
        final nameLabel = label == null || _hover < 0.2
            ? null
            : Positioned(
                left: (label.center - 90).clamp(
                  12.0,
                  math.max(12.0, surfaceWidth - 192.0),
                ),
                bottom: capsuleTop + 6,
                width: 180,
                child: IgnorePointer(
                  child: Center(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: theme.panelColor(colors.surfaceContainer),
                        borderRadius: theme.borderRadius(8),
                        border: Border.all(color: colors.hairline),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        child: Text(
                          label.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.text.systemBarCaption.copyWith(
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );

        _DockEntry? dragEntry;
        for (final entry in entries) {
          if (entry.pin != null &&
              normalizeAppId(entry.pin!.appId) == _dragKey) {
            dragEntry = entry;
            break;
          }
        }
        final willUnpin = _dragOutside;

        return Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: frame.capsuleLeft,
              bottom: capsuleBottom,
              width: frame.width,
              height: DockSettings.capsuleHeight,
              child: ShellInputRegion(
                debugLabel: 'Dock capsule',
                active: _reveal > 0.5,
                child: MouseRegion(
                  onHover: _onHover,
                  onExit: _onExit,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(child: _capsuleSurface(theme)),
                      for (var i = 0; i < specs.length; i++)
                        if (_slotChild(
                              context,
                              spec: specs[i],
                              slot: frame.slots[i],
                              capsuleLeft: frame.capsuleLeft,
                              entries: entries,
                              dragging: _dragKey != null,
                            )
                            case final Widget child)
                          child,
                    ],
                  ),
                ),
              ),
            ),
            if (dragEntry != null)
              Positioned(
                left: _dragCenterX - DockSettings.iconSize * 0.55,
                top: _dragCenterY - DockSettings.iconSize * 0.55,
                width: DockSettings.iconSize * 1.1,
                height: DockSettings.iconSize * 1.1,
                child: IgnorePointer(
                  // The dragged source lifts off the dock: it grows slightly
                  // and turns translucent while held, as in the reference.
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: const Duration(milliseconds: 120),
                    curve: Curves.easeOutCubic,
                    builder: (context, t, child) => Transform.scale(
                      scale: 1 + 0.10 * t,
                      child: Opacity(
                        opacity: (1 - 0.12 * t) * (willUnpin ? 0.55 : 1),
                        child: child,
                      ),
                    ),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: theme.borderRadius(12),
                        boxShadow: [
                          BoxShadow(
                            color: colors.shadow.withValues(alpha: 0.45),
                            blurRadius: 18,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: widget.services.buildApplicationIcon(
                        context,
                        dragEntry.appId,
                      ),
                    ),
                  ),
                ),
              ),
            if (nameLabel != null) nameLabel,
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 4,
              child: ShellInputRegion(
                debugLabel: 'Dock reveal edge',
                child: MouseRegion(
                  onEnter: _onEdgeEnter,
                  onExit: _onEdgeExit,
                  child: const ColoredBox(color: Color(0x00000000)),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _capsuleSurface(ShellThemeData theme) {
    final radius = theme.borderRadius(20);
    return ShellBackdropBlur(
      blur: theme.effectivePanelOpacity < 1,
      separateChild: true,
      borderRadius: radius,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          color: theme.panelColor(theme.colors.surfaceContainer),
          border: Border.all(color: theme.colors.hairline),
        ),
      ),
    );
  }

  Widget? _slotChild(
    BuildContext context, {
    required _SlotSpec spec,
    required DockSlotLayout slot,
    required double capsuleLeft,
    required List<_DockEntry> entries,
    required bool dragging,
  }) {
    final left = slot.center - capsuleLeft - slot.half;
    final lift =
        (slot.scale - 1.0) * DockSettings.iconSize * DockSettings.liftRatio;
    // Neighbours ease into their new slot while an icon is being dragged,
    // matching the reorder animation in the reference docks.
    Widget slotAt({
      required double left,
      required double bottom,
      required double width,
      required double height,
      required Widget child,
      Key? key,
    }) => AnimatedPositioned(
      key: key,
      // Zero duration keeps magnification frame-exact; the drag uses a short
      // ease so neighbours slide into their new slot.
      duration: dragging ? const Duration(milliseconds: 180) : Duration.zero,
      curve: Curves.easeOutCubic,
      left: left,
      bottom: bottom,
      width: width,
      height: height,
      child: child,
    );

    switch (spec.kind) {
      case _SlotKind.divider:
        return slotAt(
          left: slot.center - capsuleLeft - 0.5,
          bottom: DockSettings.padding + DockSettings.iconSize * 0.24,
          width: 1,
          height: DockSettings.iconSize * 0.52,
          child: ColoredBox(color: context.shellTheme.colors.hairline),
        );
      case _SlotKind.launcher:
        return slotAt(
          left: left,
          bottom: DockSettings.padding,
          width: slot.half * 2,
          height: slot.half * 2,
          child: _LauncherItem(
            size: slot.half * 2,
            lift: lift,
            onTap: widget.services.toggleLauncher,
          ),
        );
      case _SlotKind.app:
        final entryIndex = spec.entry!;
        final entry = entries[entryIndex];
        // The dragged source stays mounted but invisible: it owns the pan
        // recognizer, and unmounting it mid-gesture would kill the drag.
        final isSource =
            dragging &&
            entry.pin != null &&
            normalizeAppId(entry.pin!.appId) == _dragKey;
        final pinIndex = entries
            .take(entryIndex)
            .where((candidate) => candidate.pinned)
            .length;
        return slotAt(
          key: ValueKey('dock-${entry.appId}'),
          left: left,
          bottom: DockSettings.padding,
          width: slot.half * 2,
          height: slot.half * 2,
          child: Opacity(
            opacity: isSource ? 0 : 1,
            child: DockItemWidget(
              appId: entry.appId,
              launchId: entry.launchId,
              name: entry.name,
              windows: entry.windows,
              pinned: entry.pin != null,
              dragging: dragging,
              services: widget.services,
              monitorId: widget.monitorId,
              monitorBounds: widget.environment.output.logicalRect,
              size: slot.half * 2,
              lift: lift,
              onTogglePin: () => _togglePin(entry),
              onOverlayChanged: _setOverlayHold,
              onDragStart: entry.pin == null
                  ? null
                  : (pointer) =>
                        _startDrag(entry, entryIndex, pinIndex, pointer),
              onDragUpdate: entry.pin == null ? null : _updateDrag,
              onDragEnd: entry.pin == null ? null : _endDrag,
            ),
          ),
        );
    }
  }

  _LabelTarget? _labelFor(
    DockLayoutFrame frame,
    List<_SlotSpec> specs,
    List<_DockEntry> entries,
  ) {
    final nearest = frame.nearest(_pointer);
    if (nearest == null) return null;
    final (index, slot, distance) = nearest;
    if (distance > slot.half + 20) return null;
    final spec = specs[index];
    final center = slot.center;
    return switch (spec.kind) {
      _SlotKind.app => _LabelTarget(
        name: entries[spec.entry!].name,
        center: center,
      ),
      _SlotKind.launcher => _LabelTarget(name: '启动台', center: center),
      _SlotKind.divider => null,
    };
  }
}

enum _SlotKind { app, divider, launcher }

class _SlotSpec {
  const _SlotSpec({required this.kind, required this.half, this.entry});

  final _SlotKind kind;
  final double half;
  final int? entry;

  bool get growable => kind != _SlotKind.divider;
}

class _DockEntry {
  const _DockEntry({
    required this.appId,
    required this.launchId,
    required this.name,
    required this.windows,
    required this.pin,
  });

  final String appId;
  final String? launchId;
  final String name;
  final List<ApplicationWindow> windows;
  final DockPin? pin;

  bool get pinned => pin != null;
}

class _LabelTarget {
  const _LabelTarget({required this.name, required this.center});

  final String name;
  final double center;
}

class _LauncherItem extends StatelessWidget {
  const _LauncherItem({
    required this.size,
    required this.lift,
    required this.onTap,
  });

  final double size;
  final double lift;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final backing = Color.alphaBlend(
      theme.accent.withValues(alpha: 0.18),
      theme.cardColor(theme.colors.surfaceContainerHigh),
    );
    return Transform.translate(
      offset: Offset(0, -lift),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(shape: BoxShape.circle, color: backing),
          child: Center(
            child: SizedBox.square(
              dimension: size * 0.42,
              child: CustomPaint(painter: _LauncherGlyphPainter(theme.accent)),
            ),
          ),
        ),
      ),
    );
  }
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
