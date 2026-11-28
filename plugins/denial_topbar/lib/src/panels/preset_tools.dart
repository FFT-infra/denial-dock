import 'dart:io';

import 'package:denial_flutter_sdk/theme.dart';
import 'package:denial_shell_kit/detached_run.dart';
import 'package:denial_shell_kit/kit_store.dart';
import 'package:denial_shell_kit/shell_preset.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bar_preferences.dart';
import '../bar_settings.dart';
import '../bar_type.dart';
import '../l10n.dart';
import 'setting_bits.dart';

enum _Tool { none, naming, importing, exporting, deleting }

/// What can be done with presets beside choosing one: saving the shell as it
/// stands under a name, writing a preset over with it, bringing one in from
/// a file or the clipboard, sending one out the same way, and dropping one.
/// Everything opens in place under the row of buttons, so the settings
/// window never has a second window over it.
class PresetTools extends ConsumerStatefulWidget {
  const PresetTools({
    required this.current,
    required this.modified,
    required this.settings,
    super.key,
  });

  /// The preset in force.
  final ShellPreset current;

  /// Whether the shell has moved away from it.
  final bool modified;
  final BarSettings settings;

  @override
  ConsumerState<PresetTools> createState() => _PresetToolsState();
}

class _PresetToolsState extends ConsumerState<PresetTools> {
  final TextEditingController _name = TextEditingController();
  _Tool _tool = _Tool.none;
  List<File> _files = const <File>[];

  /// What the last action came to, and whether it failed.
  String? _message;
  bool _failed = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _open(_Tool tool) => setState(() {
    _tool = _tool == tool ? _Tool.none : tool;
    _message = null;
    if (_tool == _Tool.importing) _files = kitPresets.files();
    if (_tool == _Tool.naming) _name.text = '';
  });

  void _done(String message, {bool failed = false}) {
    if (!mounted) return;
    setState(() {
      _tool = _Tool.none;
      _message = message;
      _failed = failed;
    });
  }

  String _fault(ShellPresetFault fault) => context.tr(switch (fault) {
    ShellPresetFault.notJson =>
      'That is not a preset: the text is not valid JSON.',
    ShellPresetFault.notPreset =>
      'That is not a preset of this shell.',
    ShellPresetFault.newer =>
      'That preset was written by a newer version and cannot be read here.',
  });

  void _saveAs() {
    final label = _name.text.trim();
    if (label.isEmpty) return;
    final preset = saveShellPresetAs(widget.settings, label);
    _done(context.tr('Saved as “{}”.', preset.label));
  }

  void _update() {
    final current = widget.current;
    kitPresets.save(
      snapshotShellPreset(
        widget.settings,
        id: current.id,
        label: current.label,
      ),
    );
    _done(context.tr('“{}” now holds the shell as it stands.', current.label));
  }

  void _import(String Function() read) {
    try {
      final preset = importShellPreset(read());
      applyShellPreset(ref, preset, fresh: true);
      _done(context.tr('Imported “{}”.', preset.label));
    } on ShellPresetException catch (error) {
      _done(_fault(error.fault), failed: true);
    } on FileSystemException {
      _done(_fault(ShellPresetFault.notPreset), failed: true);
    }
  }

  Future<void> _importClipboard() async {
    final pasted = await runDetached('wl-paste', const <String>[
      '-n',
      '-t',
      'text',
    ]);
    if (!mounted) return;
    if (pasted.exitCode != 0 || pasted.stdout.trim().isEmpty) {
      _done(context.tr('The clipboard holds no text.'), failed: true);
      return;
    }
    _import(() => pasted.stdout);
  }

  Future<void> _exportClipboard() async {
    final preset = widget.current;
    final copied = await runDetached(
      'wl-copy',
      const <String>[],
      input: kitPresets.export(preset),
    );
    if (!mounted) return;
    copied.exitCode == 0
        ? _done(context.tr('Copied “{}” to the clipboard.', preset.label))
        : _done(context.tr('Could not reach the clipboard.'), failed: true);
  }

