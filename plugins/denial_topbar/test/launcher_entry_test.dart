import 'dart:io';

import 'package:denial_topbar/src/clipboard_history.dart';
import 'package:denial_topbar/src/island/island_timer.dart';
import 'package:denial_topbar/src/mic_users.dart';
import 'package:denial_topbar/src/tray_address.dart';

void main() {
  final clips = ClipboardHistory(limit: 3);
  _expect(!clips.add('  '), 'blank text is not kept');
  _expect(clips.add('a') && clips.add('b'), 'new text is kept');
  _expect(!clips.add('b'), 'the same text twice in a row is one entry');
  clips.add('a');
  _expect(
    clips.items.join() == 'ab',
    'copying an old text moves it to the top',
  );
  clips
    ..add('c')
    ..add('d');
  _expect(clips.items.join() == 'dca', 'the oldest entry falls off the end');
  _expect(clipboardPreview(' x\n  y ') == 'x y', 'a preview is one line');

  final t0 = DateTime(2026);
  _expect(clockSpan(const Duration(seconds: 65)) == '1:05', 'minutes');
  _expect(clockSpan(const Duration(milliseconds: 400)) == '0:01', 'rounds up');
  _expect(clockSpan(const Duration(seconds: 3725)) == '1:02:05', 'hours');

  final timer = IslandTimer();
  timer.start(const Duration(minutes: 5), t0);
  timer.toggle(t0.add(const Duration(minutes: 1)));
  _expect(timer.paused, 'a running timer pauses');
  _expect(
    timer.remaining(t0.add(const Duration(minutes: 3))).inMinutes == 4,
    'and keeps what was left',
  );
  timer.add(const Duration(minutes: 1), t0);
  _expect(timer.remaining(t0).inMinutes == 5, 'time can be added');
  timer.cancel();
  _expect(!timer.active, 'and it can be cancelled');

  final unique = trayAddress(':1.2555/org/ayatana/NotificationItem/nm_applet');
  _expect(
    unique?.service == ':1.2555' &&
        unique?.path == '/org/ayatana/NotificationItem/nm_applet',
    'a watcher entry splits into service and path',
  );
  _expect(
    trayAddress('org.kde.StatusNotifierItem-670474-1')?.path ==
        '/StatusNotifierItem',
    'a bare service uses the default path',
  );
  _expect(trayAddress('nm-applet') == null, 'a plain name is not an address');
  _expect(
    trayFallbackName(
          'org.kde.StatusNotifierItem-670474-1/StatusNotifierItem',
        ) ==
        'StatusNotifierItem',
    'the fallback name is the last path part',
  );

  _expect(parseMicUsers('[]').isEmpty, 'nobody is recording');
  _expect(parseMicUsers('oops').isEmpty, 'broken output means nobody');
  final users = parseMicUsers(
    '[{"properties":{"application.name":"Firefox"}},'
    '{"properties":{"application.name":"Firefox"}},'
    '{"properties":{"application.name":"Volume Control",'
    '"application.id":"org.PulseAudio.pavucontrol"}},'
    '{"properties":{"media.name":"Peak detect","application.name":"x"}},'
    '{"properties":{"application.process.binary":"arecord"}}]',
  );
  _expect(users.join(',') == 'Firefox,arecord', 'recorders are named once');

  stdout.writeln('All launcher entry tests passed.');
}

void _expect(bool condition, String message) {
  if (!condition) {
    stderr.writeln('FAILED: $message');
    exit(1);
  }
}
