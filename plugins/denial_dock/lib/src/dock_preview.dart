import 'dart:async';

import 'package:denial_flutter_sdk/effects.dart';
import 'package:denial_flutter_sdk/services.dart';
import 'package:flutter/material.dart';

/// Live window preview thumbnail card with desktop peeking emphasis.
class DockWindowPreviewCard extends StatefulWidget {
  const DockWindowPreviewCard({
    required this.window,
    required this.monitorId,
    required this.services,
    required this.onActivated,
    super.key,
  });

  final ApplicationWindow window;
  final int monitorId;
  final ShellServices services;
  final VoidCallback onActivated;

  @override
  State<DockWindowPreviewCard> createState() => _DockWindowPreviewCardState();
}

class _DockWindowPreviewCardState extends State<DockWindowPreviewCard> {
  Timer? _emphasisTimer;
  VoidCallback? _releaseEmphasis;
  bool _isHovered = false;

  void _onEnter() {
    setState(() => _isHovered = true);
    _emphasisTimer?.cancel();
    _emphasisTimer = Timer(const Duration(milliseconds: 250), () {
      if (mounted && _isHovered) {
        _releaseEmphasis = widget.services.emphasizeWindow(
          widget.window.id,
          monitorId: widget.monitorId,
        );
      }
    });
  }

  void _onExit() {
    setState(() => _isHovered = false);
    _clearEmphasis();
  }

  void _clearEmphasis() {
    _emphasisTimer?.cancel();
    _emphasisTimer = null;
    final release = _releaseEmphasis;
    _releaseEmphasis = null;
    release?.call();
  }

  @override
  void dispose() {
    _clearEmphasis();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final previewWidth = widget.window.previewSize.width > 0
        ? widget.window.previewSize.width
        : 192.0;
    final previewHeight = widget.window.previewSize.height > 0
        ? widget.window.previewSize.height
        : 120.0;
    final aspectRatio = (previewWidth / previewHeight).clamp(1.2, 2.2);

    return MouseRegion(
      onEnter: (_) => _onEnter(),
      onExit: (_) => _onExit(),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          widget.services.activateWindow(widget.window.id);
          widget.onActivated();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          width: 220,
          margin: const EdgeInsets.symmetric(horizontal: 4.0),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12.0),
            color: _isHovered
                ? Colors.white.withValues(alpha: 0.18)
                : Colors.white.withValues(alpha: 0.08),
            border: Border.all(
              color: _isHovered
                  ? Colors.white.withValues(alpha: 0.4)
                  : Colors.white.withValues(alpha: 0.15),
              width: 0.8,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 12.0,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Title bar header with app title and close button
              Padding(
                padding: const EdgeInsets.fromLTRB(10.0, 6.0, 6.0, 4.0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.window.title.isNotEmpty
                            ? widget.window.title
                            : widget.window.appId,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4.0),
                    InkWell(
                      onTap: () {
                        widget.services.minimizeWindow(widget.window.id);
                      },
                      borderRadius: BorderRadius.circular(10.0),
                      child: Container(
                        padding: const EdgeInsets.all(2.5),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.12),
                        ),
                        child: const Icon(
                          Icons.close,
                          size: 11.0,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Live window preview texture thumbnail
              Padding(
                padding: const EdgeInsets.fromLTRB(6.0, 0.0, 6.0, 6.0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8.0),
                  child: AspectRatio(
                    aspectRatio: aspectRatio,
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.45),
                      child: widget.services.buildWindowPreview(
                        context,
                        widget.window.id,
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
}

/// Frosted popover tray presenting multiple window thumbnails.
class DockWindowPreviewTray extends StatelessWidget {
  const DockWindowPreviewTray({
    required this.windows,
    required this.monitorId,
    required this.services,
    required this.onDismiss,
    super.key,
  });

  final List<ApplicationWindow> windows;
  final int monitorId;
  final ShellServices services;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    if (windows.isEmpty) return const SizedBox.shrink();

    return ShellBackdropBlur(
      borderRadius: BorderRadius.circular(16.0),
      child: Container(
        padding: const EdgeInsets.all(8.0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16.0),
          color: const Color(0xCC18181A),
          border: Border.all(color: Colors.white.withValues(alpha: 0.22), width: 0.8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 24.0,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final window in windows)
                DockWindowPreviewCard(
                  window: window,
                  monitorId: monitorId,
                  services: services,
                  onActivated: onDismiss,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
