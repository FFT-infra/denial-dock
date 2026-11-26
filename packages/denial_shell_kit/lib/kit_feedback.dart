/// How a control answers a pointer, a press, a key and being unavailable,
/// as numbers every look shares. Kept free of Flutter so the rules run as an
/// ordinary Dart test.
///
/// The states rank: unavailable hides the rest, pressed outranks hovered,
/// and each is stronger than the one below it, so no two states look alike.
abstract final class KitFeedback {
  /// The share of the ink laid over a control under the pointer.
  static const double hoverWash = 0.05;

  /// The same while it is held.
  static const double pressWash = 0.12;

  /// The line a flat look draws round a control under the pointer, as a
  /// share of the ink, and while it is held.
  static const double hoverLine = 0.22;
  static const double pressLine = 0.45;

  /// What is left of a control that cannot be used.
  static const double disabledOpacity = 0.4;

  /// The width of the ring round whatever the keyboard has reached.
  static const double ringWidth = 2;

  /// The wash over a control in the given state.
  static double wash({
    required bool hovered,
    required bool pressed,
    bool enabled = true,
  }) => !enabled
      ? 0
      : pressed
      ? pressWash
      : hovered
      ? hoverWash
      : 0;

  /// The line round a control in the given state. Only a [flat] look draws
  /// one: its fills have no gloss, so a wash alone is easy to miss.
  static double line({
    required bool hovered,
    required bool pressed,
    required bool flat,
    bool enabled = true,
  }) => !enabled || !flat
      ? 0
      : pressed
      ? pressLine
      : hovered
      ? hoverLine
      : 0;

  /// A fill of [rest] opacity as the given state shows it: lifted under the
  /// pointer, more while held, and never past solid. For a plate that is
  /// drawn at rest too, such as a button's.
  static double plate(
    double rest, {
    required bool hovered,
    required bool pressed,
    bool enabled = true,
  }) {
    final lift = wash(hovered: hovered, pressed: pressed, enabled: enabled);
    final shown = rest + lift;
    return shown > 1 ? 1 : shown;
  }

  /// How large a held control is drawn. An unavailable one does not give.
  static double scale(
    double pressed, {
    required bool held,
    bool enabled = true,
  }) => held && enabled ? pressed : 1;
}
