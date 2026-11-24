import 'dart:convert';
import 'dart:io';

class RecentDocument {
  const RecentDocument({
    required this.path,
    required this.modified,
    required this.directory,
  });

  final String path;
  final DateTime modified;
  final bool directory;

  String get name {
    final parts = path.split('/').where((part) => part.isNotEmpty);
    return parts.isEmpty ? '/' : parts.last;
  }
}

final RegExp _bookmark = RegExp(
  r'<bookmark\s+href="([^"]+)"([^>]*)>(.*?)</bookmark>',
  dotAll: true,
);
final RegExp _modified = RegExp(r'modified="([^"]+)"');
final RegExp _mime = RegExp(r'<mime:mime-type\s+type="([^"]+)"');

/// Local files from a `recently-used.xbel` document, newest first.
List<RecentDocument> parseRecentDocuments(String xbel) {
  final documents = <RecentDocument>[];
  for (final match in _bookmark.allMatches(xbel)) {
    final uri = Uri.tryParse(match.group(1)!.replaceAll('&amp;', '&'));
    if (uri == null ||
        uri.scheme != 'file' ||
        uri.hasQuery ||
        uri.hasFragment) {
      continue;
    }
    final stamp = _modified.firstMatch(match.group(2)!)?.group(1);
    final modified = stamp == null ? null : DateTime.tryParse(stamp);
    if (modified == null) continue;
    documents.add(
      RecentDocument(
        path: uri.toFilePath(),
        modified: modified,
        directory:
            _mime.firstMatch(match.group(3)!)?.group(1) == 'inode/directory',
      ),
    );
  }
  documents.sort((a, b) => b.modified.compareTo(a.modified));
  return documents;
}

String? _home() {
  final home = Platform.environment['HOME'];
  return home != null && home.startsWith('/') ? home : null;
}

List<RecentDocument> readRecentDocuments({
  int limit = 10,
  DateTime? clearedAt,
}) {
  final home = _home();
  if (home == null) return const <RecentDocument>[];
  final env = Platform.environment['XDG_DATA_HOME'];
  final root = env != null && env.startsWith('/') ? env : '$home/.local/share';
  try {
    final all = parseRecentDocuments(
      File('$root/recently-used.xbel').readAsStringSync(),
    );
    return all
        .where(
          (document) =>
              (clearedAt == null || document.modified.isAfter(clearedAt)) &&
              FileSystemEntity.typeSync(document.path) !=
                  FileSystemEntityType.notFound,
        )
        .take(limit)
        .toList();
  } on FileSystemException {
    return const <RecentDocument>[];
  }
}

class Place {
  const Place(this.uri, this.label);

  final String uri;
  final String label;

  /// Anything that is not a local folder is a server.
  bool get remote => !uri.startsWith('file://');
}

/// The sidebar bookmarks of the file manager, from a GTK `bookmarks` file:
/// one `uri optional label` per line.
List<Place> parseGtkBookmarks(String text) {
  final places = <Place>[];
  for (final raw in text.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final space = line.indexOf(' ');
    final address = space < 0 ? line : line.substring(0, space);
    final uri = Uri.tryParse(address);
    if (uri == null || !uri.hasScheme) continue;
    var label = space < 0 ? '' : line.substring(space + 1).trim();
    if (label.isEmpty) {
      final parts = uri.pathSegments.where((part) => part.isNotEmpty);
      label = parts.isEmpty ? uri.host : parts.last;
    }
    if (label.isEmpty) continue;
    places.add(Place(address, label));
  }
  return places;
}

List<Place> readPlaces() {
  final home = _home();
  if (home == null) return const <Place>[];
  final env = Platform.environment['XDG_CONFIG_HOME'];
  final root = env != null && env.startsWith('/') ? env : '$home/.config';
  for (final name in const <String>['gtk-3.0/bookmarks', 'gtk-4.0/bookmarks']) {
    try {
      final places = parseGtkBookmarks(File('$root/$name').readAsStringSync());
      if (places.isNotEmpty) return places;
    } on FileSystemException {
      continue;
    }
  }
  return const <Place>[];
}

/// Application ids the dock remembers as recently used, newest first.
List<String> readRecentApplicationIds() {
  final home = _home();
  if (home == null) return const <String>[];
  final env = Platform.environment['XDG_CONFIG_HOME'];
  final root = env != null && env.startsWith('/') ? env : '$home/.config';
  try {
    final json = jsonDecode(
      File('$root/denial/plugins/denial_dock.json').readAsStringSync(),
    );
    if (json is! Map<String, dynamic>) return const <String>[];
    final ids = <String>[];
    for (final key in const <String>['recentsOrder', 'parkedRecents']) {
      final value = json[key];
      if (value is! List) continue;
      final list = value.whereType<String>().toList();
      // The dock keeps its visible recents oldest-first.
      ids.addAll(key == 'recentsOrder' ? list.reversed : list);
    }
    return ids;
  } on FileSystemException {
    return const <String>[];
  } on FormatException {
    return const <String>[];
  }
}

void openPath(String path) {
  Process.start('xdg-open', <String>[
    path,
  ], mode: ProcessStartMode.detached).then((_) {}, onError: (_) {});
}
