import 'dart:io';

import 'package:denial_topbar/src/island/island_lyrics.dart';

void main() {
  final lines = parseLrc(
    '[ar:Someone]\n'
    '[ti:A Song]\n'
    '[00:12.50]First line\r\n'
    '[00:05]Opening\n'
    '[01:02.345][00:30.1]Chorus\n'
    '[00:40.00]\n'
    'words with no stamp\n',
  );
  _expect(lines.length == 5, 'tags and bare text are left out');
  _expect(lines.first.text == 'Opening', 'lines are put in order');
  _expect(
    lines[1].at == const Duration(seconds: 12, milliseconds: 500),
    'hundredths are read as such',
  );
  _expect(
    lines[2].at == const Duration(seconds: 30, milliseconds: 100),
    'a tenth is a tenth',
  );
  _expect(
    lines.last.at == const Duration(minutes: 1, seconds: 2, milliseconds: 345),
    'a repeated line lands at each of its stamps',
  );

  Duration s(num seconds) => Duration(milliseconds: (seconds * 1000).round());
  _expect(lyricAt(lines, s(0)) == null, 'nothing before the first line');
  _expect(lyricAt(lines, s(5)) == 'Opening', 'a line starts on its stamp');
  _expect(lyricAt(lines, s(12.4)) == 'Opening', 'and holds until the next');
  _expect(lyricAt(lines, s(20)) == 'First line', 'the next line');
  _expect(lyricAt(lines, s(35)) == 'Chorus', 'a repeated line, first time');
  _expect(lyricAt(lines, s(45)) == null, 'an empty line is a gap');
  _expect(lyricAt(lines, s(600)) == 'Chorus', 'the last line stays');
  _expect(lyricAt(const <LyricLine>[], s(3)) == null, 'no lyrics, no line');

  _expect(parseLrc('just words\nand more').isEmpty, 'untimed text is unusable');
  final early = parseLrc('[offset:+500]\n[00:10.00]Soon\n[00:00.20]Now');
  _expect(early.last.at == s(9.5), 'a positive offset brings lines forward');
  _expect(early.first.at == Duration.zero, 'never before the start');

  _expect(
    lrcBeside('file:///home/u/Music/A%20Song.flac') == '/home/u/Music/A Song.lrc',
    'the same name beside a local track',
  );
  _expect(lrcBeside('file:///music/noext') == '/music/noext.lrc', 'no ending');
  _expect(lrcBeside('file:///music/.hidden') == '/music/.hidden.lrc', 'dotfile');
  _expect(lrcBeside('https://example.com/a.mp3') == null, 'nothing remote');
  _expect(lrcBeside('') == null && lrcBeside('file:///music/') == null, 'none');

  stdout.writeln('All island lyric tests passed.');
}

void _expect(bool condition, String message) {
  if (!condition) {
    stderr.writeln('FAIL: $message');
    exit(1);
  }
}
