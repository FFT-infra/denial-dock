import 'dart:math' as math;

import 'package:denial_flutter_sdk/models.dart';
import 'package:denial_flutter_sdk/services.dart';
import 'package:denial_flutter_sdk/state.dart';
import 'package:denial_flutter_sdk/theme.dart';
import 'package:denial_shell_kit/kit_motion.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bar_icons.dart';
import '../bar_panel.dart';
import '../bar_preferences.dart';
import '../bar_settings.dart';
import '../bar_type.dart';
import '../debug_remote.dart';
import '../l10n.dart';
import 'mac_kit.dart';
import 'tile_grid.dart';
import 'widgets.dart';

const double notificationCenterWidth = 360;

/// Opens the column of notifications and widgets at the bar's far end. There
/// is no slab behind it: every card floats on the desktop on its own.
void showNotificationCenter({
  required WidgetRef ref,
  required ShellServices services,
  required PanelEdge side,
  required double barHeight,
  bool notifications = true,
  bool widgets = true,
  String panelId = 'clock',
}) {
  if (kitOpenPanel.value == panelId) {
    closeKitPanel();
    return;
  }
  showKitLayer(
    ref: ref,
    keyName: kitPanelKey,
    panelId: panelId,
    open: KitMotion.settle,
    close: KitMotion.enter,
    builder: (context, close) => _Column(
      services: services,
      side: side,
      barHeight: barHeight,
      notifications: notifications,
      widgets: widgets,
      onClose: close,
    ),
  );
}

class _Column extends ConsumerStatefulWidget {
  const _Column({
    required this.services,
    required this.side,
    required this.barHeight,
    required this.notifications,
    required this.widgets,
    required this.onClose,
  });

  final ShellServices services;
  final PanelEdge side;
  final double barHeight;
  final bool notifications;
  final bool widgets;
  final VoidCallback onClose;

  @override
  ConsumerState<_Column> createState() => _ColumnState();
}

class _ColumnState extends ConsumerState<_Column> {
  bool _editing = false;
  bool _readScheduled = false;

  @override
  void initState() {
    super.initState();
    debugCommand.addListener(_debug);
  }

  @override
  void dispose() {
    debugCommand.removeListener(_debug);
    super.dispose();
  }

  void _debug() {
    final words = debugWords();
    if (words.isEmpty) return;
    switch (words.first) {
      case 'ncedit':
        setState(() => _editing = !_editing);
      case 'widgets' when words.length > 1:
        _save(words[1].split(','));
      case 'wide' when words.length > 1:
        _resize(words[1]);
    }
  }

  ShellServices get services => widget.services;
  PanelEdge get side => widget.side;
  double get barHeight => widget.barHeight;
  bool get notifications => widget.notifications;
  bool get widgets => widget.widgets;
  VoidCallback get onClose => widget.onClose;

  void _save(List<String> ids) => ref
      .read(barSettingsProvider.notifier)
      .save((s) => s.copyWith(widgets: ids));

  void _resize(String id) => ref.read(barSettingsProvider.notifier).save((s) {
    final sizes = parseTileSizes(s.tileSizes);
    final key = widgetSizeKey(id);
    final wide = (sizes[key]?.w ?? 1) > 1;
    return s.copyWith(
      tileSizes: writeTileSizes(<String, TileSize>{
        ...sizes,
        key: TileSize(wide ? 1 : 2, 1),
      }),
    );
  });

