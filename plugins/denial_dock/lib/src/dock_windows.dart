/// Rules about which windows and sounds belong to a dock icon, free of
/// Flutter so they run as plain Dart tests.
abstract final class DockWindows {
  /// The windows on [workspace]. A window the compositor reports no workspace
  /// for is kept: hiding it would leave no way back to it.
  static List<T> onWorkspace<T>(
    List<T> windows, {
    required int Function(T window) idOf,
    required Map<int, int> workspaceById,
    required int workspace,
  }) => [
    for (final window in windows)
      if ((workspaceById[idOf(window)] ?? workspace) == workspace) window,
  ];

  /// Whether an audio stream called [stream] belongs to this application.
  /// The mixer only names a stream, so the name is compared with the
  /// application's name and with its id, whole and by its last segment.
  static bool ownsStream(
    String stream, {
    required String appId,
    required String name,
  }) {
    final wanted = _plain(stream);
    if (wanted.isEmpty) return false;
    final id = appId.trim().replaceFirst(RegExp(r'\.desktop$'), '');
    return wanted == _plain(name) ||
        wanted == _plain(id) ||
        wanted == _plain(id.substring(id.lastIndexOf('.') + 1));
  }

  static String _plain(String text) =>
      text.toLowerCase().replaceAll(RegExp(r'[\s._-]+'), '');
}
