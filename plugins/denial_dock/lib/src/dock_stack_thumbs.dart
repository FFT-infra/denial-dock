import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// A thumbnail found for a file: where the image is and what version of the
/// file it shows.
class DockThumbnail {
  const DockThumbnail(this.path, {required this.knownVersion});

  final String path;

  /// The mtime the thumbnail was made from, when the file that carries it
  /// records one. A freedesktop thumbnail does.
  final DateTime? knownVersion;
}

/// Thumbnails for the files in a folder stack.
///
/// Reads the freedesktop cache the file manager and the thumbnailers fill,
/// matching entries by the `Thumb::URI` text chunk rather than by hashing a
/// path: the hash is MD5 over the file URI, and reading the chunk needs no
/// dependency. A video without a cached thumbnail is made one with `ffmpeg`,
/// which the reference docks also rely on.
abstract final class DockStackThumbs {
  static const List<String> _sizes = ['x-large', 'large', 'xx-large', 'normal'];

  /// Extensions handed to ffmpeg. Images are left alone: the shell draws them
  /// itself, and a decoded copy would only cost memory.
  static const Set<String> _videoExtensions = {
    'mp4',
    'mov',
    'm4v',
    'webm',
    'mkv',
    'avi',
    'ogv',
    'mpg',
    'mpeg',
  };

  /// Extensions the shell can decode itself, so the file is its own preview.
  static const Set<String> _imageExtensions = {
    'png',
    'jpg',
    'jpeg',
    'gif',
    'webp',
    'bmp',
  };

  static _ThumbIndex? _index;
  static DateTime? _indexedAt;
  static Future<void>? _warming;

  /// The image to draw for [file]: a cached thumbnail, else the file itself
  /// when it is an image, else null.
  ///
  /// Reads the index only, and starts building it in the background on a miss:
  /// the first scan opens every PNG in the cache, which is not work to do
  /// while the fan is opening.
  static String? preview(String file) {
    final cached = _peek(file);
    if (cached != null) return cached;
    final extension = _extension(file);
    if (_imageExtensions.contains(extension)) return file;
    if (_videoExtensions.contains(extension)) warm();
    return null;
  }

  /// Whether [warm] would have to scan, so a caller can skip a pointless
  /// rebuild when the index is already there.
  static bool get stale {
    final cached = _index;
    return cached == null ||
        _indexedAt == null ||
        DateTime.now().difference(_indexedAt!).inSeconds.abs() >= 30;
  }

  /// Builds the thumbnail index now, and resolves once it is there.
  ///
  /// The dock calls this when it mounts, so the index is usually ready long
  /// before a folder is opened; an open fan calls it again to redraw once the
  /// thumbnails it could not find the first time are known.
  static Future<void> warm() {
    if (!stale) return Future.value();
    return _warming ??= Future(() {
      _loadIndex();
      _warming = null;
    });
  }

  /// The cached thumbnail for [file], answered from the index alone.
  static String? _peek(String file) {
    final index = _index;
    if (index == null) {
      warm();
      return null;
    }
    final stat = _stat(file);
    if (stat == null) return null;
    final path = index.entries[Uri.file(file).toString()];
    if (path == null) return null;
    final version = _stamp(path);
    // A thumbnail older than the file shows the wrong version of it.
    if (version != null && version.isBefore(stat.modified)) return null;
    return path;
  }

  /// The thumbnail for [file], or null when there is none and none can be
  /// made. Never blocks for long: a missing thumbnail is generated in the
  /// background and appears on the next open.
  static DockThumbnail? lookup(String file) {
    final cached = _cached(file);
    if (cached != null) return cached;
    final extension = _extension(file);
    if (!_videoExtensions.contains(extension)) return null;
    return _generated(file);
  }

  /// Drops the cached index, so the next lookup sees thumbnails written since.
  static void invalidate() {
    _index = null;
    _indexedAt = null;
  }

  static DockThumbnail? _cached(String file) {
    final stat = _stat(file);
    if (stat == null) return null;
    final index = _loadIndex();
    final uri = Uri.file(file).toString();
    final path = index[uri];
    if (path == null) return null;
    final version = _stamp(path);
    // A thumbnail older than the file shows the wrong version of it.
    if (version != null && version.isBefore(stat.modified)) return null;
    return DockThumbnail(path, knownVersion: version);
  }

