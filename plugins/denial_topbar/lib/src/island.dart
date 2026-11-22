import 'dart:math' as math;

import 'package:denial_flutter_sdk/models.dart';
import 'package:denial_flutter_sdk/services.dart';
import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/widgets.dart';

import 'bar_icons.dart';
import 'bar_tokens.dart';
import 'bar_type.dart';
import 'island_mode.dart';

export 'island_mode.dart';

/// The resting pill.
///
/// macOS 27's own island is a 58 × 31 pt capsule 8.5 pt from the top edge,
/// with a 32 pt radius once expanded and 16 pt of padding [S27]. A 24 pt menu
/// bar cannot hold 31, so the pill takes the bar's height and the expanded
/// card keeps the measured radius and padding. revo-shell's
/// `DynamicIsland.qml` supplies the content layout and the width clamp.
class TopBarIsland extends StatefulWidget {
  const TopBarIsland({
    required this.mode,
    required this.showClock,
    required this.timeText,
    required this.mediaTitle,
    required this.noticeSummary,
    required this.expanded,
    required this.height,
    required this.onOpen,
    this.onHover,
    this.workspace,
    this.workspaceWidth = 0,
    this.onNoticeClose,
    super.key,
  });

  final IslandMode mode;
  final bool showClock;
  final String timeText;
  final String mediaTitle;
  final String noticeSummary;
  final bool expanded;

  /// Capsule height, clamped by the strip the surface was given.
  final double height;
  final VoidCallback onOpen;
  final ValueChanged<bool>? onHover;

  /// Workspace switcher, shown in place of the idle clock when the settings
  /// put it here.
  final Widget? workspace;

  /// Width the workspace switcher needs, so the pill can size itself before
  /// its child is laid out.
  final double workspaceWidth;
  final VoidCallback? onNoticeClose;

  @override
  State<TopBarIsland> createState() => _TopBarIslandState();
}

class _TopBarIslandState extends State<TopBarIsland> {
  /// revo-shell sizes the pill from `TextMetrics` of the same string and
  /// style. A `TextPainter` measures the same way without a layout pass.
  double _measure(BuildContext context, String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 1,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  @override
  Widget build(BuildContext context) {
    final label = switch (widget.mode) {
      IslandMode.media => widget.mediaTitle,
      IslandMode.notice => widget.noticeSummary,
      IslandMode.quiet => '',
    };
    final width = switch (widget.mode) {
      IslandMode.media when widget.expanded =>
        (_measure(context, label, BarType.islandLabel) +
                BarTokens.islandMediaTextPad)
            .clamp(
              BarTokens.islandMediaMinWidth,
              BarTokens.islandMediaMaxWidth,
            ),
      IslandMode.notice when widget.expanded =>
        (_measure(context, label, BarType.islandLabel) +
                BarTokens.islandNoticeTextPad)
            .clamp(
              BarTokens.islandNoticeMinWidth,
              BarTokens.islandNoticeMaxWidth,
            ),
      // The resting capsule is 58 wide on macOS, which is enough for a clock
      // but not for every locale's format, so the measured text can widen it.
      _ => math.max(
        BarTokens.islandIdleWidth,
        math.max(
          widget.workspaceWidth,
          widget.showClock
              ? _measure(context, widget.timeText, BarType.islandLabel) + 18
              : 0.0,
        ),
      ),
    };

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => widget.onHover?.call(true),
      onExit: (_) => widget.onHover?.call(false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onOpen,
        child: Semantics(
          button: true,
          label: 'Dynamic Island',
          child: AnimatedContainer(
            duration: BarTokens.islandWidth,
            curve: Curves.easeOutCubic,
            width: width,
            height: widget.height,
            decoration: BoxDecoration(
              color: const Color(BarTokens.islandFill),
              borderRadius: BorderRadius.circular(widget.height / 2),
              // The system island is a hole in the screen, so it needs a
              // hairline to separate it from a black wallpaper.
              border: Border.all(
                color: const Color(0xffffffff)
                    .withValues(alpha: BarTokens.islandBorderAlpha * 0.5),
                width: 0.6,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 9),
            child: _content(),
          ),
        ),
      ),
    );
  }

  Widget _content() {
    const ink = Color(0xffffffff);
    // An expanded pill with nothing to report (playback stopped, notice
    // dismissed) falls back to the resting content rather than an empty row.
    if (!widget.expanded || widget.mode.isQuiet) {
      final workspace = widget.workspace;
      if (workspace != null) return Center(child: workspace);
      return Center(
        child: widget.showClock
            ? Text(
                widget.timeText,
                maxLines: 1,
                style: BarType.islandLabel.copyWith(
                  color: ink,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              )
            : Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  color: ink.withValues(alpha: 0.42),
                  shape: BoxShape.circle,
                ),
              ),
      );
    }

    final isNotice = widget.mode == IslandMode.notice;
    final label = isNotice ? widget.noticeSummary : widget.mediaTitle;
    return Row(
      children: <Widget>[
        _StatusDot(
          colour: isNotice
              ? const Color(0xffff453a)
              : context.shellTheme.accent,
          isNotice: isNotice,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label.replaceAll(RegExp(r'\s*\n\s*'), ' '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: BarType.islandLabel.copyWith(color: ink),
          ),
        ),
        if (!isNotice) const _Equalizer(),
        if (isNotice && widget.onNoticeClose != null)
          _CloseDot(onTap: widget.onNoticeClose!),
      ],
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.colour, required this.isNotice});

