import 'dart:async';
import 'dart:math' as math;

import 'package:denial_shell_kit/kit_motion.dart';
import 'package:denial_shell_kit/kit_style.dart';
import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'bar_icons.dart';
import 'bar_panel.dart';
import 'bar_type.dart';

sealed class BarMenuEntry {
  const BarMenuEntry();
}

class BarMenuSeparator extends BarMenuEntry {
  const BarMenuSeparator();
}

class BarMenuHeader extends BarMenuEntry {
  const BarMenuHeader(this.label);

  final String label;
}

class BarMenuItem extends BarMenuEntry {
  const BarMenuItem({
    required this.label,
    this.icon,
    this.leading,
    this.badge,
    this.shortcut,
    this.enabled = true,
    this.checked = false,
    this.onSelected,
    this.submenu,
    this.alternate,
  });

  final String label;
  final IconData? icon;

  /// A 16 pt widget in the icon column, for application icons.
  final Widget? leading;
  final String? badge;
  final String? shortcut;
  final bool enabled;
  final bool checked;
  final VoidCallback? onSelected;
  final List<BarMenuEntry>? submenu;

  /// Shown in this item's place while Alt or Shift is held.
  final BarMenuItem? alternate;

  bool get selectable => enabled && (onSelected != null || submenu != null);
}

abstract final class _M {
  static const double rowHeight = 30;
  static const double radius = 13;
  static const double inset = 5;
  static const double rowRadius = 8;
  static const double minWidth = 220;
  static const double maxWidth = 440;
}

/// Opens a menu under [anchor] (or beside it for a vertical bar).
void showBarMenu({
  required WidgetRef ref,
  required String panelId,
  required List<BarMenuEntry> Function(BuildContext context) entries,
  GlobalKey? anchor,
  Offset? at,
  bool vertical = false,
  bool fromRight = false,
}) {
  if (kitOpenPanel.value == panelId) {
    closeKitPanel();
    return;
  }
  final rect = at != null
      ? Rect.fromLTWH(at.dx + 4, at.dy, 0, 0)
      : (anchor == null ? null : kitSceneRect(anchor)) ?? Rect.zero;
  showKitLayer(
    ref: ref,
    keyName: kitPanelKey,
    panelId: panelId,
    open: KitMotion.menuOpen,
    close: KitMotion.menuExit,
    builder: (context, close) => _MenuTree(
      anchor: rect,
      vertical: vertical,
      fromRight: fromRight,
      entries: entries(context),
      close: close,
    ),
  );
}

class _MenuTree extends StatefulWidget {
  const _MenuTree({
    required this.anchor,
    required this.vertical,
    required this.fromRight,
    required this.entries,
    required this.close,
  });

  final Rect anchor;
  final bool vertical;
  final bool fromRight;
  final List<BarMenuEntry> entries;
  final VoidCallback close;

  @override
  State<_MenuTree> createState() => _MenuTreeState();
}

class _MenuTreeState extends State<_MenuTree> {
  final FocusNode _focus = FocusNode(debugLabel: 'bar-menu');
  final GlobalKey _rootKey = GlobalKey();

