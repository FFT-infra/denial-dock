import 'dart:math' as math;

import 'package:denial_flutter_sdk/effects.dart';
import 'package:denial_flutter_sdk/input.dart';
import 'package:denial_flutter_sdk/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dock_item.dart';
import 'dock_math.dart';
import 'dock_preferences.dart';
import 'dock_preview.dart';

/// The root floating macOS-style Dock container.
class DockContainer extends ConsumerStatefulWidget {
  const DockContainer({
    required this.monitorId,
    required this.services,
    this.preferences = const DockPreferences(),
    super.key,
  });

  final int monitorId;
  final ShellServices services;
  final DockPreferences preferences;

  @override
  ConsumerState<DockContainer> createState() => _DockContainerState();
}

class _DockContainerState extends ConsumerState<DockContainer>
    with SingleTickerProviderStateMixin {
  late Ticker _ticker;
  late List<String> _pinnedAppIds;

  // Physics animation state
  double _currentPointerX = -1000.0;
  double _targetPointerX = -1000.0;
  double _hoverProgress = 0.0; // 0.0 to 1.0
  double _targetHoverProgress = 0.0;
  Duration _lastTick = Duration.zero;

  // Active preview state
  String? _previewAppId;
  List<ApplicationWindow>? _previewWindows;
  double? _previewCenterX;

  // Hover name label state
  String? _hoveredAppName;
  double _hoveredAppCenterX = 0.0;

  @override
  void initState() {
    super.initState();
    _pinnedAppIds = List<String>.from(widget.preferences.pinnedAppIds);
    _ticker = createTicker(_onTick);
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _ensureTickerRunning() {
    if (!_ticker.isActive) {
      _lastTick = Duration.zero;
      _ticker.start();
    }
  }

  void _onTick(Duration elapsed) {
    if (_lastTick == Duration.zero) {
      _lastTick = elapsed;
      return;
    }
    final dt = (elapsed - _lastTick).inMicroseconds / 1000000.0;
    _lastTick = elapsed;

    // Advance hover entrance/exit progress
    final nextProgress = DockMath.advance(
      _hoverProgress,
      _targetHoverProgress,
      dt,
      responseSeconds: 0.032,
    );

    // Advance pointer tracking position
    final nextPointer = DockMath.advance(
      _currentPointerX,
      _targetPointerX,
      dt,
      responseSeconds: 0.026,
    );

    final progressChanged = (_hoverProgress - nextProgress).abs() > 0.0001;
    final pointerChanged = (_currentPointerX - nextPointer).abs() > 0.001;

    if (progressChanged || pointerChanged) {
      setState(() {
        _hoverProgress = nextProgress;
        _currentPointerX = nextPointer;
      });
    } else {
      // Settle reached: stop ticker to conserve CPU
      _ticker.stop();
      _lastTick = Duration.zero;
    }
  }

  void _onPointerHover(PointerHoverEvent event, double dockLocalLeft) {
    final localX = event.localPosition.dx - dockLocalLeft;
    _targetPointerX = localX;
    _targetHoverProgress = 1.0;
    _ensureTickerRunning();
  }

  void _onPointerExit() {
    _targetHoverProgress = 0.0;
    _hoveredAppName = null;
    _ensureTickerRunning();
  }

  String _normalizeAppId(String id) {
    return id.trim().toLowerCase().replaceFirst(RegExp(r'\.desktop$'), '');
  }

  @override
  Widget build(BuildContext context) {
    final allWindows = ref.watch(widget.services.windows(widget.monitorId));
    final catalogApps = ref.watch(widget.services.applications);

    // Map installed apps by normalized id
    final catalogMap = <String, LaunchableApplication>{};
    for (final app in catalogApps) {
      catalogMap[_normalizeAppId(app.id)] = app;
      catalogMap[_normalizeAppId(app.appId)] = app;
      for (final wId in app.windowAppIds) {
        catalogMap[_normalizeAppId(wId)] = app;
      }
    }

    // Group windows by normalized appId
    final windowGroups = <String, List<ApplicationWindow>>{};
    for (final win in allWindows) {
      final key = _normalizeAppId(win.appId);
      windowGroups.putIfAbsent(key, () => []).add(win);
    }

    // Build the ordered entries
    final pinnedEntries = <_DockEntry>[];
    final unpinnedRunningEntries = <_DockEntry>[];

    for (final pinnedId in _pinnedAppIds) {
      final normKey = _normalizeAppId(pinnedId);
      final catalogEntry = catalogMap[normKey];
      final appName = catalogEntry?.name ?? pinnedId.split('.').first;
      final wins = windowGroups[normKey] ?? const [];
      pinnedEntries.add(
        _DockEntry(
          appId: pinnedId,
          displayName: appName,
          windows: wins,
          isPinned: true,
        ),
      );
    }

    for (final entry in windowGroups.entries) {
      final normKey = entry.key;
      final isAlreadyPinned = _pinnedAppIds.any(
        (id) => _normalizeAppId(id) == normKey,
      );
      if (!isAlreadyPinned) {
        final catalogEntry = catalogMap[normKey];
        final appName =
            catalogEntry?.name ??
            (entry.value.isNotEmpty ? entry.value.first.title : normKey);
        unpinnedRunningEntries.add(
          _DockEntry(
            appId: entry.value.isNotEmpty ? entry.value.first.appId : normKey,
            displayName: appName,
            windows: entry.value,
            isPinned: false,
          ),
        );
      }
    }

    final hasSeparator = unpinnedRunningEntries.isNotEmpty;
    final totalItemsCount =
        pinnedEntries.length +
        unpinnedRunningEntries.length +
        1; // +1 for App Launcher button

    // Layout slots calculation
    final iconBase = widget.preferences.iconSize;
    final spacing = widget.preferences.itemSpacing;
    final radius = widget.preferences.magnificationRadius;
    final maxScale = widget.preferences.maxScale;
    final padding = widget.preferences.capsulePadding;

    // Resting slots positions
    var currentRestingX = padding + (iconBase / 2.0);
    final slotCenters = <double>[];
    final slotHalfWidths = <double>[];
    final allEntries = <_DockEntry?>[];

    for (final item in pinnedEntries) {
      slotCenters.add(currentRestingX);
      slotHalfWidths.add(iconBase / 2.0);
      allEntries.add(item);
      currentRestingX += iconBase + spacing;
    }

    if (hasSeparator) {
      // Space for vertical divider
      currentRestingX += 6.0;
    }

    for (final item in unpinnedRunningEntries) {
      slotCenters.add(currentRestingX);
      slotHalfWidths.add(iconBase / 2.0);
      allEntries.add(item);
      currentRestingX += iconBase + spacing;
    }

    // App Launcher icon at right
    slotCenters.add(currentRestingX);
    slotHalfWidths.add(iconBase / 2.0);
    allEntries.add(null); // special launcher token

    final totalDockWidth = currentRestingX + (iconBase / 2.0) + padding;

    // Compute magnification wave scales and dx displacements
    final scales = <double>[];
    final dxs = <double>[];

    final amplitude = math.max(0.0, maxScale - 1.0) * _hoverProgress;
    final pitch = iconBase + spacing;
    final density = iconBase / pitch;
    final shoulder = pitch / 2.0;

    for (var i = 0; i < slotCenters.length; ++i) {
      final cx = slotCenters[i];
      final d = cx - _currentPointerX;
      final influence = _hoverProgress * DockMath.influenceAt(d, radius);
      final s = 1.0 + (maxScale - 1.0) * influence;
      scales.add(s);

      final dx = DockMath.computeDisplacement(
        d: d,
        density: density,
        shoulder: shoulder,
        support: radius,
        amplitude: amplitude,
      );
      dxs.add(dx);
    }

    // Update continuous name owner
    if (_hoverProgress > 0.05) {
      final ownerIndex = DockMath.resolveNameOwner(
        iconCenters: slotCenters,
        iconHalfWidths: slotHalfWidths,
        pointerX: _currentPointerX,
      );
      if (ownerIndex != null && ownerIndex < allEntries.length) {
        final entry = allEntries[ownerIndex];
        _hoveredAppName = entry?.displayName ?? '启动台';
        _hoveredAppCenterX = slotCenters[ownerIndex] + dxs[ownerIndex];
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;
        final dockLeft = (screenWidth - totalDockWidth) / 2.0;

        return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.bottomCenter,
          children: [
            // Floating Preview Popover
            if (_previewAppId != null &&
                _previewWindows != null &&
                _previewCenterX != null)
              Positioned(
                bottom: widget.preferences.restingThickness + 22.0,
                left: math.max(
                  12.0,
                  math.min(
                    screenWidth - 340.0,
                    dockLeft + _previewCenterX! - 160.0,
                  ),
                ),
                child: ShellInputRegion(
                  debugLabel: 'DockPreviewTray',
                  child: DockWindowPreviewTray(
                    windows: _previewWindows!,
                    monitorId: widget.monitorId,
                    services: widget.services,
                    onDismiss: () {
                      setState(() {
                        _previewAppId = null;
                        _previewWindows = null;
                      });
                    },
                  ),
                ),
              ),

            // Continuous Floating App Name Label
            if (_hoveredAppName != null && _hoverProgress > 0.3)
              Positioned(
                bottom: widget.preferences.restingThickness + 14.0,
                left: (dockLeft + _hoveredAppCenterX - 80.0).clamp(
                  12.0,
                  screenWidth - 160.0,
                ),
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: _hoverProgress.clamp(0.0, 1.0),
                    duration: const Duration(milliseconds: 140),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10.0,
                          vertical: 4.5,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8.0),
                          color: const Color(0xDD202022),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.18),
                            width: 0.8,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.35),
                              blurRadius: 8.0,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Text(
                          _hoveredAppName!,
                          maxLines: 1,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12.0,
                            fontWeight: FontWeight.w500,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            // The Dock Capsule
            Positioned(
              bottom: 10.0,
              child: ShellInputRegion(
                debugLabel: 'DockCapsule',
                child: MouseRegion(
                  onHover: (e) => _onPointerHover(e, dockLeft),
                  onExit: (_) => _onPointerExit(),
                  child: ShellBackdropBlur(
                    borderRadius: BorderRadius.circular(22.0),
                    child: Container(
                      width: totalDockWidth,
                      height: widget.preferences.restingThickness,
                      padding: EdgeInsets.symmetric(horizontal: padding),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(22.0),
                        color: Colors.black.withValues(alpha: 0.28),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.20),
                          width: 0.8,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.35),
                            blurRadius: 24.0,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Pinned Items
                          for (var i = 0; i < pinnedEntries.length; i++)
                            DockItemWidget(
                              appId: pinnedEntries[i].appId,
                              name: pinnedEntries[i].displayName,
                              windows: pinnedEntries[i].windows,
                              isPinned: true,
                              services: widget.services,
                              monitorId: widget.monitorId,
                              baseSize: iconBase,
                              scale: scales[i],
                              dx: dxs[i],
                              liftRatio: widget.preferences.liftRatio,
                              onTap: () {
                                setState(() {
                                  _previewAppId = null;
                                  _previewWindows = null;
                                });
                              },
                              onTogglePin: (pin) {
                                setState(() {
                                  if (!pin) {
                                    _pinnedAppIds.remove(
                                      pinnedEntries[i].appId,
                                    );
                                  }
                                });
                              },
                              onRequestPreview: () {
                                setState(() {
                                  _previewAppId = pinnedEntries[i].appId;
                                  _previewWindows = pinnedEntries[i].windows;
                                  _previewCenterX = slotCenters[i] + dxs[i];
                                });
                              },
                            ),

                          // Subtle Glass Divider
                          if (hasSeparator)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4.0,
                              ),
                              child: Container(
                                width: 1.0,
                                height: iconBase * 0.55,
                                color: Colors.white.withValues(alpha: 0.18),
                              ),
                            ),

                          // Unpinned Running Items
                          for (
                            var j = 0;
                            j < unpinnedRunningEntries.length;
                            j++
                          )
                            Builder(
                              builder: (context) {
                                final idx = pinnedEntries.length + j;
                                final item = unpinnedRunningEntries[j];
                                return DockItemWidget(
                                  appId: item.appId,
                                  name: item.displayName,
                                  windows: item.windows,
                                  isPinned: false,
                                  services: widget.services,
                                  monitorId: widget.monitorId,
                                  baseSize: iconBase,
                                  scale: scales[idx],
                                  dx: dxs[idx],
                                  liftRatio: widget.preferences.liftRatio,
                                  onTap: () {
                                    setState(() {
                                      _previewAppId = null;
                                      _previewWindows = null;
                                    });
                                  },
                                  onTogglePin: (pin) {
                                    setState(() {
                                      if (pin &&
                                          !_pinnedAppIds.contains(item.appId)) {
                                        _pinnedAppIds.add(item.appId);
                                      }
                                    });
                                  },
                                  onRequestPreview: () {
                                    setState(() {
                                      _previewAppId = item.appId;
                                      _previewWindows = item.windows;
                                      _previewCenterX =
                                          slotCenters[idx] + dxs[idx];
                                    });
                                  },
                                );
                              },
                            ),

                          // Launcher Icon at end
                          Builder(
                            builder: (context) {
                              final launcherIdx = totalItemsCount - 1;
                              return Transform(
                                transform: Matrix4.identity()
                                  ..translate(
                                    dxs[launcherIdx],
                                    -(scales[launcherIdx] - 1.0) *
                                        (iconBase *
                                            widget.preferences.liftRatio),
                                  )
                                  ..scale(scales[launcherIdx]),
                                alignment: Alignment.bottomCenter,
                                child: GestureDetector(
                                  onTap: () {
                                    widget.services.toggleLauncher();
                                  },
                                  child: Container(
                                    width: iconBase,
                                    height: iconBase,
                                    margin: EdgeInsets.only(
                                      left: spacing / 2.0,
                                    ),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.white.withValues(alpha: 0.12),
                                      border: Border.all(
                                        color: Colors.white.withValues(alpha: 0.20),
                                        width: 0.8,
                                      ),
                                    ),
                                    child: const Center(
                                      child: Icon(
                                        Icons.apps_rounded,
                                        size: 24.0,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DockEntry {
  const _DockEntry({
    required this.appId,
    required this.displayName,
    required this.windows,
    required this.isPinned,
  });

  final String appId;
  final String displayName;
  final List<ApplicationWindow> windows;
  final bool isPinned;
}
