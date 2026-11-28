import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:denial_shell_kit/detached_run.dart';

import 'dock_thumbnailer_registry.dart';

/// A thumbnail found for a file: where the image is and what version of the
/// file it shows.
class DockThumbnail {
  const DockThumbnail(this.path, {required this.knownVersion});

  final String path;

  /// The mtime the thumbnail was made from, when the file that carries it
  /// records one. A freedesktop thumbnail does.
  final DateTime? knownVersion;
}

/// Lifecycle state of one thumbnail entry keyed by `path|mtime|size`.
enum DockThumbStatus { ready, pending, failed }

/// Process executor hook for tests (defaults to [runDetached]).
typedef DockThumbRunner =
    Future<int> Function(String program, List<String> arguments);

/// Lightweight revision broadcaster when background thumbnailers complete.
class DockThumbRevision {
  DockThumbRevision._();

  int value = 0;
  bool _scheduled = false;
  final List<void Function()> _listeners = <void Function()>[];

  void addListener(void Function() listener) => _listeners.add(listener);
  void removeListener(void Function() listener) => _listeners.remove(listener);

  /// Broadcasts an update to listeners (also used by MIME icon indexing).
  void notify() => _bump();

  void _bump() {
    if (_scheduled) return;
    _scheduled = true;
    scheduleMicrotask(() {
      _scheduled = false;
      value++;
      for (final listener in List<void Function()>.of(_listeners)) {
        listener();
      }
    });
  }
}

final DockThumbRevision dockThumbsRevision = DockThumbRevision._();

class _ThumbRecord {
  _ThumbRecord({
    required this.key,
    required this.status,
    this.thumbPath,
    this.aspectRatio,
  });

  final String key;
  DockThumbStatus status;
  String? thumbPath;
  double? aspectRatio;
}

class _PendingJob {
  _PendingJob({
    required this.filePath,
    required this.key,
    required this.mtime,
    required this.size,
  });

  final String filePath;
  final String key;
  final DateTime mtime;
  final int size;
}

/// Thumbnails for the files in a folder stack and pinned files on the dock.
///
/// Lookup during widget `build()` ([preview], [aspectRatioCached]) is strictly
/// in-memory: zero `statSync`, zero file IO, zero process forks. All disk
/// inspection, header aspect-ratio reads, and sandboxed thumbnailer execution
/// happen asynchronously via [request] / [warm], deduplicated by
/// `path + mtime + size`, capped at 2 concurrent jobs, and negative-cached in
/// both memory and `fail/` on disk.
abstract final class DockStackThumbs {
  static const List<String> _sizes = ['x-large', 'large', 'xx-large', 'normal'];
  static const int _maxConcurrent = 2;
  static const int _thumbPixelSize = 320;

  /// Extensions the shell can decode itself directly.
  static const Set<String> _imageExtensions = {
    'png',
    'jpg',
    'jpeg',
    'gif',
    'webp',
    'bmp',
  };

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

  static const Set<String> _pdfExtensions = {'pdf'};

  static _ThumbIndex? _index;
  static DateTime? _indexedAt;
  static Future<void>? _warming;
  static ThumbnailerRegistry? _registry;

  /// Memory table: file path → latest record (keyed internally by mtime+size).
  static final Map<String, _ThumbRecord> _records = <String, _ThumbRecord>{};

  /// Memory table: preview image path → clamped width/height ratio.
  static final Map<String, double?> _aspectCache = <String, double?>{};

  static const int _maxCacheEntries = 512;
  static const int _maxQueueLength = 64;
  static const int _maxPngTextBytes = 65536;
  static const int _maxPngScanBytes = 262144;

  static void _putRecord(String file, _ThumbRecord record) {
    _records.remove(file);
    _records[file] = record;
    while (_records.length > _maxCacheEntries) {
      _records.remove(_records.keys.first);
    }
  }

  static void _putAspect(String path, double? ratio) {
    _aspectCache.remove(path);
    _aspectCache[path] = ratio;
    while (_aspectCache.length > _maxCacheEntries) {
      _aspectCache.remove(_aspectCache.keys.first);
    }
  }

