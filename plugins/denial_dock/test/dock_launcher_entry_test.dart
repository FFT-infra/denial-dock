import 'dart:io';

import 'package:denial_dock/src/dock_launcher_entry.dart';

void main() {
  // The URI names a desktop file; the scheme, case and suffix all go.
  _expect(
    LauncherEntries.applicationId('application://Firefox.desktop') == 'firefox',
    'uri with scheme',
  );
  _expect(
    LauncherEntries.applicationId('org.gnome.Nautilus.desktop') ==
        'org.gnome.nautilus',
    'bare desktop id',
  );
  _expect(LauncherEntries.applicationId('application://') == null, 'empty uri');

  // A signal only carries what changed; the rest of the entry is kept.
  var entry = const LauncherEntry().merge({
    'progress': 0.25,
    'progress-visible': true,
  });
  _expect(entry.shownProgress == 0.25, 'progress shown');
  entry = entry.merge({'count': 3, 'count-visible': true});
  _expect(entry.shownProgress == 0.25 && entry.shownCount == 3, 'kept $entry');
  entry = entry.merge({'progress-visible': false});
  _expect(entry.shownProgress == null && entry.progress == 0.25, 'hidden');

  // Values from the bus are untrusted: wrong types are ignored, numbers are
  // clamped, and a count is hidden unless the sender says it is visible.
  final hostile = const LauncherEntry().merge({
    'count': 'many',
    'count-visible': 1,
    'progress': double.nan,
    'progress-visible': 'yes',
    'urgent': 'true',
  });
  _expect(hostile == const LauncherEntry(), 'wrong types ignored $hostile');
  _expect(
    const LauncherEntry().merge({'progress': 7}).progress == 1 &&
        const LauncherEntry().merge({'progress': -2.0}).progress == 0,
    'progress clamped',
  );
  _expect(
    const LauncherEntry().merge({'count': -4}).count == 0 &&
        const LauncherEntry().merge({'count': 1 << 40}).count == 0,
    'count bounds',
  );
  _expect(
    const LauncherEntry(count: 5).shownCount == 0 &&
        const LauncherEntry(count: 5, countVisible: true).shownCount == 5,
    'count needs visibility',
  );
  _expect(const LauncherEntry(count: 5).idle, 'hidden count is idle');
  _expect(!const LauncherEntry(urgent: true).idle, 'urgent is not idle');

  // One entry per application, and the sender that spoke last is shown.
  final entries = LauncherEntries();
  _expect(
    entries.update(':1.10', 'application://chrome.desktop', {
          'progress': 0.5,
          'progress-visible': true,
        }) ==
        'chrome',
    'first update reports the app',
  );
  _expect(
    entries.update(':1.10', 'application://chrome.desktop', {
          'progress': 0.5,
        }) ==
        null,
    'an unchanged update reports nothing',
  );
  _expect(entries.update('', 'application://x.desktop', {}) == null, 'sender');
  entries.update(':1.20', 'chrome.desktop', {
    'count': 2,
    'count-visible': true,
  });
  _expect(
    entries.entry('chrome')?.shownCount == 2 &&
        entries.entry('chrome')?.shownProgress == null,
    'last sender wins',
  );
  _expect(entries.active.keys.single == 'chrome', 'active ${entries.active}');

  // A sender that leaves the bus takes its entry with it, and the one below
  // shows again.
  _expect(
    entries.removeSender(':1.20').single == 'chrome',
    'removing the top sender changes the app',
  );
  _expect(entries.entry('chrome')?.shownProgress == 0.5, 'earlier sender back');
  _expect(entries.removeSender(':1.99').isEmpty, 'unknown sender');
  entries.removeSender(':1.10');
  _expect(entries.entry('chrome') == null && entries.isEmpty, 'all gone');
  _expect(entries.active.isEmpty, 'nothing active');

  stdout.writeln('All dock launcher entry tests passed.');
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
