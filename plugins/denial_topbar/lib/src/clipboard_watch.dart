import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:denial_shell_kit/detached_run.dart';
import 'package:flutter/foundation.dart';

import 'clipboard_history.dart';
import 'tethered.dart';

/// Records copied text through `wl-paste --watch` while it runs. Selections a
/// password manager marks as secret are skipped.
class ClipboardWatch extends ValueNotifier<List<String>> {
  ClipboardWatch() : super(const <String>[]);

  static const String _script =
      'wl-paste -l 2>/dev/null | grep -q x-kde-passwordManagerHint && exit 0; '
      'wl-paste -l 2>/dev/null | grep -q "^text/" || exit 0; '
      'wl-paste -n -t text 2>/dev/null | head -c 20000 | base64 -w0; echo';

  final ClipboardHistory _history = ClipboardHistory();
  Process? _process;
  bool _wanted = false;

  /// False once `wl-paste` turned out to be missing.
  bool available = true;

  Future<void> setRunning(bool on) async {
    if (on == _wanted) return;
    _wanted = on;
    if (!on) {
      final process = _process;
      if (process != null) stopTethered(process);
      _process = null;
      _history.clear();
      value = const <String>[];
      return;
    }
    try {
      final process = await startTethered(const <String>[
        'wl-paste',
        '--watch',
        'sh',
        '-c',
        _script,
      ]);
      if (!_wanted) {
        stopTethered(process);
        return;
      }
      _process = process;
      unawaited(process.stderr.drain<void>());
      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_onLine);
    } on ProcessException {
      available = false;
      notifyListeners();
    }
  }

  void _onLine(String line) {
    if (line.isEmpty) return;
    try {
      final text = utf8.decode(base64.decode(line), allowMalformed: true);
      if (_history.add(text)) value = _history.items;
    } on FormatException {
      return;
    }
  }

  /// Puts [text] back on the clipboard.
  Future<void> copy(String text) async {
    await runDetached('wl-copy', const <String>[], input: text);
  }

  void remove(String text) {
    if (_history.remove(text)) value = _history.items;
  }

  void clear() {
    _history.clear();
    value = const <String>[];
  }
}

final ClipboardWatch clipboardWatch = ClipboardWatch();