  /// Active + queued thumbnail jobs deduplicated by `key`.
  static final Set<String> _inFlightKeys = <String>{};
  static final Queue<_PendingJob> _queue = Queue<_PendingJob>();
  static int _activeJobs = 0;
  static int _generation = 0;
  static bool _loggedMissingBwrap = false;

  /// Drops queued (not yet started) thumbnail jobs, e.g. when a stack closes.
  static void cancelPending() {
    _generation++;
    for (final job in _queue) {
      _inFlightKeys.remove(job.key);
      final rec = _records[job.filePath];
      if (rec != null && rec.status == DockThumbStatus.pending) {
        _records.remove(job.filePath);
      }
    }
    _queue.clear();
  }

  /// Optional test overrides.
  static DockThumbRunner? processRunnerOverride;
  static ThumbnailerRegistry? registryOverride;
  static String? cacheDirOverride;

  /// Purely in-memory lookup safe to call inside `build()`.
  ///
  /// Never performs filesystem IO or forks a process. Call [request] from
  /// `initState`, `didUpdateWidget`, or folder open to populate misses.
  static String? preview(String file) {
    final record = _records[file];
    if (record != null) {
      return record.status == DockThumbStatus.ready ? record.thumbPath : null;
    }
    final extension = _extension(file);
    if (_imageExtensions.contains(extension)) return file;
    final index = _index;
    if (index != null) {
      final path = index.entries[Uri.file(file).toString()];
      if (path != null) return path;
    }
    return null;
  }

  /// Purely in-memory aspect ratio lookup safe to call inside `build()`.
  static double? aspectRatioCached(String path) => _aspectCache[path];

  /// Natural width / height aspect ratio of an image file clamped to
  /// `[0.55, 1.85]`, respecting JPEG EXIF orientation.
  ///
  /// Synchronous helper kept for off-frame callers and unit tests; widget
  /// `build()` methods should call [aspectRatioCached] instead.
  static double? aspectRatio(String path) {
    if (_aspectCache.containsKey(path)) return _aspectCache[path];
    final ratio = _readAspectRatio(path);
    if (_aspectCache.length > 512) _aspectCache.clear();
    _aspectCache[path] = ratio;
    return ratio;
  }

  /// Schedules background thumbnail resolution (cache check, aspect ratio read,
  /// and sandboxed `.thumbnailer` generation on miss) for [paths].
  ///
  /// Safe to call repeatedly from `initState`, `didUpdateWidget`, or stack
  /// open; deduplicates in-flight keys and respects failure memory.
  static Future<void> request(Iterable<String> paths) {
    final list = paths.toList(growable: false);
    if (list.isEmpty) return Future<void>.value();
    final gen = _generation;
    return Future<void>(() async {
      if (stale) await warm();
      if (gen != _generation) return;
      final registry = _ensureRegistry();
      var changed = false;
      for (var i = 0; i < list.length; i++) {
        if (gen != _generation) return;
        final didChange = _resolveOne(list[i], registry);
        if (didChange) changed = true;
        if ((i & 15) == 15) {
          await Future<void>.delayed(Duration.zero);
        }
      }
      if (changed) dockThumbsRevision._bump();
      _pumpQueue();
    });
  }

