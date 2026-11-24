import 'dart:io';

import 'package:denial_topbar/src/l10n/tables.dart';
import 'package:denial_topbar/src/recent_items.dart';

void main() {
  const xbel = '''
<xbel>
  <bookmark href="file:///home/u/a%20b.pdf" added="2026-01-01T00:00:00Z" modified="2026-10-01T00:00:00Z">
    <info><metadata><mime:mime-type type="application/pdf"/></metadata></info>
  </bookmark>
  <bookmark href="file:///home/u/Project" modified="2026-11-01T00:00:00Z">
    <info><metadata><mime:mime-type type="inode/directory"/></metadata></info>
  </bookmark>
  <bookmark href="file:///" modified="2026-09-01T00:00:00Z"><info/></bookmark>
  <bookmark href="smb://server/share" modified="2026-12-01T00:00:00Z"><info/></bookmark>
</xbel>''';
  final documents = parseRecentDocuments(xbel);
  _expect(documents.length == 3, 'only local files are kept');
  _expect(documents.last.name == '/', 'the root has a name');
  _expect(documents.first.name == 'Project', 'newest first');
  _expect(documents.first.directory, 'directory mime is recognised');
  _expect(documents[1].name == 'a b.pdf', 'percent-encoding is decoded');

  // Every label the code asks for has a Chinese form.
  final call = RegExp(r"""\.tr\(\s*'((?:[^'\\]|\\.)*)'""");
  final keys = <String>{};
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    for (final match in call.allMatches(entity.readAsStringSync())) {
      final key = match.group(1)!.replaceAll(r"\'", "'");
      keys.add(key);
    }
  }
  for (final MapEntry(key: code, value: table) in barLabels.entries) {
    final missing = keys.difference(table.keys.toSet());
    _expect(missing.isEmpty, '$code lacks: $missing');
  }

  final places = parseGtkBookmarks(
    'file:///home/u/Documents\n'
    'file:///home/u/My%20Work Work files\n'
    '\n'
    'not a uri\n'
    'sftp://nas.local/share NAS\n'
    'smb://box/\n',
  );
  _expect(places.length == 4, 'bookmarks without a scheme are skipped');
  _expect(places[0].label == 'Documents', 'the folder names an unlabelled one');
  _expect(places[1].label == 'Work files', 'a label may contain spaces');
  _expect(places[2].remote && !places[0].remote, 'servers are told apart');
  _expect(places[3].label == 'box', 'a bare server is named by its host');

  stdout.writeln('All recent item and label tests passed.');
}

void _expect(bool condition, String message) {
  if (!condition) {
    stderr.writeln('FAILED: $message');
    exit(1);
  }
}
