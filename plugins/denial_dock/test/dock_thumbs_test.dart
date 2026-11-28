import 'dart:io';
import 'dart:typed_data';

import 'package:denial_dock/src/dock_stack_thumbs.dart';
import 'package:denial_dock/src/dock_thumbnailer_registry.dart';

void _expect(bool ok, String what) {
  if (!ok) throw StateError(what);
}

Uint8List _makePng(int width, int height) {
  final png = Uint8List(24)
    ..setAll(0, const <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    ..setAll(12, const <int>[0x49, 0x48, 0x44, 0x52]);
  ByteData.sublistView(png)
    ..setUint32(16, width)
    ..setUint32(20, height);
  return png;
}

/// Minimal JPEG with EXIF APP1 orientation tag + SOF0 (width x height).
Uint8List _makeJpegWithExif(int width, int height, int orientation) {
  final out = BytesBuilder();
  // SOI
  out.add(const <int>[0xFF, 0xD8]);
  // APP1: "Exif\0\0" + little-endian TIFF header + 1 IFD entry (tag 0x0112)
  final exif = Uint8List(6 + 8 + 2 + 12 + 4);
  exif.setAll(0, const <int>[0x45, 0x78, 0x69, 0x66, 0x00, 0x00]); // Exif\0\0
  exif.setAll(6, const <int>[0x49, 0x49]); // II (little-endian)
  final bd = ByteData.sublistView(exif);
  bd.setUint16(8, 42, Endian.little);
  bd.setUint32(10, 8, Endian.little); // IFD0 at offset 8 from TIFF start
  bd.setUint16(14, 1, Endian.little); // 1 entry
  bd.setUint16(16, 0x0112, Endian.little); // Orientation tag
  bd.setUint16(18, 3, Endian.little); // SHORT
  bd.setUint32(20, 1, Endian.little); // count = 1
  bd.setUint16(24, orientation, Endian.little);
  final app1Len = exif.length + 2;
  out.add(<int>[0xFF, 0xE1, (app1Len >> 8) & 0xFF, app1Len & 0xFF]);
  out.add(exif);
  // SOF0: length 11, precision 8, height, width, 1 component
  out.add(<int>[
    0xFF,
    0xC0,
    0x00,
    0x0B,
    0x08,
    (height >> 8) & 0xFF,
    height & 0xFF,
    (width >> 8) & 0xFF,
    width & 0xFF,
    0x01,
    0x01,
    0x11,
    0x00,
  ]);
  // EOI
  out.add(const <int>[0xFF, 0xD9]);
  return out.toBytes();
}

Future<void> main() async {
  final home = Platform.environment['HOME'];
  final root = home != null && Directory('$home/Lab/Bridge/tmp').existsSync()
      ? Directory('$home/Lab/Bridge/tmp')
      : Directory.systemTemp;
  final dir = Directory(
    '${root.path}/dock_thumbs_test_${DateTime.now().microsecondsSinceEpoch}',
  )..createSync(recursive: true);
  final cacheDir = '${dir.path}/cache';

  try {
    // 1. PNG aspect ratio & tall clamp
    final pngFile = File('${dir.path}/sample.png')
      ..writeAsBytesSync(_makePng(1600, 900));
    final ratio = DockStackThumbs.aspectRatio(pngFile.path);
    _expect(
      ratio != null && (ratio - (1600 / 900)).abs() < 1e-4,
      'reads PNG natural aspect ratio ($ratio)',
    );
    final tallFile = File('${dir.path}/tall.png')
      ..writeAsBytesSync(_makePng(200, 1000));
    _expect(
      DockStackThumbs.aspectRatio(tallFile.path) == 0.55,
      'clamps ultra-tall ratio to 0.55',
    );

    // 2. JPEG EXIF orientation 6 swaps 1600x900 -> 900/1600 = 0.5625
    final jpegFile = File('${dir.path}/rotated.jpg')
      ..writeAsBytesSync(_makeJpegWithExif(1600, 900, 6));
    final rotRatio = DockStackThumbs.aspectRatio(jpegFile.path);
    _expect(
      rotRatio != null && (rotRatio - (900 / 1600)).abs() < 1e-4,
      'respects JPEG EXIF orientation 6 ($rotRatio)',
    );

    // 3. Thumbnailer parsing, globs2 weight precedence, %s/%u/%i/%o expansion, bwrap wrapping
    final entry = ThumbnailerEntry.parse('papers.thumbnailer', '''
[Thumbnailer Entry]
TryExec=papers-thumbnailer
Exec=papers-thumbnailer -s %s %u %o
MimeType=application/pdf;image/tiff;
''');
    _expect(entry != null, 'parses papers.thumbnailer');
    _expect(entry!.mimeTypes.contains('application/pdf'), 'has pdf mime');
    final argv = entry.expand(
      inputPath: '/tmp/a b.pdf',
      outputPath: '/cache/out.png',
      size: 320,
    );
    _expect(
      argv.length == 5 &&
          argv[0] == 'papers-thumbnailer' &&
          argv[2] == '320' &&
          argv[3] == 'file:///tmp/a%20b.pdf' &&
          argv[4] == '/cache/out.png',
      'expands %s %u %o accurately ($argv)',
    );
    final globs = ThumbnailerRegistry.parseGlobs2('''
50:application/pdf:*.pdf
40:text/plain:*.pdf
80:video/mp4:*.mp4
''');
    _expect(globs['pdf'] == 'application/pdf', 'higher weight globs2 wins');
    _expect(globs['mp4'] == 'video/mp4', 'parses mp4 glob');

    final fakeRegistry = ThumbnailerRegistry(
      entries: <ThumbnailerEntry>[entry],
      extToMime: globs,
      hasBwrap: true,
      hasLib64: true,
      executableExists: (exe) => exe == 'papers-thumbnailer',
    );
    final sandboxed = fakeRegistry.buildCommand(
      argv,
      inputPath: '/tmp/a.pdf',
      outputDir: cacheDir,
    );
    _expect(
      sandboxed.sandboxed &&
          sandboxed.program == 'timeout' &&
          sandboxed.args.contains('--kill-after=2') &&
          sandboxed.args.contains('bwrap') &&
          sandboxed.args.contains('--unshare-net') &&
          sandboxed.args.contains('--unshare-pid') &&
          sandboxed.args.contains('--unshare-ipc') &&
          sandboxed.args.contains('--clearenv') &&
          sandboxed.args.contains('--die-with-parent'),
      'wraps thumbnailer in strict bwrap sandbox with timeout escalation',
    );
    final noBwrapRegistry = ThumbnailerRegistry(
      entries: <ThumbnailerEntry>[entry],
      extToMime: globs,
      hasBwrap: false,
      hasLib64: true,
      executableExists: (exe) => exe == 'papers-thumbnailer',
    );
    final refused = noBwrapRegistry.buildCommand(
      argv,
      inputPath: '/tmp/a.pdf',
      outputDir: cacheDir,
    );
    _expect(
      !refused.sandboxed && refused.program.isEmpty && refused.args.isEmpty,
      'refuses unsandboxed thumbnailer execution when bwrap is absent',
    );

    // 3b. Corrupt PNG with malicious 32-bit chunk length must never OOM
    final corruptPng = File('${dir.path}/corrupt.png')
      ..writeAsBytesSync(<int>[
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
        0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
        0, 0, 0, 1, 0, 0, 0, 1, 8, 2, 0, 0, 0, 0, 0, 0, 0,
        // tEXt chunk claiming 0xFFFFFFF0 bytes:
        0xFF, 0xFF, 0xFF, 0xF0, 0x74, 0x45, 0x58, 0x74,
        0x41, 0x00, 0x42,
      ]);
    _expect(
      DockStackThumbs.aspectRatio(corruptPng.path) != null,
      'corrupt PNG header does not throw or OOM',
    );
    DockStackThumbs.cancelPending();

    // 4. Dedup, failure memory (memory + disk), mtime retry, cache hit
    DockStackThumbs.invalidate();
    DockStackThumbs.cacheDirOverride = cacheDir;
    DockStackThumbs.registryOverride = fakeRegistry;

    final pdfFile = File('${dir.path}/doc.pdf')..writeAsStringSync('pdf-v1');
    var calls = 0;
    var shouldSucceed = false;

    DockStackThumbs.processRunnerOverride = (program, args) async {
      calls++;
      // Output path is the last token for papers-thumbnailer
      final outPath = args.last;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      if (!shouldSucceed) return 1;
      File(outPath).writeAsBytesSync(_makePng(600, 800));
      return 0;
    };

    // Fire 10 concurrent requests for the same PDF -> only 1 process spawned
    await Future.wait(<Future<void>>[
      for (var i = 0; i < 10; i++) DockStackThumbs.request(<String>[pdfFile.path]),
    ]);
    final statusFail = await DockStackThumbs.resolveForTest(pdfFile.path);
    _expect(statusFail == DockThumbStatus.failed, 'failed job marked failed');
    _expect(calls == 1, '10 concurrent requests spawn exactly 1 process ($calls)');

    // Subsequent requests do not re-spawn
    await DockStackThumbs.resolveForTest(pdfFile.path);
    _expect(calls == 1, 'memory failure cache prevents retry ($calls)');

    // Even after invalidate(), disk fail/ marker prevents retry while file unchanged
    DockStackThumbs.invalidate();
    final statusDiskFail = await DockStackThumbs.resolveForTest(pdfFile.path);
    _expect(statusDiskFail == DockThumbStatus.failed, 'disk fail marker honored');
    _expect(calls == 1, 'disk failure cache prevents retry ($calls)');

    // Mutate file size + mtime -> retries and succeeds!
    shouldSucceed = true;
    pdfFile.writeAsStringSync('pdf-v2-longer-content');
    pdfFile.setLastModifiedSync(DateTime.now().add(const Duration(seconds: 5)));
    final statusOk = await DockStackThumbs.resolveForTest(pdfFile.path);
    _expect(statusOk == DockThumbStatus.ready, 'changed file retries and succeeds');
    _expect(calls == 2, 'exactly 1 retry after mtime/size change ($calls)');
    final preview = DockStackThumbs.preview(pdfFile.path);
    _expect(preview != null && File(preview).existsSync(), 'preview ready in memory');
    final thumbRatio = DockStackThumbs.aspectRatioCached(preview!);
    _expect(
      thumbRatio != null && (thumbRatio - 0.75).abs() < 1e-4,
      'aspect ratio cached off-frame ($thumbRatio)',
    );

    // Cache hit after invalidate() spawns 0 processes
    DockStackThumbs.invalidate();
    final statusHit = await DockStackThumbs.resolveForTest(pdfFile.path);
    _expect(statusHit == DockThumbStatus.ready, 'own cache hit ready');
    _expect(calls == 2, 'cache hit spawns 0 processes ($calls)');

    stdout.writeln('All dock thumbnail tests passed.');
  } finally {
    DockStackThumbs.processRunnerOverride = null;
    DockStackThumbs.registryOverride = null;
    DockStackThumbs.cacheDirOverride = null;
    DockStackThumbs.invalidate();
    dir.deleteSync(recursive: true);
  }
}
