import 'dart:async';
import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:denial_flutter_sdk/models.dart' show MprisPlaybackState;
import 'package:flutter/foundation.dart';

import 'island_lyrics.dart';
import 'island_subline.dart';

/// Lyrics for the track playing, from what is already on this machine: the
/// text a player publishes with the track, or an `.lrc` file of the same
/// name beside a local one. Nothing is fetched from anywhere.
class IslandLyricSource implements IslandSubline {
  static const int _largest = 512 * 1024;

  final ValueNotifier<String?> _line = ValueNotifier<String?>(null);
  DBusClient? _client;
  Timer? _tick;
  MprisPlaybackState? _playback;
  List<LyricLine> _lines = const <LyricLine>[];
  String _track = '';
  int _asked = 0;

  @override
  ValueListenable<String?> get line => _line;

  /// Follows [playback]. Safe to call while building: the line only ever
  /// changes from a timer or once a read comes back.
  void follow(MprisPlaybackState? playback) {
    _playback = playback;
    final track = playback == null || !playback.available
        ? ''
        : '${playback.serviceName}\n${playback.title}\n${playback.album}\n'
              '${playback.length.inMilliseconds}';
    if (track != _track) {
      _track = track;
      _lines = const <LyricLine>[];
      final asked = ++_asked;
      scheduleMicrotask(() {
        if (asked != _asked) return;
        _line.value = null;
        if (track.isNotEmpty) unawaited(_load(playback!.serviceName, asked));
      });
    }
    final runs = _lines.isNotEmpty && (playback?.playing ?? false);
    if (runs && _tick == null) {
      _tick = Timer.periodic(const Duration(milliseconds: 250), (_) => _show());
    } else if (!runs) {
      _tick?.cancel();
      _tick = null;
    }
  }

  void _show() {
    final playback = _playback;
    _line.value = playback == null || _lines.isEmpty
        ? null
        : lyricAt(_lines, playback.positionAt(DateTime.now()));
  }

  Future<void> _load(String service, int asked) async {
    var lines = const <LyricLine>[];
    try {
      final client = _client ??= DBusClient.session();
      final found = await DBusRemoteObject(
        client,
        name: service,
        path: DBusObjectPath('/org/mpris/MediaPlayer2'),
      )
          .getProperty('org.mpris.MediaPlayer2.Player', 'Metadata')
          .timeout(const Duration(seconds: 3));
      String text(String name) {
        if (found is! DBusDict) return '';
        var value = found.children[DBusString(name)];
        while (value is DBusVariant) {
          value = value.value;
        }
        return value is DBusString ? value.value : '';
      }

      lines = parseLrc(text('xesam:asText'));
      final path = lines.isEmpty ? lrcBeside(text('xesam:url')) : null;
      if (path != null) {
        final file = File(path);
        if (await file.exists() && await file.length() <= _largest) {
          lines = parseLrc(await file.readAsString());
        }
      }
    } on Object {
      // A player that does not answer, or a file that will not read, is a
      // track without lyrics.
    }
    if (asked != _asked) return;
    _lines = lines;
    follow(_playback);
    _show();
  }

  void dispose() {
    _asked++;
    _tick?.cancel();
    _tick = null;
    unawaited(_client?.close());
    _client = null;
    _line.dispose();
  }
}
