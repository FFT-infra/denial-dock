import 'dart:math' as math;

import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/material.dart'
    show Icons, InputBorder, InputDecoration, Material, MaterialType, TextField;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'kit_layer.dart';
import 'kit_motion.dart';
import 'kit_pressable.dart';
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
    this.group,
    this.subtitle,
    this.keywords = const <String>[],
    this.order = 500,
    this.colour = const Color(0xff8e8e93),
    this.readable = true,
  });

  /// `plugin.page`, such as `bar.layout` or `dock.visibility`.
  final String id;

  /// The page's name in the shell's language.
  final String Function(BuildContext context) title;

  /// Optional sidebar section header for grouping related pages.
  final String Function(BuildContext context)? group;

  /// Optional short description shown below the page heading.
  final String Function(BuildContext context)? subtitle;

  /// Additional words matched by the sidebar search box.
  final List<String> keywords;

  /// Whether the search box may build the page out of sight to read what
  /// its rows say. A page that acts on the shell just by being built, such
  /// as one that previews a draft, turns this off and is found by its
  /// [keywords] alone.
  final bool readable;
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

const double _settingsWidth = 880;
const double _sidebarWidth = 228;

/// The page an open settings window is asked to turn to.
final ValueNotifier<String?> _wanted = ValueNotifier<String?>(null);

