import 'package:denial_flutter_sdk/theme.dart';
import 'package:denial_shell_kit/kit_style.dart';
import 'package:denial_shell_kit/kit_widgets.dart';
import 'package:flutter/material.dart'
    show InputBorder, InputDecoration, Material, MaterialType, TextField;
import 'package:flutter/widgets.dart';

import '../bar_icons.dart';
import '../bar_type.dart';
import '../l10n.dart';
import 'mac_kit.dart';
import 'widgets.dart';

/// Visual Widget Gallery for Notification Centre edit mode:
/// - Category filter pills
/// - Glass vs Color card style toggle
/// - Per-widget S / M / L size tabs before adding
/// - Inline "+ New Custom Widget" creator (Command / Shortcut / Note)
class WidgetGallery extends StatefulWidget {
  const WidgetGallery({
    required this.activeIds,
    required this.onAdd,
    super.key,
  });

  final List<String> activeIds;
  final void Function(String id, KitWidgetSize size) onAdd;

  @override
  State<WidgetGallery> createState() => _WidgetGalleryState();
}

class _WidgetGalleryState extends State<WidgetGallery> {
  KitWidgetCategory? _category;
  final Map<String, KitWidgetSize> _pickedSize = <String, KitWidgetSize>{};
  bool _creating = false;
  KitCustomWidgetKind _newKind = KitCustomWidgetKind.command;
  KitWidgetSize _newSize = KitWidgetSize.medium;
  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _bodyCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    ensureCustomWidgetsLoaded();
    kitWidgetRegistry.addListener(_refresh);
  }

  @override
  void dispose() {
    kitWidgetRegistry.removeListener(_refresh);
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _createCustom() {
    final title = _titleCtrl.text.trim();
    final body = _bodyCtrl.text.trim();
    if (title.isEmpty) return;
    final id = kitWidgetRegistry.freshCustomId(title);
    final def = KitCustomWidgetDef(
      id: id,
      title: title,
      kind: _newKind,
      command: _newKind == KitCustomWidgetKind.note ? '' : body,
      noteText: _newKind == KitCustomWidgetKind.note ? body : '',
      defaultSize: _newSize,
    );
    kitWidgetRegistry.registerCustom(def);
    persistCustomWidgets();
    _titleCtrl.clear();
    _bodyCtrl.clear();
    setState(() => _creating = false);
    widget.onAdd(id, _newSize);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final style = KitStyle.of(context);
    final accent = style.accent(theme);
    final ink = theme.colors.textPrimary;
    final available = <KitWidgetSpec>[
      for (final spec in kitWidgetRegistry.all)
        if (!widget.activeIds.contains(spec.id) &&
            spec.id != 'date' &&
            (_category == null || spec.category == _category))
          spec,
    ];

    Widget chip(String label, bool selected, VoidCallback onTap) => Pressable(
      onTap: onTap,
      scale: Pressable.small,
      wash: true,
      shape: BorderRadius.circular(style.pill(24)),
      child: Container(
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(style.pill(24)),
          color: selected ? accent : ink.withValues(alpha: 0.08),
        ),
        child: Text(
          label,
          style: BarType.caption.copyWith(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: selected ? style.onAccent(theme) : ink,
          ),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  context.tr('Widget Gallery'),
                  style: BarType.title.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: ink,
                  ),
                ),
              ),
              chip(
                context.tr(_creating ? 'Close' : '+ Custom'),
                _creating,
                () => setState(() => _creating = !_creating),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Glass vs Color card style toggle (NextKDE widgetStyle)
          ValueListenableBuilder<KitWidgetStyle>(
            valueListenable: kitWidgetStyle,
            builder: (context, wStyle, _) => Row(
              children: <Widget>[
                Text(
                  context.tr('Card style'),
                  style: BarType.caption.copyWith(
                    fontSize: 11.5,
                    color: theme.colors.textSecondary,
                  ),
                ),
                const Spacer(),
                chip(
                  context.tr('Glass'),
                  wStyle == KitWidgetStyle.glass,
                  () => kitWidgetStyle.value = KitWidgetStyle.glass,
                ),
                const SizedBox(width: 6),
                chip(
                  context.tr('Color'),
                  wStyle == KitWidgetStyle.color,
                  () => kitWidgetStyle.value = KitWidgetStyle.color,
                ),
              ],
            ),
          ),
          if (_creating) ...<Widget>[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: ink.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(style.corner(12)),
                border: style.controlLine(theme),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Wrap(
                    spacing: 6,
                    children: <Widget>[
                      for (final kind in KitCustomWidgetKind.values)
                        chip(
                          context.tr(switch (kind) {
                            KitCustomWidgetKind.command => 'Command',
                            KitCustomWidgetKind.shortcut => 'Shortcut',
                            KitCustomWidgetKind.note => 'Note',
                          }),
                          _newKind == kind,
                          () => setState(() => _newKind = kind),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _field(context, _titleCtrl, context.tr('Widget title')),
                  const SizedBox(height: 6),
                  _field(
                    context,
                    _bodyCtrl,
                    context.tr(switch (_newKind) {
                      KitCustomWidgetKind.command => 'Shell command (e.g. uptime -p)',
                      KitCustomWidgetKind.shortcut => 'Command to launch',
                      KitCustomWidgetKind.note => 'Note text',
                    }),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: <Widget>[
                      for (final s in KitWidgetSize.values) ...<Widget>[
                        chip(
                          s.gridLabel,
                          _newSize == s,
                          () => setState(() => _newSize = s),
                        ),
                        const SizedBox(width: 4),
                      ],
                      const Spacer(),
                      chip(context.tr('Create'), true, _createCustom),
                    ],
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: <Widget>[
                chip(
                  context.tr('All'),
                  _category == null,
                  () => setState(() => _category = null),
                ),
                for (final cat in KitWidgetCategory.values) ...<Widget>[
                  const SizedBox(width: 6),
                  chip(
                    context.tr(cat.label),
                    _category == cat,
                    () => setState(() => _category = cat),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          if (available.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Center(
                child: Text(
                  context.tr('Everything is already here.'),
                  style: BarType.caption.copyWith(
                    color: theme.colors.textSecondary,
                  ),
                ),
              ),
            )
          else
            Column(
              children: <Widget>[
                for (final spec in available)
                  _GalleryItem(
                    spec: spec,
                    picked: _pickedSize[spec.id] ?? spec.defaultSize,
                    onPickSize: (sz) =>
                        setState(() => _pickedSize[spec.id] = sz),
                    onAdd: () => widget.onAdd(
                      spec.id,
                      _pickedSize[spec.id] ?? spec.defaultSize,
                    ),
                    onDeleteCustom: spec.isCustom
                        ? () {
                            kitWidgetRegistry.removeCustom(spec.id);
                            persistCustomWidgets();
                          }
                        : null,
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _field(
    BuildContext context,
    TextEditingController ctrl,
    String hint,
  ) {
    final theme = context.shellTheme;
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: theme.colors.textPrimary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(KitStyle.of(context).corner(8)),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: TextField(
          controller: ctrl,
          style: BarType.caption.copyWith(
            fontSize: 12,
            color: theme.colors.textPrimary,
          ),
          decoration: InputDecoration(
            isDense: true,
            border: InputBorder.none,
            hintText: hint,
            hintStyle: BarType.caption.copyWith(
              fontSize: 12,
              color: theme.colors.textTertiary,
            ),
          ),
        ),
      ),
    );
  }
}

class _GalleryItem extends StatelessWidget {
  const _GalleryItem({
    required this.spec,
    required this.picked,
    required this.onPickSize,
    required this.onAdd,
    this.onDeleteCustom,
  });

  final KitWidgetSpec spec;
  final KitWidgetSize picked;
  final ValueChanged<KitWidgetSize> onPickSize;
  final VoidCallback onAdd;
  final VoidCallback? onDeleteCustom;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final style = KitStyle.of(context);
    final ink = theme.colors.textPrimary;
    final accent = style.accent(theme);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      decoration: BoxDecoration(
        color: ink.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(style.corner(14)),
        border: style.controlLine(theme),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(style.corner(8)),
                ),
                child: BarGlyph(
                  widgetIconFor(spec.id),
                  size: 14,
                  color: accent,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      spec.isCustom ? spec.title : context.tr(spec.title),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: BarType.title.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: ink,
                      ),
                    ),
                    if (spec.description.isNotEmpty)
                      Text(
                        spec.isCustom
                            ? spec.description
                            : context.tr(spec.description),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: BarType.caption.copyWith(
                          fontSize: 11,
                          color: theme.colors.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
              if (onDeleteCustom != null)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Pressable(
                    onTap: onDeleteCustom,
                    scale: Pressable.small,
                    wash: true,
                    shape: style.disc(24),
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: BarGlyph(
                        BarIcons.trash,
                        size: 12,
                        color: macRed,
                      ),
                    ),
                  ),
                ),
              Pressable(
                onTap: onAdd,
                scale: Pressable.small,
                wash: true,
                shape: BorderRadius.circular(style.pill(24)),
                child: Container(
                  height: 24,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: macGreen,
                    borderRadius: BorderRadius.circular(style.pill(24)),
                  ),
                  child: Text(
                    '+ ${context.tr('Add')}',
                    style: BarType.caption.copyWith(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xffffffff),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (spec.supportedSizes.length > 1) ...<Widget>[
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                for (final s in spec.supportedSizes) ...<Widget>[
                  Pressable(
                    onTap: () => onPickSize(s),
                    scale: Pressable.small,
                    wash: true,
                    shape: BorderRadius.circular(style.pill(22)),
                    child: Container(
                      height: 22,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(style.pill(22)),
                        color: picked == s ? accent : ink.withValues(alpha: 0.08),
                      ),
                      child: Text(
                        '${context.tr(s.label)} ${s.gridLabel}',
                        style: BarType.caption.copyWith(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: picked == s ? style.onAccent(theme) : ink,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}
