import 'package:denial_shell_kit/debug_file.dart';
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
  var count = 0;
  debugFileCommands('denial_topbar').listen((words) {
    debugCommand.value = '${words.join(' ')} #${count++}';
  });
}

/// The command without its sequence number, split into words.
List<String> debugWords() =>
    debugCommand.value.split(' #').first.split(' ')
      ..removeWhere((word) => word.isEmpty);