/// Switches an already-open shell settings window to [pageId].
void openKitSettingsPage(String pageId) {
  _wanted.value = pageId;
}

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
  final TextEditingController _search = TextEditingController();
  String _query = '';

  /// What every page says on its rows, read once the search box is first
  /// typed in, so a search finds an option by its own label and not only
  /// the page that holds it.
  final Map<String, List<String>> _said = <String, List<String>>{};
  bool _reading = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Another language or another look says other things.
    _said.clear();
    _reading = _query.trim().isNotEmpty;
  }

  void _read(String id, List<String> lines) {
    _said[id] = lines;
    if (!mounted) return;
    final pages = kitSettingsPages.pages;
    if (pages.every((page) => !page.readable || _said.containsKey(page.id))) {
      setState(() => _reading = false);
    }
  }

  /// The row of [entry] a search for [_query] found, when it was found by a
  /// row and not by the page's own name.
  String? _found(BuildContext context, KitSettingsPage entry) {
    final terms = _query.trim().toLowerCase().split(RegExp(r'\s+'));
    if (terms.first.isEmpty) return null;
    if (terms.every(entry.title(context).toLowerCase().contains)) return null;
    for (final line in _said[entry.id] ?? const <String>[]) {
      final lower = line.toLowerCase();
      if (terms.any(lower.contains)) return line;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _open++;
    _wanted.addListener(_turn);
    kitSettingsPages.addListener(_changed);
    _search.addListener(_searched);
  }

  @override
  void dispose() {
    _open--;
    _wanted.removeListener(_turn);
    kitSettingsPages.removeListener(_changed);
    _search
      ..removeListener(_searched)
      ..dispose();
    super.dispose();
  }

  void _searched() {
    final next = _search.text;
    if (next == _query || !mounted) return;
    setState(() {
      _query = next;
      if (next.trim().isNotEmpty && _said.isEmpty) _reading = true;
    });
  }

  void _turn() {
    if (mounted) setState(() => _page = _wanted.value);
  }

  void _changed() {
    if (!mounted) return;
    setState(() {
      _said.clear();
      _reading = _query.trim().isNotEmpty;
    });
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

  String _groupOf(BuildContext context, KitSettingsPage entry, bool chinese) =>
      entry.group?.call(context) ??
      switch (_plugin(entry.id)) {
        'bar' => chinese ? '菜单栏' : 'Menu Bar',
        'dock' => chinese ? '程序坞' : 'Dock',
        final other => other,
      };

  @override
  Widget build(BuildContext context) {
    final allPages = kitSettingsPages.pages;
    final chinese = Localizations.maybeLocaleOf(context)?.languageCode == 'zh';
    final height = math.min(680.0, widget.maxHeight);
    if (allPages.isEmpty) {
      return SizedBox(width: _settingsWidth, height: math.min(160, height));
    }
    final filtered = kitFilterPages<KitSettingsPage>(
      allPages,
      _query,
      titleOf: (entry) => entry.title(context),
      groupOf: (entry) => _groupOf(context, entry, chinese),
      keywordsOf: (entry) => <String>[
        ...entry.keywords,
        ...?_said[entry.id],
      ],
    );
    // The page stays the one that was chosen while a search narrows the
    // sidebar; only when the search leaves it out does the first match open.
    final ids = <String>[for (final page in allPages) page.id];
    final chosen = allPages[kitPageIndex(ids, _page)];
    final index = filtered.indexOf(chosen);
    final page = index >= 0 || filtered.isEmpty ? chosen : filtered.first;
    final subtitle = page.subtitle?.call(context);

    return SizedBox(
      width: _settingsWidth,
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          if (_reading)
            Offstage(
              child: ExcludeFocus(
                child: TickerMode(
                  enabled: false,
                  child: OverflowBox(
                    alignment: Alignment.topLeft,
                    minWidth: _settingsWidth - _sidebarWidth - 1,
                    maxWidth: _settingsWidth - _sidebarWidth - 1,
                    // Tall enough that a page which builds its rows lazily
                    // builds them all.
                    minHeight: 6000,
                    maxHeight: 6000,
                    child: Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        for (final entry in allPages)
                          if (entry.readable && !_said.containsKey(entry.id))
                            _PageReader(
                              key: ValueKey<String>('read.${entry.id}'),
                              onRead: (lines) => _read(entry.id, lines),
                              child: entry.builder(context),
                            ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          _window(context, filtered, index, page, subtitle, chinese),
        ],
      ),
    );
  }

  Widget _window(
    BuildContext context,
    List<KitSettingsPage> filtered,
    int index,
    KitSettingsPage page,
    String? subtitle,
    bool chinese,
  ) {
    final theme = context.shellTheme;
    final colors = theme.colors;
    return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            width: _sidebarWidth,
            color: colors.textPrimary.withValues(alpha: 0.04),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                KitWindowHandle(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 12, 10),
                    child: Text(
                      chinese ? '外壳设置' : 'Shell Settings',
                      style: _type(17, FontWeight.w700, colors.textPrimary),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: _SearchBar(
                    controller: _search,
                    hint: chinese ? '搜索设置' : 'Search settings',
                    textStyle: _type(12.5, FontWeight.w400, colors.textPrimary),
                    hintStyle: _type(12.5, FontWeight.w400, colors.textTertiary),
                    onClear: () => _search.clear(),
                  ),
                ),
                Expanded(
                  child: filtered.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
                          child: Text(
                            chinese ? '没有匹配的设置项' : 'No matching settings',
                            style: _type(
                              12.5,
                              FontWeight.w400,
                              colors.textTertiary,
                            ),
                          ),
                        )
                      : SingleChildScrollView(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              for (final (at, entry) in filtered.indexed) ...<Widget>[
                                if (at == 0 ||
                                    _groupOf(context, entry, chinese) !=
                                        _groupOf(
                                          context,
                                          filtered[at - 1],
                                          chinese,
                                        ))
                                  Padding(
                                    padding: EdgeInsets.fromLTRB(
                                      18,
                                      at == 0 ? 4 : 12,
                                      12,
                                      4,
                                    ),
                                    child: Text(
                                      _groupOf(context, entry, chinese),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: _type(
                                        11,
                                        FontWeight.w700,
                                        colors.textTertiary,
                                      ),
                                    ),
                                  ),
                                _SidebarItem(
                                  label: entry.title(context),
                                  icon: entry.icon,
                                  colour: entry.colour,
                                  selected: entry.id == page.id,
                                  found: _found(context, entry),
                                  foundStyle: _type(
                                    11,
                                    FontWeight.w400,
                                    entry.id == page.id
                                        ? KitStyle.of(
                                            context,
                                          ).onAccent(theme).withValues(
                                            alpha: 0.8,
                                          )
                                        : colors.textTertiary,
                                  ),
                                  style: _type(
                                    13,
                                    entry.id == page.id
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                    entry.id == page.id
                                        ? KitStyle.of(context).onAccent(theme)
                                        : colors.textPrimary,
                                  ),
                                  // Remembered outside the window too: a preset that moves
                                  // the bar rebuilds the window, which must
                                  // come back on this page.
                                  onTap: () {
                                    _wanted.value = entry.id;
                                    setState(() => _page = entry.id);
                                  },
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
                    padding: EdgeInsets.fromLTRB(
                      22,
                      14,
                      14,
                      subtitle == null ? 8 : 10,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Text(
                                page.title(context),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: _type(
                                  16,
                                  FontWeight.w700,
                                  colors.textPrimary,
                                ),
                              ),
                              if (subtitle != null) ...<Widget>[
                                const SizedBox(height: 3),
                                Text(
                                  subtitle,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: _type(
                                    12,
                                    FontWeight.w400,
                                    colors.textSecondary,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
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
                    // A search that finds nothing leaves the page that was
                    // open where it is; the sidebar says nothing matched.
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
    );
  }

  static String _plugin(String id) {
    final dot = id.indexOf('.');
    return dot < 0 ? id : id.substring(0, dot);
  }
}

/// Builds a page out of sight and reports the text it shows.
class _PageReader extends StatefulWidget {
  const _PageReader({required this.onRead, required this.child, super.key});

  final ValueChanged<List<String>> onRead;
  final Widget child;

  @override
  State<_PageReader> createState() => _PageReaderState();
}

class _PageReaderState extends State<_PageReader> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final lines = <String>{};
      void visit(Element element) {
        final widget = element.widget;
        if (widget is RichText) {
          final line = widget.text.toPlainText().trim();
          if (line.length > 1) lines.add(line);
        }
        element.visitChildren(visit);
      }

      context.visitChildElements(visit);
      widget.onRead(lines.toList());
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.hint,
    required this.textStyle,
    required this.hintStyle,
    required this.onClear,
  });

  final TextEditingController controller;
  final String hint;
  final TextStyle textStyle;
  final TextStyle hintStyle;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final look = KitStyle.of(context);
    final colors = theme.colors;
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: colors.textPrimary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(look.corner(8)),
        border: Border.all(color: colors.textPrimary.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.search, size: 14, color: colors.textTertiary),
          const SizedBox(width: 6),
          Expanded(
            child: Material(
              type: MaterialType.transparency,
              child: TextField(
                controller: controller,
                maxLines: 1,
                style: textStyle,
                cursorColor: look.accent(theme),
                decoration: InputDecoration(
                  isDense: true,
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: hint,
                  hintStyle: hintStyle,
                ),
              ),
            ),
          ),
          if (controller.text.isNotEmpty)
            Pressable(
              onTap: onClear,
              scale: Pressable.small,
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(Icons.close, size: 13, color: colors.textTertiary),
              ),
            ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.label,
    required this.icon,
    required this.colour,
    required this.selected,
    required this.style,
    required this.onTap,
    this.found,
    this.foundStyle,
  });

  /// The row a search found on this page, shown under its name.
  final String? found;
  final TextStyle? foundStyle;
  final String label;
  final IconData icon;
  final Color colour;
  final bool selected;
  final TextStyle style;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final look = KitStyle.of(context);
    final shape = BorderRadius.circular(look.corner(8));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
      child: Pressable(
        onTap: onTap,
        scale: Pressable.large,
        wash: !selected,
        shape: shape,
        child: AnimatedContainer(
          duration: KitMotion.duration(context, KitMotion.fade),
          height: found == null ? 34 : 46,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: look.accent(theme).withValues(alpha: selected ? 1 : 0),
            borderRadius: shape,
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: colour,
                  borderRadius: BorderRadius.circular(look.corner(6)),
                  border: Border.all(
                    color: const Color(0x33ffffff),
                    width: 0.5,
                  ),
                ),
                child: Icon(icon, size: 13, color: const Color(0xffffffff)),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: style,
                    ),
                    if (found != null)
                      Text(
                        found!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: foundStyle,
                      ),
                  ],
                ),
              ),
            ],
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
    // A disc, or a block where the look is square.
    final shape = KitStyle.of(context).disc(26);
    return Pressable(
      onTap: onTap,
      scale: Pressable.small,
      wash: true,
      shape: shape,
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          borderRadius: shape,
          color: colors.textPrimary.withValues(alpha: 0.10),
        ),
        child: CustomPaint(painter: _CrossPainter(colors.textSecondary)),
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
