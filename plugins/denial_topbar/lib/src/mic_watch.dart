import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'mic_users.dart';
import 'tethered.dart';

/// Who is recording from a microphone right now. `pactl subscribe` reports
/// each change, so nothing is polled.
class MicWatch extends ValueNotifier<List<String>> {
  MicWatch() : super(const <String>[]);

  Timer? _debounce;
  bool _started = false;
  int _failures = 0;

  void start() {
    if (_started) return;
    _started = true;
    unawaited(_subscribe());
  }

  Future<void> _subscribe() async {
    try {
      // The event names are translated; match them in the C locale.
      final process = await startTethered('mic', const <String>[
        'env',
        'LC_ALL=C',
        'pactl',
        'subscribe',
      ]);
      unawaited(process.stderr.drain<void>());
      unawaited(_refresh());
      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .where((line) => line.contains('source-output'))
          .listen((_) {
            _failures = 0;
            _debounce?.cancel();
            _debounce = Timer(const Duration(milliseconds: 250), _refresh);
          });
      await process.exitCode;
    } on ProcessException {
      return;
    }
    // The sound server went away; give it a few chances to come back.
    if (++_failures > 5) return;
    Timer(Duration(seconds: 5 * _failures), _subscribe);
  }

  Future<void> _refresh() async {
    try {
      final result = await Process.run('pactl', const <String>[
        '-f',
        'json',
        'list',
        'source-outputs',
      ]);
      final next = result.exitCode == 0
          ? parseMicUsers('${result.stdout}')
          : const <String>[];
      if (!listEquals(next, value)) value = next;
    } on ProcessException {
      return;
    }
  }
}

final MicWatch micWatch = MicWatch();
