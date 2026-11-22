import 'dart:async';
import 'dart:math' as math;

import 'package:denial_flutter_sdk/models.dart';
import 'package:denial_flutter_sdk/services.dart';
import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/widgets.dart';

import 'bar_icons.dart';
import 'bar_tokens.dart';
import 'bar_type.dart';
import 'island_mode.dart';
import 'media_art.dart';

export 'island_mode.dart';

/// The resting pill.
///
/// macOS 27's island is a 58 × 31 pt capsule 8.5 pt from the top edge, with a
/// 32 pt radius once expanded and 16 pt of padding [S27]. A 28 pt menu bar
/// cannot hold 31, so the pill takes the bar's height and the expanded card
/// keeps the measured radius and padding.
///
/// The three faces follow darkshadow `DynIsland.qml`: idle is the date beside
/// the time in a pill of the key colour, media is the 20 pt cover and the
/// waveform at the measured 133 pt [S27], and a notice is the app dot and the
/// summary. A charging flash takes the pill for a moment when the charger goes
/// in, which is the one island event macOS shows with no way to turn it off
/// [S28].
class TopBarIsland extends StatefulWidget {
  const TopBarIsland({
    required this.mode,
    required this.showClock,
    required this.timeText,
    required this.dateText,
    required this.mediaTitle,
    required this.noticeSummary,
    required this.expanded,
    required this.height,
    required this.onOpen,
    this.onHover,
    this.workspace,
    this.workspaceWidth = 0,
    this.onNoticeClose,
    this.artworkUrl = '',
    this.chargePercent,
    super.key,
  });

  final IslandMode mode;
  final bool showClock;
  final String timeText;

  /// `Sat, 23/11`; darkshadow's idle row puts it before the time pill.
  final String dateText;
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

  /// `mpris:artUrl` of the playing track, if the player published one.
  final String artworkUrl;

  /// Battery percentage while the charge flash is up.
  final int? chargePercent;

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

  /// The time pill darkshadow draws: `implicitWidth + 18` inside a 38 pt
  /// strip, `height - 14` tall. This strip is shorter, so the pill keeps the
  /// same proportion but never shrinks below the 12 pt type it holds.
  double get _timePillHeight => math.max(14, widget.height - 12);

