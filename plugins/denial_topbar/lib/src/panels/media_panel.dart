import 'dart:async';
import 'dart:typed_data';

import 'package:denial_flutter_sdk/models.dart';
import 'package:denial_flutter_sdk/services.dart';
import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class TopBarMediaPanel extends ConsumerStatefulWidget {
  const TopBarMediaPanel({required this.services, super.key});

  final ShellServices services;

  @override
  ConsumerState<TopBarMediaPanel> createState() => _TopBarMediaPanelState();
}

class _TopBarMediaPanelState extends ConsumerState<TopBarMediaPanel> {
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

  @override
  Widget build(BuildContext context) {
    final playback = ref.watch(widget.services.media).value;
    final theme = context.shellTheme;
    if (playback == null || !playback.available) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Text(
          'Nothing playing',
          style: theme.text.systemBarValue.copyWith(
            color: theme.colors.textSecondary,
          ),
        ),
      );
    }
    final commands = ref.read(widget.services.mediaCommands);
    final position = playback.positionAt(DateTime.now());
    final fractions = playback.length > Duration.zero
        ? (position.inMilliseconds / playback.length.inMilliseconds).clamp(
            0.0,
            1.0,
          )
        : 0.0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _Artwork(playback: playback, services: widget.services, size: 58),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      playback.title.isEmpty
                          ? playback.identity
                          : playback.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.text.cardTitle.copyWith(
                        color: theme.colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      playback.artistLabel.isEmpty
                          ? playback.album
                          : playback.artistLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.text.systemBarCaption.copyWith(
                        color: theme.colors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      playback.identity,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.text.systemBarCaption.copyWith(
                        color: theme.colors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: fractions,
              minHeight: 3,
              backgroundColor: theme.colors.textPrimary.withValues(alpha: 0.12),
              valueColor: AlwaysStoppedAnimation<Color>(theme.accent),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: <Widget>[
              Text(
                _formatTime(position),
                style: theme.text.systemBarCaption.copyWith(
                  color: theme.colors.textTertiary,
                ),
              ),
              const Spacer(),
              Text(
                _formatTime(playback.length),
                style: theme.text.systemBarCaption.copyWith(
                  color: theme.colors.textTertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              _Control(
                icon: Icons.skip_previous,
                enabled: playback.canGoPrevious,
                onTap: commands.previous,
              ),
              const SizedBox(width: 12),
              _Control(
                icon: playback.playing ? Icons.pause : Icons.play_arrow,
                enabled: playback.playing
                    ? playback.canPause
                    : playback.canPlay,
                onTap: commands.playPause,
                primary: true,
              ),
              const SizedBox(width: 12),
              _Control(
                icon: Icons.skip_next,
                enabled: playback.canGoNext,
                onTap: commands.next,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Control extends StatelessWidget {
  const _Control({
    required this.icon,
    required this.enabled,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final bool enabled;
  final Future<void> Function() onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final size = primary ? 38.0 : 32.0;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      child: GestureDetector(
        onTap: enabled ? () => unawaited(onTap()) : null,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: primary
                ? theme.accent.withValues(alpha: 0.16)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(size / 2),
          ),
          child: Icon(
            icon,
            size: primary ? 21 : 18,
            color: enabled
                ? theme.colors.textPrimary
                : theme.colors.textTertiary.withValues(alpha: 0.5),
          ),
        ),
      ),
    );
  }
}

class _Artwork extends ConsumerWidget {
  const _Artwork({
    required this.playback,
    required this.services,
    required this.size,
  });

  final MprisPlaybackState playback;
  final ShellServices services;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.shellTheme;
    final uri = Uri.tryParse(playback.artUrl);
    Widget art = _fallback(context);
    if (uri?.scheme == 'file') {
      String? path;
      try {
        path = uri!.toFilePath();
      } on UnsupportedError {
        path = null;
      }
      if (path != null) {
        final Uint8List? bytes = ref.watch(services.imageBytes(path)).value;
        if (bytes != null) {
          art = Image.memory(
            bytes,
            fit: BoxFit.cover,
            cacheWidth: 240,
            cacheHeight: 240,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => _fallback(context),
          );
        }
      }
    } else if (uri?.scheme == 'http' || uri?.scheme == 'https') {
      art = Image.network(
        playback.artUrl,
        fit: BoxFit.cover,
        cacheWidth: 240,
        cacheHeight: 240,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => _fallback(context),
      );
    }
    return SizedBox.square(
      dimension: size,
      child: ClipRRect(borderRadius: theme.borderRadius(12), child: art),
    );
  }

  Widget _fallback(BuildContext context) {
    final theme = context.shellTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            theme.accent.withValues(alpha: 0.55),
            theme.colors.surfaceContainerHighest,
          ],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.music_note_rounded,
          size: 26,
          color: theme.colors.textPrimary,
        ),
      ),
    );
  }
}

String _formatTime(Duration value) {
  final seconds = value.inSeconds.clamp(0, 86400);
  final minutes = seconds ~/ 60;
  final rest = seconds % 60;
  return '$minutes:${rest.toString().padLeft(2, '0')}';
}
