import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:denial_shell_kit/detached_run.dart';
import 'package:flutter/foundation.dart';

import 'mic_users.dart';
import 'tethered.dart';

/// Who is recording from a microphone right now. `pactl subscribe` reports
/// each change, so nothing is polled.
class MicWatch extends ValueNotifier<List<String>> {
  MicWatch() : super(const <String>[]);

  Timer? _debounce;
  Timer? _retry;
  Process? _process;
  bool _wanted = false;
  bool get wanted => _wanted;
  bool _running = false;
  int _failures = 0;

  void start() => setRunning(true);

  void stop() => setRunning(false);

  void setRunning(bool on) {
    if (_wanted == on) return;
    _wanted = on;
    if (on) {
      if (!_running) {
        _running = true;
        _failures = 0;
        unawaited(_subscribe());
      }
    } else {
      _debounce?.cancel();
      _debounce = null;
      _retry?.cancel();
      _retry = null;
      final proc = _process;
      _process = null;
      if (proc != null) {
        Process.killPid(proc.pid, ProcessSignal.sigkill);
      }
      _running = false;
      if (value.isNotEmpty) value = const <String>[];
    }
  }

  Future<void> _subscribe() async {
    if (!_wanted) {
      _running = false;
      return;
    }
    try {
      // The event names are translated; match them in the C locale.
      final process = await startTethered(const <String>[
        'env',
        'LC_ALL=C',
        'pactl',
        'subscribe',
      ]);
      if (!_wanted) {
        Process.killPid(process.pid, ProcessSignal.sigkill);
        _running = false;
        return;
      }
      _process = process;
      unawaited(process.stderr.drain<void>());
      unawaited(_refresh());
      await process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .where((line) => line.contains('source-output'))
          .forEach((_) {
            if (!_wanted) return;
            _failures = 0;
            _debounce?.cancel();
            _debounce = Timer(const Duration(milliseconds: 250), _refresh);
          });
      if (identical(_process, process)) _process = null;
    } on ProcessException {
      _running = false;
      return;
    }
    if (!_wanted) {
      _running = false;
      return;
    }
    // The sound server went away; give it a few chances to come back.
    if (++_failures > 5) {
      _running = false;
      return;
    }
    _retry?.cancel();
    _retry = Timer(Duration(seconds: 5 * _failures), _subscribe);
  }

  Future<void> _refresh() async {
    if (!_wanted) return;
    final result = await runDetached('pactl', const <String>[
      '-f',
      'json',
      'list',
      'source-outputs',
    ]);
    if (!_wanted) return;
    final next = result.exitCode == 0
        ? parseMicUsers(result.stdout)
        : const <String>[];
    if (!listEquals(next, value)) value = next;
  }
}

final MicWatch micWatch = MicWatch();