  @override
  Widget build(BuildContext context) {
    final width = _width(context);

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
            child: _content(context),
          ),
        ),
      ),
    );
  }

  /// Whether the workspace switcher owns the pill this frame.
  ///
  /// The switcher is Denial's own addition and takes the resting pill, which
  /// is otherwise empty. A live activity keeps the pill instead, because the
  /// compact Now Playing and the notice are what macOS shows there, and the
  /// workspaces come back as soon as the activity ends.
  bool get _workspaceOwnsPill =>
      widget.workspace != null && widget.mode.isQuiet && !widget.expanded;

  /// The pill's outer width.
  ///
  /// darkshadow sizes each face from its row's `implicitWidth` plus the row's
  /// own padding; this adds the 9 pt the capsule spends on each side, so the
  /// content below never has to know its container's inset.
  double _width(BuildContext context) {
    const padding = 18.0;
    if (_workspaceOwnsPill) {
      return math.max(
        BarTokens.islandIdleWidth,
        widget.workspaceWidth + padding,
      );
    }
    final clock = widget.showClock
        ? _measure(context, widget.timeText, BarType.islandLabel) +
              18 +
              (widget.dateText.isEmpty
                  ? 0
                  : _measure(context, widget.dateText, BarType.caption) + 9)
        : 0.0;
    final content = switch (widget.mode) {
      // S27: Now Playing compact is 133 wide, the 20 pt cover plus the wave.
      // The hover peek reveals the track name past that floor, up to the
      // notice ceiling so a long title cannot eat the bar.
      IslandMode.media => math.max(
        BarTokens.islandCompactMediaWidth - padding,
        math.max(
          widget.workspaceWidth,
          widget.expanded
              ? (_measure(context, widget.mediaTitle, BarType.islandLabel) +
                        48)
                    .clamp(
                      BarTokens.islandCompactMediaWidth - padding,
                      BarTokens.islandNoticeMaxWidth - padding,
                    )
              : 0.0,
        ),
      ),
      // The notice keeps its summary, so it widens with the text between the
      // measured floor and ceiling.
      IslandMode.notice => (_measure(
        context,
        widget.noticeSummary,
        BarType.islandLabel,
      ) + 28).clamp(
        BarTokens.islandNoticeMinWidth - padding,
        BarTokens.islandNoticeMaxWidth - padding,
      ),
      IslandMode.charging => 132.0,
      IslandMode.quiet => math.max(BarTokens.islandIdleWidth - padding, clock),
    };
    return content + padding;
  }

  Widget _content(BuildContext context) {
    if (_workspaceOwnsPill) return Center(child: widget.workspace!);
    // An expanded pill with nothing to report (playback stopped, notice
    // dismissed) falls back to the resting content rather than an empty row.
    if (widget.mode.isQuiet) return _idle(context);
    return switch (widget.mode) {
      IslandMode.media => _media(context),
      IslandMode.notice => _notice(context),
      IslandMode.charging => _charge(context),
      IslandMode.quiet => _idle(context),
    };
  }

  /// darkshadow's idle row: the date at 13 Medium, then the time in a pill of
  /// the key colour, with the cover and the wave while something plays.
  Widget _idle(BuildContext context) {
    const ink = Color(0xffffffff);
    final theme = context.shellTheme;
    final time = Text(
      widget.timeText,
      maxLines: 1,
      style: BarType.islandLabel.copyWith(
        color: theme.colors.textPrimary,
        fontWeight: FontWeight.w600,
        fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
      ),
    );
    if (!widget.showClock) {
      return Center(
        child: Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(
            color: ink.withValues(alpha: 0.42),
            shape: BoxShape.circle,
          ),
        ),
      );
    }
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (widget.dateText.isNotEmpty) ...<Widget>[
            Text(
              widget.dateText,
              maxLines: 1,
              style: BarType.caption.copyWith(
                color: ink,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 9),
          ],
          Container(
            height: _timePillHeight,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.accent,
              borderRadius: BorderRadius.circular(_timePillHeight / 2),
            ),
            child: time,
          ),
        ],
      ),
    );
  }

  /// S27's compact Now Playing: a 20 pt cover at the 24% radius every island
  /// element uses, then the waveform, 133 wide in all.
  Widget _media(BuildContext context) {
    final theme = context.shellTheme;
    final cover = BarTokens.islandCompactCover;
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          MediaArtwork(
            url: widget.artworkUrl,
            size: cover,
            radius: cover * 0.24,
            fallback: Container(
              width: cover,
              height: cover,
              decoration: BoxDecoration(
                color: const Color(0xff1c1c1e),
                borderRadius: BorderRadius.circular(cover * 0.24),
              ),
              child: const Center(
                child: Icon(
                  BarIcons.playFill,
                  size: 10,
                  color: Color(0xffa0a0a8),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          _Equalizer(colour: theme.accent),
          if (widget.expanded) ...<Widget>[
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                widget.mediaTitle.replaceAll(RegExp(r'\s*\n\s*'), ' '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: BarType.islandLabel.copyWith(
                  color: const Color(0xffffffff),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _notice(BuildContext context) {
    const ink = Color(0xffffffff);
    return Row(
      children: <Widget>[
        const _StatusDot(colour: Color(0xffff453a), isNotice: true),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            widget.noticeSummary.replaceAll(RegExp(r'\s*\n\s*'), ' '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: BarType.islandLabel.copyWith(color: ink),
          ),
        ),
        if (widget.onNoticeClose != null) _CloseDot(onTap: widget.onNoticeClose!),
      ],
    );
  }

  /// darkshadow's charge face, cut to the strip: the bolt, the percentage and
  /// a fill that runs up to the level.
  Widget _charge(BuildContext context) {
    const ink = Color(0xffffffff);
    final percent = (widget.chargePercent ?? 0).clamp(0, 100);
    return Row(
      children: <Widget>[
        const Icon(BarIcons.boltFill, size: 13, color: Color(0xff9be08f)),
        const SizedBox(width: 7),
        Text(
          '$percent%',
          style: BarType.islandLabel.copyWith(
            color: ink,
            fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: SizedBox(
              height: 4,
              child: Stack(
                children: <Widget>[
                  Positioned.fill(
                    child: ColoredBox(
                      color: ink.withValues(alpha: 0.22),
                    ),
                  ),
                  FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: percent / 100,
                    child: const ColoredBox(color: Color(0xff9be08f)),
                  ),
                ],
              ),
            ),
          ),
        ),
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
  const _Equalizer({required this.colour, this.height = 12, this.bars = 3});

  final Color colour;
  final double height;
  final int bars;

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
    final bars = widget.bars;
    return SizedBox(
      width: bars * 4,
      height: widget.height,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              for (var index = 0; index < bars; index++)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1),
                  child: Container(
                    width: 2,
                    height:
                        widget.height *
                        (0.42 +
                            0.58 *
                                (0.5 +
                                    0.5 *
                                        math.sin(
                                          _controller.value * math.pi * 2 +
                                              index * 1.1,
                                        ))),
                    decoration: BoxDecoration(
                      color: widget.colour,
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
/// macOS 27 measures 32 continuous corners on all four sides and 16 pt of
/// padding [S27]; meniscus caps the card at 560 × 132 and puts its player
/// cover at 44 [S36]. The media card takes darkshadow's 470 × 184 (its type
/// and transport are the ones transcribed below) and the banner takes
/// meniscus's 360, so neither face is drawn at a width it was never measured
/// at.
class IslandExpandedBody extends StatelessWidget {
  const IslandExpandedBody({
    required this.mode,
    required this.notification,
    required this.playback,
    required this.artworkUrl,
    required this.onDismissNotice,
    required this.onActivateNotice,
    required this.commands,
    this.chargePercent,
    super.key,
  });

  final IslandMode mode;
  final DesktopNotification? notification;
  final MprisPlaybackState? playback;
  final String artworkUrl;
  final VoidCallback onDismissNotice;
  final VoidCallback onActivateNotice;
  final MediaCommands commands;

  /// Battery percentage for the charge face.
  final int? chargePercent;

  /// The card's outer width for [mode], padding included; the popup opens at
  /// exactly this width. Each number is the width its reference face was
  /// measured at, so the content inside lands where the reference puts it.
  static double widthFor(IslandMode mode) => switch (mode) {
    IslandMode.notice => BarTokens.islandBannerWidth,
    IslandMode.charging => BarTokens.islandChargeWidth,
    _ => BarTokens.islandMediaWidth,
  };

  /// meniscus's banner spends 8 pt a side; the player and the charge face
  /// spend the island's measured 16 [S27][S36].
  static double _insetFor(IslandMode mode) => mode == IslandMode.notice
      ? BarTokens.islandBannerInset
      : BarTokens.islandPopupPadding;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widthFor(mode),
      child: Padding(
        padding: EdgeInsets.all(_insetFor(mode)),
        child: switch (mode) {
          IslandMode.notice => _NoticeView(
            notification: notification,
            onDismiss: onDismissNotice,
            onActivate: onActivateNotice,
          ),
          IslandMode.charging => _ChargeView(percent: chargePercent ?? 0),
          _ => _MediaView(
            playback: playback,
            artworkUrl: artworkUrl,
            commands: commands,
          ),
        },
      ),
    );
  }
}

/// meniscus's banner: a 30 pt tile, the app at 13 over the summary at 14
/// semibold and the body at 11, an 8 pt inset and a 10 pt gap [S36].
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
    const tile = BarTokens.islandBannerTile;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onActivate,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: tile,
            height: tile,
            decoration: BoxDecoration(
              color: const Color(0xff1c1c1e),
              borderRadius: BorderRadius.circular(tile * 0.24),
            ),
            child: const Center(
              child: Icon(
                BarIcons.bellFill,
                size: 15,
                color: Color(0xffa0a0a8),
              ),
            ),
          ),
          const SizedBox(width: BarTokens.islandBannerGap),
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
                const SizedBox(height: 1),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: BarType.islandTitle.copyWith(
                    color: const Color(0xffffffff),
                  ),
                ),
                if (body.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 1),
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

/// darkshadow's player: the 44 pt cover at `x: 16, y: 16`, the identity at 10
/// bold with 1.2 letter spacing, the title at 17 semibold, the artist at 13,
/// the wave at `y: 105`, and the transport row at `y: 134` with 22 pt gaps and
/// a 40 pt play button.
class _MediaView extends StatefulWidget {
  const _MediaView({
    required this.playback,
    required this.artworkUrl,
    required this.commands,
  });

  final MprisPlaybackState? playback;
  final String artworkUrl;
  final MediaCommands commands;

  @override
  State<_MediaView> createState() => _MediaViewState();
}

class _MediaViewState extends State<_MediaView> {
  /// The elapsed time redraws once a second; MPRIS reports a position only
  /// when it changes.
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  String _clock(Duration value) {
    final total = value.inSeconds.clamp(0, 359999);
    return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final state = widget.playback;
    final playing = state?.playing ?? false;
    final length = state?.length ?? Duration.zero;
    final position = state?.positionAt(DateTime.now()) ?? Duration.zero;
    final progress = length <= Duration.zero
        ? 0.0
        : (position.inMilliseconds / length.inMilliseconds).clamp(0.0, 1.0);
    final title = state?.title.isNotEmpty == true
        ? state!.title
        : 'Nothing Playing';
    final artist = state == null || state.artists.isEmpty
        ? (state?.album ?? '')
        : state.artists.join(', ');
    final identity = (state?.identity ?? '').toUpperCase();
    const muted = Color(0xffa0a0a8);
    final timeStyle = BarType.islandCaption.copyWith(
      color: muted,
      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            MediaArtwork(
              url: widget.artworkUrl,
              size: BarTokens.islandPlayerCover,
              radius: BarTokens.islandPlayerCover * 0.24,
              fallback: Container(
                width: BarTokens.islandPlayerCover,
                height: BarTokens.islandPlayerCover,
                decoration: BoxDecoration(
                  color: const Color(0xff1c1c1e),
                  borderRadius: BorderRadius.circular(
                    BarTokens.islandPlayerCover * 0.24,
                  ),
                ),
                child: const Center(
                  child: Icon(BarIcons.playFill, size: 18, color: muted),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (identity.isNotEmpty)
                    Text(
                      identity,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: BarType.caption.copyWith(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                        color: theme.accent,
                      ),
                    ),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: BarType.islandTitle.copyWith(
                      fontSize: 17,
                      color: const Color(0xffffffff),
                    ),
                  ),
                  Text(
                    artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: BarType.islandCaption.copyWith(
                      fontSize: 13,
                      color: muted,
                    ),
                  ),
                ],
              ),
            ),
            if (playing) ...<Widget>[
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: _Equalizer(
                  colour: theme.accent,
                  height: 22,
                  bars: 5,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            SizedBox(
              width: 38,
              child: Text(_clock(position), style: timeStyle),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: SizedBox(
                  height: 4,
                  child: Stack(
                    children: <Widget>[
                      Positioned.fill(
                        child: ColoredBox(
                          color: const Color(0xffffffff).withValues(alpha: 0.18),
                        ),
                      ),
                      FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: progress,
                        child: ColoredBox(color: theme.accent),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SizedBox(
              width: 38,
              child: Text(
                length > Duration.zero ? '-${_clock(length - position)}' : '',
                textAlign: TextAlign.right,
                style: timeStyle,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            _TransportButton(
              icon: BarIcons.backward,
              onTap: widget.commands.previous,
              size: 18,
            ),
            const SizedBox(width: 22),
            _PlayButton(
              playing: playing,
              accent: theme.accent,
              onTap: widget.commands.playPause,
            ),
            const SizedBox(width: 22),
            _TransportButton(
              icon: BarIcons.forward,
              onTap: widget.commands.next,
              size: 18,
            ),
          ],
        ),
      ],
    );
  }
}

/// The charge face in the expanded card: the bolt over the percentage and a
/// bar that fills to the level.
class _ChargeView extends StatelessWidget {
  const _ChargeView({required this.percent});

  final int percent;

  @override
  Widget build(BuildContext context) {
    const green = Color(0xff9be08f);
    final level = percent.clamp(0, 100);
    return Row(
      children: <Widget>[
        const Icon(BarIcons.boltFill, size: 30, color: green),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '$level%',
                style: BarType.islandTitle.copyWith(
                  fontSize: 20,
                  color: const Color(0xffffffff),
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: SizedBox(
                  height: 5,
                  child: Stack(
                    children: <Widget>[
                      Positioned.fill(
                        child: ColoredBox(
                          color: const Color(0xffffffff).withValues(alpha: 0.18),
                        ),
                      ),
                      FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: level / 100,
                        child: const ColoredBox(color: green),
                      ),
                    ],
                  ),
                ),
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

/// darkshadow's play button: 40 pt, the accent while playing and a circle
/// while it waits, squeezed to 0.86 on press.
class _PlayButton extends StatefulWidget {
  const _PlayButton({
    required this.playing,
    required this.accent,
    required this.onTap,
  });

  final bool playing;
  final Color accent;
  final VoidCallback onTap;

  @override
  State<_PlayButton> createState() => _PlayButtonState();
}

class _PlayButtonState extends State<_PlayButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutBack,
          scale: _pressed ? 0.86 : 1,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: widget.accent,
              shape: BoxShape.circle,
            ),
            child: Icon(
              widget.playing ? BarIcons.pauseFill : BarIcons.playFill,
              size: 20,
              color: const Color(0xffffffff),
            ),
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
