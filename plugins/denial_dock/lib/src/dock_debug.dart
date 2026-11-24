import 'package:denial_shell_kit/debug_file.dart';

/// Lets a developer drive the dock without a pointer. When the file
/// `denial_dock.debug` exists beside the preferences at start, each write to
/// it is a command, so a screenshot can show what a pointer would open:
///
/// - `settings 3` opens the sheet on its fourth page
/// - `click 2` acts as a click on the second application
/// - `preview code`, `menu code` open an application's previews or menu
/// - `folder downloads fan` opens a folder's stack, optionally in one view
/// - `menu downloads` opens a folder's or the trash's menu
/// - `dockmenu` opens the dock's own menu, `close` shuts whatever is open
///
/// Without the file nothing is watched.
abstract final class DockDebug {
  static Stream<List<String>> get commands =>
      debugFileCommands('denial_dock');
}
