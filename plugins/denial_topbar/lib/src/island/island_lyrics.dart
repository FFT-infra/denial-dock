/// Timed lyrics in the LRC form, read from text a player hands over or from
/// a file beside the track. Plain Dart, so it runs as an ordinary test.
library;

/// One line and the moment it starts.
class LyricLine {
  const LyricLine(this.at, this.text);

  final Duration at;
  final String text;
}

final RegExp _stamp = RegExp(r'\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]');
final RegExp _offset = RegExp(r'\[offset:\s*([+-]?\d+)\s*\]', caseSensitive: false);

/// The timed lines of [text], in order. A line may carry several stamps;
/// text with no stamps at all gives nothing, since there is no telling when
/// any of it is sung.
List<LyricLine> parseLrc(String text) {
  final lines = <LyricLine>[];
  // A positive offset means the lyrics come that much sooner.
  final shift = int.tryParse(_offset.firstMatch(text)?.group(1) ?? '') ?? 0;
  for (final raw in text.split(RegExp(r'\r?\n'))) {
    final stamps = <Duration>[];
    var rest = raw.trimLeft();
    while (true) {
      final match = _stamp.matchAsPrefix(rest);
      if (match == null) break;
      final fraction = match.group(3) ?? '';
      final millis = fraction.isEmpty
          ? 0
          : (int.parse(fraction.padRight(3, '0').substring(0, 3)));
      stamps.add(
        Duration(
          minutes: int.parse(match.group(1)!),
          seconds: int.parse(match.group(2)!),
          milliseconds: millis - shift,
        ),
      );
      rest = rest.substring(match.end).trimLeft();
    }
    final words = rest.trim();
    for (final at in stamps) {
      lines.add(LyricLine(at.isNegative ? Duration.zero : at, words));
    }
  }
  // Stable, so two lines at one moment keep the order they were written in.
  final order = <int>[for (var i = 0; i < lines.length; i++) i]
    ..sort((a, b) {
      final by = lines[a].at.compareTo(lines[b].at);
      return by != 0 ? by : a.compareTo(b);
    });
  return <LyricLine>[for (final i in order) lines[i]];
}

/// The line being sung at [position], or null before the first one and
/// during a gap the lyrics leave empty.
String? lyricAt(List<LyricLine> lines, Duration position) {
  var low = 0;
  var high = lines.length;
  while (low < high) {
    final middle = (low + high) >> 1;
    if (lines[middle].at <= position) {
      low = middle + 1;
    } else {
      high = middle;
    }
  }
  if (low == 0) return null;
  final text = lines[low - 1].text;
  return text.isEmpty ? null : text;
}

/// Where the lyrics of the local track at [url] would be: the same name
/// with an `.lrc` ending. Null for anything that is not a local file.
String? lrcBeside(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.scheme != 'file') return null;
  final String path;
  try {
    path = uri.toFilePath(windows: false);
  } on Object {
    return null;
  }
  final slash = path.lastIndexOf('/');
  final dot = path.lastIndexOf('.');
  if (path.isEmpty || slash == path.length - 1) return null;
  return '${dot > slash + 1 ? path.substring(0, dot) : path}.lrc';
}
