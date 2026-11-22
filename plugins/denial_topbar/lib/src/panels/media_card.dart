import 'dart:async';

import 'package:denial_flutter_sdk/effects.dart';
import 'package:denial_flutter_sdk/models.dart';
import 'package:denial_flutter_sdk/services.dart';
import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bar_icons.dart';
import '../bar_tokens.dart';
import '../bar_type.dart';
import '../media_art.dart';

/// Now Playing, sized to NextKDE `ControlCenterPanel.qml`'s media card
/// (127 high, radius 25) with revo-shell's transport row inside it.
class MediaCard extends ConsumerWidget {
  const MediaCard({required this.services, super.key});

  final ShellServices services;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.shellTheme;
    final playback = ref.watch(services.media).value;
    final commands = ref.watch(services.mediaCommands);
    final shape = BorderRadius.circular(25);
    final title = playback?.title.isNotEmpty == true
        ? playback!.title
        : 'Nothing Playing';
    final artist = playback == null || playback.artists.isEmpty
        ? (playback?.identity ?? '')
        : playback.artists.join(', ');
    final playing = playback?.status == MprisPlaybackStatus.playing;

    return ShellBackdropBlur(
      borderRadius: shape,
      blendMode: BlendMode.srcOver,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colors.surfaceContainer.withValues(alpha: 0.62),
          borderRadius: shape,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
          child: Row(
            children: <Widget>[
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  color: theme.colors.textPrimary.withValues(alpha: 0.08),
                  borderRadius: theme.borderRadius(12),
                ),
                child: BarGlyph(
                  BarIcons.playFill,
                  size: 24,
                  color: theme.colors.textSecondary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: BarType.title.copyWith(
                        color: theme.colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: BarType.caption.copyWith(
                        color: theme.colors.textSecondary,
                      ),
                    ),
                    const Spacer(),
                    Row(
                      children: <Widget>[
                        _Transport(
                          icon: BarIcons.backward,
                          enabled: playback?.canGoPrevious ?? false,
                          onTap: commands.previous,
                        ),
                        const SizedBox(width: 16),
                        _Transport(
                          icon: playing
                              ? BarIcons.pauseFill
                              : BarIcons.playFill,
                          enabled: playback?.available ?? false,
                          onTap: commands.playPause,
                          size: 20,
                        ),
                        const SizedBox(width: 16),
                        _Transport(
                          icon: BarIcons.forward,
                          enabled: playback?.canGoNext ?? false,
                          onTap: commands.next,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Transport extends StatelessWidget {
  const _Transport({
    required this.icon,
    required this.enabled,
    required this.onTap,
    this.size = 15,
  });

  final IconData icon;
  final bool enabled;
  final Future<void> Function() onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      child: GestureDetector(
        onTap: enabled ? () => onTap() : null,
        child: BarGlyph(
          icon,
          size: size,
          color: enabled
              ? theme.colors.textPrimary
              : theme.colors.textTertiary.withValues(alpha: 0.45),
        ),
      ),
    );
  }
}

/// The full-height media panel a bar click opens, mirroring NextKDE's
/// standalone media page rather than the card.
class MediaPanel extends ConsumerWidget {
  const MediaPanel({required this.services, super.key});

  final ShellServices services;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.all(BarTokens.panelPadding),
      child: SizedBox(
        width: BarTokens.panelMaxWidth - BarTokens.panelPadding * 2,
        height: 127,
        child: MediaCard(services: services),
      ),
    );
  }
}

/// The Now Playing card Control Centre's media tile opens.
///
/// Follows the measured shape in the research doc's §12 (meniscus): a 44 pt
/// cover, the title at 13 semibold over the artist at 12, a 4 pt progress bar
/// with 10 pt monospaced-digit timecodes, and a 15 / 22 / 15 transport row.
class NowPlayingPanel extends ConsumerStatefulWidget {
  const NowPlayingPanel({required this.services, super.key});

  final ShellServices services;

  @override
  ConsumerState<NowPlayingPanel> createState() => _NowPlayingPanelState();
}

class _NowPlayingPanelState extends ConsumerState<NowPlayingPanel> {
  /// The elapsed time redraws once a second while a track plays; MPRIS only
  /// reports a position when it changes, so the clock fills the gaps.
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
    final minutes = total ~/ 60;
    final seconds = total % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final services = widget.services;
    final playback = ref.watch(services.media).value;
    final commands = ref.watch(services.mediaCommands);
    final playing = playback?.playing ?? false;
    final length = playback?.length ?? Duration.zero;
    final position = playback?.positionAt(DateTime.now()) ?? Duration.zero;
    final progress = length <= Duration.zero
        ? 0.0
        : (position.inMilliseconds / length.inMilliseconds).clamp(0.0, 1.0);
    final title = playback?.title.isNotEmpty == true
        ? playback!.title
        : 'Nothing Playing';
    final artist = playback == null || playback.artists.isEmpty
        ? (playback?.album ?? '')
        : playback.artists.join(', ');
    final timeStyle = BarType.caption.copyWith(
      fontSize: 10,
      color: theme.colors.textSecondary,
      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
    );

    return SizedBox(
      width: BarTokens.panelMaxWidth - BarTokens.panelPadding * 2,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              MediaArtwork(
                url: playback?.artUrl ?? '',
                size: 44,
                radius: 8,
                fallback: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: theme.colors.textPrimary.withValues(alpha: 0.08),
                    borderRadius: theme.borderRadius(8),
                  ),
                  child: BarGlyph(
                    BarIcons.playFill,
                    size: 18,
                    color: theme.colors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: BarType.menuRow.copyWith(
                        fontWeight: FontWeight.w600,
                        color: playback == null
                            ? theme.colors.textSecondary
                            : theme.colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: BarType.shortcut.copyWith(
                        color: theme.colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: SizedBox(
              height: 4,
              child: Stack(
                children: <Widget>[
                  Positioned.fill(
                    child: ColoredBox(
                      color: theme.colors.textPrimary.withValues(alpha: 0.14),
                    ),
                  ),
                  FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: progress,
                    child: ColoredBox(color: theme.colors.textPrimary),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 3),
          Row(
            children: <Widget>[
              Text(_clock(position), style: timeStyle),
              const Spacer(),
              Text(_clock(length), style: timeStyle),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              _Transport(
                icon: BarIcons.backward,
                enabled: playback?.canGoPrevious ?? false,
                onTap: commands.previous,
                size: 15,
              ),
              const SizedBox(width: 22),
              _Transport(
                icon: playing ? BarIcons.pauseFill : BarIcons.playFill,
                enabled: playback?.available ?? false,
                onTap: commands.playPause,
                size: 22,
              ),
              const SizedBox(width: 22),
              _Transport(
                icon: BarIcons.forward,
                enabled: playback?.canGoNext ?? false,
                onTap: commands.next,
                size: 15,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
