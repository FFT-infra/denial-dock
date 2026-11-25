import 'package:flutter/foundation.dart';

/// A second line for the island's playback card: a lyric, a chapter title.
///
/// Nothing provides one yet. A source hands [Island] an implementation, and
/// the card shows [line] under the title whenever it is not null; the source
/// decides what the line is for the track playing and when it changes.
abstract interface class IslandSubline {
  ValueListenable<String?> get line;
}
