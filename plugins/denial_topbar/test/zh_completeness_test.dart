import 'dart:io';

import 'package:denial_topbar/src/l10n/zh.dart';

/// Verifies that every literal `context.tr('...')` across `denial_topbar/lib`
/// has a matching entry in `zh.dart` (preventing untranslated English UI slips).
void main() {
  final libDir = Directory('lib');
  if (!libDir.existsSync()) {
    throw StateError('Run from plugins/denial_topbar');
  }
  final pattern = RegExp(r"context\.tr\(\s*'((?:\\'|[^'])+)'");
  final missing = <String>[];
  for (final entity in libDir.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    if (entity.path.endsWith('l10n/zh.dart')) continue;
    final text = entity.readAsStringSync();
    for (final match in pattern.allMatches(text)) {
      final raw = match.group(1)!.replaceAll(r"\'", "'");
      if (!zh.containsKey(raw) && !missing.contains(raw)) {
        missing.add(raw);
      }
    }
  }
  if (missing.isNotEmpty) {
    throw StateError(
      'Missing ${missing.length} zh.dart translations: ${missing.join(', ')}',
    );
  }
}
