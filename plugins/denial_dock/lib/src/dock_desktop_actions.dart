import 'dart:io';

/// One `[Desktop Action …]` group of a desktop file: the extra entries an
/// application offers besides starting, such as a browser's private window.
class DesktopAction {
  const DesktopAction({
    required this.id,
    required this.name,
    required this.argv,
  });

  final String id;
  final String name;

  /// The command, already split and without field codes.
  final List<String> argv;
}

/// Reads the actions out of desktop files. Denial's application catalog does
/// not carry them, so the dock looks the file up itself, the way Plasma's task
/// manager builds its jump list.
abstract final class DesktopActions {
  /// Most menus stop being readable past a handful of rows.
  static const int limit = 8;

  /// The actions [content] declares, in the order of its `Actions=` key.
  /// [locale] is a language tag such as `zh_CN`; a name in that language wins
  /// over the plain one.
  static List<DesktopAction> parse(String content, {String? locale}) {
    final groups = <String, Map<String, String>>{};
    Map<String, String>? group;
    for (final raw in content.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      if (line.startsWith('[') && line.endsWith(']')) {
        group = groups.putIfAbsent(
          line.substring(1, line.length - 1),
          () => {},
        );
        continue;
      }
      final equals = line.indexOf('=');
      if (group == null || equals <= 0) continue;
      group.putIfAbsent(
        line.substring(0, equals).trim(),
        () => line.substring(equals + 1).trim(),
      );
    }
    final entry = groups['Desktop Entry'];
    if (entry == null) return const [];
    final actions = <DesktopAction>[];
    for (final id in (entry['Actions'] ?? '').split(';')) {
      final key = id.trim();
      if (key.isEmpty) continue;
      final action = groups['Desktop Action $key'];
      if (action == null) continue;
      final name = _localized(action, 'Name', locale);
      final command = argv(action['Exec'] ?? '');
      if (name == null || name.isEmpty || command.isEmpty) continue;
      actions.add(DesktopAction(id: key, name: name, argv: command));
      if (actions.length >= limit) break;
    }
    return actions;
  }

  static String? _localized(
    Map<String, String> group,
    String key,
    String? locale,
  ) {
    if (locale != null && locale.isNotEmpty) {
      final tag = locale.replaceAll('-', '_');
      final language = tag.split('_').first;
      final value = group['$key[$tag]'] ?? group['$key[$language]'];
      if (value != null) return _unescape(value);
    }
    final value = group[key];
    return value == null ? null : _unescape(value);
  }

  /// The escapes the specification defines for a string value. Anything else
  /// keeps its backslash, which the quoting rules of `Exec=` still need.
  static String _unescape(String value) => value.replaceAllMapped(
    RegExp(r'\\(.)'),
    (match) => switch (match[1]) {
      's' => ' ',
      'n' => '\n',
      't' => '\t',
      'r' => '\r',
      r'\' => r'\',
      _ => match[0]!,
    },
  );

  /// Splits an `Exec=` value the way the Desktop Entry specification quotes
  /// it and drops the field codes: an action starts with no file to pass.
  static List<String> argv(String exec) {
    final text = _unescape(exec);
    final words = <String>[];
    final word = StringBuffer();
    var quoted = false;
    var started = false;
    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      if (quoted) {
        if (char == r'\' && i + 1 < text.length) {
          word.write(text[++i]);
        } else if (char == '"') {
          quoted = false;
        } else {
          word.write(char);
        }
        continue;
      }
      if (char == '"') {
        quoted = true;
        started = true;
      } else if (char == ' ' || char == '\t') {
        if (started) words.add(word.toString());
        word.clear();
        started = false;
      } else if (char == '%' && i + 1 < text.length) {
        // `%%` is a literal percent sign; every other code names a file, a
        // URL or a piece of the entry that an action launch does not have.
        if (text[++i] == '%') {
          word.write('%');
          started = true;
        }
      } else {
        word.write(char);
        started = true;
      }
    }
    if (started) words.add(word.toString());
    return words;
  }

  /// The `applications` directories to search, most specific first.
  static List<String> directories(Map<String, String> environment) {
    final home = environment['HOME'];
    final dataHome = environment['XDG_DATA_HOME'];
    final dataDirs = environment['XDG_DATA_DIRS'];
    final roots = <String>[
      if (dataHome != null && dataHome.startsWith('/'))
        dataHome
      else if (home != null && home.startsWith('/'))
        '$home/.local/share',
      if (dataDirs != null && dataDirs.isNotEmpty)
        ...dataDirs.split(':').where((dir) => dir.startsWith('/'))
      else ...[
        '/usr/local/share',
        '/usr/share',
      ],
      if (home != null && home.startsWith('/'))
        '$home/.local/share/flatpak/exports/share',
      '/var/lib/flatpak/exports/share',
      '/var/lib/snapd/desktop',
    ];
    final seen = <String>{};
    return [
      for (final root in roots)
        if (seen.add(root.replaceFirst(RegExp(r'/+$'), '')))
          '${root.replaceFirst(RegExp(r'/+$'), '')}/applications',
    ];
  }

  /// A launch identity as a desktop file name: without the `desktop:` prefix
  /// the launcher's recents carry, and with the suffix.
  static String? fileName(String id) {
    var text = id.trim();
    final colon = text.indexOf(':');
    if (colon >= 0) text = text.substring(colon + 1);
    if (text.isEmpty || text.contains('/')) return null;
    return text.endsWith('.desktop') ? text : '$text.desktop';
  }

  /// The actions of the first desktop file one of [ids] names.
  static Future<List<DesktopAction>> load(
    Iterable<String> ids, {
    String? locale,
    Map<String, String>? environment,
  }) async {
    final names = <String>[];
    for (final id in ids) {
      final name = fileName(id);
      if (name != null && !names.contains(name)) names.add(name);
    }
    if (names.isEmpty) return const [];
    final lower = {for (final name in names) name.toLowerCase()};
    for (final directory in directories(environment ?? Platform.environment)) {
      for (final name in names) {
        final actions = await _read(File('$directory/$name'), locale);
        if (actions != null) return actions;
      }
      // A window's app id is often the file name in another case.
      try {
        await for (final entity in Directory(directory).list()) {
          if (entity is! File) continue;
          final base = entity.path.substring(entity.path.lastIndexOf('/') + 1);
          if (!lower.contains(base.toLowerCase())) continue;
          final actions = await _read(entity, locale);
          if (actions != null) return actions;
        }
      } on FileSystemException {
        continue;
      }
    }
    return const [];
  }

  static Future<List<DesktopAction>?> _read(File file, String? locale) async {
    try {
      if (!await file.exists()) return null;
      return parse(await file.readAsString(), locale: locale);
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
  }

  static Future<bool> run(DesktopAction action) async {
    if (action.argv.isEmpty) return false;
    try {
      await Process.start(
        action.argv.first,
        action.argv.sublist(1),
        mode: ProcessStartMode.detached,
      );
      return true;
    } on ProcessException {
      return false;
    }
  }
}
