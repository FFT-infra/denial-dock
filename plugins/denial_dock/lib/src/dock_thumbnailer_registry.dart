import 'dart:io';

/// One freedesktop `.thumbnailer` registration parsed from
/// `/usr/share/thumbnailers` or `$XDG_DATA_DIRS/thumbnailers`.
class ThumbnailerEntry {
  const ThumbnailerEntry({
    required this.name,
    required this.tryExec,
    required this.exec,
    required this.mimeTypes,
  });

  final String name;
  final String? tryExec;
  final String exec;
  final Set<String> mimeTypes;

  /// Parses the INI text of a `.thumbnailer` file. Returns null when the file
  /// lacks a `[Thumbnailer Entry]` section, an `Exec` line, or `MimeType`s.
  static ThumbnailerEntry? parse(String name, String content) {
    var inSection = false;
    String? tryExec;
    String? exec;
    final mimes = <String>{};
    for (final raw in content.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      if (line.startsWith('[') && line.endsWith(']')) {
        inSection = line == '[Thumbnailer Entry]';
        continue;
      }
      if (!inSection) continue;
      final eq = line.indexOf('=');
      if (eq <= 0) continue;
      final key = line.substring(0, eq).trim();
      final value = line.substring(eq + 1).trim();
      if (value.isEmpty) continue;
      switch (key) {
        case 'TryExec':
          tryExec = value;
        case 'Exec':
          exec = value;
        case 'MimeType':
          for (final part in value.split(';')) {
            final mime = part.trim().toLowerCase();
            if (mime.isNotEmpty) mimes.add(mime);
          }
      }
    }
    if (exec == null || exec.isEmpty || mimes.isEmpty) return null;
    return ThumbnailerEntry(
      name: name,
      tryExec: tryExec,
      exec: exec,
      mimeTypes: mimes,
    );
  }

  /// Expands `%s`, `%u`, `%i`, `%o` into argv tokens respecting quotes.
  List<String> expand({
    required String inputPath,
    required String outputPath,
    required int size,
  }) {
    final uri = Uri.file(inputPath).toString();
    final sizeText = '$size';
    final rawTokens = splitCommandLine(exec);
    final out = <String>[];
    for (final token in rawTokens) {
      if (token == '%s') {
        out.add(sizeText);
      } else if (token == '%u') {
        out.add(uri);
      } else if (token == '%i') {
        out.add(inputPath);
      } else if (token == '%o') {
        out.add(outputPath);
      } else {
        out.add(
          token
              .replaceAll('%s', sizeText)
              .replaceAll('%u', uri)
              .replaceAll('%i', inputPath)
              .replaceAll('%o', outputPath),
        );
      }
    }
    return out;
  }

  /// Splits a desktop/thumbnailer `Exec` line into argv tokens.
  static List<String> splitCommandLine(String command) {
    final tokens = <String>[];
    final buf = StringBuffer();
    String? quote;
    var escape = false;
    var hasToken = false;
    for (var i = 0; i < command.length; i++) {
      final ch = command[i];
      if (escape) {
        buf.write(ch);
        escape = false;
        hasToken = true;
        continue;
      }
      if (ch == r'\' && quote != "'") {
        escape = true;
        continue;
      }
      if (quote != null) {
        if (ch == quote) {
          quote = null;
        } else {
          buf.write(ch);
        }
        continue;
      }
      if (ch == '"' || ch == "'") {
        quote = ch;
        hasToken = true;
        continue;
      }
      if (ch == ' ' || ch == '\t') {
        if (hasToken) {
          tokens.add(buf.toString());
          buf.clear();
          hasToken = false;
        }
        continue;
      }
      buf.write(ch);
      hasToken = true;
    }
    if (hasToken) tokens.add(buf.toString());
    return tokens;
  }
}

