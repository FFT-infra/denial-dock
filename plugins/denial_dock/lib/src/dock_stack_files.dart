import 'dart:io';

import 'dock_settings.dart' show DockStackSortMode;

/// How a folder stack orders its entries. `added` is the Finder default for a
/// Stack: the file that arrived last sits closest to the icon.
///
/// The setting type and this one name the same four orders; the settings layer
/// owns the stored spelling, this one the sort itself.
typedef DockStackSort = DockStackSortMode;

/// One file inside a stack folder.
class DockStackEntry {
  const DockStackEntry({
    required this.path,
    required this.name,
    required this.isDirectory,
    required this.addedAt,
    required this.modifiedAt,
  });

  final String path;
  final String name;
  final bool isDirectory;

  /// When the entry arrived in this folder: the change time, because a move
  /// into the folder rewrites it while the birth time comes from wherever the
  /// file was made. A directory keeps its birth time instead, since its change
  /// time moves every time anything inside it changes.
  final DateTime addedAt;

  final DateTime modifiedAt;

  String get extension {
    final dot = name.lastIndexOf('.');
    return dot <= 0 || dot == name.length - 1
        ? ''
        : name.substring(dot + 1).toLowerCase();
  }
}

/// A directory read for a stack. Pure file-system work, so the sort rules can
/// be tested without a display.
abstract final class DockStackFiles {
  /// Entries read at most. A folder past this is truncated rather than
  /// allowed to stall the dock.
  static const int maxEntries = 5000;

  static List<DockStackEntry> list(
    String path, {
    DockStackSort sort = DockStackSort.added,
    List<String> order = const [],
    int limit = maxEntries,
  }) {
    final directory = Directory(path);
    final entries = <DockStackEntry>[];
    try {
      for (final entity in directory.listSync(followLinks: false)) {
        final name = entity.uri.pathSegments.lastWhere(
          (segment) => segment.isNotEmpty,
          orElse: () => '',
        );
        if (name.isEmpty || name.startsWith('.')) continue;
        if (entries.length >= maxEntries) break;
        final FileStat stat;
        try {
          stat = entity.statSync();
        } on FileSystemException {
          continue;
        }
        final isDirectory = stat.type == FileSystemEntityType.directory;
        entries.add(
          DockStackEntry(
            path: entity.path,
            name: name,
            isDirectory: isDirectory,
            addedAt: isDirectory ? stat.modified : stat.changed,
            modifiedAt: stat.modified,
          ),
        );
      }
    } on FileSystemException {
      return const [];
    }
    sortEntries(entries, sort, order: order);
    return entries.length > limit ? entries.sublist(0, limit) : entries;
  }

  /// Orders [entries] in place. Folders come first only where the reference
  /// groups them; by date they mix with files, the way a macOS Stack does.
  static void sortEntries(
    List<DockStackEntry> entries,
    DockStackSort sort, {
    List<String> order = const [],
  }) {
    if (sort == DockStackSort.manual) {
      applyOrder(entries, order);
      return;
    }
    entries.sort((a, b) {
      if ((sort == DockStackSort.name || sort == DockStackSort.kind) &&
          a.isDirectory != b.isDirectory) {
        return a.isDirectory ? -1 : 1;
      }
      final byKey = switch (sort) {
        DockStackSort.added => b.addedAt.compareTo(a.addedAt),
        DockStackSort.modified => b.modifiedAt.compareTo(a.modifiedAt),
        DockStackSort.kind => a.extension.compareTo(b.extension),
        DockStackSort.name || DockStackSort.manual => 0,
      };
      return byKey != 0 ? byKey : naturalCompare(a.name, b.name);
    });
  }

  /// Orders [entries] in place to follow [names]: the names it lists come
  /// first in that order, and anything it does not know about — a file added
  /// since the order was saved — follows, newest first, so a fresh download
  /// still lands where the user looks.
  static void applyOrder(List<DockStackEntry> entries, List<String> names) {
    if (names.isEmpty) {
      sortEntries(entries, DockStackSort.added);
      return;
    }
    final rank = <String, int>{
      for (var i = 0; i < names.length; i++) names[i]: i,
    };
    entries.sort((a, b) {
      final ra = rank[a.name];
      final rb = rank[b.name];
      if (ra != null && rb != null) return ra.compareTo(rb);
      if (ra != null) return -1;
      if (rb != null) return 1;
      final byDate = b.addedAt.compareTo(a.addedAt);
      return byDate != 0 ? byDate : naturalCompare(a.name, b.name);
    });
  }

  /// The names in [entries], which is what a manual order is saved as.
  static List<String> names(List<DockStackEntry> entries) => [
    for (final entry in entries) entry.name,
  ];