  /// Highlighted row per level; level 1 is the open submenu.
  final List<int?> _highlight = <int?>[null, null];
  String _typed = '';
  DateTime _typedAt = DateTime(0);
  int? _openIndex;
  Rect? _openRowRect;
  Timer? _hoverOpen;
  bool _modifier = false;
  int? _blink;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onHardwareKey);
    _modifier = _modifierHeld;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    _hoverOpen?.cancel();
    _focus.dispose();
    super.dispose();
  }

  bool get _modifierHeld =>
      HardwareKeyboard.instance.isAltPressed ||
      HardwareKeyboard.instance.isShiftPressed;

  bool _onHardwareKey(KeyEvent event) {
    final held = _modifierHeld;
    if (held != _modifier && mounted) setState(() => _modifier = held);
    return false;
  }

  BarMenuEntry _resolve(BarMenuEntry entry) =>
      entry is BarMenuItem && _modifier ? (entry.alternate ?? entry) : entry;

  List<BarMenuEntry> get _root =>
      widget.entries.map(_resolve).toList(growable: false);

  List<BarMenuEntry> get _sub {
    final index = _openIndex;
    if (index == null) return const <BarMenuEntry>[];
    final entry = _root[index];
    final submenu = entry is BarMenuItem ? entry.submenu : null;
    return submenu?.map(_resolve).toList(growable: false) ??
        const <BarMenuEntry>[];
  }

  void _openSubmenu(int index, {bool highlightFirst = false}) {
    final entry = _root[index];
    if (entry is! BarMenuItem || entry.submenu == null || !entry.enabled) {
      return;
    }
    setState(() {
      _openIndex = index;
      _highlight[1] = highlightFirst ? _step(_sub, null, 1) : null;
    });
  }

  void _closeSubmenu() {
    if (_openIndex == null) return;
    setState(() {
      _openIndex = null;
      _highlight[1] = null;
    });
  }

  void _hover(int level, int? index) {
    if (_blink != null) return;
    if (_highlight[level] != index) {
      setState(() => _highlight[level] = index);
    }
    if (level != 0) return;
    _hoverOpen?.cancel();
    if (index == null || index == _openIndex) return;
    final entry = _root[index];
    final hasSub = entry is BarMenuItem && entry.submenu != null;
    _hoverOpen = Timer(Duration(milliseconds: hasSub ? 90 : 220), () {
      if (!mounted || _highlight[0] != index) return;
      hasSub ? _openSubmenu(index) : _closeSubmenu();
    });
  }

  /// Blinks the chosen row once, the way a Mac menu confirms a pick, then
  /// closes and runs the action.
  Future<void> _activate(int level, int index) async {
    final list = level == 0 ? _root : _sub;
    final entry = list[index];
    if (entry is! BarMenuItem || !entry.selectable || _blink != null) return;
    if (entry.submenu != null) {
      _openSubmenu(index);
      return;
    }
    setState(() {
      _highlight[level] = null;
      _blink = index;
    });
    await Future<void>.delayed(const Duration(milliseconds: 60));
    if (!mounted) return;
    setState(() => _highlight[level] = index);
    await Future<void>.delayed(const Duration(milliseconds: 70));
    if (!mounted) return;
    widget.close();
    entry.onSelected?.call();
  }

  int? _step(List<BarMenuEntry> list, int? from, int delta) {
    if (list.isEmpty) return null;
    var index = from ?? (delta > 0 ? -1 : list.length);
    for (var tries = 0; tries < list.length; tries++) {
      index = (index + delta) % list.length;
      if (index < 0) index += list.length;
      final entry = list[index];
      if (entry is BarMenuItem && entry.selectable) return index;
    }
    return from;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final level = _openIndex != null && _highlight[1] != null ? 1 : 0;
    final list = level == 0 ? _root : _sub;
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowUp) {
      final delta = key == LogicalKeyboardKey.arrowDown ? 1 : -1;
      setState(() => _highlight[level] = _step(list, _highlight[level], delta));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      final index = _highlight[0];
      if (level == 0 && index != null) {
        _openSubmenu(index, highlightFirst: true);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      _closeSubmenu();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space) {
      final index = _highlight[level];
      if (index != null) _activate(level, index);
      return KeyEventResult.handled;
    }
    final character = event.character?.toLowerCase();
    if (character != null && character.trim().isNotEmpty) {
      // Letters typed in quick succession spell out a prefix.
      final now = DateTime.now();
      final fresh =
          now.difference(_typedAt) > const Duration(milliseconds: 900);
      _typed = fresh ? character : _typed + character;
      _typedAt = now;
      for (var index = 0; index < list.length; index++) {
        final entry = list[index];
        if (entry is BarMenuItem &&
            entry.selectable &&
            entry.label.toLowerCase().startsWith(_typed)) {
          setState(() => _highlight[level] = index);
          return KeyEventResult.handled;
        }
      }
    }
    return KeyEventResult.ignored;
  }

  void _rowRect(Rect rect) => _openRowRect = rect;

  @override
  Widget build(BuildContext context) {
    final scene = MediaQuery.sizeOf(context);
    const margin = 6.0;
    final anchor = widget.anchor;
    final rootMaxHeight = scene.height - margin * 2;

    final root = _MenuCard(
      key: _rootKey,
      entries: _root,
      highlight: _highlight[0],
      openIndex: _openIndex,
      maxHeight: rootMaxHeight,
      onHover: (index) => _hover(0, index),
      onTap: (index) => _activate(0, index),
      onOpenRowRect: _rowRect,
    );

    final sub = _sub;
    return Focus(
      focusNode: _focus,
      onKeyEvent: _onKey,
      child: KitSwell(
        alignment: Alignment.topLeft,
        fadeOnly: true,
        child: CustomMultiChildLayout(
          delegate: _MenuLayout(
            anchor: anchor,
            vertical: widget.vertical,
            fromRight: widget.fromRight,
            margin: margin,
            hasSub: sub.isNotEmpty,
            rowRect: () => _openRowRect,
            rootKey: _rootKey,
          ),
          children: <Widget>[
            LayoutId(id: 0, child: root),
            if (sub.isNotEmpty)
              LayoutId(
                id: 1,
                child: _MenuCard(
                  key: ValueKey<int?>(_openIndex),
                  entries: sub,
                  highlight: _highlight[1],
                  openIndex: null,
                  maxHeight: rootMaxHeight,
                  appear: true,
                  onHover: (index) => _hover(1, index),
                  onTap: (index) => _activate(1, index),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MenuLayout extends MultiChildLayoutDelegate {
  _MenuLayout({
    required this.anchor,
    required this.vertical,
    required this.fromRight,
    required this.margin,
    required this.hasSub,
    required this.rowRect,
    required this.rootKey,
  });

  final Rect anchor;
  final bool vertical;
  final bool fromRight;
  final double margin;
  final bool hasSub;
  final Rect? Function() rowRect;
  final GlobalKey rootKey;

  @override
  void performLayout(Size size) {
    final loose = BoxConstraints(
      minWidth: _M.minWidth,
      maxWidth: math.min(_M.maxWidth, size.width - margin * 2),
      maxHeight: size.height - margin * 2,
    );
    final root = layoutChild(0, loose);
    // The menu's place comes from the kit, so a menu and the bar's popovers
    // agree on margins and on how they follow their item; the item's rect is
    // all this delegate knows and all the rule needs.
    final place = kitMenuPlace(
      sceneWidth: size.width,
      sceneHeight: size.height,
      anchorLeft: anchor.left,
      anchorTop: anchor.top,
      anchorRight: anchor.right,
      anchorBottom: anchor.bottom,
      width: root.width,
      height: root.height,
      vertical: vertical,
      fromRight: fromRight,
      margin: margin,
      gap: 4,
      sideGap: 6,
      sideLift: _M.inset,
    );
    final x = place.left;
    final y = place.top;
    positionChild(0, Offset(x, y));

    if (!hasSub || !hasChild(1)) return;
    final sub = layoutChild(1, loose);
    final row = rowRect();
    var sx = x + root.width - 3;
    if (sx + sub.width > size.width - margin) sx = x - sub.width + 3;
    var sy = (row?.top ?? y) - _M.inset;
    sx = sx.clamp(margin, math.max(margin, size.width - sub.width - margin));
    sy = sy.clamp(margin, math.max(margin, size.height - sub.height - margin));
    positionChild(1, Offset(sx, sy));
  }

  @override
  bool shouldRelayout(_MenuLayout oldDelegate) => true;
}

class _MenuCard extends StatelessWidget {
  const _MenuCard({
    required this.entries,
    required this.highlight,
    required this.openIndex,
    required this.maxHeight,
    required this.onHover,
    required this.onTap,
    this.onOpenRowRect,
    this.appear = false,
    super.key,
  });

  final List<BarMenuEntry> entries;
  final int? highlight;
  final int? openIndex;
  final double maxHeight;
  final ValueChanged<int?> onHover;
  final ValueChanged<int> onTap;
  final ValueChanged<Rect>? onOpenRowRect;
  final bool appear;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final hasLead = entries.any(
      (entry) =>
          entry is BarMenuItem &&
          (entry.icon != null || entry.leading != null || entry.checked),
    );
    Widget card = Listener(
      behavior: HitTestBehavior.opaque,
      child: KitCard(
        radius: _M.radius,
        elevation: 0.7,
        fill: theme.panelColor(theme.colors.surfaceContainer),
        child: MouseRegion(
          onExit: (_) => onHover(openIndex),
          child: IntrinsicWidth(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(_M.inset),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (var index = 0; index < entries.length; index++)
                    switch (entries[index]) {
                      BarMenuSeparator() => const _Separator(),
                      BarMenuHeader(:final label) => _Header(label: label),
                      final BarMenuItem item => _Row(
                        item: item,
                        lead: hasLead,
                        active: highlight == index || openIndex == index,
                        reportRect: openIndex == index ? onOpenRowRect : null,
                        onHover: () => onHover(index),
                        onTap: () => onTap(index),
                      ),
                    },
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (appear) {
      card = TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: 1),
        duration: KitMotion.duration(context, KitMotion.tap),
        builder: (context, t, child) => Opacity(opacity: t, child: child),
        child: card,
      );
    }
    return card;
  }
}

class _Separator extends StatelessWidget {
  const _Separator();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: SizedBox(
        height: 1,
        child: ColoredBox(color: context.shellTheme.colors.hairline),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 5, 10, 3),
      child: Text(
        label,
        style: BarType.caption.copyWith(
          fontWeight: FontWeight.w600,
          color: context.shellTheme.colors.textTertiary,
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.item,
    required this.lead,
    required this.active,
    required this.onHover,
    required this.onTap,
    this.reportRect,
  });

  final BarMenuItem item;
  final bool lead;
  final bool active;
  final VoidCallback onHover;
  final VoidCallback onTap;
  final ValueChanged<Rect>? reportRect;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final lit = active && item.selectable;
    final row = KitStyle.of(context)
        .menuRow(theme, hot: lit, enabled: item.enabled);
    final ink = row.ink;
    final dim = row.dim;

    final report = reportRect;
    if (report != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final render = context.findRenderObject();
        if (render is RenderBox && render.attached) {
          report(render.localToGlobal(Offset.zero) & render.size);
        }
      });
    }

    Widget? leading;
    if (item.checked) {
      leading = BarGlyph(BarIcons.checkmark, size: 12, color: ink);
    } else if (item.leading != null) {
      leading = item.leading;
    } else if (item.icon != null) {
      leading = BarGlyph(item.icon!, size: 15, color: ink);
    }

    return MouseRegion(
      cursor: item.selectable ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => onHover(),
      onHover: (_) {
        if (!active) onHover();
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => onHover(),
        onTap: item.selectable ? onTap : null,
        child: Container(
          height: _M.rowHeight,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: row.fill,
            borderRadius: BorderRadius.circular(
              KitStyle.of(context).corner(_M.rowRadius),
            ),
          ),
          child: Row(
            children: <Widget>[
              if (lead)
                SizedBox(
                  width: 24,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(width: 16, height: 16, child: leading),
                  ),
                ),
              Expanded(
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: BarType.menuRow.copyWith(color: ink),
                ),
              ),
              if (item.badge != null)
                Container(
                  margin: const EdgeInsets.only(left: 16),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  height: 18,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: ink.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(
                    item.badge!,
                    style: BarType.caption.copyWith(
                      fontWeight: FontWeight.w600,
                      color: ink.withValues(alpha: 0.85),
                    ),
                  ),
                ),
              if (item.shortcut != null)
                Padding(
                  padding: const EdgeInsets.only(left: 24),
                  child: Text(
                    item.shortcut!,
                    style: BarType.menuRow.copyWith(color: dim),
                  ),
                ),
              if (item.submenu != null)
                Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: BarGlyph(BarIcons.chevronRight, size: 11, color: ink),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
