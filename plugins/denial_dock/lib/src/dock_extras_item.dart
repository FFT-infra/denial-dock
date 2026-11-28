import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:denial_shell_kit/kit_layer.dart' show kitOverlayRect;
import 'package:denial_shell_kit/kit_motion.dart';
import 'package:denial_shell_kit/kit_style.dart';
import 'package:denial_flutter_sdk/input.dart';
import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind, kPrimaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'dock_look_style.dart';
import 'dock_debug.dart';
import 'dock_extras.dart';
import 'dock_icon.dart';
import 'dock_mac_icons.dart';
import 'dock_pile.dart';
import 'dock_menu.dart';
import 'dock_mime_icons.dart';
import 'dock_settings.dart';
import 'dock_stack_files.dart'
    show DockDownloadProgress, DockStackEntry, DockStackFiles;
import 'dock_stack_thumbs.dart';
import 'dock_stack_view.dart';
import 'dock_stack_watch.dart';

typedef DockAccessoryMenuBuilder = List<Widget> Function(
  BuildContext context,
  VoidCallback close,
);

/// A folder shortcut or the trash can at the accessory end of the dock. Both
/// share the same frame: a tinted tile, hover magnification supplied by the
/// parent, a right-click menu, and a long press that opens that menu on touch.
class DockAccessoryItem extends StatefulWidget {
  const DockAccessoryItem({
    required this.label,
    required this.icon,
    required this.size,
    required this.lift,
    required this.position,
    required this.onTap,
    required this.menuBuilder,
    required this.onOverlayChanged,
    required this.monitorBounds,
    this.badge = 0,
    this.glyph,
    this.fill,
    this.download,
    this.face,
    super.key,
  });

  final String label;
  final IconData icon;

  /// Drawn instead of [icon] when given, so a folder can show the newest file
  /// in it the way a macOS Stack does.
  final Widget? glyph;

  /// Painted behind [glyph] and clipped to the tile: a folder's newest file
  /// fills the tile instead of sitting in a circle inside it.
  final Widget? fill;

  /// Replaces the tinted tile with the caller's own artwork — the macOS-style
  /// stack, trash can or Launchpad grid. The press, menu and badge wiring
  /// around it stays the same.
  final Widget Function(bool pressed)? face;

  /// A transfer running into this folder, drawn as a bar along the tile's
  /// bottom edge.
  final DockDownloadProgress? download;
  final double size;
  final double lift;
  final DockPosition position;
  final VoidCallback onTap;
  final DockAccessoryMenuBuilder menuBuilder;
  final ValueChanged<bool> onOverlayChanged;
  final Rect monitorBounds;

  /// A small count drawn on the tile corner; zero hides it.
  final int badge;

  @override
  State<DockAccessoryItem> createState() => _DockAccessoryItemState();
}

class _DockAccessoryItemState extends State<DockAccessoryItem> {
  final OverlayPortalController _portal = OverlayPortalController();
  bool _menuOpen = false;
  bool _pressed = false;
  Timer? _longPressTimer;
  Offset? _downPosition;

  StreamSubscription<List<String>>? _debug;

  @override
  void initState() {
    super.initState();
    _debug = DockDebug.commands.listen((words) {
      if (!mounted) return;
      if (words.first == 'close') return _closeMenu();
      if (words.first == 'menu' &&
          words.length > 1 &&
          widget.label.toLowerCase().contains(words[1])) {
        _openMenu();
      }
    });
  }

  @override
  void dispose() {
    unawaited(_debug?.cancel());
    _longPressTimer?.cancel();
    if (_menuOpen) widget.onOverlayChanged(false);
    super.dispose();
  }

  void _pressDown() {
    if (!_pressed) setState(() => _pressed = true);
  }

  void _pressUp() {
    if (!_pressed) return;
    setState(() => _pressed = false);
  }

  void _openMenu() {
    if (_menuOpen) return;
    setState(() => _menuOpen = true);
    if (!_portal.isShowing) _portal.show();
    widget.onOverlayChanged(true);
  }