/// Discovers installed freedesktop `.thumbnailer` helpers, maps file extensions
/// to MIME types via `/usr/share/mime/globs2`, and wraps commands in `bwrap`
/// when available.
class ThumbnailerRegistry {
  ThumbnailerRegistry({
    required this.entries,
    required this.extToMime,
    required this.hasBwrap,
    required this.hasLib64,
    bool Function(String executable)? executableExists,
  }) : _executableExists = executableExists ?? _defaultExecutableExists;

  final List<ThumbnailerEntry> entries;
  final Map<String, String> extToMime;
  final bool hasBwrap;
  final bool hasLib64;
  final bool Function(String executable) _executableExists;

  final Map<String, bool> _execCache = <String, bool>{};

  static const Map<String, String> _fallbackMimes = <String, String>{
    'pdf': 'application/pdf',
    'mp4': 'video/mp4',
    'mov': 'video/quicktime',
    'm4v': 'video/x-m4v',
    'webm': 'video/webm',
    'mkv': 'video/x-matroska',
    'avi': 'video/x-msvideo',
    'ogv': 'video/ogg',
    'mpg': 'video/mpeg',
    'mpeg': 'video/mpeg',
    'epub': 'application/epub+zip',
    'ttf': 'font/ttf',
    'otf': 'font/otf',
    'docx':
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xlsx':
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'pptx':
        'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'odt': 'application/vnd.oasis.opendocument.text',
    'ods': 'application/vnd.oasis.opendocument.spreadsheet',
    'odp': 'application/vnd.oasis.opendocument.presentation',
  };

  /// Loads the system `.thumbnailer` registry and `/usr/share/mime/globs2`
  /// once. Intended to be called off the UI frame.
  factory ThumbnailerRegistry.loadSystem() {
    final env = Platform.environment;
    final home = env['HOME'];
    final dataHome = env['XDG_DATA_HOME'];
    final dataDirs = (env['XDG_DATA_DIRS'] ?? '/usr/local/share:/usr/share')
        .split(':')
        .where((s) => s.isNotEmpty)
        .toList();
    final dirs = <String>[
      if (dataHome != null && dataHome.startsWith('/'))
        '$dataHome/thumbnailers'
      else if (home != null && home.startsWith('/'))
        '$home/.local/share/thumbnailers',
      for (final d in dataDirs) '$d/thumbnailers',
      if (!dataDirs.contains('/usr/share')) '/usr/share/thumbnailers',
    ];
    final seenNames = <String>{};
    final entries = <ThumbnailerEntry>[];
    for (final dirPath in dirs) {
      final dir = Directory(dirPath);
      List<FileSystemEntity> list;
      try {
        list = dir.listSync(followLinks: false);
      } on FileSystemException {
        continue;
      }
      list.sort((a, b) => a.path.compareTo(b.path));
      for (final entity in list) {
        if (entity is! File || !entity.path.endsWith('.thumbnailer')) continue;
        final name = entity.path.split('/').last;
        if (!seenNames.add(name)) continue;
        try {
          final parsed = ThumbnailerEntry.parse(name, entity.readAsStringSync());
          if (parsed != null) entries.add(parsed);
        } on FileSystemException {
          continue;
        }
      }
    }
    final extToMime = _loadGlobs2('/usr/share/mime/globs2');
    return ThumbnailerRegistry(
      entries: entries,
      extToMime: extToMime,
      hasBwrap: _defaultExecutableExists('bwrap'),
      hasLib64: Directory('/lib64').existsSync(),
    );
  }

  /// Parses `/usr/share/mime/globs2` lines (`weight:mime:*.ext`) into a
  /// lowercase extension → MIME table, keeping the highest weight per ext.
  static Map<String, String> parseGlobs2(String content) {
    final best = <String, ({int weight, String mime})>{};
    for (final raw in content.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final parts = line.split(':');
      if (parts.length < 3) continue;
      final weight = int.tryParse(parts[0]) ?? 50;
      final mime = parts[1].trim().toLowerCase();
      final pattern = parts[2].trim().toLowerCase();
      if (!pattern.startsWith('*.')) continue;
      final ext = pattern.substring(2);
      if (ext.isEmpty ||
          ext.contains('*') ||
          ext.contains('?') ||
          ext.contains('[') ||
          ext.contains('.')) {
        continue;
      }
      final prev = best[ext];
      if (prev == null || weight > prev.weight) {
        best[ext] = (weight: weight, mime: mime);
      }
    }
    return <String, String>{
      for (final e in best.entries) e.key: e.value.mime,
    };
  }

