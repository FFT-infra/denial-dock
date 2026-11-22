import 'dart:async';

import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/material.dart';

import '../top_bar_settings.dart';
import 'island_activity.dart';

class TopBarIsland extends StatefulWidget {
  const TopBarIsland({
    required this.activity,
    required this.bodyHeight,
    required this.clockInIsland,
    required this.showDate,
    required this.timeText,
    required this.dateText,
    required this.mediaTitle,
    required this.batteryText,
    required this.notificationText,
    required this.style,
    required this.hoverPeek,
    required this.expanded,
    required this.onOpen,
    super.key,
  });

  final IslandActivity activity;
  final double bodyHeight;
  final bool clockInIsland;
  final bool showDate;
  final String timeText;
  final String dateText;
  final String mediaTitle;
  final String batteryText;
  final String notificationText;
  final TopBarIslandStyle style;
  final bool hoverPeek;
  final bool expanded;
  final VoidCallback onOpen;

  @override
  State<TopBarIsland> createState() => _TopBarIslandState();
}

class _TopBarIslandState extends State<TopBarIsland> {
  Timer? _enter;
  Timer? _leave;
  bool _hovered = false;
  bool _peeked = false;

  @override
  void dispose() {
    _enter?.cancel();
    _leave?.cancel();
    super.dispose();
  }

  void _setHovered(bool value) {
    if (value == _hovered) return;
    _hovered = value;
    _leave?.cancel();
    _enter?.cancel();
    if (!widget.hoverPeek) return;
    if (value) {
      _enter = Timer(const Duration(milliseconds: 90), () {
        if (mounted) setState(() => _peeked = true);
      });
    } else {
      _leave = Timer(const Duration(milliseconds: 200), () {
        if (mounted) setState(() => _peeked = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final black = widget.style == TopBarIslandStyle.black;
    final width = widget.expanded
        ? 224.0
        : _peeked
        ? 232.0
        : widget.clockInIsland
        ? 118.0
        : widget.activity.isQuiet
        ? 56.0
        : 104.0;
    final height = (widget.bodyHeight - (_peeked ? 4 : 8)).clamp(20.0, 44.0);
    final foreground = black ? Colors.white : theme.colors.textPrimary;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onOpen,
        child: Semantics(
          button: true,
          label: 'System island',
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Motion.md3EmphasizedDecelerate,
            width: width,
            height: height,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: black
                  ? const Color(0xff08080a)
                  : theme.panelColor(theme.colors.panelBackground),
              borderRadius: BorderRadius.circular(height / 2),
              border: Border.all(
                color: black
                    ? Colors.white.withValues(alpha: 0.10)
                    : theme.colors.hairline,
                width: 0.8,
              ),
            ),
            child: ClipRect(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: _content(foreground),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(Color foreground) {
    if (widget.expanded || _peeked) {
      final label = switch (widget.activity) {
        IslandActivity.media => widget.mediaTitle,
        IslandActivity.charging => widget.batteryText,
        IslandActivity.notification => widget.notificationText,
        IslandActivity.quiet =>
          widget.showDate ? widget.dateText : widget.timeText,
      };
      return Row(
        key: const ValueKey('peek'),
        children: <Widget>[
          _activityGlyph(foreground),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.shellTheme.text.systemBarValue.copyWith(
                color: foreground,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      );
    }
    if (widget.clockInIsland) {
      return Center(
        key: const ValueKey('clock'),
        child: Text(
          widget.timeText,
          maxLines: 1,
          style: context.shellTheme.text.systemBarValue.copyWith(
            color: foreground,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }
    return Center(
      key: const ValueKey('idle'),
      child: _activityGlyph(foreground),
    );
  }

  Widget _activityGlyph(Color foreground) {
    return SizedBox(
      width: 18,
      height: 18,
      child: switch (widget.activity) {
        IslandActivity.media => Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            _Bar(height: 7, color: foreground),
            const SizedBox(width: 2),
            _Bar(height: 13, color: foreground),
            const SizedBox(width: 2),
            _Bar(height: 10, color: foreground),
          ],
        ),
        IslandActivity.charging => Icon(
          Icons.bolt,
          size: 17,
          color: foreground,
        ),
        IslandActivity.notification => Icon(
          Icons.notifications_none,
          size: 16,
          color: foreground,
        ),
        IslandActivity.quiet => Center(
          child: Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: foreground.withValues(alpha: 0.42),
              shape: BoxShape.circle,
            ),
          ),
        ),
      },
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.height, required this.color});

  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 3,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(1.5),
      ),
    );
  }
}
