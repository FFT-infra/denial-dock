import 'dart:io';

import 'package:denial_dock/src/dock_autohide_math.dart';
import 'package:denial_dock/src/dock_mime_icons.dart';
import 'package:denial_dock/src/dock_recent_docs.dart';
import 'package:denial_dock/src/dock_settings.dart';

void _expect(bool condition, String message) {
  if (!condition) {
    stderr.writeln('FAIL: $message');
    exitCode = 1;
  }
}

void main() {
  // 1. DockMimeIcons.parseGlobs2 & iconCandidates
  final globs = DockMimeIcons.parseGlobs2('''
# comment
50:application/pdf:*.pdf
80:text/rust:*.rs
40:text/plain:*.rs
50:application/zip:*.zip
50:text/plain:README*
''');
  _expect(globs['pdf'] == 'application/pdf', 'pdf mime parsed');
  _expect(globs['rs'] == 'text/rust', 'higher weight wins for .rs');
  _expect(globs['zip'] == 'application/zip', 'zip mime parsed');
  _expect(!globs.containsKey('README*'), 'non-extension glob ignored');
  final pdfCandidates = DockMimeIcons.iconCandidates('application/pdf');
  _expect(pdfCandidates.first == 'application-pdf', 'primary mime icon name');
  final zipCandidates = DockMimeIcons.iconCandidates('application/zip');
  _expect(
    zipCandidates.contains('package-x-generic'),
    'archive mime includes package-x-generic',
  );

  // 2. DockRecentDocs.parseXbel
  final docs = DockRecentDocs.parseXbel('''
<?xml version="1.0" encoding="UTF-8"?>
<xbel version="1.0">
  <bookmark href="file:///home/user/old.pdf" modified="2026-11-01T10:00:00Z">
    <info><metadata><bookmark:applications>
      <bookmark:application name="Okular"/>
    </bookmark:applications></metadata></info>
  </bookmark>
  <bookmark href="file:///home/user/report%202.pdf" modified="2026-11-28T05:00:00Z">
    <info><metadata><bookmark:applications>
      <bookmark:application name="org.kde.okular"/>
    </bookmark:applications></metadata></info>
  </bookmark>
  <bookmark href="https://example.com/ignored" modified="2026-11-28T06:00:00Z">
    <info><metadata><bookmark:applications>
      <bookmark:application name="Chrome"/>
    </bookmark:applications></metadata></info>
  </bookmark>
</xbel>
''');
  _expect(docs.length == 2, 'only local file:// bookmarks kept');
  _expect(docs.first.name == 'report 2.pdf', 'newest bookmark first & URI decoded');
  _expect(docs.first.applications.contains('org.kde.okular'), 'app parsed');

  // 3. DockPosition.top geometry
  const out = (left: 0.0, top: 0.0, width: 1524.0, height: 1016.0);
  const work = (left: 0.0, top: 32.0, width: 1524.0, height: 984.0);
  final topRect = dockRect(
    output: out,
    position: DockPosition.top,
    extent: 400,
    thickness: 60,
    inset: 10,
  );
  _expect(topRect.top == 10.0 && topRect.height == 60.0, 'top dock rect');
  final deep = overlapDepth(topRect, position: DockPosition.top, depth: 12);
  _expect(deep.top == 10.0 && deep.height == 48.0, 'top overlap depth trims bottom');
  final res = reservedEdge(
    output: out,
    workArea: work,
    position: DockPosition.top,
  );
  _expect(res == 32.0, 'top reserved edge reads top bar height');

  // 4. DockSettings JSON round-trip for top + allMonitors + showMinimizedWindows
  final parsed = DockSettings.fromJson(<String, dynamic>{
    'position': 'top',
    'allMonitors': false,
    'showMinimizedWindows': false,
  });
  _expect(parsed.position == DockPosition.top, 'top position parses');
  _expect(!parsed.allMonitors, 'allMonitors false parses');
  _expect(!parsed.showMinimizedWindows, 'showMinimizedWindows false parses');

  if (exitCode == 0) {
    stdout.writeln('All Batch 5 dock tests passed.');
  }
}