  List<Widget> _widgets(BuildContext context, double width) {
    final theme = context.shellTheme;
    final sizes = parseTileSizes(
      ref.watch(
        barSettingsProvider.select(
          (state) => state.value?.tileSizes ?? const <String>[],
        ),
      ),
    );
    bool wide(String id) => (sizes[widgetSizeKey(id)]?.w ?? 1) > 1;
    final order = ref.watch(
      barSettingsProvider.select(
        (state) => state.value?.widgets ?? defaultWidgets,
      ),
    );
    final spare = <TileChoice>[
      for (final choice in widgetLibrary)
        if (!order.contains(choice.id))
          TileChoice(
            id: choice.id,
            icon: choice.icon,
            label: context.tr(choice.label),
          ),
    ];
    return <Widget>[
      TileGrid(
        tiles: <Tile>[
          for (final id in order)
            if (widgetSize(id) != null)
              Tile(
                id: id,
                size: widgetSize(id, wide: wide(id))!,
                onResize: widgetResizable(id) ? () => _resize(id) : null,
                child: _Surface(
                  child: buildBarWidget(id, services, width, wide: wide(id)),
                ),
              ),
        ],
        columns: 2,
        cell: Size((width - widgetGap) / 2, widgetCellHeight),
        gap: widgetGap,
        editing: _editing,
        onReorder: _save,
        onRemove: (id) => _save(<String>[
          for (final other in order)
            if (other != id) other,
        ]),
      ),
      Reveal(
        open: _editing,
        child: Padding(
          padding: const EdgeInsets.only(top: widgetGap),
          child: _Surface(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      context.tr('Add Widgets'),
                      style: BarType.section.copyWith(
                        color: theme.colors.textSecondary,
                      ),
                    ),
                  ),
                  TileLibrary(
                    choices: spare,
                    empty: context.tr('Everything is already here.'),
                    onAdd: (id) => _save(<String>[...order, id]),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 12),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          if (_editing) ...<Widget>[
            _ClearChip(
              label: context.tr('Reset'),
              onTap: () => _save(defaultWidgets),
            ),
            const SizedBox(width: 8),
          ],
          _ClearChip(
            label: context.tr(_editing ? 'Done' : 'Edit Widgets'),
            onTap: () => setState(() => _editing = !_editing),
          ),
        ],
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final scene = MediaQuery.sizeOf(context);
    final animation = KitLayer.of(context).animation;
    final state = ref.watch(desktopNotificationsProvider);
    final controller = ref.read(desktopNotificationsProvider.notifier);
    final groups = notifications
        ? state.groups
        : const <DesktopNotificationGroup>[];
    // Whatever is listed here has been seen, including what arrives while
    // the column is open. The state may not change during a build.
    if (notifications && state.unreadCount > 0 && !_readScheduled) {
      _readScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _readScheduled = false;
        if (mounted) controller.markAllRead();
      });
    }
    final width = math.min(notificationCenterWidth, scene.width - 20);
    final onLeft = side == PanelEdge.left;
    final theme = context.shellTheme;

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        Positioned(
          left: onLeft ? barHeight + 10 : null,
          right: onLeft
              ? null
              : (side == PanelEdge.right ? barHeight + 10 : 10),
          top: side == PanelEdge.top ? barHeight + 8 : 10,
          bottom: side == PanelEdge.bottom ? barHeight + 8 : 10,
          width: width,
          child: AnimatedBuilder(
            animation: animation,
            builder: (context, child) {
              final forward = animation.status != AnimationStatus.reverse;
              final t = forward
                  ? KitMotion.outCubic.transform(animation.value)
                  : KitMotion.inCubic.transform(animation.value);
              return Transform.translate(
                offset: Offset((onLeft ? -1 : 1) * (width + 24) * (1 - t), 0),
                child: child,
              );
            },
            child: Align(
              alignment: Alignment.topCenter,
              child: KitCardGroup(
                child: SingleChildScrollView(
                  clipBehavior: Clip.none,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      if (groups.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(6, 0, 2, 8),
                          child: Row(
                            children: <Widget>[
                              Expanded(
                                child: Text(
                                  context.tr('Notification Center'),
                                  style: BarType.display.copyWith(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xffffffff),
                                    shadows: const <Shadow>[
                                      Shadow(
                                        color: Color(0x66000000),
                                        blurRadius: 8,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              _ClearChip(
                                label: context.tr('Clear All'),
                                onTap: controller.clearAll,
                              ),
                            ],
                          ),
                        ),
                      for (final group in groups)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _GroupStack(
                            key: ValueKey<String>(group.key),
                            group: group,
                            services: services,
                            onActivate: (id) {
                              controller.invokeDefaultAction(id);
                              onClose();
                            },
                            onDismiss: controller.dismissFromHistory,
                            onDismissGroup: () =>
                                controller.dismissGroupFromHistory(group.key),
                          ),
                        ),
                      if (widgets) ...<Widget>[
                        if (groups.isNotEmpty) const SizedBox(height: 4),
                        ..._widgets(context, width),
                      ] else if (groups.isEmpty)
                        _Surface(
                          child: SizedBox(
                            height: 72,
                            child: Center(
                              child: Text(
                                context.tr('No Notifications'),
                                style: BarType.menuRow.copyWith(
                                  color: theme.colors.textSecondary,
                                ),
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
      ],
    );
  }
}

class _Surface extends StatelessWidget {
  const _Surface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      child: KitCard(radius: 22, elevation: 0.6, child: child),
    );
  }
}

class _ClearChip extends StatelessWidget {
  const _ClearChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    return Pressable(
      onTap: onTap,
      scale: 0.92,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        child: KitCard(
          radius: 12,
          elevation: 0.3,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Text(
              label,
              style: BarType.caption.copyWith(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: theme.colors.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One application's notifications. Two or more sit as a stack with the older
/// cards peeking out underneath; a tap fans the stack open.
class _GroupStack extends StatefulWidget {
  const _GroupStack({
    required this.group,
    required this.services,
    required this.onActivate,
    required this.onDismiss,
    required this.onDismissGroup,
    super.key,
  });

  final DesktopNotificationGroup group;
  final ShellServices services;
  final ValueChanged<int> onActivate;
  final ValueChanged<int> onDismiss;
  final VoidCallback onDismissGroup;

  @override
  State<_GroupStack> createState() => _GroupStackState();
}

class _GroupStackState extends State<_GroupStack> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    final members = group.members;
    final open = _open && group.stacked;
    final peeks = open ? 0 : math.min(2, members.length - 1);
    final newest = group.newest.notification;

    return AnimatedSize(
      duration: KitMotion.loop(context, KitMotion.unfold),
      curve: KitMotion.spring,
      alignment: Alignment.topCenter,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (open)
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 2, 0, 8),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      _appName(newest),
                      style: BarType.title.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xffffffff),
                        shadows: const <Shadow>[
                          Shadow(color: Color(0x66000000), blurRadius: 8),
                        ],
                      ),
                    ),
                  ),
                  _ClearChip(
                    label: context.tr('Show Less'),
                    onTap: () => setState(() => _open = false),
                  ),
                  const SizedBox(width: 6),
                  _ClearChip(
                    label: context.tr('Clear'),
                    onTap: widget.onDismissGroup,
                  ),
                ],
              ),
            ),
          Padding(
            padding: EdgeInsets.only(bottom: peeks * 8.0),
            child: Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                for (var index = peeks; index >= 1; index--)
                  Positioned(
                    left: index * 12.0,
                    right: index * 12.0,
                    bottom: -index * 8.0,
                    height: 40,
                    child: Opacity(
                      opacity: 1 - index * 0.25,
                      child: const KitCard(
                        radius: 22,
                        elevation: 0.3,
                        child: SizedBox.expand(),
                      ),
                    ),
                  ),
                _Card(
                  notification: newest,
                  services: widget.services,
                  more: open ? 0 : members.length - 1,
                  onTap: group.stacked && !open
                      ? () => setState(() => _open = true)
                      : () => widget.onActivate(newest.id),
                  onDismiss: group.stacked && !open
                      ? widget.onDismissGroup
                      : () => widget.onDismiss(newest.id),
                ),
              ],
            ),
          ),
          if (open)
            for (final record in members.skip(1))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _Card(
                  key: ValueKey<int>(record.notification.id),
                  notification: record.notification,
                  services: widget.services,
                  more: 0,
                  onTap: () => widget.onActivate(record.notification.id),
                  onDismiss: () => widget.onDismiss(record.notification.id),
                ),
              ),
        ],
      ),
    );
  }
}

