import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'dock_stack_thumbs.dart' show dockThumbsRevision;

/// Resolves system freedesktop icon theme MIME PNG icons for files that have
/// no thumbnail (folder stacks and pinned single files).
///
/// Lookup during widget `build()` ([iconPathCached]) is strictly in-memory
/// with zero filesystem IO. All `/usr/share/mime/globs2` parsing and icon
/// directory scanning run asynchronously via [request] and broadcast updates
/// on [dockThumbsRevision].
abstract final class DockMimeIcons {
  static bool _loaded = false;
  static Future<void>? _loading;

  /// Lower-case extension -> MIME type (e.g. `pdf` -> `application/pdf`).
  static final Map<String, String> _extToMime = <String, String>{};

  /// MIME type or generic icon name -> resolved PNG path (or null if absent).
  static final Map<String, String?> _mimeToPng = <String, String?>{};

  /// Icon name (without `.png`) -> resolved PNG path from active icon themes.
  static final Map<String, String> _iconIndex = <String, String>{};

  /// Purely in-memory lookup safe to call inside `build()`.
  static String? iconPathCached(String filePath) {
    if (!_loaded) return null;
    final ext = _extOf(filePath);
    if (ext.isEmpty) return null;
    final mime = _extToMime[ext];
    if (mime == null) return null;
    if (_mimeToPng.containsKey(mime)) return _mimeToPng[mime];
    final resolved = _lookupMime(mime);
    _mimeToPng[mime] = resolved;
    return resolved;
  }

  /// Ensures MIME tables and icon theme directories are indexed asynchronously,
  /// then notifies listeners if any path in [paths] gained a MIME icon.
  static Future<void> request(Iterable<String> paths) async {
    if (_loaded) return;
    await (_loading ??= _load());
    final hasHit = paths.any((p) => iconPathCached(p) != null);
    if (hasHit) {
      // Bump shared revision so DockFolderItem / DockFileItem / DockStackView
      // repaint with newly indexed MIME icons.
      dockThumbsRevision.notify();
    }
  }

  /// Parses `/usr/share/mime/globs2` lines (`weight:mime:*.ext`).
  /// Exposed for unit tests.
  static Map<String, String> parseGlobs2(String content) {
    final weights = <String, int>{};
    final result = <String, String>{};
    for (final raw in const LineSplitter().convert(content)) {
      if (raw.isEmpty || raw.startsWith('#')) continue;
      final parts = raw.split(':');
      if (parts.length < 3) continue;
      final weight = int.tryParse(parts[0]) ?? 50;
      final mime = parts[1].trim();
      final glob = parts[2].trim();
      if (!glob.startsWith('*.') || glob.contains('/', 2)) continue;
      final ext = glob.substring(2).toLowerCase();
      if (ext.isEmpty || ext.contains('*') || ext.contains('?')) continue;
      final prev = weights[ext];
      if (prev == null || weight > prev) {
        weights[ext] = weight;
        result[ext] = mime;
      }
    }
    return result;
  }

  /// Candidate freedesktop icon names for [mime], ordered most-specific first.
  static List<String> iconCandidates(String mime) {
    final slash = mime.indexOf('/');
    if (slash <= 0 || slash == mime.length - 1) return const <String>[];
    final major = mime.substring(0, slash);
    final minor = mime.substring(slash + 1);
    final dashed = '$major-$minor';
    final cleanMinor = minor.startsWith('x-') ? minor.substring(2) : minor;
    return <String>[
      dashed,
      'gnome-mime-$dashed',
      if (cleanMinor != minor) '$major-$cleanMinor',
      if (minor == 'pdf') 'application-pdf',
      if (minor.contains('zip') || minor.contains('tar') || minor.contains('gzip'))
        'package-x-generic',
      '$major-x-generic',
      'text-x-generic',
    ];
  }

  static String? _lookupMime(String mime) {
    for (final name in iconCandidates(mime)) {
      final hit = _iconIndex[name];
      if (hit != null) return hit;
    }
    return null;
  }

  static Future<void> _load() async {
    try {
      await _loadGlobs();
      await _loadIconThemes();
    } finally {
      _loaded = true;
    }
  }

  static Future<void> _loadGlobs() async {
    final env = Platform.environment;
    final home = env['HOME'];
    final candidates = <String>[
      '/usr/share/mime/globs2',
      '/usr/local/share/mime/globs2',
      if (home != null && home.startsWith('/'))
        '$home/.local/share/mime/globs2',
    ];
    for (final path in candidates) {
      final file = File(path);
      try {
        if (!await file.exists()) continue;
        final text = await file.readAsString();
        _extToMime.addAll(parseGlobs2(text));
      } on FileSystemException {
        continue;
      }
    }
  }

  static Future<void> _loadIconThemes() async {
    final themes = await _discoverThemes();
    final home = Platform.environment['HOME'];
    final roots = <String>[
      if (home != null && home.startsWith('/')) '$home/.local/share/icons',
      if (home != null && home.startsWith('/')) '$home/.icons',
      '/usr/local/share/icons',
      '/usr/share/icons',
    ];
    const sizes = <String>[
      '64x64/mimetypes',
      '48x48/mimetypes',
      '128x128/mimetypes',
      '32x32/mimetypes',
      'mimetypes/64',
      'mimetypes/48',
    ];
    for (final theme in themes) {
      for (final root in roots) {
        for (final sub in sizes) {
          final dir = Directory('$root/$theme/$sub');
          try {
            if (!await dir.exists()) continue;
            await for (final entity in dir.list(followLinks: true)) {
              final path = entity.path;
              if (!path.endsWith('.png')) continue;
              final base = path.split('/').last;
              final name = base.substring(0, base.length - 4);
              _iconIndex.putIfAbsent(name, () => path);
            }
          } on FileSystemException {
            continue;
          }
        }
      }
    }
  }

  static Future<List<String>> _discoverThemes() async {
    final ordered = <String>[];
    void add(String? name) {
      final clean = name?.trim();
      if (clean != null && clean.isNotEmpty && !ordered.contains(clean)) {
        ordered.add(clean);
      }
    }

    final home = Platform.environment['HOME'];
    if (home != null && home.startsWith('/')) {
      add(await _readIniValue('$home/.config/gtk-3.0/settings.ini', 'gtk-icon-theme-name'));
      add(await _readIniValue('$home/.config/gtk-4.0/settings.ini', 'gtk-icon-theme-name'));
      add(await _readIniValue('$home/.config/kdeglobals', 'Theme'));
    }
    for (final fallback in const <String>[
      'Papirus',
      'Papirus-Dark',
      'breeze',
      'breeze-dark',
      'Adwaita',
      'WhiteSur',
      'Tela',
      'hicolor',
    ]) {
      add(fallback);
    }
    return ordered;
  }

  static Future<String?> _readIniValue(String path, String key) async {
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      final prefix = '$key=';
      for (final line in const LineSplitter().convert(await file.readAsString())) {
        final trimmed = line.trim();
        if (trimmed.startsWith(prefix)) {
          return trimmed.substring(prefix.length).trim();
        }
      }
    } on FileSystemException {
      return null;
    }
    return null;
  }

  static String _extOf(String path) {
    final name = path.split('/').last;
    final dot = name.lastIndexOf('.');
    return dot <= 0 || dot == name.length - 1
        ? ''
        : name.substring(dot + 1).toLowerCase();
  }
}