  final Color colour;
  final bool isNotice;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
      child: Icon(
        isNotice ? BarIcons.bellFill : BarIcons.playFill,
        size: 9,
        color: const Color(0xffffffff),
      ),
    );
  }
}

/// revo-shell's three bars: heights 6 / 10 / 8, width 2, radius 1, animated
/// on a 900 ms cycle while playing.
class _Equalizer extends StatefulWidget {
  const _Equalizer();

  @override
  State<_Equalizer> createState() => _EqualizerState();
}

class _EqualizerState extends State<_Equalizer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = context.shellTheme.accent;
    const base = <double>[6, 10, 8];
    return SizedBox(
      width: 10,
      height: 12,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              for (var index = 0; index < 3; index++)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1),
                  child: Container(
                    width: 2,
                    height:
                        base[index] +
                        (index == 1 ? 2 : 0) *
                            (1 + _controller.value * (index == 0 ? 1 : 0.6)),
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _CloseDot extends StatefulWidget {
  const _CloseDot({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_CloseDot> createState() => _CloseDotState();
}

class _CloseDotState extends State<_CloseDot> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: _hovered
                ? const Color(0xffffffff).withValues(alpha: 0.2)
                : const Color(0x00000000),
            shape: BoxShape.circle,
          ),
          child: Icon(BarIcons.xmark, size: 8, color: const Color(0xffa0a0a8)),
        ),
      ),
    );
  }
}

/// The expanded card.
///
/// macOS 27 measures 340 wide, 32 continuous corners on all four sides and
/// 16 pt of padding [S27]; the content follows revo-shell's `islandPopup`:
/// a 52 pt app tile with the title over two lines of body for a notice, and
/// a 68 pt cover with the transport row for media.
class IslandExpandedBody extends StatelessWidget {
  const IslandExpandedBody({
    required this.mode,
    required this.notification,
    required this.playback,
    required this.artwork,
    required this.onDismissNotice,
    required this.onActivateNotice,
    required this.commands,
    super.key,
  });

  final IslandMode mode;
  final DesktopNotification? notification;
  final MprisPlaybackState? playback;
  final Widget? artwork;
  final VoidCallback onDismissNotice;
  final VoidCallback onActivateNotice;
  final MediaCommands commands;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: BarTokens.islandPopupWidth,
      child: Padding(
        padding: const EdgeInsets.all(BarTokens.islandPopupPadding),
        child: mode == IslandMode.notice
            ? _NoticeView(
                notification: notification,
                onDismiss: onDismissNotice,
                onActivate: onActivateNotice,
              )
            : _MediaView(
                playback: playback,
                artwork: artwork,
                commands: commands,
              ),
      ),
    );
  }
}

