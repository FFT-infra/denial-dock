import 'dart:math' as math;

import 'package:denial_flutter_sdk/services.dart';
import 'package:denial_flutter_sdk/theme.dart';
import 'package:denial_shell_kit/kit_layer.dart';
import 'package:denial_shell_kit/kit_style.dart';
import 'package:denial_shell_kit/kit_widgets.dart';
import 'package:flutter/material.dart'
    show InputBorder, InputDecoration, Material, MaterialType, TextField;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bar_icons.dart';
import '../bar_type.dart';
import '../l10n.dart';
import 'mac_kit.dart';
import 'widgets.dart';

const String _galleryDialogKey = 'denial_topbar.widget_gallery';

const List<int?> _accentChoices = <int?>[
  null,
  0x0a84ff,
  0x30d158,
  0xff9f0a,
  0xff453a,
  0xbf5af2,
  0x64d2ff,
];

/// Opens the floating macOS-style Widget Gallery modal with search, category
/// filtering, live S/M/L previews, and full Custom Widget create/edit support.
void showWidgetGalleryDialog({
  required WidgetRef ref,
  required ShellServices services,
  required List<String> activeIds,
  required void Function(String id, KitWidgetSize size) onAdd,
  void Function(String id)? onRemoveFromGrid,
  KitCustomWidgetDef? editingCustom,
}) {
  final sceneW = MediaQuery.maybeSizeOf(ref.context)?.width ?? 1280.0;
  final width = math.min(680.0, math.max(420.0, sceneW - 64));
  showKitDialog(
    ref: ref,
    width: width,
    keyName: _galleryDialogKey,
    debugLabel: 'Widget gallery',
    builder: (context, close) => ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: math.min(640.0, MediaQuery.sizeOf(context).height - 80),
      ),
      child: WidgetGallery(
        services: services,
        activeIds: activeIds,
        initialEdit: editingCustom,
        onAdd: (id, size) {
          onAdd(id, size);
        },
        onRemoveFromGrid: onRemoveFromGrid,
        onClose: close,
      ),
    ),
  );
}

/// Visual Widget Gallery for Notification Centre:
/// - Search bar + category filter pills
/// - Glass vs Color card style toggle
/// - Live S / M / L widget previews
/// - Full Create & Edit Custom Widget form (Command / Shortcut / Note,
///   subtitle, refresh interval, accent color)
class WidgetGallery extends StatefulWidget {
  const WidgetGallery({
    required this.activeIds,
    required this.onAdd,
    this.services,
    this.initialEdit,
    this.onRemoveFromGrid,
    this.onClose,
    super.key,
  });

  final ShellServices? services;
  final List<String> activeIds;
  final KitCustomWidgetDef? initialEdit;
  final void Function(String id, KitWidgetSize size) onAdd;
  final void Function(String id)? onRemoveFromGrid;
  final VoidCallback? onClose;

  @override
  State<WidgetGallery> createState() => _WidgetGalleryState();
}

class _WidgetGalleryState extends State<WidgetGallery> {
  KitWidgetCategory? _category;
  final Map<String, KitWidgetSize> _pickedSize = <String, KitWidgetSize>{};
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  bool _creating = false;
  String? _editingCustomId;
  KitCustomWidgetKind _newKind = KitCustomWidgetKind.command;
  KitWidgetSize _newSize = KitWidgetSize.medium;
  int? _newAccentRgb;
  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _subtitleCtrl = TextEditingController();
  final TextEditingController _bodyCtrl = TextEditingController();
  final TextEditingController _refreshCtrl = TextEditingController(text: '30');

  @override
  void initState() {
    super.initState();
    ensureCustomWidgetsLoaded();
    kitWidgetRegistry.addListener(_refresh);
    _searchCtrl.addListener(() {
      final q = _searchCtrl.text.trim().toLowerCase();
      if (q != _query && mounted) setState(() => _query = q);
    });
    if (widget.initialEdit != null) {
      _beginEditCustom(widget.initialEdit!);
    }
  }