  static Map<String, String> _loadIndex() {
    final now = DateTime.now();
    final cached = _index;
    if (cached != null &&
        _indexedAt != null &&
        now.difference(_indexedAt!).inSeconds.abs() < 30) {
      return cached.entries;
    }
    final entries = <String, String>{};
    final home = Platform.environment['HOME'];
    final roots = <String>[
      if (Platform.environment['XDG_CACHE_HOME'] case final String cache)
        '$cache/thumbnails'
      else if (home != null)
        '$home/.cache/thumbnails',
    ];
    for (final root in roots) {
      for (final size in _sizes) {
        final directory = Directory('$root/$size');
        final List<FileSystemEntity> files;
        try {
          files = directory.listSync(followLinks: false);
        } on FileSystemException {
          continue;
        }
        for (final entity in files) {
          if (entity is! File || !entity.path.endsWith('.png')) continue;
          final meta = _readPngMeta(entity.path);
          final uri = meta.uri;
          if (uri == null) continue;
          entries.putIfAbsent(uri, () => entity.path);
        }
      }
    }
    _index = _ThumbIndex(entries);
    _indexedAt = now;
    return entries;
  }

  /// `Thumb::URI` and `Thumb::MTime` from a freedesktop thumbnail.
  static ({String? uri, DateTime? version}) _readPngMeta(String path) {
    final meta = _readTextChunks(path);
    final mtime = int.tryParse(meta['Thumb::MTime'] ?? '');
    return (
      uri: meta['Thumb::URI'],
      version: mtime == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(mtime * 1000),
    );
  }

  static DateTime? _stamp(String path) => _readPngMeta(path).version;

  /// The `tEXt` chunks of a PNG, keyed by keyword. Stops at the first chunk
  /// that is not a header, so a thumbnail is not read past its metadata.
  static Map<String, String> _readTextChunks(String path) {
    final out = <String, String>{};
    RandomAccessFile? file;
    try {
      file = File(path).openSync();
      final signature = file.readSync(8);
      if (signature.length != 8) return out;
      while (true) {
        final header = file.readSync(8);
        if (header.length != 8) break;
        final length = ByteData.sublistView(header).getUint32(0);
        final type = String.fromCharCodes(header.sublist(4));
        if (type == 'tEXt') {
          final data = file.readSync(length);
          final zero = data.indexOf(0);
          if (zero > 0) {
            out[String.fromCharCodes(data.sublist(0, zero))] =
                String.fromCharCodes(data.sublist(zero + 1));
          }
          file.readSync(4);
          continue;
        }
        if (type != 'IHDR') break;
        file.setPositionSync(file.positionSync() + length + 4);
      }
    } on FileSystemException {
      return out;
    } finally {
      file?.closeSync();
    }
    return out;
  }

  static DockThumbnail? _generated(String file) {
    final cacheDir = _ownCacheDir();
    if (cacheDir == null) return null;
    final name = _stableName(file);
    final out = File('$cacheDir/$name.png');
    final stat = _stat(file);
    if (stat == null) return null;
    try {
      if (out.existsSync()) {
        final made = out.statSync().modified;
        if (!made.isBefore(stat.modified)) {
          return DockThumbnail(out.path, knownVersion: made);
        }
      }
    } on FileSystemException {
      return null;
    }
    // Generated off the caller's frame: a 4K video takes a moment, and the
    // dock must not stall for it. The row shows a plain file tile until the
    // next open picks the result up.
    Directory(cacheDir).createSync(recursive: true);
    unawaited(
      _runFfmpeg(file, out.path).then((ok) {
        if (!ok) return;
        try {
          out.setLastModifiedSync(stat.modified);
        } on FileSystemException {
          // A missing stamp only costs one regeneration.
        }
      }),
    );
    return null;
  }

  static Future<bool> _runFfmpeg(String input, String output) async {
    final temporary = '$output.tmp.png';
    try {
      final process = await Process.run('ffmpeg', [
        '-nostdin',
        '-loglevel',
        'error',
        '-y',
        '-ss',
        '0',
        '-i',
        input,
        '-frames:v',
        '1',
        '-vf',
        'scale=256:-1',
        temporary,
      ], runInShell: false);
      if (process.exitCode != 0) return false;
      final file = File(temporary);
      if (!file.existsSync() || file.lengthSync() == 0) return false;
      file.renameSync(output);
      return true;
    } on ProcessException {
      return false;
    } on FileSystemException {
      return false;
    }
  }

  static String? _ownCacheDir() {
    final home = Platform.environment['HOME'];
    if (home == null) return null;
    final cache = Platform.environment['XDG_CACHE_HOME'] ?? '$home/.cache';
    return '$cache/denial_dock/thumbnails';
  }

  /// A stable file name for [path]. A path hash keeps the name short and
  /// collision-free enough for a cache directory.
  static String _stableName(String path) {
    var hash = 0x811c9dc5;
    for (final unit in path.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  static String _extension(String path) {
    final name = path.split('/').last;
    final dot = name.lastIndexOf('.');
    return dot <= 0 || dot == name.length - 1
        ? ''
        : name.substring(dot + 1).toLowerCase();
  }

  static FileStat? _stat(String path) {
    try {
      return FileStat.statSync(path);
    } on FileSystemException {
      return null;
    }
  }
}

class _ThumbIndex {
  const _ThumbIndex(this.entries);

  final Map<String, String> entries;
}
