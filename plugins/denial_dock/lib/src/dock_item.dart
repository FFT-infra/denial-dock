import 'package:denial_flutter_sdk/services.dart';
import 'package:flutter/material.dart';

import 'dock_math.dart';

/// Single interactive application item in the Dock.
class DockItemWidget extends StatefulWidget {
  const DockItemWidget({
    required this.appId,
    required this.name,
    required this.windows,
    required this.isPinned,
    required this.services,
    required this.monitorId,
    required this.baseSize,
    required this.scale,
    required this.dx,
    required this.liftRatio,
    required this.onTap,
    required this.onTogglePin,
    required this.onRequestPreview,
    super.key,
  });

  final String appId;
  final String name;
  final List<ApplicationWindow> windows;
  final bool isPinned;
  final ShellServices services;
  final int monitorId;
  final double baseSize;
  final double scale;
  final double dx;
  final double liftRatio;
  final VoidCallback onTap;
  final ValueChanged<bool> onTogglePin;
  final VoidCallback onRequestPreview;

  @override
  State<DockItemWidget> createState() => _DockItemWidgetState();
}

class _DockItemWidgetState extends State<DockItemWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bounceController;
  bool _isLaunching = false;

  @override
  void initState() {
    super.initState();
    _bounceController =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 700),
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed) {
            if (_isLaunching && widget.windows.isEmpty) {
              _bounceController.forward(from: 0.0);
            } else {
              setState(() => _isLaunching = false);
            }
          }
        });
  }

  @override
  void didUpdateWidget(DockItemWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_isLaunching && widget.windows.isNotEmpty) {
      _isLaunching = false;
    }
  }

  @override
  void dispose() {
    _bounceController.dispose();
    super.dispose();
  }

  void _handleClick() {
    if (widget.windows.isEmpty) {
      setState(() => _isLaunching = true);
      _bounceController.forward(from: 0.0);
      widget.services.launchApplication(
        widget.appId,
        monitorId: widget.monitorId,
      );
      widget.onTap();
    } else if (widget.windows.length == 1) {
      final win = widget.windows.first;
      if (win.active) {
        widget.services.minimizeWindow(win.id);
      } else {
        widget.services.activateWindow(win.id);
      }
      widget.onTap();
    } else {
      // Multiple windows: open preview tray
      widget.onRequestPreview();
    }
  }

  void _showContextMenu(BuildContext context, TapDownDetails details) {
    final position = RelativeRect.fromRect(
      Rect.fromPoints(details.globalPosition, details.globalPosition),
      Offset.zero & MediaQuery.of(context).size,
    );

    showMenu<String>(
      context: context,
      position: position,
      color: const Color(0xEE222224),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.0),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.2), width: 0.8),
      ),
      items: [
        PopupMenuItem(
          value: 'launch',
          child: Text(
            widget.windows.isEmpty ? '启动应用' : '打开新窗口',
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
        ),
        PopupMenuItem(
          value: 'pin',
          child: Text(
            widget.isPinned ? '从 Dock 中移除' : '保留在 Dock',
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
        ),
        if (widget.windows.isNotEmpty)
          PopupMenuItem(
            value: 'close',
            child: const Text(
              '关闭全部窗口',
              style: TextStyle(color: Colors.redAccent, fontSize: 13),
            ),
          ),
      ],
    ).then((choice) {
      if (!mounted || choice == null) return;
      switch (choice) {
        case 'launch':
          widget.services.launchApplication(
            widget.appId,
            monitorId: widget.monitorId,
          );
          break;
        case 'pin':
          widget.onTogglePin(!widget.isPinned);
          break;
        case 'close':
          for (final win in widget.windows) {
            widget.services.minimizeWindow(win.id);
          }
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isRunning = widget.windows.isNotEmpty;
    final hasActiveWindow = widget.windows.any((w) => w.active);
    final accentColor = Theme.of(context).colorScheme.primary;

    return AnimatedBuilder(
      animation: _bounceController,
      builder: (context, child) {
        final bounceOffset = _isLaunching
            ? -DockMath.launchBounce(_bounceController.value) *
                  (widget.baseSize * 0.45)
            : 0.0;
        final liftOffset =
            -(widget.scale - 1.0) * (widget.baseSize * widget.liftRatio);
        final totalOffsetY = liftOffset + bounceOffset;

        return Transform(
          transform: Matrix4.identity()
            ..translate(widget.dx, totalOffsetY)
            ..scale(widget.scale),
          alignment: Alignment.bottomCenter,
          child: child,
        );
      },
      child: GestureDetector(
        onTap: _handleClick,
        onSecondaryTapDown: (details) => _showContextMenu(context, details),
        child: SizedBox(
          width: widget.baseSize,
          height: widget.baseSize + 10.0,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.topCenter,
            children: [
              // Icon Container
              Container(
                width: widget.baseSize,
                height: widget.baseSize,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(13.0),
                  color: Colors.transparent,
                ),
                child: Center(
                  child: widget.services.buildApplicationIcon(
                    context,
                    widget.appId,
                  ),
                ),
              ),

              // macOS Active Indicator Dot
              if (isRunning)
                Positioned(
                  bottom: 2.0,
                  child: Container(
                    width: widget.windows.length > 1 ? 7.0 : 4.0,
                    height: 4.0,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(2.0),
                      color: hasActiveWindow
                          ? accentColor
                          : Colors.white.withValues(alpha: 0.85),
                      boxShadow: [
                        BoxShadow(
                          color: (hasActiveWindow ? accentColor : Colors.white)
                              .withValues(alpha: 0.6),
                          blurRadius: 4.0,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
