/// The texts copied while the history is on, newest first. Kept in memory
/// only: nothing is written to disk and the list is gone when the shell
/// restarts.
class ClipboardHistory {
  ClipboardHistory({this.limit = 30, this.maxLength = 20000});

  final int limit;
  final int maxLength;
  final List<String> _items = <String>[];

  List<String> get items => List<String>.unmodifiable(_items);

  /// Returns whether the list changed.
  bool add(String text) {
    if (text.trim().isEmpty || text.length > maxLength) return false;
    if (_items.isNotEmpty && _items.first == text) return false;
    _items.remove(text);
    _items.insert(0, text);
    if (_items.length > limit) _items.removeRange(limit, _items.length);
    return true;
  }

  bool remove(String text) => _items.remove(text);

  void clear() => _items.clear();
}

/// One line that stands for [text] in a list.
String clipboardPreview(String text, {int length = 120}) {
  final line = text.trim().replaceAll(RegExp(r'\s+'), ' ');
  return line.length <= length ? line : '${line.substring(0, length)}…';
}