  void _closeMenu() {
    if (!_menuOpen) return;
    setState(() => _menuOpen = false);
    _portal.hide();
    widget.onOverlayChanged(false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    return OverlayPortal.overlayChildLayoutBuilder(
      controller: _portal,
      overlayChildBuilder: (context, layout) =>
          _menuOpen ? _buildMenu(context, layout) : const SizedBox.shrink(),
      child: Transform.translate(
        offset: switch (widget.position) {
          DockPosition.bottom => Offset(0, -widget.lift),
          DockPosition.top => Offset(0, widget.lift),
          DockPosition.left => Offset(widget.lift, 0),
          DockPosition.right => Offset(-widget.lift, 0),
        },
        child: Semantics(
          label: widget.label,
          button: true,
          child: Listener(
            onPointerDown: (event) {
              _downPosition = event.position;
              if (event.buttons == kPrimaryButton) _pressDown();
              if (event.kind != PointerDeviceKind.mouse &&
                  event.buttons == kPrimaryButton) {
                _longPressTimer?.cancel();
                _longPressTimer = Timer(const Duration(milliseconds: 550), () {
                  _longPressTimer = null;
                  if (mounted) _openMenu();
                });
              }
            },
            onPointerMove: (event) {
              if (_longPressTimer != null &&
                  _downPosition != null &&
                  (event.position - _downPosition!).distance > 6) {
                _longPressTimer?.cancel();
                _longPressTimer = null;
              }
            },
            onPointerUp: (_) {
              _pressUp();
              _longPressTimer?.cancel();
              _longPressTimer = null;
              _downPosition = null;
            },
            onPointerCancel: (_) {
              _pressUp();
              _longPressTimer?.cancel();
              _longPressTimer = null;
              _downPosition = null;
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                if (_menuOpen) {
                  _closeMenu();
                  return;
                }
                widget.onTap();
              },
              onSecondaryTapDown: (_) => _menuOpen ? _closeMenu() : _openMenu(),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child:
                        widget.face?.call(_pressed) ??
                        DockTile(
                          size: widget.size,
                          accent: theme.kitAccent,
                          fill: widget.fill,
                          pressed: _pressed,
                          // A full-bleed picture is the item's face; drawing
                          // the type icon over it would be two icons in one
                          // tile.
                          child: widget.fill != null
                              ? const SizedBox.shrink()
                              : widget.glyph ??
                                    Icon(
                                      widget.icon,
                                      size: widget.size * 0.46,
                                      color: theme.kitAccent,
                                    ),
                        ),
                  ),
                  if (widget.download case final download?)
                    Positioned(
                      left: widget.size * 0.18,
                      right: widget.size * 0.18,
                      bottom: widget.size * 0.14,
                      child: _DownloadBar(
                        download: download,
                        color: theme.colors.background,
                        track: theme.colors.background.withValues(alpha: 0.3),
                      ),
                    ),
                  if (widget.badge > 0)
                    Positioned(
                      top: widget.size * 0.04,
                      right: widget.size * 0.04,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(
                            kitStyle.value.corner(7),
                          ),
                          color: theme.kitAccent,
                        ),
                        child: Text(
                          widget.badge > 99 ? '99+' : '${widget.badge}',
                          style: theme.text.systemBarCaption.inLook.copyWith(
                            color: theme.colors.background,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMenu(BuildContext context, OverlayChildLayoutInfo layout) {
    final theme = context.shellTheme;
    final anchor = MatrixUtils.transformRect(
      layout.childPaintTransform,
      Offset.zero & layout.childSize,
    );
    final scene = Offset.zero & layout.overlaySize;
    final output = widget.monitorBounds.intersect(scene);
    final bounds = output.isEmpty ? scene : output;
    final width = math.min(
      dockLookMetrics.menuWidth,
      math.max(0.0, bounds.width - 16),
    );
    final maxHeight = switch (widget.position) {
      DockPosition.bottom => math.max(0.0, anchor.top - bounds.top - 16),
      DockPosition.top => math.max(0.0, bounds.bottom - anchor.bottom - 16),
      DockPosition.left || DockPosition.right => math.max(0.0, bounds.height - 16),
    };
    if (width <= 0 || maxHeight <= 0) return const SizedBox.shrink();
    final placement = dockMenuAnchor(
      anchor: anchor,
      output: bounds,
      width: width,
      position: widget.position,
    );
    if (placement == null) return const SizedBox.shrink();
    return ShellInputRegion(
      debugLabel: 'Dock accessory menu',
      pointerPolicy: ShellPointerPolicy.fullScene,
      keyboardPolicy: ShellKeyboardPolicy.capture,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): _closeMenu,
        },
        child: Focus(
          autofocus: true,
          child: Stack(
            children: [
              Positioned.fill(
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (_) => _closeMenu(),
                  child: const ColoredBox(color: Color(0x00000000)),
                ),
              ),
              DockMenuLayer(
                anchor: placement,
                overlaySize: layout.overlaySize,
                child: DockMenuPanel(
                  radius: dockMenuRadius(context),
                  maxHeight: maxHeight,
                  tail: placement.tail,
                  tailAlignment: placement.tailAlignment,
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
                            child: Text(
                              widget.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.text.systemBarCaption.inLook.copyWith(
                                color: theme.colors.textTertiary,
                              ),
                            ),
                          ),
                          ...widget.menuBuilder(context, _closeMenu),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A transfer's progress along the bottom of a stack icon.
///
/// A folder that reserves its final size shows a real fraction; a browser
/// download, which records no total anywhere, shows a short sweep instead of
/// a bar that would claim to know how far along it is.
class _DownloadBar extends StatefulWidget {
  const _DownloadBar({
    required this.download,
    required this.color,
    required this.track,
  });

  final DockDownloadProgress download;
  final Color color;
  final Color track;

  @override
  State<_DownloadBar> createState() => _DownloadBarState();
}

class _DownloadBarState extends State<_DownloadBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    // A loop: it keeps its rhythm and only the speed scales it.
    duration: KitMotion.now.scaled(KitMotion.sweep),
  );

  @override
  void initState() {
    super.initState();
    _syncSweep();
  }

  @override
  void didUpdateWidget(covariant _DownloadBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncSweep();
  }

  void _syncSweep() {
    if (widget.download.determinate) {
      if (_sweep.isAnimating) _sweep.stop();
    } else if (!_sweep.isAnimating) {
      _sweep.repeat();
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 3,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(kitStyle.value.pill(3)),
        child: ColoredBox(
          color: widget.track,
          child: widget.download.determinate
              ? FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: widget.download.value,
                  child: ColoredBox(color: widget.color),
                )
              : AnimatedBuilder(
                  animation: _sweep,
                  builder: (context, _) => CustomPaint(
                    painter: _SweepPainter(
                      progress: _sweep.value,
                      color: widget.color,
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

/// A short bar travelling left to right, for a transfer with no known total.
class _SweepPainter extends CustomPainter {
  const _SweepPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width * 0.35;
    final left = (size.width + width) * progress - width;
    canvas.drawRect(
      Rect.fromLTWH(left, 0, width, size.height),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _SweepPainter old) =>
      old.progress != progress || old.color != color;
}

/// The trash can. It counts its items when mounted, after emptying, and on a
/// slow poll, because the shell offers no trash-change event.
class DockTrashItem extends StatefulWidget {
  const DockTrashItem({
    required this.size,
    required this.lift,
    required this.position,
    required this.zh,
    required this.onOverlayChanged,
    required this.monitorBounds,
    required this.onOpenSettings,
    this.appearance = DockAppearance.macos,
    super.key,
  });

  final double size;
  final double lift;
  final DockPosition position;
  final bool zh;
  final ValueChanged<bool> onOverlayChanged;
  final Rect monitorBounds;
  final VoidCallback onOpenSettings;
  final DockAppearance appearance;

  @override
  State<DockTrashItem> createState() => _DockTrashItemState();
}

class _DockTrashItemState extends State<DockTrashItem> {
  List<String>? _roots;
  int _count = 0;
  bool _emptyRequested = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  bool _refreshing = false;

  Future<List<String>> _trashRootsAsync() async {
    final cached = _roots;
    if (cached != null) return cached;
    final env = Platform.environment;
    final uid = await DockExtras.readUidAsync() ?? 1000;
    final mounts = await DockExtras.readMountPointsAsync();
    final roots = DockExtras.trashRoots(
      env: env,
      uid: uid,
      mountPoints: mounts,
    );
    _roots = roots;
    return roots;
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final roots = await _trashRootsAsync();
      final count = await DockExtras.countTrashAsync(roots);
      if (!mounted) return;
      if (count != _count) setState(() => _count = count);
    } finally {
      _refreshing = false;
    }
  }

  String get _label => widget.zh ? '回收站' : 'Trash';

  Future<void> _open() async {
    final opened = await DockExtras.openTrash();
    if (!opened) {
      final roots = await _trashRootsAsync();
      if (roots.isNotEmpty) {
        await DockExtras.openPath('${roots.first}/files');
      }
    }
  }

  Future<void> _empty() async {
    if (_count == 0) return;
    if (!_emptyRequested) {
      // Emptying is irreversible, so the first press only arms the action.
      setState(() => _emptyRequested = true);
      return;
    }
    setState(() => _emptyRequested = false);
    await DockExtras.emptyTrash(await _trashRootsAsync());
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final full = _count > 0;
    final mac = widget.appearance == DockAppearance.macos;
    return DockAccessoryItem(
      label: full ? '$_label ($_count)' : _label,
      icon: full ? Icons.delete_rounded : Icons.delete_outline_rounded,
      size: widget.size,
      lift: widget.lift,
      position: widget.position,
      // The macOS can shows its state in the artwork, so a count pill on top
      // of it would be a second, redundant badge.
      badge: mac ? 0 : _count,
      onTap: _open,
      onOverlayChanged: (open) {
        if (!open && _emptyRequested) {
          setState(() => _emptyRequested = false);
        }
        widget.onOverlayChanged(open);
      },
      monitorBounds: widget.monitorBounds,
      face: mac
          ? (pressed) =>
                DockTrashIcon(size: widget.size, pressed: pressed, full: full)
          : null,
      menuBuilder: (context, close) => [
        DockMenuRow(
          icon: Icons.open_in_new,
          label: widget.zh ? '打开回收站' : 'Open Trash',
          onTap: () {
            close();
            _open();
          },
        ),
        DockMenuRow(
          icon: Icons.delete_forever_outlined,
          label: _emptyRequested
              ? (widget.zh ? '再次点击：清空回收站' : 'Click again to empty')
              : (widget.zh ? '清空回收站' : 'Empty Trash'),
          onTap: _empty,
        ),
        DockMenuRow(
          icon: Icons.tune,
          label: widget.zh ? 'Dock 设置…' : 'Dock settings…',
          onTap: () {
            close();
            widget.onOpenSettings();
          },
        ),
      ],
    );
  }
}

/// A single file pinned to the dock: its own picture or type icon, opening in
/// whatever the system uses for that kind. macOS keeps a dragged-out file
/// beside the stacks, so the dock does the same.
class DockFileItem extends StatefulWidget {
  const DockFileItem({
    required this.file,
    required this.size,
    required this.lift,
    required this.position,
    required this.zh,
    required this.onOpen,
    required this.onReveal,
    required this.onRemove,
    required this.onOpenSettings,
    required this.onOverlayChanged,
    required this.monitorBounds,
    this.appearance = DockAppearance.macos,
    super.key,
  });

  final DockFile file;
  final double size;
  final double lift;
  final DockPosition position;
  final bool zh;
  final VoidCallback onOpen;
  final VoidCallback onReveal;
  final VoidCallback onRemove;
  final VoidCallback onOpenSettings;
  final ValueChanged<bool> onOverlayChanged;
  final Rect monitorBounds;
  final DockAppearance appearance;

  @override
  State<DockFileItem> createState() => _DockFileItemState();
}

class _DockFileItemState extends State<DockFileItem> {
  String? _preview;

  @override
  void initState() {
    super.initState();
    _preview = DockStackThumbs.preview(widget.file.path);
    dockThumbsRevision.addListener(_onThumbs);
    unawaited(DockStackThumbs.request(<String>[widget.file.path]));
    unawaited(DockMimeIcons.request(<String>[widget.file.path]));
  }

  @override
  void didUpdateWidget(covariant DockFileItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.path != widget.file.path) {
      _preview = DockStackThumbs.preview(widget.file.path);
      unawaited(DockStackThumbs.request(<String>[widget.file.path]));
      unawaited(DockMimeIcons.request(<String>[widget.file.path]));
    }
  }

  @override
  void dispose() {
    dockThumbsRevision.removeListener(_onThumbs);
    super.dispose();
  }

  void _onThumbs() {
    if (!mounted) return;
    final next = DockStackThumbs.preview(widget.file.path);
    if (next != _preview) setState(() => _preview = next);
  }

  @override
  Widget build(BuildContext context) {
    final extension = DockStackFiles.extensionOf(widget.file.path);
    final art = _FileArt(
      path: widget.file.path,
      preview: _preview,
      icon: stackFileIcon(extension),
      color: stackFileColor(extension),
      size: widget.size,
    );
    return DockAccessoryItem(
      label: widget.file.label,
      icon: stackFileIcon(extension),
      size: widget.size,
      lift: widget.lift,
      position: widget.position,
      onTap: widget.onOpen,
      onOverlayChanged: widget.onOverlayChanged,
      monitorBounds: widget.monitorBounds,
      // The macOS dock shows a pinned file as its own artwork; the Denial
      // look keeps the accent tile with the type glyph inside it.
      face: widget.appearance == DockAppearance.macos ? (pressed) => art : null,
      glyph: widget.appearance == DockAppearance.macos ? null : art,
      menuBuilder: (context, close) => [
        DockMenuRow(
          icon: Icons.open_in_new,
          label: widget.zh ? '打开' : 'Open',
          onTap: () {
            close();
            widget.onOpen();
          },
        ),
        DockMenuRow(
          icon: Icons.folder_open_outlined,
          label: widget.zh ? '在文件管理器中显示' : 'Show in Files',
          onTap: () {
            close();
            widget.onReveal();
          },
        ),
        DockMenuSeparator(),
        DockMenuSubmenuRow(
          icon: Icons.tune,
          label: widget.zh ? '选项' : 'Options',
          submenu: (context) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DockMenuRow(
                icon: Icons.remove_circle_outline,
                label: widget.zh ? '从 Dock 中移除' : 'Remove from Dock',
                onTap: () {
                  close();
                  widget.onRemove();
                },
              ),
              DockMenuRow(
                icon: Icons.settings_outlined,
                label: widget.zh ? 'Dock 设置…' : 'Dock settings…',
                onTap: () {
                  close();
                  widget.onOpenSettings();
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A file's picture: its thumbnail, or the type glyph on a card when the file
/// has none. Clipped to the dock's tile radius so it reads as one item.
class _FileArt extends StatelessWidget {
  const _FileArt({
    required this.path,
    required this.preview,
    required this.icon,
    required this.color,
    required this.size,
  });

  final String path;
  final String? preview;
  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final mimeIcon = preview == null ? DockMimeIcons.iconPathCached(path) : null;
    final glyph = Icon(icon, size: size * 0.52, color: color);
    final Widget fallback = DecoratedBox(
      decoration: BoxDecoration(
        color: theme.panelColor(theme.colors.surfaceContainerHigh),
        border: Border.all(color: theme.colors.hairline),
      ),
      child: Center(child: glyph),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.22),
      child: preview != null
          ? Image.file(
              File(preview!),
              width: size,
              height: size,
              fit: BoxFit.cover,
              cacheWidth: (size * 3).round(),
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => fallback,
            )
          : mimeIcon != null
          ? DecoratedBox(
              decoration: BoxDecoration(
                color: theme.panelColor(theme.colors.surfaceContainerHigh),
                border: Border.all(color: theme.colors.hairline),
              ),
              child: Padding(
                padding: EdgeInsets.all(size * 0.14),
                child: Image.file(
                  File(mimeIcon),
                  fit: BoxFit.contain,
                  cacheWidth: (size * 2).round(),
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => Center(child: glyph),
                ),
              ),
            )
          : fallback,
    );
  }
}

/// A folder shortcut. Clicking fans the folder's contents out above the icon,
/// the way a macOS Stack does; the menu opens the folder in the file manager
/// or removes it from the dock.
class DockFolderItem extends StatefulWidget {
  const DockFolderItem({
    required this.folder,
    required this.size,
    required this.lift,
    required this.position,
    required this.zh,
    required this.onRemove,
    required this.onOverlayChanged,
    required this.monitorBounds,
    required this.onOpenSettings,
    required this.onSetView,
    required this.onSetSort,
    required this.onSetStacked,
    required this.onReorder,
    this.workArea,
    this.appearance = DockAppearance.macos,
    this.trashRect,
    super.key,
  });

  final DockFolder folder;
  final double size;
  final double lift;
  final DockPosition position;
  final bool zh;
  final VoidCallback onRemove;
  final ValueChanged<bool> onOverlayChanged;
  final Rect monitorBounds;

  /// The output minus the system bar strip, which bounds the open fan.
  final Rect? workArea;

  /// Which icon language the stack draws itself in.
  final DockAppearance appearance;
  final VoidCallback onOpenSettings;
  final ValueChanged<DockStackMode> onSetView;
  final ValueChanged<DockStackSortMode> onSetSort;
  final ValueChanged<bool> onSetStacked;

  /// A dragged order from the open stack, in file names.
  final ValueChanged<List<String>> onReorder;

  /// The trash icon's rectangle in scene coordinates, so a row dragged out of
  /// the stack can be dropped on it. Null when the dock hides the trash, and
  /// then a drag reorders only.
  final Rect? trashRect;

  @override
  State<DockFolderItem> createState() => _DockFolderItemState();
}

class _DockFolderItemState extends State<DockFolderItem> {
  final OverlayPortalController _fan = OverlayPortalController();
  bool _fanOpen = false;
  List<DockStackEntry> _entries = const [];
  String? _preview;
  DockDownloadProgress? _download;
  Timer? _downloadPoll;
  DockStackWatch? _watch;

  StreamSubscription<List<String>>? _debug;

  /// A view asked for by a debug command, for this opening only.
  DockStackMode? _debugView;

  @override
  void initState() {
    super.initState();
    dockThumbsRevision.addListener(_onThumbs);
    _scheduleRefresh();
    _debug = DockDebug.commands.listen((words) {
      if (!mounted) return;
      if (words.first == 'close') return _closeFan();
      if (words.first != 'folder' ||
          words.length < 2 ||
          !widget.folder.label.toLowerCase().contains(words[1])) {
        return;
      }
      _closeFan();
      _debugView = words.length > 2
          ? DockStackMode.values.asNameMap()[words[2]]
          : null;
      _toggleFan();
    });
  }

  void _onThumbs() {
    if (!mounted || _entries.isEmpty) return;
    final next = DockStackThumbs.preview(_entries.first.path);
    if (next != _preview) {
      setState(() => _preview = next);
    } else if (widget.folder.stacked) {
      setState(() {});
    }
  }

  @override
  void didUpdateWidget(covariant DockFolderItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.folder.path != widget.folder.path) {
      _closeFan();
      _preview = null;
      _download = null;
      _scheduleRefresh();
      return;
    }
    // A sort or order change re-reads the listing whether or not the fan is
    // open: the icon's pile is drawn from the same list, and the sort menu
    // can be reached from the icon without ever opening the fan.
    if (oldWidget.folder.sort != widget.folder.sort ||
        !_sameOrder(oldWidget.folder.order, widget.folder.order)) {
      _reloadEntries();
    }
  }

  static bool _sameOrder(List<String> first, List<String> second) {
    if (first.length != second.length) return false;
    for (var i = 0; i < first.length; i++) {
      if (first[i] != second[i]) return false;
    }
    return true;
  }

  @override
  void dispose() {
    dockThumbsRevision.removeListener(_onThumbs);
    _downloadPoll?.cancel();
    unawaited(_debug?.cancel());
    _watch?.stop();
    if (_fanOpen) widget.onOverlayChanged(false);
    super.dispose();
  }

  /// Reads the icon's picture after the dock has painted: the walk is
  /// synchronous, and a large folder must not delay the first frame.
  void _scheduleRefresh() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _refresh();
    });
  }

  void _requestPileThumbs(List<DockStackEntry> entries, {bool all = false}) {
    final slice = all ? entries : entries.take(DockPile.count);
    final paths = <String>[
      for (final e in slice)
        if (!e.isDirectory) e.path,
    ];
    if (paths.isNotEmpty) {
      unawaited(DockStackThumbs.request(paths));
      unawaited(DockMimeIcons.request(paths));
    }
  }

  /// Re-reads the folder for the icon and the download bar off the UI thread.
  Future<void> _refresh() async {
    final entries = await DockStackFiles.listAsync(
      widget.folder.path,
      sort: widget.folder.sort,
      order: widget.folder.order,
    );
    if (!mounted) return;
    _requestPileThumbs(entries);
    final preview = entries.isEmpty
        ? null
        : DockStackThumbs.preview(entries.first.path);
    final download = await DockStackFiles.progressAsync(entries);
    if (!mounted) return;
    // The stacked icon draws the newest few entries, so the list has to be
    // kept here too, not only when the fan opens. A card in the pile can
    // change while the first and last names stay put.
    final shown = math.min(DockPile.count, entries.length);
    final sameEntries =
        _entries.length == entries.length &&
        _samePaths(_entries, entries, shown);
    if (preview == _preview &&
        _sameDownload(download, _download) &&
        sameEntries) {
      return;
    }
    setState(() {
      _entries = entries;
      _preview = preview;
      _download = download;
    });
    _watchDownloads(download);
  }

  /// Whether the first [count] entries of both listings name the same files.
  static bool _samePaths(
    List<DockStackEntry> first,
    List<DockStackEntry> second,
    int count,
  ) {
    for (var i = 0; i < count; i++) {
      if (first[i].path != second[i].path) return false;
    }
    return true;
  }

  static bool _sameDownload(
    DockDownloadProgress? first,
    DockDownloadProgress? second,
  ) {
    if (first == null || second == null) return first == second;
    return first.files == second.files && first.fraction == second.fraction;
  }

  /// Polls while a transfer is live, because the shell reports no file change
  /// and a bar that never moves is worse than none. Stops as soon as the folder
  /// has no live download, so an idle dock does no work.
  void _watchDownloads(DockDownloadProgress? download) {
    if (download == null) {
      _downloadPoll?.cancel();
      _downloadPoll = null;
      return;
    }
    _downloadPoll ??= Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted) return;
      _refresh();
    });
  }

  /// Re-reads the listing for an open stack: called on a sort change and by
  /// the folder watch when a file lands or leaves.
  Future<void> _reloadEntries() async {
    if (!mounted) return;
    final entries = await DockStackFiles.listAsync(
      widget.folder.path,
      sort: widget.folder.sort,
      order: widget.folder.order,
    );
    if (!mounted) return;
    _requestPileThumbs(entries, all: _fanOpen);
    final preview = entries.isEmpty
        ? null
        : DockStackThumbs.preview(entries.first.path);
    final download = await DockStackFiles.progressAsync(entries);
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _preview = preview;
      _download = download;
    });
    _watchDownloads(download);
  }

  Future<void> _openFolder() async {
    _closeFan();
    await DockExtras.openPath(widget.folder.path);
  }

  /// Reads the folder and opens it. The read is a synchronous walk of one
  /// directory: the reference docks do the same, and a folder that large is
  /// already truncated at [DockStackFiles.maxEntries].
  void _toggleFan() {
    if (_fanOpen) {
      _closeFan();
      return;
    }
    final entries = DockStackFiles.list(
      widget.folder.path,
      sort: widget.folder.sort,
      order: widget.folder.order,
    );
    _requestPileThumbs(entries, all: true);
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _preview = entries.isEmpty
          ? null
          : DockStackThumbs.preview(entries.first.path);
      _fanOpen = true;
    });
    unawaited(
      DockStackFiles.progressAsync(entries).then((download) {
        if (!mounted || _sameDownload(download, _download)) return;
        setState(() => _download = download);
        _watchDownloads(download);
      }),
    );
    // The folder is watched only while it is open: a stack nobody is looking
    // at has nothing to update.
    (_watch ??= DockStackWatch(widget.folder.path, _reloadEntries)).start();
    _fan.show();
    widget.onOverlayChanged(true);
  }

  void _closeFan() {
    if (!_fanOpen) return;
    _watch?.stop();
    _watch = null;
    setState(() {
      _fanOpen = false;
      _debugView = null;
    });
    _fan.hide();
    widget.onOverlayChanged(false);
  }

  Future<void> _openEntry(DockStackEntry entry) async {
    _closeFan();
    await DockExtras.openPath(entry.path);
  }

  /// A dragged order keeps the stack open, so the user sees the result and can
  /// keep dragging. The reorder is applied to the listing in place rather than
  /// re-walking the directory on disk.
  void _reorder(List<String> order) {
    widget.onReorder(order);
    final reordered = List<DockStackEntry>.of(_entries);
    DockStackFiles.applyOrder(reordered, order);
    setState(() {
      _entries = reordered;
      _preview = reordered.isEmpty
          ? null
          : DockStackThumbs.preview(reordered.first.path);
    });
  }

  /// A row dropped on the trash. The stack closes first: the file it was
  /// showing is gone, so the listing behind it is stale either way.
  Future<void> _trash(DockStackEntry entry) async {
    _closeFan();
    final removed = await DockExtras.trashPath(entry.path);
    if (removed && mounted) _refresh();
  }

  /// The icon's rect where it sits right now, in scene coordinates.
  ///
  /// The rect the portal measured when the fan opened is the icon at the
  /// moment it was clicked — magnified, and with the dock slid aside for its
  /// neighbours. By the time the cards fold back the pointer is elsewhere and
  /// the icon has moved, so a flight aimed at the old rect lands beside it.
  Rect _iconNow(Rect fallback) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return fallback;
    // In the overlay's own space, where the fan is laid out.
    return kitOverlayRect(context, box)?.rect ?? fallback;
  }

  @override
  Widget build(BuildContext context) {
    return OverlayPortal.overlayChildLayoutBuilder(
      controller: _fan,
      overlayChildBuilder: (context, layout) {
        if (!_fanOpen) return const SizedBox.shrink();
        final anchor = MatrixUtils.transformRect(
          layout.childPaintTransform,
          Offset.zero & layout.childSize,
        );
        final scene = Offset.zero & layout.overlaySize;
        final output = widget.monitorBounds.intersect(scene);
        final bounds = output.isEmpty ? scene : output;
        final work = widget.workArea?.intersect(scene);
        return ShellInputRegion(
          debugLabel: 'Dock folder stack',
          pointerPolicy: ShellPointerPolicy.fullScene,
          keyboardPolicy: ShellKeyboardPolicy.capture,
          child: DockStackView(
            entries: _entries,
            folderPath: widget.folder.path,
            sort: widget.folder.sort,
            order: widget.folder.order,
            anchor: anchor,
            anchorNow: () => _iconNow(anchor),
            bounds: bounds,
            workArea: work == null || work.isEmpty ? null : work,
            position: widget.position,
            mode: _debugView ?? widget.folder.view,
            title: widget.folder.label,
            zh: widget.zh,
            onDismiss: _closeFan,
            onOpenFolder: _openFolder,
            onOpenPath: (path) {
              _closeFan();
              unawaited(DockExtras.openPath(path));
            },
            onOpenEntry: _openEntry,
            onReorder: _reorder,
            trashRect: widget.trashRect,
            onTrash: widget.trashRect == null ? null : _trash,
          ),
        );
      },
      child: DockAccessoryItem(
        label: widget.folder.label,
        // While the stack is out the plain tile shows the same chevron the
        // macOS-style face does, pointing at the rows.
        icon: !_fanOpen
            ? Icons.folder_rounded
            : switch (widget.position) {
                DockPosition.bottom => Icons.keyboard_arrow_down_rounded,
                DockPosition.top => Icons.keyboard_arrow_up_rounded,
                DockPosition.left => Icons.keyboard_arrow_right_rounded,
                DockPosition.right => Icons.keyboard_arrow_left_rounded,
              },
        fill: _fanOpen || _preview == null
            ? null
            : Image.file(
                File(_preview!),
                fit: BoxFit.cover,
                cacheWidth: (widget.size * 3).round(),
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
        face: widget.appearance == DockAppearance.macos
            ? (pressed) {
                final previews = widget.folder.stacked
                    ? [
                        for (final entry in _entries.take(DockPile.count))
                          DockStackPreview(
                            // A folder is drawn as the blue folder at card
                            // size, the way macOS piles folders and files
                            // together.
                            folder: entry.isDirectory,
                            path: entry.isDirectory
                                ? null
                                : DockStackThumbs.preview(entry.path),
                            icon: entry.isDirectory
                                ? null
                                : stackFileIcon(entry.extension),
                            color: entry.isDirectory
                                ? null
                                : stackFileColor(entry.extension),
                          ),
                      ]
                    : const <DockStackPreview>[];
                // While the stack is out its cards are in the rows, so the
                // icon is a plate with a chevron pointing at them. The two
                // faces cross over rather than swap, so the pile is not gone
                // for a frame before its cards have left it.
                return AnimatedSwitcher(
                  duration: KitMotion.duration(context, KitMotion.fade),
                  switchInCurve: KitMotion.out,
                  switchOutCurve: KitMotion.out,
                  child: _fanOpen
                      ? DockStackOpenIcon(
                          key: const ValueKey('stack-open'),
                          size: widget.size,
                          quarterTurns: switch (widget.position) {
                            DockPosition.bottom => 0,
                            DockPosition.top => 2,
                            DockPosition.left => 3,
                            DockPosition.right => 1,
                          },
                        )
                      : DockStackIcon(
                          key: const ValueKey('stack-pile'),
                          size: widget.size,
                          previews: previews,
                          pressed: pressed,
                        ),
                );
              }
            : null,
        size: widget.size,
        lift: widget.lift,
        position: widget.position,
        onTap: _toggleFan,
        onOverlayChanged: widget.onOverlayChanged,
        monitorBounds: widget.monitorBounds,
        download: _download,
        menuBuilder: (context, close) => [
          // The same flat sections macOS puts on a stack's menu, in its order:
          // sort, then how the icon looks, then how the stack opens.
          DockMenuSectionLabel(widget.zh ? '排序方式' : 'Sort by'),
          for (final sort in [
            DockStackSortMode.name,
            DockStackSortMode.added,
            DockStackSortMode.modified,
            DockStackSortMode.kind,
            // A dragged order is a sort of its own; the four Finder orders
            // would otherwise all read unchecked after a drag.
            if (widget.folder.sort == DockStackSortMode.manual ||
                widget.folder.order.isNotEmpty)
              DockStackSortMode.manual,
          ])
            DockMenuRow(
              label: switch (sort) {
                DockStackSortMode.name => widget.zh ? '名称' : 'Name',
                DockStackSortMode.added => widget.zh ? '添加日期' : 'Date Added',
                DockStackSortMode.modified =>
                  widget.zh ? '修改日期' : 'Date Modified',
                DockStackSortMode.kind => widget.zh ? '种类' : 'Kind',
                DockStackSortMode.manual => widget.zh ? '自定顺序' : 'Custom Order',
              },
              selected: widget.folder.sort == sort,
              onTap: () {
                close();
                widget.onSetSort(sort);
              },
            ),
          DockMenuSeparator(),
          DockMenuSectionLabel(widget.zh ? '显示为' : 'Display as'),
          for (final stacked in const [true, false])
            DockMenuRow(
              label: stacked
                  ? (widget.zh ? '叠放' : 'Stack')
                  : (widget.zh ? '文件夹' : 'Folder'),
              selected: widget.folder.stacked == stacked,
              onTap: () {
                close();
                widget.onSetStacked(stacked);
              },
            ),
          DockMenuSeparator(),
          DockMenuSectionLabel(widget.zh ? '显示内容为' : 'View content as'),
          for (final view in const [
            DockStackMode.fan,
            DockStackMode.grid,
            DockStackMode.list,
            DockStackMode.auto,
          ])
            DockMenuRow(
              label: switch (view) {
                DockStackMode.fan => widget.zh ? '扇状' : 'Fan',
                DockStackMode.grid => widget.zh ? '网格' : 'Grid',
                DockStackMode.list => widget.zh ? '列表' : 'List',
                DockStackMode.auto => widget.zh ? '自动' : 'Automatic',
              },
              selected: widget.folder.view == view,
              onTap: () {
                close();
                widget.onSetView(view);
              },
            ),
          DockMenuSeparator(),
          DockMenuSubmenuRow(
            icon: Icons.tune,
            label: widget.zh ? '选项' : 'Options',
            submenu: (context) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DockMenuRow(
                  icon: Icons.remove_circle_outline,
                  label: widget.zh ? '从 Dock 中移除' : 'Remove from Dock',
                  onTap: () {
                    close();
                    widget.onRemove();
                  },
                ),
                DockMenuRow(
                  icon: Icons.settings_outlined,
                  label: widget.zh ? 'Dock 设置…' : 'Dock settings…',
                  onTap: () {
                    close();
                    widget.onOpenSettings();
                  },
                ),
              ],
            ),
          ),
          DockMenuRow(
            label: widget.zh
                ? '打开“${widget.folder.label}”'
                : 'Open “${widget.folder.label}”',
            onTap: () {
              close();
              _openFolder();
            },
          ),
        ],
      ),
    );
  }
}
