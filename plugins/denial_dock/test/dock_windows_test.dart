import 'dart:io';

import 'package:denial_dock/src/dock_windows.dart';

void main() {
  final kept = DockWindows.onWorkspace<int>(
    [1, 2, 3, 4],
    idOf: (id) => id,
    workspaceById: {1: 1, 2: 2, 3: 1},
    workspace: 1,
  );
  _expect(kept.toString() == '[1, 3, 4]', 'workspace filter $kept');

  bool owns(String stream, String appId, String name) =>
      DockWindows.ownsStream(stream, appId: appId, name: name);
  _expect(owns('Firefox', 'firefox.desktop', 'Firefox Web Browser'), 'by id');
  _expect(owns('Google Chrome', 'google-chrome.desktop', 'Chrome'), 'spaces');
  _expect(owns('Chromium', 'org.chromium.Chromium', 'Web'), 'last segment');
  _expect(owns('mpv Media Player', 'mpv', 'mpv Media Player'), 'by name');
  _expect(!owns('Firefox', 'org.gnome.Nautilus', 'Files'), 'different app');
  _expect(!owns('  ', 'a', 'b'), 'unnamed stream');

  stdout.writeln('All dock window tests passed.');
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