  void _exportFile() {
    final file = kitPresets.exportFile(widget.current);
    file == null
        ? _done(context.tr('Could not write the file.'), failed: true)
        : _done(context.tr('Written to {}', file.path));
  }

  void _delete() {
    final gone = widget.current;
    kitPresets.remove(gone.id);
    // The shell stays as it is and keeps the removed name, which no preset
    // answers to: calling it Denial would have the next switch remember
    // this arrangement as Denial's own.
    setState(() {});
    _done(context.tr('Deleted “{}”.', gone.label));
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final current = widget.current;
    final mine = current.group == ShellPresetGroup.user;
    final caption = BarType.caption.copyWith(
      fontSize: 12,
      height: 1.35,
      color: theme.colors.textSecondary,
    );
    Widget row(List<Widget> children) => Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: children,
    );

    final Widget? detail = switch (_tool) {
      _Tool.none => null,
      _Tool.naming => Row(
        children: <Widget>[
          Expanded(
            child: NameField(
              controller: _name,
              hint: context.tr('Name of the new preset'),
              onSubmitted: _saveAs,
            ),
          ),
          const SizedBox(width: 6),
          SmallButton(
            label: context.tr('Save preset'),
            primary: true,
            onTap: _saveAs,
          ),
        ],
      ),
      _Tool.importing => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          row(<Widget>[
            SmallButton(
              label: context.tr('From the clipboard'),
              onTap: _importClipboard,
            ),
            for (final file in _files)
              SmallButton(
                label: file.uri.pathSegments.last,
                onTap: () => _import(() {
                  // A file too big to be a preset is turned away unread.
                  if (file.lengthSync() > ShellPresetFile.longest) {
                    throw const ShellPresetException(
                      ShellPresetFault.notPreset,
                    );
                  }
                  return file.readAsStringSync();
                }),
              ),
          ]),
          const SizedBox(height: 6),
          Text(
            context.tr(
              'Preset files are read from {}',
              kitStore.presetsDirectory?.path ?? '—',
            ),
            style: caption.copyWith(color: theme.colors.textTertiary),
          ),
        ],
      ),
      _Tool.exporting => row(<Widget>[
        Text(context.tr('“{}”:', current.label), style: caption),
        SmallButton(
          label: context.tr('Copy to the clipboard'),
          onTap: _exportClipboard,
        ),
        SmallButton(label: context.tr('Write a file'), onTap: _exportFile),
      ]),
      _Tool.deleting => row(<Widget>[
        Text(context.tr('Delete “{}”?', current.label), style: caption),
        SmallButton(
          label: context.tr('Delete preset'),
          danger: true,
          onTap: _delete,
        ),
      ]),
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 2, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          row(<Widget>[
            SmallButton(
              label: context.tr('Save as…'),
              onTap: () => _open(_Tool.naming),
            ),
            if (widget.modified)
              SmallButton(
                label: context.tr('Reset preset'),
                onTap: () {
                  applyShellPreset(ref, current, fresh: true);
                  _done(context.tr('Reset “{}”.', current.label));
                },
              ),
            if (mine)
              SmallButton(
                label: context.tr('Update “{}”', current.label),
                onTap: widget.modified ? _update : null,
              ),
            SmallButton(
              label: context.tr('Import…'),
              onTap: () => _open(_Tool.importing),
            ),
            SmallButton(
              label: context.tr('Export…'),
              onTap: () => _open(_Tool.exporting),
            ),
            if (mine)
              SmallButton(
                label: context.tr('Delete…'),
                danger: true,
                onTap: () => _open(_Tool.deleting),
              ),
          ]),
          if (detail != null) ...<Widget>[const SizedBox(height: 8), detail],
          if (_message != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              _message!,
              style: caption.copyWith(
                color: _failed
                    ? const Color(0xffff453a)
                    : theme.colors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
