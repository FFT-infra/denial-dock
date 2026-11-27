import 'package:denial_shell_kit/debug_file.dart';
import 'package:denial_shell_kit/kit_perf.dart';
import 'package:denial_shell_kit/kit_style.dart';
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
    // `look <id>` switches the look and leaves the layout alone.
    if (words.length > 1 && words.first == 'look') {
      kitStyle.choose(KitStyle.byId(words[1]));
    } else if (words.length > 1 && words.first == 'perf') {
      if (words[1] == 'start') {
        KitPerfProbe.start();
      } else if (words[1] == 'stop') {
        KitPerfProbe.stop();
      }
      return;
    } else if (words.length > 1 && words.first == 'scale') {
      kitShellScale.value = words[1] == 'auto'
          ? null
          : double.tryParse(words[1]);
      return;
    } else if (words.length > 1 && words.first == 'surface') {
      kitSurfaceMode.value = words[1] == 'auto'
          ? null
          : KitSurfaceMode.tryParse(words[1]);
      return;
    } else if (words.length > 1 && words.first == 'panelstyle') {
      kitPanelStyle.value = words[1] == 'auto'
          ? null
          : KitPanelStyle.tryParse(words[1]);
      return;
    } else if (words.length > 1 && words.first == 'widgetstyle') {
      final parsed = KitWidgetStyle.tryParse(words[1]);
      if (parsed != null) kitWidgetStyle.value = parsed;
      return;
    }
    debugCommand.value = '${words.join(' ')} #${count++}';
  });
}

/// The command without its sequence number, split into words.
List<String> debugWords() =>
    debugCommand.value.split(' #').first.split(' ')
      ..removeWhere((word) => word.isEmpty);
