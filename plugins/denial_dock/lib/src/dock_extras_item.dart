import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:denial_flutter_sdk/input.dart';
import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind, kPrimaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'dock_extras.dart';
import 'dock_menu.dart';
import 'dock_settings.dart';

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
    super.key,
  });

  final String label;
  final IconData icon;
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
  final FocusNode _focus = FocusNode(debugLabel: 'Dock accessory menu');
  bool _menuOpen = false;
  bool _pressed = false;
  Timer? _longPressTimer;
  Offset? _downPosition;

  @override
  void dispose() {
    _longPressTimer?.cancel();
    if (_menuOpen) widget.onOverlayChanged(false);
    _focus.dispose();
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
    _focus.requestFocus();
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
    final backing = Color.alphaBlend(
      theme.accent.withValues(alpha: 0.18),
      theme.cardColor(theme.colors.surfaceContainerHigh),
    );
    return OverlayPortal.overlayChildLayoutBuilder(
      controller: _portal,
      overlayChildBuilder: (context, layout) =>
          _menuOpen ? _buildMenu(context, layout) : const SizedBox.shrink(),
      child: Transform.translate(
        offset: switch (widget.position) {
          DockPosition.bottom => Offset(0, -widget.lift),
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
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: backing,
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Center(
                      child: Icon(
                        widget.icon,
                        size: widget.size * 0.46,
                        color: theme.accent,
                      ),
                    ),
                    Positioned.fill(
                      child: IgnorePointer(
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 90),
                          curve: Curves.easeOut,
                          opacity: _pressed ? 1 : 0,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFF000000)
                                  .withValues(alpha: 0.16),
                            ),
                          ),
                        ),
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
                            borderRadius: BorderRadius.circular(7),
                            color: theme.accent,
                          ),
                          child: Text(
                            widget.badge > 99 ? '99+' : '${widget.badge}',
                            style: theme.text.systemBarCaption.copyWith(
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
    final width = math.min(236.0, math.max(0.0, bounds.width - 16));
    final maxHeight = widget.position == DockPosition.bottom
        ? math.max(0.0, anchor.top - bounds.top - 16)
        : math.max(0.0, bounds.height - 16);
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
                  radius: theme.borderRadius(14),
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
                              style: theme.text.systemBarCaption.copyWith(
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
    super.key,
  });

  final double size;
  final double lift;
  final DockPosition position;
  final bool zh;
  final ValueChanged<bool> onOverlayChanged;
  final Rect monitorBounds;
  final VoidCallback onOpenSettings;

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

  List<String> _trashRoots() {
    final cached = _roots;
    if (cached != null) return cached;
    final env = Platform.environment;
    final uid = DockExtras.readUid() ?? 1000;
    final roots = DockExtras.trashRoots(
      env: env,
      uid: uid,
      mountPoints: DockExtras.readMountPoints(),
    );
    _roots = roots;
    return roots;
  }

  Future<void> _refresh() async {
    final count = await Future<int>.sync(
      () => DockExtras.countTrash(_trashRoots()),
    );
    if (!mounted) return;
    if (count != _count) setState(() => _count = count);
  }

  String get _label => widget.zh ? '回收站' : 'Trash';

  Future<void> _open() async {
    final opened = await DockExtras.openTrash();
    if (!opened) {
      final roots = _trashRoots();
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
    await DockExtras.emptyTrash(_trashRoots());
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final full = _count > 0;
    return DockAccessoryItem(
      label: full ? '$_label ($_count)' : _label,
      icon: full ? Icons.delete_rounded : Icons.delete_outline_rounded,
      size: widget.size,
      lift: widget.lift,
      position: widget.position,
      badge: _count,
      onTap: _open,
      onOverlayChanged: widget.onOverlayChanged,
      monitorBounds: widget.monitorBounds,
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

/// A folder shortcut. Clicking opens the folder with the session's file
/// manager; the menu can remove it from the dock.
class DockFolderItem extends StatelessWidget {
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
  final VoidCallback onOpenSettings;

  Future<void> _open() async {
    await DockExtras.openPath(folder.path);
  }

  @override
  Widget build(BuildContext context) {
    return DockAccessoryItem(
      label: folder.label,
      icon: Icons.folder_rounded,
      size: size,
      lift: lift,
      position: position,
      onTap: _open,
      onOverlayChanged: onOverlayChanged,
      monitorBounds: monitorBounds,
      menuBuilder: (context, close) => [
        DockMenuRow(
          icon: Icons.open_in_new,
          label: zh ? '打开文件夹' : 'Open folder',
          onTap: () {
            close();
            _open();
          },
        ),
        DockMenuRow(
          icon: Icons.remove_circle_outline,
          label: zh ? '从 Dock 中移除' : 'Remove from Dock',
          onTap: () {
            close();
            onRemove();
          },
        ),
        DockMenuRow(
          icon: Icons.tune,
          label: zh ? 'Dock 设置…' : 'Dock settings…',
          onTap: () {
            close();
            onOpenSettings();
          },
        ),
      ],
    );
  }
}