String _appName(DesktopNotification notification) =>
    notification.appName.isEmpty ? notification.sender : notification.appName;

String _when(BuildContext context, int timeMs) {
  if (timeMs <= 0) return '';
  final time = DateTime.fromMillisecondsSinceEpoch(timeMs);
  final now = DateTime.now();
  final days = DateTime(
    now.year,
    now.month,
    now.day,
  ).difference(DateTime(time.year, time.month, time.day)).inDays;
  if (days <= 0) {
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}';
  }
  return days == 1 ? context.tr('Yesterday') : context.tr('{}d ago', days);
}

/// A notification card. Drag it sideways to clear it; with a pointer, a
/// close button shows at its corner.
class _Card extends StatefulWidget {
  const _Card({
    required this.notification,
    required this.services,
    required this.more,
    required this.onTap,
    required this.onDismiss,
    super.key,
  });

  final DesktopNotification notification;
  final ShellServices services;
  final int more;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  @override
  State<_Card> createState() => _CardState();
}

class _CardState extends State<_Card> with SingleTickerProviderStateMixin {
  late final AnimationController _slide = AnimationController.unbounded(
    vsync: this,
  );
  bool _hovered = false;
  bool _gone = false;

  @override
  void dispose() {
    _slide.dispose();
    super.dispose();
  }

