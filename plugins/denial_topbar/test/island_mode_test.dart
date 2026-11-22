import 'dart:io';

import 'package:denial_topbar/src/island_mode.dart';

void main() {
  // revo-shell's priority: a fresh notification wins over playback, playback
  // wins over nothing.
  _expect(
    resolveIslandMode(
          mediaEnabled: true,
          mediaPlaying: true,
          notificationsEnabled: true,
          hasNotice: true,
        ) ==
        IslandMode.notice,
    'notice beats media',
  );
  _expect(
    resolveIslandMode(
          mediaEnabled: true,
          mediaPlaying: true,
          notificationsEnabled: true,
          hasNotice: false,
        ) ==
        IslandMode.media,
    'media when no notice',
  );
  _expect(
    resolveIslandMode(
          mediaEnabled: true,
          mediaPlaying: false,
          notificationsEnabled: true,
          hasNotice: false,
        ) ==
        IslandMode.quiet,
    'paused playback is quiet',
  );

  // Turning a source off in settings must silence it even when it is active.
  _expect(
    resolveIslandMode(
          mediaEnabled: false,
          mediaPlaying: true,
          notificationsEnabled: true,
          hasNotice: false,
        ) ==
        IslandMode.quiet,
    'disabled media stays quiet',
  );
  _expect(
    resolveIslandMode(
          mediaEnabled: true,
          mediaPlaying: true,
          notificationsEnabled: false,
          hasNotice: true,
        ) ==
        IslandMode.media,
    'disabled notices fall through to media',
  );
  _expect(
    resolveIslandMode(
          mediaEnabled: false,
          mediaPlaying: false,
          notificationsEnabled: false,
          hasNotice: true,
        ) ==
        IslandMode.quiet,
    'everything disabled is quiet',
  );

  _expect(IslandMode.quiet.isQuiet, 'quiet reports itself');
  _expect(!IslandMode.media.isQuiet, 'media is not quiet');
  _expect(!IslandMode.notice.isQuiet, 'notice is not quiet');
  _expect(!IslandMode.charging.isQuiet, 'charging is not quiet');

  // The charge flash is what macOS shows on every plug with no switch to turn
  // it off [S28], so it takes the pill from playback for its few seconds but
  // never from a fresh notification.
  _expect(
    resolveIslandMode(
          mediaEnabled: true,
          mediaPlaying: true,
          notificationsEnabled: true,
          hasNotice: false,
          charging: true,
        ) ==
        IslandMode.charging,
    'charging beats media',
  );
  _expect(
    resolveIslandMode(
          mediaEnabled: true,
          mediaPlaying: true,
          notificationsEnabled: true,
          hasNotice: true,
          charging: true,
        ) ==
        IslandMode.notice,
    'notice beats charging',
  );
  _expect(
    resolveIslandMode(
          mediaEnabled: true,
          mediaPlaying: false,
          notificationsEnabled: true,
          hasNotice: false,
          charging: false,
        ) ==
        IslandMode.quiet,
    'no charge flash without a change',
  );

  stdout.writeln('All island mode tests passed.');
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
