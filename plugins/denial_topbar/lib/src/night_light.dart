import 'dart:io';

import 'package:denial_shell_kit/detached_run.dart';
import 'package:flutter/foundation.dart';

/// Night light, done with the compositor's desktop LUT. A LUT the user had
/// loaded is remembered when the tint goes on and put back when it goes off.
abstract final class NightLight {
  static final ValueNotifier<bool> enabled = ValueNotifier<bool>(false);
  static bool _synced = false;

  /// The compositor reports a loaded LUT by its title, not its file.
  static const String _title = 'Top Bar Night Light';

  static const double _green = 0.86;
  static const double _blue = 0.66;

  static String get _dir {
    final env = Platform.environment;
    return '${env['XDG_CACHE_HOME'] ?? '${env['HOME']}/.cache'}/denial';
  }

  static File get _cube => File('$_dir/denial_topbar-night.cube');
  static File get _previous => File('$_dir/denial_topbar-night.previous');

  static Future<String?> _currentLut() async {
    final result = await runDetached('denialctl', const <String>['color']);
    for (final line in result.stdout.split('\n')) {
      const prefix = 'desktop LUT:';
      if (!line.startsWith(prefix)) continue;
      final value = line.substring(prefix.length).trim();
      return value.isEmpty || value == 'none' ? null : value;
    }
    return null;
  }

  static Future<bool> _run(List<String> arguments) async =>
      (await runDetached('denialctl', arguments)).exitCode == 0;

  static Future<void> sync() async {
    if (_synced) return;
    _synced = true;
    try {
      enabled.value = (await _currentLut())?.startsWith(_title) ?? false;
    } on ProcessException {
      // No denialctl: the switch stays off.
    }
  }

  static bool _busy = false;

  /// The switch moves at once and goes back if the compositor refuses.
  static Future<void> toggle() async {
    if (_busy) return;
    _busy = true;
    final next = !enabled.value;
    enabled.value = next;
    var done = false;
    try {
      done = next ? await _enable() : await _disable();
    } on ProcessException {
      // No denialctl.
    } on FileSystemException {
      // Cache directory not writable.
    } finally {
      if (!done) enabled.value = !next;
      _busy = false;
    }
  }

  static Future<bool> _enable() async {
    final current = await _currentLut();
    await _cube.parent.create(recursive: true);
    if (current != null && !current.startsWith(_title)) {
      await _previous.writeAsString(current);
    } else if (await _previous.exists()) {
      await _previous.delete();
    }
    await _cube.writeAsString(_table());
    return _run(<String>['color', 'lut', 'load', _cube.path]);
  }

  static Future<bool> _disable() async {
    final previous = await _previous.exists()
        ? (await _previous.readAsString()).trim()
        : '';
    return previous.isNotEmpty && await File(previous).exists()
        ? _run(<String>['color', 'lut', 'load', previous])
        : _run(const <String>['color', 'lut', 'clear']);
  }

  static String _table() {
    final out = StringBuffer('TITLE "$_title"\nLUT_3D_SIZE 2\n');
    for (var b = 0; b < 2; b++) {
      for (var g = 0; g < 2; g++) {
        for (var r = 0; r < 2; r++) {
          out.writeln('$r.0 ${g * _green} ${b * _blue}');
        }
      }
    }
    return out.toString();
  }
}
