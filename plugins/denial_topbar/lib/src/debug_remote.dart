import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Lets a developer drive the bar without a pointer: when the file
/// `denial_topbar.debug` exists beside the preferences at start, each write
/// to it is a command (`cc`, `settings 2`, `island open`, `timer 90`, …).
/// Without the file nothing is watched.
final ValueNotifier<String> debugCommand = ValueNotifier<String>('');

bool _started = false;

void startDebugRemote() {
  if (_started) return;
  _started = true;
  final home = Platform.environment['HOME'];
  if (home == null) return;
  final file = File('$home/.config/denial/plugins/denial_topbar.debug');
  if (!file.existsSync()) return;
  var count = 0;
  Timer? settle;
  file.parent.watch().where((event) => event.path == file.path).listen((_) {
    settle?.cancel();
    settle = Timer(const Duration(milliseconds: 60), () {
      try {
        final text = file.readAsStringSync().trim();
        if (text.isNotEmpty) debugCommand.value = '$text #${count++}';
      } on FileSystemException {
        return;
      }
    });
  }, onError: (_) {});
}

/// The command without its sequence number, split into words.
List<String> debugWords() =>
    debugCommand.value.split(' #').first.split(' ')
      ..removeWhere((word) => word.isEmpty);
