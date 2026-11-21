import 'dart:io';
import 'dart:math' as math;

import 'package:denial_flutter_sdk/effects.dart';
import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dock_extras.dart';
import 'dock_preferences.dart';

/// The dock settings sheet. Denial gives plugins no settings page, so the sheet
/// is shown as a managed shell popup: it gets the scene barrier, focus, Escape
/// and an outside tap to dismiss for free, and it paints above every surface.
class DockSettingsPanel extends ConsumerStatefulWidget {
  const DockSettingsPanel({required this.onClose, super.key});

  final VoidCallback onClose;

  @override
  ConsumerState<DockSettingsPanel> createState() => _DockSettingsPanelState();
}

class _DockSettingsPanelState extends ConsumerState<DockSettingsPanel> {
  /// Non-null while the folder browser is open.
  String? _browsePath;
  bool _showHidden = false;

  bool get _zh => Localizations.localeOf(context).languageCode == 'zh';

  DockSettingsController get _controller =>
      ref.read(dockSettingsProvider.notifier);

  String _home() {
    final home = Platform.environment['HOME'];
    return home != null && home.startsWith('/') ? home : '/';
  }

  @override
  Widget build(BuildContext context) {
    final settings =
        ref.watch(dockSettingsProvider).value ?? DockSettings.defaults;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.min(
          460.0,
          math.max(280.0, constraints.maxWidth - 32),
        );
        final height = math.min(
          620.0,
          math.max(260.0, constraints.maxHeight - 48),
        );
        return Center(
          child: GestureDetector(
            // The barrier behind the sheet closes the popup on tap; the sheet
            // itself must win that gesture so taps inside it do nothing.
            behavior: HitTestBehavior.opaque,
            onTap: () {},
            child: SizedBox(
              width: width,
              height: height,
              child: _buildShell(context, settings),
            ),
          ),
        );
      },
    );
  }

  Widget _buildShell(BuildContext context, DockSettings settings) {
    final theme = context.shellTheme;
    final radius = theme.borderRadius(18);
    final browsing = _browsePath != null;
    return ShellBackdropBlur(
      blur: theme.effectivePanelOpacity < 1,
      separateChild: true,
      borderRadius: radius,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.panelColor(theme.colors.surfaceContainer),
          borderRadius: radius,
          border: Border.all(color: theme.colors.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(context, browsing),
            SizedBox(
              height: 1,
              child: ColoredBox(color: theme.colors.hairline),
            ),
            Expanded(
              child: browsing
                  ? _buildBrowser(context)
                  : _buildBody(context, settings),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context, bool browsing) {
    final theme = context.shellTheme;
    final colors = theme.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
      child: Row(
        children: [
          if (browsing)
            _IconButton(
              icon: Icons.arrow_back_rounded,
              tooltip: _zh ? '返回' : 'Back',
              onPressed: () => setState(() => _browsePath = null),
            )
          else
            Icon(Icons.tune_rounded, size: 19, color: theme.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  browsing
                      ? (_zh ? '选择文件夹' : 'Choose a folder')
                      : (_zh ? 'Dock 设置' : 'Dock settings'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.text.base.copyWith(
                    color: colors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (browsing)
                  Text(
                    _browsePath!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.text.systemBarCaption.copyWith(
                      color: colors.textTertiary,
                      // The caption token uses height 1, which clips descenders
                      // once the divider sits directly beneath it.
                      height: 1.3,
                    ),
                  ),
              ],
            ),
          ),
          _IconButton(
            icon: Icons.close_rounded,
            tooltip: _zh ? '关闭' : 'Close',
            onPressed: widget.onClose,
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, DockSettings settings) {
    final theme = context.shellTheme;
    final colors = theme.colors;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionLabel(_zh ? '行为' : 'Behaviour'),
          _Segmented<DockVisibilityMode>(
            value: settings.visibility,
            options: [
              (
                DockVisibilityMode.smart,
                _zh ? '智能隐藏' : 'Smart hide',
                Icons.visibility_off_outlined,
              ),
              (
                DockVisibilityMode.always,
                _zh ? '始终显示' : 'Always show',
                Icons.visibility_outlined,
              ),
            ],
            onChanged: (value) => _controller.setVisibility(value),
          ),
          const SizedBox(height: 14),
          _RowLabel(_zh ? '点击已打开的应用' : 'Clicking an open application'),
          _Segmented<DockClickAction>(
            value: settings.clickAction,
            options: [
              (
                DockClickAction.minimize,
                _zh ? '最小化' : 'Minimize',
                Icons.vertical_align_bottom,
              ),
              (
                DockClickAction.cycle,
                _zh ? '切换窗口' : 'Cycle windows',
                Icons.swap_horiz,
              ),
            ],
            onChanged: (value) => _controller.setClickAction(value),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 2),
            child: Text(
              settings.clickAction == DockClickAction.cycle
                  ? (_zh
                        ? '再次点击会把下一个窗口切到前台，按窗口列表顺序循环。'
                        : 'Another click brings the next window forward, '
                              'in window-list order.')
                  : (_zh
                        ? '点击最前面的应用会最小化它的当前窗口。'
                        : 'Clicking the front-most application minimizes its '
                              'active window.'),
              style: theme.text.systemBarCaption.copyWith(
                color: colors.textTertiary,
                height: 1.35,
              ),
            ),
          ),
          const SizedBox(height: 18),
          _SectionLabel(_zh ? '外观' : 'Appearance'),
          _Stepper(
            label: _zh ? '图标大小' : 'Icon size',
            value: settings.iconSize,
            display: '${settings.iconSize.round()}',
            onStep: (delta) => _controller.setIconSize(
              settings.iconSize + delta * DockSettings.iconSizeStep,
            ),
          ),
          const SizedBox(height: 18),
          _SectionLabel(_zh ? '布局' : 'Layout'),
          _RowLabel(_zh ? '启动台' : 'Launcher'),
          _Segmented<DockSide>(
            value: settings.launcherSide,
            options: [
              (DockSide.left, _zh ? '左侧' : 'Left', Icons.align_horizontal_left),
              (
                DockSide.right,
                _zh ? '右侧' : 'Right',
                Icons.align_horizontal_right,
              ),
              (DockSide.hidden, _zh ? '隐藏' : 'Hidden', Icons.visibility_off),
            ],
            onChanged: (value) => _controller.setLauncherSide(value),
          ),
          const SizedBox(height: 14),
          _RowLabel(_zh ? '文件夹与回收站' : 'Folders and Trash'),
          _Segmented<DockSide>(
            value: settings.extrasSide,
            options: [
              (DockSide.left, _zh ? '左侧' : 'Left', Icons.align_horizontal_left),
              (
                DockSide.right,
                _zh ? '右侧' : 'Right',
                Icons.align_horizontal_right,
              ),
              (DockSide.hidden, _zh ? '隐藏' : 'Hidden', Icons.visibility_off),
            ],
            onChanged: (value) => _controller.setExtrasSide(value),
          ),
          const SizedBox(height: 6),
          _ToggleRow(
            label: _zh ? '显示回收站' : 'Show Trash',
            value: settings.showTrash,
            onChanged: (value) => _controller.setShowTrash(show: value),
          ),
          const SizedBox(height: 12),
          _RowLabel(_zh ? '文件夹快捷方式' : 'Folder shortcuts'),
          if (settings.folders.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 4, 0, 8),
              child: Text(
                _zh ? '还没有添加文件夹。' : 'No folders added yet.',
                style: theme.text.systemBarCaption.copyWith(
                  color: colors.textTertiary,
                ),
              ),
            ),
          for (final folder in settings.folders)
            _FolderRow(
              folder: folder,
              onRemove: () => _controller.removeFolder(folder.path),
            ),
          _ActionRow(
            icon: Icons.create_new_folder_outlined,
            label: _zh ? '添加文件夹…' : 'Add folder…',
            onTap: () => setState(() {
              _browsePath = _home();
              _showHidden = false;
            }),
          ),
          const SizedBox(height: 18),
          Text(
            _zh
                ? '打开的文件夹和回收站使用系统默认程序（xdg-open / gio）。'
                : 'Folders and the Trash open with the system handler '
                      '(xdg-open / gio).',
            style: theme.text.systemBarCaption.copyWith(
              color: colors.textTertiary,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBrowser(BuildContext context) {
    final theme = context.shellTheme;
    final colors = theme.colors;
    final path = _browsePath ?? _home();
    final directories = DockExtras.listDirectories(path);
    final visible = [
      for (final directory in directories)
        if (_showHidden || !_basename(directory).startsWith('.')) directory,
    ];
    final parent = _parentOf(path);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 6),
            children: [
              _ToggleRow(
                label: _zh ? '显示隐藏文件夹' : 'Show hidden folders',
                value: _showHidden,
                onChanged: (value) => setState(() => _showHidden = value),
              ),
              if (parent != null)
                _ActionRow(
                  icon: Icons.drive_file_move_outline,
                  label: '..',
                  onTap: () => setState(() => _browsePath = parent),
                ),
              for (final directory in visible)
                _ActionRow(
                  icon: Icons.folder_outlined,
                  label: _basename(directory),
                  onTap: () => setState(() => _browsePath = directory),
                ),
              if (visible.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Text(
                    _zh ? '此文件夹里没有子文件夹。' : 'No subfolders here.',
                    style: theme.text.systemBarCaption.copyWith(
                      color: colors.textTertiary,
                    ),
                  ),
                ),
            ],
          ),
        ),
        SizedBox(height: 1, child: ColoredBox(color: colors.hairline)),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.text.systemBarCaption.copyWith(
                    color: colors.textTertiary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _PillButton(
                label: _zh ? '添加此文件夹' : 'Add this folder',
                primary: true,
                onTap: () {
                  final label = folderLabel(
                    path,
                    home: _home(),
                    homeLabel: _zh ? '主目录' : 'Home',
                  );
                  _controller.addFolder(DockFolder(path: path, label: label));
                  setState(() => _browsePath = null);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _basename(String path) {
    final trimmed = path.length > 1 && path.endsWith('/')
        ? path.substring(0, path.length - 1)
        : path;
    final index = trimmed.lastIndexOf('/');
    if (index < 0) return trimmed;
    final name = trimmed.substring(index + 1);
    return name.isEmpty ? '/' : name;
  }

  static String? _parentOf(String path) {
    if (path == '/' || path.isEmpty) return null;
    final trimmed = path.length > 1 && path.endsWith('/')
        ? path.substring(0, path.length - 1)
        : path;
    final index = trimmed.lastIndexOf('/');
    if (index <= 0) return '/';
    return trimmed.substring(0, index);
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: theme.text.systemBarCaption.copyWith(
          color: theme.colors.textTertiary,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _RowLabel extends StatelessWidget {
  const _RowLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 7),
      child: Text(
        text,
        style: theme.text.systemBarCaption.copyWith(
          color: theme.colors.textSecondary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// A segmented control. Denial's shell has no Material ancestor, so this is a
/// hand-drawn pill row instead of a Material widget.
class _Segmented<T> extends StatelessWidget {
  const _Segmented({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final T value;
  final List<(T, String, IconData)> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = theme.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: theme.borderRadius(11),
        color: colors.textPrimary.withValues(alpha: 0.06),
        border: Border.all(color: colors.hairlineSoft),
      ),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Row(
          children: [
            for (final option in options)
              Expanded(
                child: _Segment(
                  label: option.$2,
                  icon: option.$3,
                  selected: option.$1 == value,
                  onTap: () => onChanged(option.$1),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Segment extends StatefulWidget {
  const _Segment({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_Segment> createState() => _SegmentState();
}

class _SegmentState extends State<_Segment> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = theme.colors;
    final foreground = widget.selected ? theme.accent : colors.textSecondary;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          height: 34,
          decoration: BoxDecoration(
            borderRadius: theme.borderRadius(9),
            color: widget.selected
                ? Color.alphaBlend(
                    theme.accent.withValues(alpha: 0.18),
                    colors.surfaceContainerHigh,
                  )
                : _hovered
                ? colors.textPrimary.withValues(alpha: 0.05)
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(widget.icon, size: 15, color: foreground),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.text.systemBarCaption.copyWith(
                    color: foreground,
                    fontWeight: widget.selected
                        ? FontWeight.w700
                        : FontWeight.w500,
                    fontSize: 11.5,
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

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = theme.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(!value),
      child: SizedBox(
        height: 38,
        child: Row(
          children: [
            const SizedBox(width: 2),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.text.systemBarCaption.copyWith(
                  color: colors.textPrimary,
                  fontSize: 12,
                ),
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              width: 38,
              height: 22,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(11),
                color: value
                    ? theme.accent
                    : colors.textPrimary.withValues(alpha: 0.16),
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOutCubic,
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: value ? colors.background : colors.surfaceContainer,
                  ),
                  child: const SizedBox.square(dimension: 18),
                ),
              ),
            ),
            const SizedBox(width: 2),
          ],
        ),
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.label,
    required this.value,
    required this.display,
    required this.onStep,
  });

  final String label;
  final double value;
  final String display;
  final ValueChanged<double> onStep;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = theme.colors;
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          const SizedBox(width: 2),
          Expanded(
            child: Text(
              label,
              style: theme.text.systemBarCaption.copyWith(
                color: colors.textPrimary,
                fontSize: 12,
              ),
            ),
          ),
          _StepButton(
            icon: Icons.remove_rounded,
            enabled: value > DockSettings.minIconSize,
            onTap: () => onStep(-1),
          ),
          SizedBox(
            width: 46,
            child: Text(
              display,
              textAlign: TextAlign.center,
              style: theme.text.systemBarCaption.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
              ),
            ),
          ),
          _StepButton(
            icon: Icons.add_rounded,
            enabled: value < DockSettings.maxIconSize,
            onTap: () => onStep(1),
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = theme.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          borderRadius: theme.borderRadius(9),
          color: colors.textPrimary.withValues(alpha: enabled ? 0.07 : 0.02),
          border: Border.all(color: colors.hairlineSoft),
        ),
        child: Icon(
          icon,
          size: 17,
          color: colors.textPrimary.withValues(alpha: enabled ? 1 : 0.3),
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = theme.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: 38,
        child: Row(
          children: [
            const SizedBox(width: 2),
            Icon(icon, size: 17, color: colors.textSecondary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.text.systemBarCaption.copyWith(
                  color: colors.textPrimary,
                  fontSize: 12,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 16,
              color: colors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}

class _FolderRow extends StatelessWidget {
  const _FolderRow({required this.folder, required this.onRemove});

  final DockFolder folder;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = theme.colors;
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          const SizedBox(width: 2),
          Icon(Icons.folder_rounded, size: 18, color: theme.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  folder.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.text.systemBarCaption.copyWith(
                    color: colors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  folder.path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.text.systemBarCaption.copyWith(
                    color: colors.textTertiary,
                    fontSize: 10.5,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onRemove,
            child: SizedBox(
              width: 34,
              height: 34,
              child: Icon(
                Icons.remove_circle_outline,
                size: 18,
                color: colors.textTertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = theme.colors;
    final foreground = primary ? colors.background : colors.textPrimary;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          color: primary
              ? theme.accent
              : colors.textPrimary.withValues(alpha: 0.08),
          border: primary ? null : Border.all(color: colors.hairlineSoft),
        ),
        child: Center(
          child: Text(
            label,
            maxLines: 1,
            style: theme.text.systemBarCaption.copyWith(
              color: foreground,
              fontWeight: FontWeight.w700,
              fontSize: 11.5,
            ),
          ),
        ),
      ),
    );
  }
}

class _IconButton extends StatelessWidget {
  const _IconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = theme.colors;
    return Semantics(
      button: true,
      label: tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: SizedBox(
          width: 34,
          height: 34,
          child: Icon(icon, size: 19, color: colors.textSecondary),
        ),
      ),
    );
  }
}
