import 'dart:math' as math;

import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'kit_layer.dart';
import 'kit_motion.dart';
import 'kit_settings_order.dart';
import 'kit_style.dart';

/// One page of the shell's settings window.
///
/// The plugins of the shell may not import one another, yet their settings
/// belong in one window. Each plugin registers its pages here; the window
/// lists whatever is registered, so with one plugin running it holds that
/// plugin's pages and nothing else.
@immutable
class KitSettingsPage {
  const KitSettingsPage({
    required this.id,
    required this.title,
    required this.icon,
    required this.builder,
    this.order = 500,
    this.colour = const Color(0xff8e8e93),
  });

  /// `plugin.page`, such as `bar.layout` or `dock.visibility`.
  final String id;

  /// The page's name in the shell's language.
  final String Function(BuildContext context) title;
  final IconData icon;

  /// The plate under the icon in the sidebar.
  final Color colour;

  /// Where the page stands in the sidebar, lowest first.
  final int order;

  /// The page itself, filling the room beside the sidebar. It scrolls on its
  /// own when it is longer than the window.
  final WidgetBuilder builder;
}

/// Every settings page the running plugins offer, in sidebar order.
final KitSettingsPages kitSettingsPages = KitSettingsPages._();

class KitSettingsPages extends ChangeNotifier {
  KitSettingsPages._();

  final List<KitSettingsPage> _pages = <KitSettingsPage>[];

  List<KitSettingsPage> get pages =>
      kitOrderPages(_pages, orderOf: (page) => page.order);

  /// Adds [pages], replacing any registered under the same id. Safe to call
  /// again with the same pages.
  void register(Iterable<KitSettingsPage> pages) {
    if (kitMergePages(_pages, pages, idOf: (page) => page.id)) {
      notifyListeners();
    }
  }
}

/// The popup key of the shell's settings window. A host that must know
/// whether the window is open looks for it among the shell's popups.
const String kitSettingsKey = 'denial_shell.settings';

const double _settingsWidth = 760;

/// The page an open settings window is asked to turn to.
final ValueNotifier<String?> _wanted = ValueNotifier<String?>(null);

/// Opens the shell's settings window at [page]: a page id, or a plugin's
/// name for that plugin's first page. An open window turns to the page.
void showKitSettings({required WidgetRef ref, String? page}) {
  _wanted.value = page;
  if (_open > 0) return;
  showKitDialog(
    ref: ref,
    width: _settingsWidth,
    keyName: kitSettingsKey,
    debugLabel: 'Shell settings',
    builder: (context, close) => _KitSettingsWindow(
      onClose: close,
      maxHeight: MediaQuery.sizeOf(context).height - 96,
    ),
  );
}

/// How many settings windows are mounted; one at most outside a hand-over.
int _open = 0;

class _KitSettingsWindow extends StatefulWidget {
  const _KitSettingsWindow({required this.onClose, required this.maxHeight});

  final VoidCallback onClose;
  final double maxHeight;

  @override
  State<_KitSettingsWindow> createState() => _KitSettingsWindowState();
}

class _KitSettingsWindowState extends State<_KitSettingsWindow> {
  String? _page = _wanted.value;

  @override
  void initState() {
    super.initState();
    _open++;
    _wanted.addListener(_turn);
    kitSettingsPages.addListener(_changed);
  }

  @override
  void dispose() {
    _open--;
    _wanted.removeListener(_turn);
    kitSettingsPages.removeListener(_changed);
    super.dispose();
  }

