import 'dart:io';

/// One recent local document associated with an application from
/// `~/.local/share/recently-used.xbel`.
class DockRecentDocument {
  const DockRecentDocument({
    required this.path,
    required this.name,
    required this.modified,
    required this.applications,
  });

  final String path;
  final String name;
  final DateTime modified;
  final List<String> applications;
}

/// Async parser and mtime-cached index for `~/.local/share/recently-used.xbel`.
///
/// Safe for UI callers: `forAppCached` performs zero filesystem IO, while
/// `load` refreshes the cache asynchronously when the XBEL file's mtime changes.
abstract final class DockRecentDocs {
  static List<DockRecentDocument> _cached = const <DockRecentDocument>[];
  static DateTime? _cachedMtime;
  static Future<void>? _loading;

  /// Purely in-memory lookup of recent documents for an application.
  static List<DockRecentDocument> forAppCached({
    required String appId,
    required String name,
    int limit = 5,
  }) {
    if (_cached.isEmpty) return const <DockRecentDocument>[];
    final needles = _needles(appId, name);
    if (needles.isEmpty) return const <DockRecentDocument>[];
    final hits = <DockRecentDocument>[];
    for (final doc in _cached) {
      if (_matches(doc.applications, needles)) {
        hits.add(doc);
        if (hits.length >= limit) break;
      }
    }
    return hits;
  }

  /// Asynchronously reads `~/.local/share/recently-used.xbel` when modified.
  static Future<List<DockRecentDocument>> loadForApp({
    required String appId,
    required String name,
    int limit = 5,
  }) async {
    await (_loading ??= _refresh());
    return forAppCached(appId: appId, name: name, limit: limit);
  }

  static Future<void> _refresh() async {
    try {
      final path = _xbelPath();
      if (path == null) return;
      final file = File(path);
      if (!await file.exists()) return;
      final stat = await file.stat();
      if (_cachedMtime != null && _cachedMtime == stat.modified) return;
      final xml = await file.readAsString();
      final parsed = parseXbel(xml);
      final existing = <DockRecentDocument>[];
      for (final doc in parsed) {
        if (existing.length >= 60) break;
        try {
          if (await File(doc.path).exists()) existing.add(doc);
        } on FileSystemException {
          continue;
        }
      }
      _cached = existing;
      _cachedMtime = stat.modified;
    } on Object {
      // Malformed or missing XBEL is non-fatal.
    } finally {
      _loading = null;
    }
  }

  static String? _xbelPath() {
    final env = Platform.environment;
    final dataHome = env['XDG_DATA_HOME'];
    if (dataHome != null && dataHome.startsWith('/')) {
      return '$dataHome/recently-used.xbel';
    }
    final home = env['HOME'];
    if (home == null || !home.startsWith('/')) return null;
    return '$home/.local/share/recently-used.xbel';
  }

  static final RegExp _bookmarkRe = RegExp(
    r'<bookmark\s+([^>]+)>([\s\S]*?)</bookmark>',
  );
  static final RegExp _hrefRe = RegExp(r'href="([^"]+)"');
  static final RegExp _modifiedRe = RegExp(r'modified="([^"]+)"');
  static final RegExp _appRe = RegExp(
    r'<bookmark:application\s+[^>]*name="([^"]+)"',
  );

  /// Parses freedesktop XBEL XML into newest-first [DockRecentDocument]s.
  /// Pure Dart, exposed for unit tests.
  static List<DockRecentDocument> parseXbel(String xml) {
    final docs = <DockRecentDocument>[];
    for (final match in _bookmarkRe.allMatches(xml)) {
      final attrs = match.group(1) ?? '';
      final body = match.group(2) ?? '';
      final href = _hrefRe.firstMatch(attrs)?.group(1);
      if (href == null || !href.startsWith('file://')) continue;
      final String path;
      try {
        path = Uri.parse(_unescapeXml(href)).toFilePath();
      } on Object {
        continue;
      }
      if (path.isEmpty) continue;
      final name = path.split('/').last;
      if (name.isEmpty) continue;
      final modText = _modifiedRe.firstMatch(attrs)?.group(1);
      final modified =
          (modText != null ? DateTime.tryParse(modText) : null) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final apps = <String>[
        for (final appMatch in _appRe.allMatches(body))
          _unescapeXml(appMatch.group(1) ?? '').trim(),
      ]..removeWhere((s) => s.isEmpty);
      if (apps.isEmpty) continue;
      docs.add(
        DockRecentDocument(
          path: path,
          name: name,
          modified: modified,
          applications: apps,
        ),
      );
    }
    docs.sort((a, b) => b.modified.compareTo(a.modified));
    return docs;
  }

  static Set<String> _needles(String appId, String name) {
    final out = <String>{};
    void add(String raw) {
      final clean = raw
          .trim()
          .toLowerCase()
          .replaceFirst(RegExp(r'\.desktop$'), '')
          .replaceAll(RegExp(r'[\s._-]+'), '');
      if (clean.length >= 2) out.add(clean);
    }

    add(appId);
    final last = appId.split('.').last;
    add(last);
    add(name);
    return out;
  }

  static bool _matches(List<String> apps, Set<String> needles) {
    for (final app in apps) {
      final norm = app
          .trim()
          .toLowerCase()
          .replaceFirst(RegExp(r'\.desktop$'), '')
          .replaceAll(RegExp(r'[\s._-]+'), '');
      if (norm.isEmpty) continue;
      for (final needle in needles) {
        if (norm == needle || norm.contains(needle) || needle.contains(norm)) {
          return true;
        }
      }
    }
    return false;
  }

  static String _unescapeXml(String value) => value
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>');
}