  /// Name order that reads numbers as numbers, so `shot 2` precedes `shot 10`.
  static int naturalCompare(String first, String second) {
    final a = first.toLowerCase();
    final b = second.toLowerCase();
    var i = 0;
    var j = 0;
    while (i < a.length && j < b.length) {
      final ca = a.codeUnitAt(i);
      final cb = b.codeUnitAt(j);
      final aDigit = _isDigit(ca);
      final bDigit = _isDigit(cb);
      if (aDigit && bDigit) {
        var ei = i;
        var ej = j;
        while (ei < a.length && _isDigit(a.codeUnitAt(ei))) {
          ei++;
        }
        while (ej < b.length && _isDigit(b.codeUnitAt(ej))) {
          ej++;
        }
        final na = int.tryParse(a.substring(i, ei));
        final nb = int.tryParse(b.substring(j, ej));
        if (na != null && nb != null && na != nb) return na.compareTo(nb);
        i = ei;
        j = ej;
        continue;
      }
      if (ca != cb) return ca.compareTo(cb);
      i++;
      j++;
    }
    return (a.length - i).compareTo(b.length - j);
  }

  static bool _isDigit(int codeUnit) => codeUnit >= 0x30 && codeUnit <= 0x39;

  /// Entries whose name contains [query], case-insensitively. An empty query
  /// keeps everything, so a stack with no filter shows the whole folder.
  static List<DockStackEntry> filter(
    List<DockStackEntry> entries,
    String query,
  ) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return entries;
    return [
      for (final entry in entries)
        if (entry.name.toLowerCase().contains(needle)) entry,
    ];
  }

  /// A browser's download in progress: Firefox writes `name.part`, the
  /// Chromium family `name.crdownload`.
  static bool isPartialDownload(String name) {
    final lower = name.toLowerCase();
    return lower.endsWith('.part') || lower.endsWith('.crdownload');
  }

  /// The number of partial downloads still being written in [entries]. A
  /// leftover `.part` from a killed browser is not one: the file has to have
  /// changed within the last ten seconds.
  static int liveDownloads(List<DockStackEntry> entries, {DateTime? now}) {
    final clock = now ?? DateTime.now();
    var count = 0;
    for (final entry in entries) {
      if (!isPartialDownload(entry.name)) continue;
      if (clock.difference(entry.modifiedAt).inSeconds.abs() <= 10) count++;
    }
    return count;
  }

  /// How far the downloads in a folder have got, or null when none is running.
  ///
  /// Browsers record no total anywhere the dock can read: Chrome's partial file
  /// simply grows, and its history row appears only once the transfer is done.
  /// So a folder whose partials are sparse — the file reserves its final size
  /// up front, which torrent clients, aria2 and `curl -C` do — reports a real
  /// fraction, and a folder of browser downloads reports no fraction at all
  /// rather than inventing one.
  static DockDownloadProgress? progress(
    List<DockStackEntry> entries, {
    DateTime? now,
  }) {
    final clock = now ?? DateTime.now();
    final live = <String>[];
    for (final entry in entries) {
      if (!isPartialDownload(entry.name)) continue;
      if (clock.difference(entry.modifiedAt).inSeconds.abs() > 10) continue;
      live.add(entry.path);
    }
    if (live.isEmpty) return null;
    final sparse = allocatedFraction(live);
    return DockDownloadProgress(files: live.length, fraction: sparse);
  }

  /// The written share of each file's reserved size, summed, or null when no
  /// file is sparse and the total therefore unknown.
  ///
  /// `st_blocks` is not exposed by Dart's `FileStat`, so this asks `stat(1)`,
  /// which is coreutils on every Linux system the shell runs on. Called once
  /// per poll while a download is live, never per file.
  static double? allocatedFraction(List<String> paths) {
    if (paths.isEmpty) return null;
    final List<String> lines;
    try {
      final result = Process.runSync('stat', [
        '--printf',
        '%s %b %B\n',
        ...paths,
      ], runInShell: false);
      if (result.exitCode != 0) return null;
      lines = '${result.stdout}'.split('\n');
    } on ProcessException {
      return null;
    }
    var written = 0.0;
    var reserved = 0.0;
    var anySparse = false;
    for (final line in lines) {
      final fields = line.trim().split(' ');
      if (fields.length != 3) continue;
      final size = double.tryParse(fields[0]);
      final blocks = double.tryParse(fields[1]);
      final unit = double.tryParse(fields[2]);
      if (size == null || blocks == null || unit == null) continue;
      if (size <= 0) continue;
      final allocated = blocks * unit;
      // A dense file has allocated == size, which says nothing about progress;
      // only a file that reserved more than it has written carries a fraction.
      if (allocated < size * 0.999) {
        anySparse = true;
        written += allocated;
        reserved += size;
      }
    }
    if (!anySparse || reserved <= 0) return null;
    return (written / reserved).clamp(0.0, 1.0);
  }
}

/// Downloads in progress inside one stack folder.
class DockDownloadProgress {
  const DockDownloadProgress({required this.files, this.fraction});

  /// How many transfers are running.
  final int files;

  /// Completed share of the reserved bytes, or null when no total exists.
  final double? fraction;

  /// True when the folder reserves its final size, so [fraction] is real.
  bool get determinate => fraction != null;

  /// The bar's fill, 0 to 1. An indeterminate transfer draws a short sweep
  /// rather than a full bar, so this is only read when [determinate].
  double get value => (fraction ?? 0).clamp(0.0, 1.0);
}
