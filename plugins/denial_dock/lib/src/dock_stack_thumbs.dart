import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:denial_shell_kit/detached_run.dart';

/// A thumbnail found for a file: where the image is and what version of the
/// file it shows.
class DockThumbnail {
  const DockThumbnail(this.path, {required this.knownVersion});

  final String path;

  /// The mtime the thumbnail was made from, when the file that carries it
  /// records one. A freedesktop thumbnail does.
  final DateTime? knownVersion;
}

/// Lightweight revision broadcaster when background thumbnailers complete.
class DockThumbRevision {
  DockThumbRevision._();

  int value = 0;
  final List<void Function()> _listeners = <void Function()>[];

  void addListener(void Function() listener) => _listeners.add(listener);
  void removeListener(void Function() listener) => _listeners.remove(listener);

  void _bump() {
    value++;
    for (final listener in List<void Function()>.of(_listeners)) {
      listener();
    }
  }
}

final DockThumbRevision dockThumbsRevision = DockThumbRevision._();

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

  static const Set<String> _pdfExtensions = {'pdf'};

  static _ThumbIndex? _index;
  static DateTime? _indexedAt;
  static Future<void>? _warming;
  static final Map<String, double?> _aspectCache = <String, double?>{};

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
    if (_videoExtensions.contains(extension)) {
      final generated = _generated(file);
      if (generated != null) return generated.path;
      warm();
    } else if (_pdfExtensions.contains(extension)) {
      final generated = _generatedPdf(file);
      if (generated != null) return generated.path;
    }
    return null;
  }

  /// Natural width / height aspect ratio of an image file clamped to
  /// `[0.55, 1.85]`, or null when the header cannot be read cleanly.
  static double? aspectRatio(String path) {
    if (_aspectCache.containsKey(path)) return _aspectCache[path];
    final ratio = _readAspectRatio(path);
    if (_aspectCache.length > 512) _aspectCache.clear();
    _aspectCache[path] = ratio;
    return ratio;
  }

  static double? _readAspectRatio(String path) {
    RandomAccessFile? file;
    try {
      file = File(path).openSync();
      final head = file.readSync(32);
      if (head.length < 12) return null;
      // PNG IHDR
      if (head.length >= 24 &&
          head[0] == 0x89 &&
          head[1] == 0x50 &&
          head[2] == 0x4E &&
          head[3] == 0x47) {
        final data = ByteData.sublistView(head);
        final w = data.getUint32(16);
        final h = data.getUint32(20);
        if (w > 0 && h > 0) return (w / h).clamp(0.55, 1.85);
        return null;
      }
      // WebP RIFF
      if (head.length >= 30 &&
          head[0] == 0x52 &&
          head[1] == 0x49 &&
          head[2] == 0x46 &&
          head[3] == 0x46 &&
          head[8] == 0x57 &&
          head[9] == 0x45 &&
          head[10] == 0x42 &&
          head[11] == 0x50) {
        final chunk = String.fromCharCodes(head.sublist(12, 16));
        if (chunk == 'VP8X') {
          final w = 1 + (head[24] | (head[25] << 8) | (head[26] << 16));
          final h = 1 + (head[27] | (head[28] << 8) | (head[29] << 16));
          if (w > 0 && h > 0) return (w / h).clamp(0.55, 1.85);
        } else if (chunk == 'VP8L') {
          final b0 = head[21], b1 = head[22], b2 = head[23], b3 = head[24];
          final w = 1 + (b0 | ((b1 & 0x3F) << 8));
          final h = 1 + ((b1 >> 6) | (b2 << 2) | ((b3 & 0x0F) << 10));
          if (w > 0 && h > 0) return (w / h).clamp(0.55, 1.85);
        } else if (chunk == 'VP8 ') {
          final w = (head[26] | (head[27] << 8)) & 0x3FFF;
          final h = (head[28] | (head[29] << 8)) & 0x3FFF;
          if (w > 0 && h > 0) return (w / h).clamp(0.55, 1.85);
        }
        return null;
      }
      // JPEG SOF0..SOF3 / SOF5..SOF7 / SOF9..SOF11 / SOF13..SOF15
      if (head[0] == 0xFF && head[1] == 0xD8) {
        file.setPositionSync(2);
        var scanned = 2;
        while (scanned < 65536) {
          final marker = file.readSync(2);
          if (marker.length < 2) break;
          scanned += 2;
          if (marker[0] != 0xFF) break;
          var code = marker[1];
          while (code == 0xFF) {
            final next = file.readByteSync();
            if (next < 0) return null;
            scanned++;
            code = next;
          }
          if (code == 0xD9 || code == 0xDA) break;
          if (code >= 0xD0 && code <= 0xD8 || code == 0x01 || code == 0x00) {
            continue;
          }
          final lenBytes = file.readSync(2);
          if (lenBytes.length < 2) break;
          scanned += 2;
          final segLen = (lenBytes[0] << 8) | lenBytes[1];
          if (segLen < 2) break;
          final isSof =
              (code >= 0xC0 && code <= 0xC3) ||
              (code >= 0xC5 && code <= 0xC7) ||
              (code >= 0xC9 && code <= 0xCB) ||
              (code >= 0xCD && code <= 0xCF);
          if (isSof && segLen >= 7) {
            final sof = file.readSync(5);
            if (sof.length == 5) {
              final h = (sof[1] << 8) | sof[2];
              final w = (sof[3] << 8) | sof[4];
              if (w > 0 && h > 0) return (w / h).clamp(0.55, 1.85);
            }
            return null;
          }
          file.setPositionSync(file.positionSync() + segLen - 2);
          scanned += segLen - 2;
        }
      }
    } on FileSystemException {
      return null;
    } finally {
      file?.closeSync();
    }
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
        dockThumbsRevision._bump();
      }),
    );
    return null;
  }

  static DockThumbnail? _generatedPdf(String file) {
    final cacheDir = _ownCacheDir();
    if (cacheDir == null) return null;
    final name = '${_stableName(file)}_pdf';
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
    Directory(cacheDir).createSync(recursive: true);
    unawaited(
      _runPdftoppm(file, '$cacheDir/$name.tmp', out.path).then((ok) {
        if (!ok) return;
        try {
          out.setLastModifiedSync(stat.modified);
        } on FileSystemException {
          // Best-effort mtime sync.
        }
        dockThumbsRevision._bump();
      }),
    );
    return null;
  }

  static Future<bool> _runPdftoppm(
    String input,
    String tmpPrefix,
    String output,
  ) async {
    try {
      final process = await runDetached('pdftoppm', [
        '-png',
        '-f',
        '1',
        '-l',
        '1',
        '-scale-to',
        '320',
        '-singlefile',
        input,
        tmpPrefix,
      ]);
      if (process.exitCode != 0) return false;
      final file = File('$tmpPrefix.png');
      if (!file.existsSync() || file.lengthSync() == 0) return false;
      file.renameSync(output);
      return true;
    } on FileSystemException {
      return false;
    }
  }

  static Future<bool> _runFfmpeg(String input, String output) async {
    final temporary = '$output.tmp.png';
    try {
      final process = await runDetached('ffmpeg', [
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
      ]);
      if (process.exitCode != 0) return false;
      final file = File(temporary);
      if (!file.existsSync() || file.lengthSync() == 0) return false;
      file.renameSync(output);
      return true;
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

  /// Deletes generated thumbnails untouched for [maxAge], so a folder the user
  /// stopped opening does not keep its videos on disk forever.
  ///
  /// Runs off the caller's frame: a cache directory is a directory listing,
  /// and the dock asks for this while it mounts.
  static void sweepCache({Duration maxAge = const Duration(days: 60)}) {
    final directory = _ownCacheDir();
    if (directory == null) return;
    unawaited(
      Future(() {
        final cutoff = DateTime.now().subtract(maxAge);
        final List<FileSystemEntity> files;
        try {
          files = Directory(directory).listSync(followLinks: false);
        } on FileSystemException {
          return;
        }
        for (final entity in files) {
          if (entity is! File) continue;
          try {
            if (entity.statSync().modified.isBefore(cutoff)) {
              entity.deleteSync();
            }
          } on FileSystemException {
            // A file another frame is reading stays; the next sweep retries.
          }
        }
      }),
    );
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
