import 'dart:io';

/// How a folder stack orders its entries. `added` is the Finder default for a
/// Stack: the file that arrived last sits closest to the icon.
enum DockStackSort { added, modified, name, kind }

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
        if (entries.length >= limit) break;
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
    sortEntries(entries, sort);
    return entries;
  }

  /// Orders [entries] in place. Folders come first only where the reference
  /// groups them; by date they mix with files, the way a macOS Stack does.
  static void sortEntries(List<DockStackEntry> entries, DockStackSort sort) {
    entries.sort((a, b) {
      if ((sort == DockStackSort.name || sort == DockStackSort.kind) &&
          a.isDirectory != b.isDirectory) {
        return a.isDirectory ? -1 : 1;
      }
      final byKey = switch (sort) {
        DockStackSort.added => b.addedAt.compareTo(a.addedAt),
        DockStackSort.modified => b.modifiedAt.compareTo(a.modifiedAt),
        DockStackSort.kind => a.extension.compareTo(b.extension),
        DockStackSort.name => 0,
      };
      return byKey != 0 ? byKey : naturalCompare(a.name, b.name);
    });
  }

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
}