  /// Requests thumbnails for one file and awaits until its job (if queued)
  /// finishes — useful in tests.
  static Future<DockThumbStatus> resolveForTest(String file) async {
    await request(<String>[file]);
    while (_activeJobs > 0 || _queue.isNotEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    return _records[file]?.status ?? DockThumbStatus.failed;
  }

  static bool _resolveOne(String file, ThumbnailerRegistry registry) {
    final stat = _stat(file);
    if (stat == null || stat.type != FileSystemEntityType.file) return false;
    final mtimeMs = stat.modified.millisecondsSinceEpoch;
    final key = '$file|$mtimeMs|${stat.size}';
    final existing = _records[file];
    if (existing != null && existing.key == key) {
      if (existing.status == DockThumbStatus.ready &&
          existing.thumbPath != null &&
          !_aspectCache.containsKey(existing.thumbPath)) {
        _putAspect(existing.thumbPath!, _readAspectRatio(existing.thumbPath!));
        return true;
      }
      return false;
    }

    // 1. Direct decodable images are their own previews.
    final ext = _extension(file);
    if (_imageExtensions.contains(ext)) {
      final ratio = _readAspectRatio(file);
      _putAspect(file, ratio);
      _putRecord(
        file,
        _ThumbRecord(
          key: key,
          status: DockThumbStatus.ready,
          thumbPath: file,
          aspectRatio: ratio,
        ),
      );
      return true;
    }

    // 2. Shared freedesktop thumbnail cache.
    final shared = _lookupShared(file, stat.modified);
    if (shared != null) {
      final ratio = _readAspectRatio(shared);
      _putAspect(shared, ratio);
      _putRecord(
        file,
        _ThumbRecord(
          key: key,
          status: DockThumbStatus.ready,
          thumbPath: shared,
          aspectRatio: ratio,
        ),
      );
      return true;
    }

    // 3. Own cache hit.
    final cacheDir = _ownCacheDir();
    if (cacheDir == null) return false;
    final name = _stableName(file);
    final outFile = File('$cacheDir/$name.png');
    try {
      if (outFile.existsSync() && outFile.lengthSync() > 0) {
        final made = outFile.statSync().modified;
        if (!made.isBefore(stat.modified)) {
          final ratio = _readAspectRatio(outFile.path);
          _putAspect(outFile.path, ratio);
          _putRecord(
            file,
            _ThumbRecord(
              key: key,
              status: DockThumbStatus.ready,
              thumbPath: outFile.path,
              aspectRatio: ratio,
            ),
          );
          return true;
        }
      }
    } on FileSystemException {
      // Ignore and continue to fail check.
    }

    // 4. Negative (failure) cache on disk keyed by mtime + size.
    final failFile = File('$cacheDir/fail/$name.fail');
    final versionStamp = '$mtimeMs|${stat.size}';
    if (_matchesFailMarker(failFile, versionStamp)) {
      _putRecord(file, _ThumbRecord(key: key, status: DockThumbStatus.failed));
      return false;
    }

    // 5. Check whether any sandboxed thumbnailer or fallback supports this file.
    if (!registry.hasBwrap) {
      if (!_loggedMissingBwrap) {
        _loggedMissingBwrap = true;
        stderr.writeln(
          'denial_dock: bubblewrap (bwrap) not found; skipping unsandboxed thumbnail generation.',
        );
      }
      return false;
    }
    if (!_hasGeneratorFor(file, ext, registry)) {
      _putRecord(file, _ThumbRecord(key: key, status: DockThumbStatus.failed));
      return false;
    }

    // 6. Enqueue async generation (deduplicated by key, bounded queue).
    if (_queue.length >= _maxQueueLength) return false;
    _putRecord(file, _ThumbRecord(key: key, status: DockThumbStatus.pending));
    if (_inFlightKeys.add(key)) {
      _queue.add(
        _PendingJob(
          filePath: file,
          key: key,
          mtime: stat.modified,
          size: stat.size,
        ),
      );
    }
    return false;
  }

  static bool _hasGeneratorFor(
    String file,
    String ext,
    ThumbnailerRegistry registry,
  ) {
    if (registry.match(file) != null) return true;
    if (_videoExtensions.contains(ext)) return registry.hasExec('ffmpeg');
    if (_pdfExtensions.contains(ext)) return registry.hasExec('mutool');
    return false;
  }

  static void _pumpQueue() {
    while (_activeJobs < _maxConcurrent && _queue.isNotEmpty) {
      final job = _queue.removeFirst();
      _activeJobs++;
      unawaited(
        _runJob(job).whenComplete(() {
          _activeJobs--;
          _inFlightKeys.remove(job.key);
          _pumpQueue();
        }),
      );
    }
  }

  static Future<void> _runJob(_PendingJob job) async {
    final cacheDir = _ownCacheDir();
    if (cacheDir == null) return;
    final name = _stableName(job.filePath);
    final outPath = '$cacheDir/$name.png';
    final nonce = DateTime.now().microsecondsSinceEpoch;
    final jobDir = Directory('$cacheDir/.job-$name-$nonce');
    final tmpPath = '${jobDir.path}/out.png';
    final failPath = '$cacheDir/fail/$name.fail';
    final stamp = '${job.mtime.millisecondsSinceEpoch}|${job.size}';

    try {
      jobDir.createSync(recursive: true);
    } on FileSystemException {
      _markFailed(job, failPath, stamp);
      return;
    }

    try {
      final registry = _ensureRegistry();
      final ok = await _generateThumbnail(
        registry: registry,
        inputPath: job.filePath,
        tmpOutputPath: tmpPath,
        outputDir: jobDir.path,
      );

      if (ok) {
        try {
          final tmpFile = File(tmpPath);
          if (tmpFile.existsSync() && tmpFile.lengthSync() > 0) {
            tmpFile.renameSync(outPath);
            // Keep generation timestamp as mtime so the 60-day sweep does not
            // delete freshly generated thumbnails of older files; only advance
            // if the source mtime is in the future (clock skew / tests).
            if (job.mtime.isAfter(DateTime.now())) {
              try {
                File(outPath).setLastModifiedSync(job.mtime);
              } on FileSystemException {
                // Best-effort mtime sync.
              }
            }
            try {
              final fail = File(failPath);
              if (fail.existsSync()) fail.deleteSync();
            } on FileSystemException {
              // Ignore cleanup failure.
            }
            final ratio = _readAspectRatio(outPath);
            _putAspect(outPath, ratio);
            final current = _records[job.filePath];
            if (current == null || current.key == job.key) {
              _putRecord(
                job.filePath,
                _ThumbRecord(
                  key: job.key,
                  status: DockThumbStatus.ready,
                  thumbPath: outPath,
                  aspectRatio: ratio,
                ),
              );
              dockThumbsRevision._bump();
            }
            return;
          }
        } on FileSystemException {
          // Fall through to markFailed.
        }
      }
      _markFailed(job, failPath, stamp);
    } finally {
      try {
        if (jobDir.existsSync()) jobDir.deleteSync(recursive: true);
      } on FileSystemException {
        // Ignore temp job dir cleanup failure.
      }
    }
  }

  static void _markFailed(_PendingJob job, String failPath, String stamp) {
    final current = _records[job.filePath];
    if (current == null || current.key == job.key) {
      _records[job.filePath] = _ThumbRecord(
        key: job.key,
        status: DockThumbStatus.failed,
      );
    }
    try {
      final f = File(failPath);
      f.parent.createSync(recursive: true);
      f.writeAsStringSync('$stamp\n');
    } on FileSystemException {
      // Memory failure record still prevents retries for this session.
    }
  }

  static bool _matchesFailMarker(File failFile, String expectedStamp) {
    try {
      if (!failFile.existsSync()) return false;
      return failFile.readAsStringSync().trim() == expectedStamp;
    } on FileSystemException {
      return false;
    }
  }

  static Future<bool> _generateThumbnail({
    required ThumbnailerRegistry registry,
    required String inputPath,
    required String tmpOutputPath,
    required String outputDir,
  }) async {
    final runner = processRunnerOverride ?? _defaultRunner;
    // 1. Prefer registered freedesktop `.thumbnailer`. When a matching entry
    // exists, run it alone (never silently drop the sandbox or run a second
    // process when the registered thumbnailer fails).
    final entry = registry.match(inputPath);
    if (entry != null) {
      final argv = entry.expand(
        inputPath: inputPath,
        outputPath: tmpOutputPath,
        size: _thumbPixelSize,
      );
      if (argv.isEmpty) return false;
      final cmd = registry.buildCommand(
        argv,
        inputPath: inputPath,
        outputDir: outputDir,
      );
      if (!cmd.sandboxed || cmd.program.isEmpty) return false;
      return await runner(cmd.program, cmd.args) == 0;
    }

    // 2. Explicit fallbacks for video (ffmpeg) and PDF (mutool draw),
    // still wrapped in bwrap when available.
    final ext = _extension(inputPath);
    if (_videoExtensions.contains(ext) && registry.hasExec('ffmpeg')) {
      final cmd = registry.buildCommand(
        <String>[
          'ffmpeg',
          '-nostdin',
          '-loglevel',
          'error',
          '-y',
          '-ss',
          '0',
          '-i',
          inputPath,
          '-frames:v',
          '1',
          '-vf',
          'scale=$_thumbPixelSize:-1',
          tmpOutputPath,
        ],
        inputPath: inputPath,
        outputDir: outputDir,
      );
      if (!cmd.sandboxed || cmd.program.isEmpty) return false;
      return await runner(cmd.program, cmd.args) == 0;
    }
    if (_pdfExtensions.contains(ext) && registry.hasExec('mutool')) {
      final cmd = registry.buildCommand(
        <String>[
          'mutool',
          'draw',
          '-o',
          tmpOutputPath,
          '-r',
          '72',
          '-F',
          'png',
          inputPath,
          '1',
        ],
        inputPath: inputPath,
        outputDir: outputDir,
      );
      if (!cmd.sandboxed || cmd.program.isEmpty) return false;
      return await runner(cmd.program, cmd.args) == 0;
    }
    return false;
  }

  static Future<int> _defaultRunner(String program, List<String> args) async {
    final res = await runDetached(program, args);
    return res.exitCode;
  }

  static ThumbnailerRegistry _ensureRegistry() =>
      registryOverride ?? (_registry ??= ThumbnailerRegistry.loadSystem());

  /// Reads natural width/height ratio clamped to `[0.55, 1.85]`, supporting
  /// PNG, WebP, and JPEG (including EXIF orientation 5..8 dimension swap).
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
      // JPEG APP1 (EXIF orientation) + SOF0..SOF15
      if (head[0] == 0xFF && head[1] == 0xD8) {
        file.setPositionSync(2);
        var scanned = 2;
        var swapDims = false;
        while (scanned < 131072) {
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
          if (code == 0xE1 && segLen >= 14 && segLen <= 65535) {
            final app1 = file.readSync(segLen - 2);
            scanned += app1.length;
            final orient = _parseExifOrientation(app1);
            if (orient != null && orient >= 5 && orient <= 8) {
              swapDims = true;
            }
            continue;
          }
          final isSof =
              (code >= 0xC0 && code <= 0xC3) ||
              (code >= 0xC5 && code <= 0xC7) ||
              (code >= 0xC9 && code <= 0xCB) ||
              (code >= 0xCD && code <= 0xCF);
          if (isSof && segLen >= 7) {
            final sof = file.readSync(5);
            if (sof.length == 5) {
              var h = (sof[1] << 8) | sof[2];
              var w = (sof[3] << 8) | sof[4];
              if (swapDims) {
                final tmp = w;
                w = h;
                h = tmp;
              }
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

  static int? _parseExifOrientation(Uint8List data) {
    if (data.length < 14) return null;
    // "Exif\0\0"
    if (data[0] != 0x45 ||
        data[1] != 0x78 ||
        data[2] != 0x69 ||
        data[3] != 0x66 ||
        data[4] != 0x00 ||
        data[5] != 0x00) {
      return null;
    }
    final tiff = 6;
    final littleEndian = data[tiff] == 0x49 && data[tiff + 1] == 0x49;
    final bigEndian = data[tiff] == 0x4D && data[tiff + 1] == 0x4D;
    if (!littleEndian && !bigEndian) return null;
    final endian = littleEndian ? Endian.little : Endian.big;
    final bd = ByteData.sublistView(data);
    if (bd.getUint16(tiff + 2, endian) != 42) return null;
    final ifdOffset = bd.getUint32(tiff + 4, endian);
    final ifdPos = tiff + ifdOffset;
    if (ifdPos < tiff || ifdPos + 2 > data.length) return null;
    final count = bd.getUint16(ifdPos, endian);
    for (var i = 0; i < count; i++) {
      final entryPos = ifdPos + 2 + i * 12;
      if (entryPos + 12 > data.length) break;
      final tag = bd.getUint16(entryPos, endian);
      if (tag == 0x0112) {
        return bd.getUint16(entryPos + 8, endian);
      }
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

  /// Builds the thumbnail index and loads the system `.thumbnailer` registry.
  static Future<void> warm() {
    if (!stale) return Future<void>.value();
    return _warming ??= Future(() {
      try {
        _ensureRegistry();
        _loadIndex();
      } finally {
        _warming = null;
      }
    });
  }

  static String? _lookupShared(String file, DateTime mtime) {
    final index = _index;
    if (index == null) return null;
    final path = index.entries[Uri.file(file).toString()];
    if (path == null) return null;
    final version = _stamp(path);
    if (version != null && version.isBefore(mtime)) return null;
    return path;
  }

  /// Synchronous lookup kept for legacy tests; checks freedesktop cache only
  /// and triggers async generation on miss.
  static DockThumbnail? lookup(String file) {
    final stat = _stat(file);
    if (stat == null) return null;
    final index = _loadIndex();
    final uri = Uri.file(file).toString();
    final path = index[uri];
    if (path != null) {
      final version = _stamp(path);
      if (version == null || !version.isBefore(stat.modified)) {
        return DockThumbnail(path, knownVersion: version);
      }
    }
    unawaited(request(<String>[file]));
    return null;
  }

  /// Drops cached tables (used in tests and manual cache refresh).
  static void invalidate() {
    _index = null;
    _indexedAt = null;
    _records.clear();
    _aspectCache.clear();
    _inFlightKeys.clear();
    _queue.clear();
    _registry = null;
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

  static Map<String, String> _readTextChunks(String path) {
    final out = <String, String>{};
    RandomAccessFile? file;
    try {
      file = File(path).openSync();
      final fileLen = file.lengthSync();
      if (fileLen < 24) return out;
      final signature = file.readSync(8);
      if (signature.length != 8 ||
          signature[0] != 0x89 ||
          signature[1] != 0x50 ||
          signature[2] != 0x4E ||
          signature[3] != 0x47) {
        return out;
      }
      var scanned = 8;
      while (scanned + 12 <= fileLen && scanned < _maxPngScanBytes) {
        final header = file.readSync(8);
        if (header.length != 8) break;
        final length = ByteData.sublistView(header).getUint32(0);
        final type = String.fromCharCodes(header.sublist(4));
        final pos = file.positionSync();
        final remaining = fileLen - pos;
        // Guard against corrupt/malicious 32-bit chunk lengths causing OOM.
        if (length > remaining - 4) break;
        scanned += 8 + length + 4;
        if (type == 'tEXt') {
          if (length > _maxPngTextBytes) {
            file.setPositionSync(pos + length + 4);
            continue;
          }
          final data = file.readSync(length);
          final zero = data.indexOf(0);
          if (zero > 0) {
            out[String.fromCharCodes(data.sublist(0, zero))] =
                String.fromCharCodes(data.sublist(zero + 1));
          }
          file.readSync(4);
          continue;
        }
        if (type == 'IEND') break;
        if (type == 'IDAT') {
          // Stop scanning once image data starts if we already found metadata,
          // or skip bounded IDAT? Skip only pre-IDAT metadata chunks.
          break;
        }
        file.setPositionSync(pos + length + 4);
      }
    } on FileSystemException {
      return out;
    } on RangeError {
      return out;
    } finally {
      file?.closeSync();
    }
    return out;
  }

  static String? _ownCacheDir() {
    if (cacheDirOverride != null) return cacheDirOverride;
    final home = Platform.environment['HOME'];
    if (home == null) return null;
    final cache = Platform.environment['XDG_CACHE_HOME'] ?? '$home/.cache';
    return '$cache/denial_dock/thumbnails';
  }

  /// Deletes generated thumbnails untouched for [maxAge].
  static void sweepCache({Duration maxAge = const Duration(days: 60)}) {
    final directory = _ownCacheDir();
    if (directory == null) return;
    unawaited(
      Future(() {
        final cutoff = DateTime.now().subtract(maxAge);
        for (final dirPath in <String>[directory, '$directory/fail']) {
          final List<FileSystemEntity> files;
          try {
            files = Directory(dirPath).listSync(followLinks: false);
          } on FileSystemException {
            continue;
          }
          for (final entity in files) {
            if (entity is! File) continue;
            try {
              if (entity.statSync().modified.isBefore(cutoff)) {
                entity.deleteSync();
              }
            } on FileSystemException {
              // Ignore in-use files.
            }
          }
        }
      }),
    );
  }

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
