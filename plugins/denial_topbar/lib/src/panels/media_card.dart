import 'package:denial_flutter_sdk/effects.dart';
import 'package:denial_flutter_sdk/models.dart';
import 'package:denial_flutter_sdk/services.dart';
import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bar_icons.dart';
import '../bar_tokens.dart';
import '../bar_type.dart';

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
