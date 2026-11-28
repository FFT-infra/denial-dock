import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:denial_flutter_sdk/models.dart' show MprisPlaybackState;
import 'package:flutter/foundation.dart';

import 'island_lyrics.dart';
import 'island_subline.dart';

class _ListenerAwareNotifier<T> extends ValueNotifier<T> {
  _ListenerAwareNotifier(super.value, this._onListenersChanged);

  final VoidCallback _onListenersChanged;
  int _count = 0;

  bool get observed => _count > 0;

  @override
  void addListener(VoidCallback listener) {
    _count++;
    super.addListener(listener);
    _onListenersChanged();
  }

  @override
  void removeListener(VoidCallback listener) {
    if (_count > 0) _count--;
    super.removeListener(listener);
    _onListenersChanged();
  }
}

/// Lyrics for the track playing:
/// 1. MPRIS `xesam:asText`
/// 2. Sibling local `.lrc` beside `xesam:url`
/// 3. Cached online lookup via LRCLIB (short timeout, silent offline fallback)
///
/// The 250 ms position timer runs strictly while at least one widget is
/// subscribed to [line] AND playback is active — zero wakeups while collapsed.
class IslandLyricSource implements IslandSubline {
  static const int _largest = 512 * 1024;
  static const int _maxCacheEntries = 48;
  static final Map<String, List<LyricLine>> _onlineCache =
      <String, List<LyricLine>>{};

  late final _ListenerAwareNotifier<String?> _line =
      _ListenerAwareNotifier<String?>(null, _syncTick);
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
        if (track.isNotEmpty) unawaited(_load(playback!, asked));
      });
    }
    _syncTick();
  }

  void _syncTick() {
    final runs =
        _line.observed &&
        _lines.isNotEmpty &&
        (_playback?.playing ?? false);
    if (runs && _tick == null) {
      _show();
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

  Future<void> _load(MprisPlaybackState playback, int asked) async {
    var lines = const <LyricLine>[];
    final artist = playback.artistLabel;
    final title = playback.title;
    final album = playback.album;
    try {
      final client = _client ??= DBusClient.session();
      final found = await DBusRemoteObject(
        client,
        name: playback.serviceName,
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
      // A player that does not answer, or a file that will not read, falls
      // through to online lookup below.
    }
    if (asked != _asked) return;
    if (lines.isEmpty && title.trim().isNotEmpty) {
      lines = await _fetchLrcLib(
        title: title.trim(),
        artist: artist.trim(),
        album: album.trim(),
        durationSeconds: playback.length.inSeconds,
      );
    }
    if (asked != _asked) return;
    _lines = lines;
    _syncTick();
    if (_line.observed) _show();
  }

  static Future<List<LyricLine>> _fetchLrcLib({
    required String title,
    required String artist,
    required String album,
    required int durationSeconds,
  }) async {
    final key = '${artist.toLowerCase()}|${title.toLowerCase()}|$durationSeconds';
    final cached = _onlineCache[key];
    if (cached != null) return cached;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    try {
      final params = <String, String>{
        'track_name': title,
        if (artist.isNotEmpty) 'artist_name': artist,
        if (album.isNotEmpty) 'album_name': album,
        if (durationSeconds > 0) 'duration': '$durationSeconds',
      };
      final uri = Uri.https('lrclib.net', '/api/get', params);
      final req = await client.getUrl(uri).timeout(const Duration(seconds: 3));
      req.headers.set('User-Agent', 'denial-topbar/0.0.0');
      final res = await req.close().timeout(const Duration(seconds: 3));
      if (res.statusCode != 200) {
        _rememberCache(key, const <LyricLine>[]);
        return const <LyricLine>[];
      }
      final body = await res.transform(utf8.decoder).join();
      final decoded = jsonDecode(body);
      if (decoded is! Map) return const <LyricLine>[];
      final synced = decoded['syncedLyrics'];
      final parsed = synced is String ? parseLrc(synced) : const <LyricLine>[];
      _rememberCache(key, parsed);
      return parsed;
    } catch (_) {
      return const <LyricLine>[];
    } finally {
      client.close(force: true);
    }
  }

  static void _rememberCache(String key, List<LyricLine> lines) {
    if (_onlineCache.length >= _maxCacheEntries) {
      _onlineCache.remove(_onlineCache.keys.first);
    }
    _onlineCache[key] = lines;
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
