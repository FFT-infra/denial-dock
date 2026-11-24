import 'dart:io';

import 'package:denial_dock/src/dock_desktop_actions.dart';

const _chrome = '''
[Desktop Entry]
Name=Google Chrome
Exec=/usr/bin/google-chrome-stable %U
Actions=new-window;new-private-window;missing;broken;

# A comment between groups.
[Desktop Action new-window]
Name=New Window
Name[zh_CN]=新建窗口
Name[zh]=新視窗
Exec=/usr/bin/google-chrome-stable

[Desktop Action new-private-window]
Name=New Incognito Window
Name[zh]=无痕窗口
Exec=/usr/bin/google-chrome-stable --incognito %u

[Desktop Action broken]
Name=No command

[Desktop Action unlisted]
Name=Not in Actions
Exec=/bin/true
''';

void main() {
  // Only the actions the entry lists, in its order, and only complete ones.
  final actions = DesktopActions.parse(_chrome);
  _expect(
    actions.map((action) => action.id).join(',') ==
        'new-window,new-private-window',
    'listed and complete ${actions.map((action) => action.id)}',
  );
  _expect(actions.first.name == 'New Window', 'plain name');
  _expect(
    actions.last.argv.join('|') == '/usr/bin/google-chrome-stable|--incognito',
    'field code dropped ${actions.last.argv}',
  );

  // The exact locale wins, then the language, then the plain name.
  final chinese = DesktopActions.parse(_chrome, locale: 'zh_CN');
  _expect(chinese.first.name == '新建窗口', 'full locale');
  _expect(chinese.last.name == '无痕窗口', 'language only');
  final german = DesktopActions.parse(_chrome, locale: 'de-DE');
  _expect(german.first.name == 'New Window', 'unknown locale');

  _expect(DesktopActions.parse('').isEmpty, 'empty file');
  _expect(
    DesktopActions.parse('[Desktop Entry]\nName=x\n').isEmpty,
    'no actions key',
  );
  final many = StringBuffer('[Desktop Entry]\nActions=');
  for (var i = 0; i < 20; i++) {
    many.write('a$i;');
  }
  many.writeln();
  for (var i = 0; i < 20; i++) {
    many.writeln('[Desktop Action a$i]\nName=A$i\nExec=/bin/true');
  }
  _expect(
    DesktopActions.parse('$many').length == DesktopActions.limit,
    'capped',
  );

  // Quoting follows the Desktop Entry specification.
  _expect(
    DesktopActions.argv(r'sh -c "echo \"a b\" \$HOME" %F').join('|') ==
        r'sh|-c|echo "a b" $HOME',
    'quotes ${DesktopActions.argv(r'sh -c "echo \"a b\" \$HOME" %F')}',
  );
  _expect(
    DesktopActions.argv('app --name=%c --rate=50%% ""').join('|') ==
        'app|--name=|--rate=50%|',
    'codes inside a word ${DesktopActions.argv('app --name=%c --rate=50%% ""')}',
  );
  _expect(DesktopActions.argv('  ').isEmpty, 'blank command');
  _expect(DesktopActions.argv('%U').isEmpty, 'only a field code');

  _expect(
    DesktopActions.fileName('desktop:code.desktop') == 'code.desktop' &&
        DesktopActions.fileName('org.gnome.Nautilus') ==
            'org.gnome.Nautilus.desktop',
    'file names',
  );
  _expect(
    DesktopActions.fileName('../etc/passwd') == null &&
        DesktopActions.fileName(' ') == null,
    'no paths',
  );

  final dirs = DesktopActions.directories({
    'HOME': '/home/me',
    'XDG_DATA_DIRS': '/usr/share/:/opt/share:relative:/usr/share',
  });
  _expect(
    dirs.take(3).join('|') ==
        '/home/me/.local/share/applications|/usr/share/applications|'
            '/opt/share/applications',
    'directories $dirs',
  );
  _expect(
    DesktopActions.directories({}).first == '/usr/local/share/applications',
    'no home',
  );

  // The file is found by name, or by the same name in another case.
  final root = Directory.systemTemp.createTempSync('dock-actions');
  try {
    final apps = Directory('${root.path}/applications')..createSync();
    File('${apps.path}/Google-Chrome.desktop').writeAsStringSync(_chrome);
    final environment = {'XDG_DATA_HOME': root.path, 'XDG_DATA_DIRS': '/nope'};
    DesktopActions.load(
          ['missing', 'desktop:google-chrome.desktop'],
          locale: 'zh_CN',
          environment: environment,
        )
        .then((loaded) {
          _expect(loaded.length == 2 && loaded.first.name == '新建窗口', 'loaded');
          return DesktopActions.load([
            'nothing-here',
          ], environment: environment);
        })
        .then((none) {
          _expect(none.isEmpty, 'nothing found');
          root.deleteSync(recursive: true);
          stdout.writeln('All dock desktop action tests passed.');
        });
  } on Object {
    root.deleteSync(recursive: true);
    rethrow;
  }
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
