import 'dart:io';
import 'dart:typed_data';

import 'package:denial_dock/src/dock_stack_thumbs.dart';

void _expect(bool ok, String what) {
  if (!ok) throw StateError(what);
}

void main() {
  final dir = Directory.systemTemp.createTempSync('dock_thumbs_test_');
  try {
    // 16:9 PNG header (1600x900)
    final png = Uint8List(24)
      ..setAll(0, const <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
      ..setAll(12, const <int>[0x49, 0x48, 0x44, 0x52]);
    ByteData.sublistView(png)
      ..setUint32(16, 1600)
      ..setUint32(20, 900);
    final pngFile = File('${dir.path}/sample.png')..writeAsBytesSync(png);
    final ratio = DockStackThumbs.aspectRatio(pngFile.path);
    _expect(
      ratio != null && (ratio - (1600 / 900)).abs() < 1e-4,
      'reads PNG natural aspect ratio ($ratio)',
    );

    // Tall image clamped to 0.55
    ByteData.sublistView(png)
      ..setUint32(16, 200)
      ..setUint32(20, 1000);
    final tallFile = File('${dir.path}/tall.png')..writeAsBytesSync(png);
    _expect(
      DockStackThumbs.aspectRatio(tallFile.path) == 0.55,
      'clamps ultra-tall ratio to 0.55',
    );
  } finally {
    dir.deleteSync(recursive: true);
  }
}
