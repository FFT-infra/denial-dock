import 'package:flutter/foundation.dart';

/// A second line for the island's playback card: a lyric, a chapter title.
///
/// The card shows [line] under the title whenever it is not null; the source
/// decides what the line is for the track playing and when it changes. The
/// island's own source reads lyrics already on this machine; another one can
/// be handed to [Island] in its place.
abstract interface class IslandSubline {
  ValueListenable<String?> get line;
}
