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
    // The limit applies after the sort, so the one entry kept is the newest
    // rather than whichever the directory happened to hand over first.
    final newest = DockStackFiles.list(directory.path, limit: 1);
    _expect(
      newest.single.name == byAdded.first.name,
      'the limit keeps the newest: ${newest.single.name}',
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

  // The bar only appears while a transfer is live, and counts them.
  _expect(
    DockStackFiles.progress(entries, now: now)?.files == 1,
    'one live transfer is reported',
  );
  _expect(
    DockStackFiles.progress([_entry('done.mp4', now)], now: now) == null,
    'a folder with no partial has no bar',
  );

  // A dense file records no total, so the bar sweeps rather than lying about a
  // fraction. A sparse one reserves its final size, so it has a real one.
  final scratch = Directory.systemTemp.createTempSync('dock-stack-progress');
  try {
    final dense = File('${scratch.path}/dense.part')
      ..writeAsBytesSync(List<int>.filled(4096, 7));
    _expect(
      DockStackFiles.allocatedFraction([dense.path]) == null,
      'a dense file has no known total',
    );
    // A truncated file reserves its length without writing the blocks.
    final sparse = File('${scratch.path}/sparse.part');
    final handle = sparse.openSync(mode: FileMode.write);
    handle.truncateSync(1024 * 1024);
    handle.closeSync();
    final fraction = DockStackFiles.allocatedFraction([sparse.path]);
    _expect(
      fraction != null && fraction >= 0 && fraction <= 1,
      'a sparse file reports a fraction: $fraction',
    );
  } finally {
    scratch.deleteSync(recursive: true);
  }

  // A saved order keeps the names it knows first and lets a file that arrived
  // since fall in behind them, so a fresh download is never lost.
  final ordered = [
    _entry('c.png', DateTime(2026, 1, 1)),
    _entry('a.png', DateTime(2026, 1, 2)),
    _entry('new.png', DateTime(2026, 1, 3)),
  ];
  DockStackFiles.applyOrder(ordered, ['a.png', 'c.png']);
  _expect(
    ordered.map((entry) => entry.name).join('|') == 'a.png|c.png|new.png',
    'saved order then newcomers: ${ordered.map((entry) => entry.name)}',
  );

  final filtered = DockStackFiles.filter([
    _entry('Report.PDF', DateTime(2026, 1, 1)),
    _entry('notes.txt', DateTime(2026, 1, 1)),
  ], 'report');
  _expect(
    filtered.length == 1 && filtered.first.name == 'Report.PDF',
    'filter matches case-insensitively',
  );
  _expect(
    DockStackFiles.filter(filtered, '  ').length == 1,
    'a blank query keeps everything',
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
