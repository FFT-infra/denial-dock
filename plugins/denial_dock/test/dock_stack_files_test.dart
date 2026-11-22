import 'dart:io';

import 'package:denial_dock/src/dock_stack_files.dart';

void main() {
  // Name order reads digit runs as numbers, the way Finder does.
  final names = ['shot 10.png', 'shot 2.png', 'Shot 1.png', 'notes.txt'];
  names.sort(DockStackFiles.naturalCompare);
  _expect(
    names.join('|') == 'notes.txt|Shot 1.png|shot 2.png|shot 10.png',
    'natural order: $names',
  );

  final directory = Directory.systemTemp.createTempSync('dock-stack-files');
  try {
    File('${directory.path}/b.txt').writeAsStringSync('b');
    File('${directory.path}/a 10.txt').writeAsStringSync('ten');
    File('${directory.path}/a 2.txt').writeAsStringSync('two');
    File('${directory.path}/.hidden').writeAsStringSync('hidden');
    Directory('${directory.path}/folder').createSync();

    final byName = DockStackFiles.list(
      directory.path,
      sort: DockStackSort.name,
    );
    _expect(
      byName.map((entry) => entry.name).join('|') ==
          'folder|a 2.txt|a 10.txt|b.txt',
      'name order groups folders first: ${byName.map((e) => e.name)}',
    );
    _expect(
      byName.every((entry) => !entry.name.startsWith('.')),
      'hidden entries are skipped',
    );
    _expect(byName.first.isDirectory, 'the folder is marked as one');
    _expect(
      byName[1].extension == 'txt',
      'the extension is lowercased: ${byName[1].extension}',
    );

    // By date the folder mixes with the files, as a macOS Stack does.
    final byAdded = DockStackFiles.list(
      directory.path,
      sort: DockStackSort.added,
    );
    _expect(byAdded.length == byName.length, 'the same entries come back');
    for (var i = 1; i < byAdded.length; i++) {
      _expect(
        !byAdded[i].addedAt.isAfter(byAdded[i - 1].addedAt),
        'added order is newest first',
      );
    }

    _expect(
      DockStackFiles.list('${directory.path}/missing').isEmpty,
      'a missing folder yields nothing',
    );
    _expect(
      DockStackFiles.list(directory.path, limit: 2).length == 2,
      'the limit truncates',
    );
  } finally {
    directory.deleteSync(recursive: true);
  }

  // A browser's partial download, and only while it is still being written.
  _expect(DockStackFiles.isPartialDownload('clip.mp4.part'), 'firefox partial');
  _expect(
    DockStackFiles.isPartialDownload('clip.mp4.crdownload'),
    'chromium partial',
  );
  _expect(!DockStackFiles.isPartialDownload('clip.mp4'), 'a finished file');
  final now = DateTime(2026, 11, 23, 2);
  final entries = [
    _entry('a.part', now.subtract(const Duration(seconds: 3))),
    _entry('b.part', now.subtract(const Duration(minutes: 5))),
    _entry('c.mp4', now),
  ];
  _expect(
    DockStackFiles.liveDownloads(entries, now: now) == 1,
    'a leftover partial is not a live download',
  );
}

DockStackEntry _entry(String name, DateTime modified) => DockStackEntry(
  path: '/tmp/$name',
  name: name,
  isDirectory: false,
  addedAt: modified,
  modifiedAt: modified,
);

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
