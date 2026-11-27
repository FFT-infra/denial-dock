import 'dart:convert';
import 'dart:io';

/// `denial_shell_kit.json`: the settings the dock and the top bar share,
/// kept beside the plugins' own preferences.
///
/// A file without a version was written when the store held only the look,
/// which is what version 1 held. Version 3 added the looks and the presets
/// the user made, under `looks` and `userPresets`; it changed no older key,
/// so an older file is read as it is and gains the version at its next
/// write. A file with a newer version is read but
/// never written, so a build cannot drop settings it does not know; for the
/// same reason every write keeps the keys it was not asked to change.
class KitStore {
  KitStore(this.file);

  /// The version this build writes.
  static const int version = 3;

  /// Null when the program has no configuration directory; nothing is kept
  /// then.
  final File? file;

  static File? defaultFile() {
    final env = Platform.environment;
    final configured = env['XDG_CONFIG_HOME'];
    final home = env['HOME'];
    final root = configured != null && configured.startsWith('/')
        ? configured
        : home != null && home.startsWith('/')
        ? '$home/.config'
        : null;
    return root == null
        ? null
        : File('$root/denial/plugins/denial_shell_kit.json');
  }

  /// Where presets written out as files are kept: `presets` beside the
  /// store's own file. Null when there is no configuration directory.
  Directory? get presetsDirectory {
    final file = this.file;
    return file == null ? null : Directory('${file.parent.path}/presets');
  }

  Map<String, dynamic> read() {
    final file = this.file;
    if (file == null) return <String, dynamic>{};
    try {
      final json = jsonDecode(file.readAsStringSync());
      return json is Map<String, dynamic> ? json : <String, dynamic>{};
    } on Object {
      return <String, dynamic>{};
    }
  }

  /// Whether this build may write the file, decided once from its version.
  late final bool mayWrite = (() {
    final found = read()['version'];
    return found is! int || found <= version;
  })();

  /// Sets [key] and stamps the version, leaving every other key as it was.
  void put(String key, Object? value) {
    final file = this.file;
    if (file == null || !mayWrite) return;
    final json = read()
      ..['version'] = version
      ..[key] = value;
    try {
      file.parent.createSync(recursive: true);
      final temp = File('${file.path}.$pid.tmp')
        ..writeAsStringSync('${jsonEncode(json)}\n');
      temp.renameSync(file.path);
    } on FileSystemException {
      return;
    }
  }

  /// The dock shows unless the file says otherwise.
  static bool dockOf(Map<String, dynamic> json) => json['dock'] != false;

  static String? textOf(Map<String, dynamic> json, String key) {
    final value = json[key];
    return value is String ? value : null;
  }
}

/// Resolves effective shell UI scale against [hostScale] and optional [override].
double resolveKitScale(double hostScale, double? override) {
  final base = hostScale.isFinite && hostScale > 0 ? hostScale : 1.0;
  if (override == null || !override.isFinite) return base;
  return override.clamp(0.75, 1.50).toDouble();
}

/// The store every notifier of the kit reads and writes.
final KitStore kitStore = KitStore(KitStore.defaultFile());