  void _turn() {
    if (mounted) setState(() => _page = _wanted.value);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  static TextStyle _type(double size, FontWeight weight, Color colour) {
    final style = kitStyle.value;
    return TextStyle(
      fontFamily: style.fontFamily,
      package: style.fontFamily == null ? null : style.fontPackage,
      fontSize: size * style.fontScale,
      fontWeight: style.weight(weight),
      height: 1.2,
      color: colour,
      decoration: TextDecoration.none,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = theme.colors;
    final pages = kitSettingsPages.pages;
    final chinese = Localizations.maybeLocaleOf(context)?.languageCode == 'zh';
    final height = math.min(600.0, widget.maxHeight);
    if (pages.isEmpty) {
      return SizedBox(width: _settingsWidth, height: math.min(160, height));
    }
    final index = kitPageIndex(<String>[
      for (final page in pages) page.id,
    ], _page);
    final page = pages[index];

    return SizedBox(
      width: _settingsWidth,
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            width: 204,
            color: colors.textPrimary.withValues(alpha: 0.04),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                KitWindowHandle(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 18, 12, 12),
                    child: Text(
                      chinese ? '外壳设置' : 'Shell Settings',
                      style: _type(17, FontWeight.w700, colors.textPrimary),
                    ),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        for (final (at, entry) in pages.indexed) ...<Widget>[
                          // A little air where one plugin's pages end.
                          if (at > 0 &&
                              _plugin(entry.id) != _plugin(pages[at - 1].id))
                            const SizedBox(height: 10),
                          _SidebarItem(
                            label: entry.title(context),
                            icon: entry.icon,
                            colour: entry.colour,
                            selected: at == index,
                            style: _type(
                              13,
                              FontWeight.w400,
                              at == index
                                  ? KitStyle.of(context).onAccent(theme)
                                  : colors.textPrimary,
                            ),
                            onTap: () => setState(() => _page = entry.id),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: 1, child: ColoredBox(color: colors.hairline)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                KitWindowHandle(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(22, 14, 12, 8),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            page.title(context),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _type(
                              15,
                              FontWeight.w700,
                              colors.textPrimary,
                            ),
                          ),
                        ),
                        _CloseButton(onTap: widget.onClose),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: KitMotion.duration(context, KitMotion.turn),
                    layoutBuilder: (current, previous) => Stack(
                      fit: StackFit.expand,
                      children: <Widget>[...previous, ?current],
                    ),
                    child: KeyedSubtree(
                      key: ValueKey<String>(page.id),
                      child: page.builder(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _plugin(String id) {
    final dot = id.indexOf('.');
    return dot < 0 ? id : id.substring(0, dot);
  }
}

class _SidebarItem extends StatefulWidget {
  const _SidebarItem({
    required this.label,
    required this.icon,
    required this.colour,
    required this.selected,
    required this.style,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color colour;
  final bool selected;
  final TextStyle style;
  final VoidCallback onTap;

  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final style = KitStyle.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: KitMotion.duration(context, KitMotion.fade),
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: widget.selected
                  ? style.accent(theme)
                  : theme.colors.textPrimary.withValues(
                      alpha: _hovered ? 0.07 : 0,
                    ),
              borderRadius: BorderRadius.circular(style.corner(8)),
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: widget.colour,
                    borderRadius: BorderRadius.circular(style.corner(6)),
                    border: Border.all(
                      color: const Color(0x33ffffff),
                      width: 0.5,
                    ),
                  ),
                  child: Icon(
                    widget.icon,
                    size: 13,
                    color: const Color(0xffffffff),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: widget.style,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.shellTheme.colors;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colors.textPrimary.withValues(alpha: 0.10),
          ),
          child: CustomPaint(painter: _CrossPainter(colors.textSecondary)),
        ),
      ),
    );
  }
}

class _CrossPainter extends CustomPainter {
  const _CrossPainter(this.colour);

  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = colour
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    final centre = size.center(Offset.zero);
    const reach = 4.0;
    canvas
      ..drawLine(
        centre - const Offset(reach, reach),
        centre + const Offset(reach, reach),
        paint,
      )
      ..drawLine(
        centre + const Offset(-reach, reach),
        centre + const Offset(reach, -reach),
        paint,
      );
  }

  @override
  bool shouldRepaint(_CrossPainter oldDelegate) => oldDelegate.colour != colour;
}