  @override
  void dispose() {
    kitWidgetRegistry.removeListener(_refresh);
    _searchCtrl.dispose();
    _titleCtrl.dispose();
    _subtitleCtrl.dispose();
    _bodyCtrl.dispose();
    _refreshCtrl.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _beginEditCustom(KitCustomWidgetDef def) {
    _editingCustomId = def.id;
    _newKind = def.kind;
    _newSize = def.defaultSize;
    _newAccentRgb = def.accentRgb;
    _titleCtrl.text = def.title;
    _subtitleCtrl.text = def.subtitle;
    _bodyCtrl.text =
        def.kind == KitCustomWidgetKind.note ? def.noteText : def.command;
    _refreshCtrl.text = '${def.refreshSeconds}';
    _creating = true;
  }

  void _resetForm() {
    _editingCustomId = null;
    _newKind = KitCustomWidgetKind.command;
    _newSize = KitWidgetSize.medium;
    _newAccentRgb = null;
    _titleCtrl.clear();
    _subtitleCtrl.clear();
    _bodyCtrl.clear();
    _refreshCtrl.text = '30';
  }

  void _saveCustom() {
    final title = _titleCtrl.text.trim();
    final subtitle = _subtitleCtrl.text.trim();
    final body = _bodyCtrl.text.trim();
    if (title.isEmpty) return;
    final parsedSec = int.tryParse(_refreshCtrl.text.trim()) ?? 30;
    final refresh = parsedSec == 0 ? 0 : parsedSec.clamp(5, 3600);
    final isEdit = _editingCustomId != null;
    final id = _editingCustomId ?? kitWidgetRegistry.freshCustomId(title);
    final def = KitCustomWidgetDef(
      id: id,
      title: title,
      subtitle: subtitle,
      kind: _newKind,
      command: _newKind == KitCustomWidgetKind.note ? '' : body,
      noteText: _newKind == KitCustomWidgetKind.note ? body : '',
      refreshSeconds: refresh,
      accentRgb: _newAccentRgb,
      defaultSize: _newSize,
    );
    kitWidgetRegistry.registerCustom(def);
    persistCustomWidgets();
    _resetForm();
    setState(() => _creating = false);
    if (!isEdit || !widget.activeIds.contains(id)) {
      widget.onAdd(id, _newSize);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final style = KitStyle.of(context);
    final accent = style.accent(theme);
    final ink = theme.colors.textPrimary;
    final items = <KitWidgetSpec>[
      for (final spec in kitWidgetRegistry.all)
        if ((_category == null || spec.category == _category) &&
            (_query.isEmpty ||
                spec.title.toLowerCase().contains(_query) ||
                context.tr(spec.title).toLowerCase().contains(_query) ||
                spec.description.toLowerCase().contains(_query) ||
                context.tr(spec.description).toLowerCase().contains(_query)))
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
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  context.tr('Widget Gallery'),
                  style: BarType.title.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: ink,
                  ),
                ),
              ),
              chip(
                context.tr(_creating ? 'Close Form' : '+ Custom'),
                _creating,
                () => setState(() {
                  if (_creating) {
                    _creating = false;
                    _resetForm();
                  } else {
                    _resetForm();
                    _creating = true;
                  }
                }),
              ),
              if (widget.onClose != null) ...<Widget>[
                const SizedBox(width: 8),
                Pressable(
                  onTap: widget.onClose,
                  scale: Pressable.small,
                  wash: true,
                  shape: style.disc(26),
                  child: Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: ink.withValues(alpha: 0.08),
                      borderRadius: style.disc(26),
                    ),
                    child: BarGlyph(BarIcons.xmark, size: 11, color: ink),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: _field(
                  context,
                  _searchCtrl,
                  context.tr('Search widgets…'),
                ),
              ),
              const SizedBox(width: 10),
              ValueListenableBuilder<KitWidgetStyle>(
                valueListenable: kitWidgetStyle,
                builder: (context, wStyle, _) => Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    chip(
                      context.tr('Glass'),
                      wStyle == KitWidgetStyle.glass,
                      () => kitWidgetStyle.value = KitWidgetStyle.glass,
                    ),
                    const SizedBox(width: 5),
                    chip(
                      context.tr('Color'),
                      wStyle == KitWidgetStyle.color,
                      () => kitWidgetStyle.value = KitWidgetStyle.color,
                    ),
                  ],
                ),
              ),
            ],
          ),
          Reveal(
            open: _creating,
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: ink.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(style.corner(12)),
                  border: style.controlLine(theme),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        for (final kind in KitCustomWidgetKind.values) ...<Widget>[
                          chip(
                            context.tr(switch (kind) {
                              KitCustomWidgetKind.command => 'Command',
                              KitCustomWidgetKind.shortcut => 'Shortcut',
                              KitCustomWidgetKind.note => 'Note',
                            }),
                            _newKind == kind,
                            () => setState(() => _newKind = kind),
                          ),
                          const SizedBox(width: 6),
                        ],
                        const Spacer(),
                        if (_newKind == KitCustomWidgetKind.command)
                          Text(
                            context.tr('Runs via sh -c as your user'),
                            style: BarType.caption.copyWith(
                              fontSize: 10.5,
                              color: theme.colors.textTertiary,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: _field(
                            context,
                            _titleCtrl,
                            context.tr('Widget title'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _field(
                            context,
                            _subtitleCtrl,
                            context.tr('Subtitle (optional)'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: _field(
                            context,
                            _bodyCtrl,
                            context.tr(switch (_newKind) {
                              KitCustomWidgetKind.command =>
                                'Shell command (e.g. uptime -p)',
                              KitCustomWidgetKind.shortcut =>
                                'Command to launch',
                              KitCustomWidgetKind.note => 'Note text',
                            }),
                          ),
                        ),
                        if (_newKind == KitCustomWidgetKind.command) ...<Widget>[
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 88,
                            child: _field(
                              context,
                              _refreshCtrl,
                              context.tr('Refresh (s)'),
                            ),
                          ),
                        ],
                      ],
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
                        const SizedBox(width: 8),
                        for (final rgb in _accentChoices) ...<Widget>[
                          Pressable(
                            onTap: () => setState(() => _newAccentRgb = rgb),
                            shape: style.disc(18),
                            child: Container(
                              width: 18,
                              height: 18,
                              margin: const EdgeInsets.only(right: 4),
                              decoration: BoxDecoration(
                                borderRadius: style.disc(18),
                                color: rgb == null
                                    ? ink.withValues(alpha: 0.14)
                                    : Color(0xff000000 | rgb),
                                border: Border.all(
                                  color: _newAccentRgb == rgb
                                      ? ink
                                      : const Color(0x00000000),
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                        ],
                        const Spacer(),
                        chip(
                          context.tr(
                            _editingCustomId == null ? 'Create' : 'Save',
                          ),
                          true,
                          _saveCustom,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
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
          Flexible(
            child: items.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: Text(
                        context.tr('No matching widgets.'),
                        style: BarType.caption.copyWith(
                          color: theme.colors.textSecondary,
                        ),
                      ),
                    ),
                  )
                : SingleChildScrollView(
                    child: Column(
                      children: <Widget>[
                        for (final spec in items)
                          _GalleryItem(
                            spec: spec,
                            services: widget.services,
                            added: widget.activeIds.contains(spec.id),
                            picked: _pickedSize[spec.id] ?? spec.defaultSize,
                            onPickSize: (sz) =>
                                setState(() => _pickedSize[spec.id] = sz),
                            onAdd: () => widget.onAdd(
                              spec.id,
                              _pickedSize[spec.id] ?? spec.defaultSize,
                            ),
                            onEditCustom: spec.custom != null
                                ? () => setState(
                                    () => _beginEditCustom(spec.custom!),
                                  )
                                : null,
                            onDeleteCustom: spec.isCustom
                                ? () {
                                    widget.onRemoveFromGrid?.call(spec.id);
                                    kitWidgetRegistry.removeCustom(spec.id);
                                    persistCustomWidgets();
                                  }
                                : null,
                          ),
                      ],
                    ),
                  ),
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
    required this.added,
    required this.picked,
    required this.onPickSize,
    required this.onAdd,
    this.services,
    this.onEditCustom,
    this.onDeleteCustom,
  });

  final KitWidgetSpec spec;
  final ShellServices? services;
  final bool added;
  final KitWidgetSize picked;
  final ValueChanged<KitWidgetSize> onPickSize;
  final VoidCallback onAdd;
  final VoidCallback? onEditCustom;
  final VoidCallback? onDeleteCustom;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final style = KitStyle.of(context);
    final ink = theme.colors.textPrimary;
    final accent = style.accent(theme);
    final wStyle = kitWidgetStyle.value;
    final showLivePreview =
        services != null &&
        spec.custom?.kind != KitCustomWidgetKind.command;
    final previewW = picked.w == 2 ? 148.0 : 76.0;
    final previewH = picked.h == 2 ? 112.0 : 76.0;
    final fullW = picked.w == 2 ? 344.0 : 166.0;
    final fullH = picked.h == 2 ? 344.0 : 166.0;
    final plate = widgetPlate(spec.id, theme, style: wStyle);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: ink.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(style.corner(12)),
        border: style.controlLine(theme),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          if (showLivePreview) ...<Widget>[
            Container(
              width: previewW,
              height: previewH,
              decoration: BoxDecoration(
                color: plate ?? theme.colors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(style.corner(12)),
                border: Border.all(color: theme.colors.hairline, width: 0.8),
              ),
              clipBehavior: Clip.antiAlias,
              child: IgnorePointer(
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: SizedBox(
                    width: fullW,
                    height: fullH,
                    child: buildBarWidget(
                      spec.id,
                      services!,
                      166,
                      size: picked,
                      widgetStyle: wStyle,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(style.corner(7)),
                      ),
                      child: BarGlyph(
                        widgetIconFor(spec.id),
                        size: 13,
                        color: accent,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            spec.isCustom
                                ? spec.title
                                : context.tr(spec.title),
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
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    if (spec.supportedSizes.length > 1)
                      for (final sz in spec.supportedSizes) ...<Widget>[
                        Pressable(
                          onTap: () => onPickSize(sz),
                          scale: Pressable.small,
                          wash: true,
                          shape: BorderRadius.circular(style.corner(7)),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: picked == sz
                                  ? accent.withValues(alpha: 0.2)
                                  : ink.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(
                                style.corner(7),
                              ),
                              border: picked == sz
                                  ? Border.all(
                                      color: accent.withValues(alpha: 0.6),
                                      width: 0.8,
                                    )
                                  : null,
                            ),
                            child: Text(
                              '${context.tr(sz.label)} ${sz.gridLabel}',
                              style: BarType.caption.copyWith(
                                fontSize: 10.5,
                                fontWeight: picked == sz
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: picked == sz
                                    ? accent
                                    : theme.colors.textSecondary,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 5),
                      ],
                    const Spacer(),
                    if (onEditCustom != null) ...<Widget>[
                      Pressable(
                        onTap: onEditCustom,
                        scale: Pressable.small,
                        wash: true,
                        shape: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.all(5),
                          child: BarGlyph(
                            BarIcons.gear,
                            size: 12,
                            color: theme.colors.textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 2),
                    ],
                    if (onDeleteCustom != null) ...<Widget>[
                      Pressable(
                        onTap: onDeleteCustom,
                        scale: Pressable.small,
                        wash: true,
                        shape: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.all(5),
                          child: BarGlyph(
                            BarIcons.trash,
                            size: 12,
                            color: theme.colors.textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                    ],
                    Pressable(
                      onTap: added ? null : onAdd,
                      scale: Pressable.small,
                      wash: !added,
                      shape: BorderRadius.circular(style.pill(24)),
                      child: Container(
                        height: 24,
                        padding: const EdgeInsets.symmetric(horizontal: 11),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: added ? ink.withValues(alpha: 0.08) : accent,
                          borderRadius: BorderRadius.circular(style.pill(24)),
                        ),
                        child: Text(
                          context.tr(added ? 'Added' : 'Add'),
                          style: BarType.caption.copyWith(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: added
                                ? theme.colors.textSecondary
                                : style.onAccent(theme),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
