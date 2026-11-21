import 'dart:convert';
import 'dart:io';

/// Trash and folder-shortcut helpers. Denial exposes no trash or file-manager
/// service to plugins, so the dock works with the freedesktop trash layout and
/// hands paths to `xdg-open`.
///
/// Kept free of Flutter imports so the path and command rules can be tested
/// without a shell.
abstract final class DockExtras {
  /// `$XDG_DATA_HOME`, or `~/.local/share` when the variable is unset or not
  /// absolute, as the base directory specification requires.
  static String? dataHome(Map<String, String> env) {
    final configured = env['XDG_DATA_HOME'];
    if (configured != null && configured.startsWith('/')) return configured;
    final home = env['HOME'];
    if (home == null || !home.startsWith('/')) return null;
    return '$home/.local/share';
  }

  /// The home trash directory from the freedesktop trash specification.
  static String? homeTrash(Map<String, String> env) {
    final base = dataHome(env);
    return base == null ? null : '$base/Trash';
  }

  /// Candidate trash roots for [mountPoints], in home-first order. A root is
  /// only usable when it exists, so listing a mount that has no trash costs
  /// nothing.
  static List<String> trashRoots({
    required Map<String, String> env,
    required int uid,
    Iterable<String> mountPoints = const [],
  }) {
    final roots = <String>[];
    final home = homeTrash(env);
    if (home != null) roots.add(home);
    for (final mount in mountPoints) {
      if (!mount.startsWith('/') || mount == '/') continue;
      final base = mount.endsWith('/')
          ? mount.substring(0, mount.length - 1)
          : mount;
      roots.add('$base/.Trash-$uid');
      roots.add('$base/.Trash/$uid');
    }
    return roots;
  }

  /// The process uid, read from `/proc/self/status`. Trash directories on other
  /// mounts are keyed by it.
  static int? readUid({String path = '/proc/self/status'}) {
    try {
      for (final line in const LineSplitter().convert(
        File(path).readAsStringSync(),
      )) {
        final match = RegExp(r'^Uid:\s+(\d+)').firstMatch(line);
        if (match != null) return int.parse(match.group(1)!);
      }
    } on FileSystemException {
      return null;
    }
    return null;
  }

  /// Filesystems that never hold a trash directory. Probing them only produces
  /// permission errors — `/sys/fs/pstore` is root-only — so they are skipped
  /// when the mounts table is read.
  static const Set<String> _pseudoFilesystems = {
    'autofs',
    'bpf',
    'cgroup',
    'cgroup2',
    'configfs',
    'debugfs',
    'devpts',
    'devtmpfs',
    'fusectl',
    'hugetlbfs',
    'mqueue',
    'proc',
    'pstore',
    'ramfs',
    'securityfs',
    'sysfs',
    'tracefs',
  };

  /// Mount points from `/proc/self/mounts`, with pseudo filesystems left out.
  /// Unreadable or unparsable lines are skipped; a missing file yields an empty
  /// list.
  static List<String> readMountPoints({String path = '/proc/self/mounts'}) {
    final String contents;
    try {
      contents = File(path).readAsStringSync();
    } on FileSystemException {
      return const [];
    }
    final points = <String>[];
    for (final line in const LineSplitter().convert(contents)) {
      final parts = line.split(' ');
      if (parts.length < 2) continue;
      if (parts.length >= 3 && _pseudoFilesystems.contains(parts[2])) continue;
      // Octal escapes (\040 for a space) are part of the mounts format.
      final mount = parts[1].replaceAllMapped(
        RegExp(r'\\([0-7]{3})'),
        (match) => String.fromCharCode(int.parse(match[1]!, radix: 8)),
      );
      if (!points.contains(mount)) points.add(mount);
    }
    return points;
  }

  /// Number of items in the given trash roots. A root that does not exist or
  /// cannot be read contributes nothing.
  static int countTrash(Iterable<String> roots) {
    var count = 0;
    for (final root in roots) {
      final files = Directory('$root/files');
      try {
        // `existsSync` itself throws on a permission-denied parent, not just
        // returns false.
        if (!files.existsSync()) continue;
        count += files.listSync(followLinks: false).length;
      } on FileSystemException {
        continue;
      }
    }
    return count;
  }

  /// Deletes every item and its `.trashinfo`. Missing roots are ignored, and a
  /// single unreadable entry does not stop the rest.
  static Future<int> emptyTrash(Iterable<String> roots) async {
    var removed = 0;
    for (final root in roots) {
      for (final name in const ['files', 'info']) {
        final directory = Directory('$root/$name');
        List<FileSystemEntity> entries;
        try {
          if (!await directory.exists()) continue;
          entries = await directory.list(followLinks: false).toList();
        } on FileSystemException {
          continue;
        }
        for (final entry in entries) {
          try {
            await entry.delete(recursive: true);
            if (name == 'files') removed++;
          } on FileSystemException {
            continue;
          }
        }
      }
    }
    return removed;
  }

  /// Primary opener. `xdg-open` is the freedesktop entry point and handles both
  /// directories and the `trash:///` URI.
  static List<String> openCommand(String target) => ['xdg-open', target];

  /// Fallback when `xdg-open` is not installed; `gio open` ships with glib.
  static List<String> openFallback(String target) => ['gio', 'open', target];

  static const String trashUri = 'trash:///';

  /// Opens [target] with the session's default handler, falling back to gio.
  /// Returns false when neither helper exists.
  static Future<bool> openPath(String target) async {
    if (await _run(openCommand(target))) return true;
    return _run(openFallback(target));
  }

  static Future<bool> _run(List<String> command) async {
    try {
      final process = await Process.start(
        command.first,
        command.sublist(1),
        mode: ProcessStartMode.detached,
      );
      // A detached child reports its pid immediately; a missing binary throws.
      return process.pid > 0;
    } on ProcessException {
      return false;
    }
  }

  /// Immediate subdirectories of [path], sorted, hidden entries included so
  /// dot-folders remain reachable. Unreadable directories yield an empty list.
  static List<String> listDirectories(String path) {
    try {
      final entries = Directory(path)
          .listSync(followLinks: false)
          .whereType<Directory>()
          .map((directory) => directory.path)
          .toList();
      entries.sort();
      return entries;
    } on FileSystemException {
      return const [];
    }
  }
}
