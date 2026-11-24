

import 'package:denial_shell_kit/detached_run.dart';
/// Screenshot and colour-pick helpers.
///
/// Denial's own screenshot flow lives behind
/// `SystemActionsService.takeScreenshot`, which the compositor already
/// implements. A colour pick has no SDK surface, so this runs the standard
/// Wayland pair: `slurp -p` reports one point and `grim -g` grabs that single
/// pixel, which `magick` turns into a hex value and `wl-copy` puts on the
/// clipboard — the same pipeline shell27's `pickColor` uses.
abstract final class ScreenTools {
  static Future<void> pickColor() async {
    const script =
        'p=\$(slurp -p) || exit 1; '
        'hex=\$(grim -g "\$p" -t ppm - 2>/dev/null '
        '| magick - -format "%[hex:p{0,0}]" info:-) || exit 1; '
        'printf "#%s" "\$hex" | wl-copy';
    await _run(script);
  }

  static Future<void> _run(String script) async {
    // A host without grim/slurp simply gets no pick; the menu row stays
    // available so a missing tool is not mistaken for a dead command.
    await runDetached('sh', <String>['-c', script]);
  }
}
