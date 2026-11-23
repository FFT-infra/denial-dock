import 'dart:io';

import 'package:denial_dock/src/dock_extras.dart';

Future<void> main() async {
  // XDG resolution follows the base directory spec.
  _expect(
    DockExtras.dataHome({'XDG_DATA_HOME': '/data', 'HOME': '/home/me'}) ==
        '/data',
    'xdg data home',
  );
  _expect(
    DockExtras.dataHome({'XDG_DATA_HOME': 'relative', 'HOME': '/home/me'}) ==
        '/home/me/.local/share',
    'relative xdg falls back',
  );
  _expect(DockExtras.dataHome({}) == null, 'no home');
  _expect(
    DockExtras.homeTrash({'HOME': '/home/me'}) == '/home/me/.local/share/Trash',
    'home trash',
  );

  // Trash roots: home first, then per-mount candidates; root itself skipped.
  final roots = DockExtras.trashRoots(
    env: {'HOME': '/home/me'},
    uid: 1000,
    mountPoints: const ['/', '/mnt/usb', '/media/card/'],
  );
  _expect(
    _same(roots, [
      '/home/me/.local/share/Trash',
      '/mnt/usb/.Trash-1000',
      '/mnt/usb/.Trash/1000',
      '/media/card/.Trash-1000',
      '/media/card/.Trash/1000',
    ]),
    'trash roots $roots',
  );

  // Counting and emptying work on a real directory tree, and the matching
  // .trashinfo entries go with the items.
  final sandbox = Directory.systemTemp.createTempSync('dock_extras_test');
  try {
    final trash = Directory('${sandbox.path}/Trash');
    final files = Directory('${trash.path}/files')..createSync(recursive: true);
    final info = Directory('${trash.path}/info')..createSync(recursive: true);
    File('${files.path}/one.txt').writeAsStringSync('x');
    Directory('${files.path}/two').createSync();
    File('${files.path}/two/inside.txt').writeAsStringSync('y');
    File('${info.path}/one.txt.trashinfo').writeAsStringSync('[Trash Info]');
    File('${info.path}/two.trashinfo').writeAsStringSync('[Trash Info]');

    final custom = [trash.path, '${sandbox.path}/missing'];
    _expect(DockExtras.countTrash(custom) == 2, 'trash count');
    _expect(DockExtras.countTrash(const ['/nonexistent']) == 0, 'missing root');

    final removed = await DockExtras.emptyTrash(custom);
    _expect(removed == 2, 'removed $removed');
    _expect(DockExtras.countTrash(custom) == 0, 'trash emptied');
    _expect(
      info.listSync().isEmpty,
      'trashinfo emptied: ${info.listSync().length}',
    );

    // Directory listing returns subdirectories only, sorted.
    Directory('${sandbox.path}/b').createSync();
    Directory('${sandbox.path}/a').createSync();
    File('${sandbox.path}/file').writeAsStringSync('');
    final listed = DockExtras.listDirectories(sandbox.path);
    _expect(
      _same(listed, [
        '${sandbox.path}/Trash',
        '${sandbox.path}/a',
        '${sandbox.path}/b',
      ]),
      'list dirs $listed',
    );
    _expect(
      DockExtras.listDirectories('${sandbox.path}/nope').isEmpty,
      'missing dir',
    );

    // Pinnable files: hidden entries stay out unless asked for.
    File('${sandbox.path}/.secret').writeAsStringSync('');
    final visibleFiles = DockExtras.listFiles(sandbox.path);
    _expect(
      _same(visibleFiles, ['${sandbox.path}/file']),
      'list visible files $visibleFiles',
    );
    final allFiles = DockExtras.listFiles(sandbox.path, hidden: true);
    _expect(
      _same(allFiles, ['${sandbox.path}/.secret', '${sandbox.path}/file']),
      'list hidden files $allFiles',
    );
    _expect(
      DockExtras.listFiles('${sandbox.path}/nope').isEmpty,
      'missing dir files',
    );
  } finally {
    sandbox.deleteSync(recursive: true);
  }

  // Mount parsing tolerates the octal escapes the kernel writes.
  final mounts = File('${Directory.systemTemp.path}/dock_mounts_${pid}.txt');
  try {
    mounts.writeAsStringSync(
      'proc /proc proc rw 0 0\n'
      'pstore /sys/fs/pstore pstore rw,nosuid,nodev,noexec,relatime 0 0\n'
      'tmpfs /run tmpfs rw,nosuid,nodev 0 0\n'
      '/dev/sda1 /mnt/My\\040Disk ext4 rw 0 0\n'
      '/dev/sdb1 /mnt/My\\040Disk ext4 rw 0 0\n',
    );
    final points = DockExtras.readMountPoints(path: mounts.path);
    // The kernel-only filesystems are dropped; /run (tmpfs) is kept because
    // tmpfs is a real mount a user could open.
    _expect(_same(points, ['/run', '/mnt/My Disk']), 'mounts $points');
  } finally {
    if (mounts.existsSync()) mounts.deleteSync();
  }
  _expect(
    DockExtras.readMountPoints(path: '/definitely/not/here').isEmpty,
    'missing mounts file',
  );

  // The shell exports no WAYLAND_DISPLAY, so the opener needs one: the
  // highest-numbered socket in the runtime directory.
  final runtime = Directory.systemTemp.createTempSync('dock_runtime');
  try {
    File('${runtime.path}/wayland-1').writeAsStringSync('');
    File('${runtime.path}/wayland-1.lock').writeAsStringSync('');
    File('${runtime.path}/wayland-12').writeAsStringSync('');
    File('${runtime.path}/wayland-12.lock').writeAsStringSync('');
    File('${runtime.path}/bus').writeAsStringSync('');
    _expect(
      DockExtras.discoverWaylandDisplay(
            env: const {'XDG_RUNTIME_DIR': '/run/user/1000'},
            runtimeDir: runtime.path,
          ) ==
          'wayland-12',
      'display picked',
    );
    _expect(
      DockExtras.discoverWaylandDisplay(
            env: const {'WAYLAND_DISPLAY': 'wayland-3'},
            runtimeDir: runtime.path,
          ) ==
          'wayland-3',
      'display env wins',
    );
    _expect(
      DockExtras.discoverWaylandDisplay(
            env: const {'XDG_RUNTIME_DIR': 'relative'},
            runtimeDir: null,
          ) ==
          null,
      'display relative runtime',
    );
    final override = DockExtras.openerEnvironment(
      env: {'XDG_RUNTIME_DIR': runtime.path},
    );
    _expect(
      override.length == 1 && override['WAYLAND_DISPLAY'] == 'wayland-12',
      'opener env override $override',
    );
    _expect(
      DockExtras.openerEnvironment(
        env: {'XDG_RUNTIME_DIR': runtime.path, 'WAYLAND_DISPLAY': 'wayland-12'},
      ).isEmpty,
      'opener env keeps a good display',
    );
    _expect(
      DockExtras.openerEnvironment(
        env: const {'XDG_RUNTIME_DIR': '/nonexistent/runtime'},
      ).isEmpty,
      'no socket means no override',
    );
  } finally {
    runtime.deleteSync(recursive: true);
  }

  // Opener commands: xdg-open first, gio as the fallback.
  _expect(
    _same(DockExtras.openCommand('/home/me/Docs'), [
      'xdg-open',
      '/home/me/Docs',
    ]),
    'open command',
  );
  _expect(
    _same(DockExtras.openFallback(DockExtras.trashUri), [
      'gio',
      'open',
      'trash:///',
    ]),
    'open fallback',
  );
  // The trash goes through gio first: xdg-open has no handler for the scheme
  // and still exits 0 after failing, so the caller cannot fall back on it.
  final trashCommands = DockExtras.trashCommands;
  _expect(
    _same(trashCommands.first, ['gio', 'open', 'trash:///']),
    'trash command prefers gio',
  );
  // Revealing a file selects it in the running file manager over D-Bus, with
  // the path escaped as a file URI.
  final reveal = DockExtras.revealCommand('/home/me/a b.pdf');
  _expect(
    reveal.contains('org.freedesktop.FileManager1.ShowItems') &&
        reveal.contains('array:string:file:///home/me/a%20b.pdf') &&
        reveal.first == 'dbus-send',
    'reveal command $reveal',
  );

  stdout.writeln('All dock extras tests passed.');
}

bool _same(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