class _NoticeView extends StatelessWidget {
  const _NoticeView({
    required this.notification,
    required this.onDismiss,
    required this.onActivate,
  });

  final DesktopNotification? notification;
  final VoidCallback onDismiss;
  final VoidCallback onActivate;

  @override
  Widget build(BuildContext context) {
    final note = notification;
    if (note == null) return const SizedBox(height: 70);
    final title = note.summary.replaceAll(RegExp(r'\s*\n\s*'), ' ');
    final body = note.body.replaceAll(RegExp(r'\s*\n\s*'), ' ');
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onActivate,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: const Color(0xff1c1c1e),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(
              child: Icon(
                BarIcons.bellFill,
                size: 24,
                color: Color(0xffa0a0a8),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  note.appName.isEmpty ? note.sender : note.appName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: BarType.islandCaption.copyWith(
                    color: const Color(0xffa0a0a8),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: BarType.islandTitle.copyWith(
                    color: const Color(0xffffffff),
                  ),
                ),
                if (body.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: BarType.islandCaption.copyWith(
                      color: const Color(0xffa0a0a8),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onDismiss,
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: const Color(0xffffffff).withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                BarIcons.xmark,
                size: 10,
                color: Color(0xffa0a0a8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MediaView extends StatelessWidget {
  const _MediaView({
    required this.playback,
    required this.artwork,
    required this.commands,
  });

  final MprisPlaybackState? playback;
  final Widget? artwork;
  final MediaCommands commands;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final state = playback;
    final playing = state?.status == MprisPlaybackStatus.playing;
    final title = state?.title.isNotEmpty == true
        ? state!.title
        : 'Nothing playing';
    final artist = state == null || state.artists.isEmpty
        ? ''
        : state.artists.join(', ');

    return Row(
      children: <Widget>[
        Container(
          width: 68,
          height: 68,
          decoration: BoxDecoration(
            color: const Color(0xff1c1c1e),
            borderRadius: BorderRadius.circular(14),
          ),
          clipBehavior: Clip.antiAlias,
          child:
              artwork ??
              const Center(
                child: Icon(
                  BarIcons.playFill,
                  size: 26,
                  color: Color(0xffa0a0a8),
                ),
              ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: BarType.islandTitle.copyWith(
                  color: const Color(0xffffffff),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: BarType.islandCaption.copyWith(
                  color: const Color(0xffa0a0a8),
                ),
              ),
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  _TransportButton(
                    icon: BarIcons.backward,
                    onTap: () => commands.previous(),
                    size: 18,
                  ),
                  const SizedBox(width: 20),
                  _PlayButton(
                    playing: playing,
                    accent: theme.accent,
                    onTap: () => commands.playPause(),
                  ),
                  const SizedBox(width: 20),
                  _TransportButton(
                    icon: BarIcons.forward,
                    onTap: () => commands.next(),
                    size: 18,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TransportButton extends StatelessWidget {
  const _TransportButton({
    required this.icon,
    required this.onTap,
    required this.size,
  });

  final IconData icon;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Icon(icon, size: size, color: const Color(0xffffffff)),
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({
    required this.playing,
    required this.accent,
    required this.onTap,
  });

  final bool playing;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
          child: Icon(
            playing ? BarIcons.pauseFill : BarIcons.playFill,
            size: 13,
            color: const Color(0xffffffff),
          ),
        ),
      ),
    );
  }
}

/// Where the island sits relative to the bar.
///
/// macOS centres its island on the camera housing; a clone without one puts
/// it in the middle of the strip, which is what this returns.
double islandCentreOffset(double stripWidth, double islandWidth) =>
    math.max(0, (stripWidth - islandWidth) / 2);