  void _end(DragEndDetails details, double width) {
    final velocity = details.primaryVelocity ?? 0;
    final far = _slide.value.abs() > width * 0.35 || velocity.abs() > 700;
    if (far) {
      _gone = true;
      final target = (_slide.value + velocity * 0.1) < 0 ? -width : width;
      _slide
          .animateTo(
            target * 1.2,
            duration: KitMotion.duration(context, KitMotion.enter),
            curve: KitMotion.out,
          )
          .whenComplete(widget.onDismiss);
    } else {
      _slide.animateTo(
        0,
        duration: KitMotion.duration(context, KitMotion.rebound),
        curve: KitMotion.spring,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final ink = theme.colors.textPrimary;
    final note = widget.notification;
    final summary = note.summary.replaceAll(RegExp(r'\s*\n\s*'), ' ');
    final body = note.body.replaceAll(RegExp(r'\s*\n\s*'), ' ');
    final iconId = note.desktopEntry.isNotEmpty
        ? note.desktopEntry
        : note.appName;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: (details) {
              if (!_gone) _slide.value += details.primaryDelta ?? 0;
            },
            onHorizontalDragEnd: (details) => _end(details, width),
            child: AnimatedBuilder(
              animation: _slide,
              builder: (context, child) => Transform.translate(
                offset: Offset(_slide.value, 0),
                child: Opacity(
                  opacity: (1 - _slide.value.abs() / width).clamp(0.0, 1.0),
                  child: child,
                ),
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  Pressable(
                    onTap: widget.onTap,
                    scale: 0.985,
                    child: _Surface(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: SizedBox(
                                width: 36,
                                height: 36,
                                child: iconId.isEmpty
                                    ? BarGlyph(
                                        BarIcons.bellFill,
                                        size: 22,
                                        color: theme.colors.textSecondary,
                                      )
                                    : widget.services.buildApplicationIcon(
                                        context,
                                        iconId,
                                      ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Row(
                                    children: <Widget>[
                                      Expanded(
                                        child: Text(
                                          summary.isEmpty
                                              ? _appName(note)
                                              : summary,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: BarType.title.copyWith(
                                            color: ink,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        _when(context, note.timeMs),
                                        style: BarType.caption.copyWith(
                                          color: theme.colors.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (body.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 1),
                                      child: Text(
                                        body,
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis,
                                        style: BarType.menuRow.copyWith(
                                          color: ink.withValues(alpha: 0.86),
                                        ),
                                      ),
                                    ),
                                  if (widget.more > 0)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 3),
                                      child: Text(
                                        context.tr('{} more', widget.more),
                                        style: BarType.caption.copyWith(
                                          color: theme.colors.textSecondary,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: -6,
                    top: -6,
                    child: AnimatedOpacity(
                      duration: KitMotion.duration(context, KitMotion.ease),
                      opacity: _hovered ? 1 : 0,
                      child: IgnorePointer(
                        ignoring: !_hovered,
                        child: Pressable(
                          onTap: widget.onDismiss,
                          scale: 0.85,
                          child: KitCard(
                            radius: 11,
                            elevation: 0.3,
                            child: SizedBox(
                              width: 22,
                              height: 22,
                              child: BarGlyph(
                                BarIcons.xmark,
                                size: 10,
                                color: ink,
                              ),
                            ),
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
      },
    );
  }
}