  static Map<String, String> _loadGlobs2(String path) {
    try {
      return parseGlobs2(File(path).readAsStringSync());
    } on FileSystemException {
      return const <String, String>{};
    }
  }

  /// Resolves the MIME type of [filePath] by extension.
  String? mimeFor(String filePath) {
    final name = filePath.split('/').last;
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) return null;
    final ext = name.substring(dot + 1).toLowerCase();
    return extToMime[ext] ?? _fallbackMimes[ext];
  }

  bool _hasExec(String exe) =>
      _execCache.putIfAbsent(exe, () => _executableExists(exe));

  /// Whether [exe] exists on `PATH` (cached).
  bool hasExec(String exe) => _hasExec(exe);

  /// Finds the first runnable `.thumbnailer` entry matching [filePath].
  ThumbnailerEntry? match(String filePath) {
    final mime = mimeFor(filePath);
    if (mime == null) return null;
    for (final entry in entries) {
      if (!entry.mimeTypes.contains(mime)) continue;
      final probe = entry.tryExec ?? ThumbnailerEntry.splitCommandLine(entry.exec).firstOrNull;
      if (probe == null || probe.isEmpty) continue;
      if (_hasExec(probe)) return entry;
    }
    return null;
  }

  /// Wraps [argv] in `timeout --kill-after=2 <timeoutSeconds> bwrap ...` when
  /// `bwrap` is installed.
  ///
  /// When `bwrap` is absent, refuses to execute untrusted thumbnailers bare
  /// (`program: ''`, `sandboxed: false`) so downloads are never parsed
  /// unsandboxed with full compositor user rights.
  ///
  /// The sandbox exposes `/usr`, `/lib`, `/lib64` (if present), `/etc`, and
  /// [inputPath] read-only, binds [outputDir] read-write, clears the inherited
  /// environment, isolates network/PID/IPC namespaces, and dies with parent.
  ({String program, List<String> args, bool sandboxed}) buildCommand(
    List<String> argv, {
    required String inputPath,
    required String outputDir,
    int timeoutSeconds = 10,
  }) {
    if (argv.isEmpty || !hasBwrap) {
      return (program: '', args: const <String>[], sandboxed: false);
    }
    return (
      program: 'timeout',
      args: <String>[
        '--kill-after=2',
        '$timeoutSeconds',
        'bwrap',
        '--ro-bind',
        '/usr',
        '/usr',
        '--ro-bind',
        '/lib',
        '/lib',
        if (hasLib64) ...const <String>['--ro-bind', '/lib64', '/lib64'],
        '--ro-bind',
        '/etc',
        '/etc',
        '--ro-bind',
        inputPath,
        inputPath,
        '--bind',
        outputDir,
        outputDir,
        '--proc',
        '/proc',
        '--dev',
        '/dev',
        '--tmpfs',
        '/tmp',
        '--clearenv',
        '--setenv',
        'PATH',
        '/usr/bin:/bin',
        '--setenv',
        'LANG',
        'C.UTF-8',
        '--unshare-net',
        '--unshare-pid',
        '--unshare-ipc',
        '--die-with-parent',
        '--',
        ...argv,
      ],
      sandboxed: true,
    );
  }

  static bool _defaultExecutableExists(String exe) {
    if (exe.contains('/')) {
      try {
        return File(exe).existsSync();
      } on FileSystemException {
        return false;
      }
    }
    final pathEnv = Platform.environment['PATH'] ?? '/usr/bin:/bin';
    for (final dir in pathEnv.split(':')) {
      if (dir.isEmpty) continue;
      try {
        if (File('$dir/$exe').existsSync()) return true;
      } on FileSystemException {
        continue;
      }
    }
    return false;
  }
}
