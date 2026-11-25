import 'package:denial_shell_kit/kit_motion.dart';
import 'package:denial_shell_kit/kit_style.dart';
import 'package:denial_flutter_sdk/services.dart';
import 'package:denial_flutter_sdk/state.dart';
import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_menus.dart';
import '../bar_icons.dart';
import '../bar_panel.dart';
import '../bar_type.dart';
import '../l10n.dart';
import 'mac_kit.dart';

/// A capsule push button; [primary] fills it with the accent.
class DialogButton extends StatefulWidget {
  const DialogButton({
    required this.label,
    required this.onTap,
    this.primary = false,
    super.key,
  });

  final String label;
  final VoidCallback? onTap;
  final bool primary;

  @override
  State<DialogButton> createState() => _DialogButtonState();
}

class _DialogButtonState extends State<DialogButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final style = KitStyle.of(context);
    final enabled = widget.onTap != null;
    final ink = theme.colors.textPrimary;
    final fill = widget.primary
        ? theme.kitAccent.withValues(alpha: enabled ? 1 : 0.4)
        : ink.withValues(alpha: _hovered ? 0.16 : 0.10);
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          duration: KitMotion.duration(context, KitMotion.fade),
          scale: _pressed && enabled ? 0.96 : 1,
          child: AnimatedContainer(
            duration: KitMotion.duration(context, KitMotion.fade),
            height: 32,
            constraints: const BoxConstraints(minWidth: 84),
            padding: const EdgeInsets.symmetric(horizontal: 18),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(style.pill(32)),
              border: widget.primary ? null : style.controlLine(theme),
            ),
            child: Text(
              widget.label,
              style: BarType.title.copyWith(
                color: widget.primary
                    ? const Color(0xffffffff)
                    : ink.withValues(alpha: enabled ? 1 : 0.4),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// An alert: a mark, a bold question, a line of detail, Cancel and the action.
class ConfirmDialog extends StatelessWidget {
  const ConfirmDialog({
    required this.mark,
    required this.title,
    required this.detail,
    required this.action,
    required this.onConfirm,
    required this.onClose,
    super.key,
  });

  static const double width = 280;

  final Widget mark;
  final String title;
  final String detail;
  final String action;
  final VoidCallback onConfirm;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(width: 52, height: 52, child: mark),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: BarType.title.copyWith(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: theme.colors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: BarType.caption.copyWith(
              fontSize: 12,
              color: theme.colors.textSecondary,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: <Widget>[
              Expanded(
                child: DialogButton(
                  label: context.tr('Cancel'),
                  onTap: onClose,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DialogButton(
                  label: action,
                  primary: true,
                  onTap: () {
                    onClose();
                    onConfirm();
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Force Quit Applications: the running applications in a list, one selected,
/// and a button that closes every window of it.
class ForceQuitDialog extends ConsumerStatefulWidget {
  const ForceQuitDialog({
    required this.services,
    required this.onClose,
    super.key,
  });

  static const double width = 400;

  final ShellServices services;
  final VoidCallback onClose;

  @override
  ConsumerState<ForceQuitDialog> createState() => _ForceQuitDialogState();
}

class _ForceQuitDialogState extends ConsumerState<ForceQuitDialog> {
  String? _selected;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final ink = theme.colors.textPrimary;
    final state = ref.watch(shellControllerProvider);
    final catalog = ref.watch(widget.services.applications);
    final front = state.foregroundWindow?.appId;

    final apps = <String, String>{};
    for (final window in state.openAppWindows) {
      if (window.appId.isEmpty || apps.containsKey(window.appId)) continue;
      var name = '';
      for (final application in catalog) {
        if (application.appId == window.appId ||
            application.windowAppIds.contains(window.appId)) {
          name = application.name;
          break;
        }
      }
      apps[window.appId] = name.isEmpty ? window.appId : name;
    }
    final ids = apps.keys.toList()
      ..sort(
        (a, b) => apps[a]!.toLowerCase().compareTo(apps[b]!.toLowerCase()),
      );
    final selected = ids.contains(_selected)
        ? _selected
        : (ids.contains(front) ? front : null);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        WindowHeader(
          icon: BarIcons.xmarkCircleFill,
          title: context.tr('Force Quit Applications'),
          onClose: widget.onClose,
        ),
        SizedBox(height: 1, child: ColoredBox(color: theme.colors.hairline)),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
          child: Text(
            context.tr('Select an app and click Force Quit.'),
            style: BarType.menuRow.copyWith(color: ink),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            height: 224,
            decoration: BoxDecoration(
              color: ink.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(
                KitStyle.of(context).corner(8),
              ),
              border: Border.all(color: theme.colors.hairline),
            ),
            clipBehavior: Clip.antiAlias,
            child: ids.isEmpty
                ? Center(
                    child: Text(
                      context.tr('No Open Applications'),
                      style: BarType.menuRow.copyWith(
                        color: theme.colors.textTertiary,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: ids.length,
                    itemExtent: 32,
                    itemBuilder: (context, index) {
                      final id = ids[index];
                      final active = id == selected;
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => setState(() => _selected = id),
                        child: ColoredBox(
                          color: active
                              ? theme.kitAccent
                              : const Color(0x00000000),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Row(
                              children: <Widget>[
                                SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: widget.services.buildApplicationIcon(
                                    context,
                                    id,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    apps[id]!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: BarType.menuRow.copyWith(
                                      fontSize: 14,
                                      color: active
                                          ? const Color(0xffffffff)
                                          : ink,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              DialogButton(
                label: context.tr('Force Quit'),
                onTap: selected == null
                    ? null
                    : () => closeApplication(ref, selected),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The title strip Denial's own settings windows use: an accent tile, the
/// title and a close button. Dragging it moves the window.
class WindowHeader extends StatelessWidget {
  const WindowHeader({
    required this.icon,
    required this.title,
    required this.onClose,
    super.key,
  });

  final IconData icon;
  final String title;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    return KitWindowHandle(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 10, 0),
        child: SizedBox(
          height: 56,
          child: Row(
            children: <Widget>[
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: theme.kitAccent.withValues(alpha: 0.18),
                  borderRadius:
                      theme.borderRadius(8) * KitStyle.of(context).cornerScale,
                  border: Border.all(
                    color: theme.kitAccent.withValues(alpha: 0.26),
                  ),
                ),
                child: BarGlyph(icon, size: 17, color: theme.kitAccent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: BarType.title.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: theme.colors.textPrimary,
                  ),
                ),
              ),
              Pressable(
                onTap: onClose,
                scale: 0.88,
                child: const SizedBox.shrink(),
                builder: (context, hovered, pressed) => Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: theme.colors.textPrimary.withValues(
                      alpha: hovered ? 0.10 : 0,
                    ),
                    borderRadius:
                        theme.borderRadius(7) *
                        KitStyle.of(context).cornerScale,
                  ),
                  child: BarGlyph(
                    BarIcons.xmark,
                    size: 13,
                    color: theme.colors.textSecondary,
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
