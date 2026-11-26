import 'dart:convert';

import 'package:denial_flutter_sdk/theme.dart';
import 'package:denial_shell_kit/detached_run.dart';
import 'package:denial_shell_kit/kit_glass.dart';
import 'package:denial_shell_kit/kit_look.dart' show KitMaterialJson;
import 'package:denial_shell_kit/kit_material.dart';
import 'package:denial_shell_kit/kit_palette.dart';
import 'package:denial_shell_kit/kit_settings.dart';
import 'package:denial_shell_kit/kit_style.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

import '../bar_icons.dart';
import '../bar_type.dart';
import '../l10n.dart';
import 'dialogs.dart';
import 'mac_kit.dart';
import 'setting_bits.dart';

const KitSettingsPage _lookPage = KitSettingsPage(
  id: 'bar.look',
  // Building the editor previews its draft, so the search does not read it.
  readable: false,
  title: _lookTitle,
  group: _lookGroup,
  subtitle: _lookSubtitle,
  keywords: <String>[
    'look',
    'theme',
    'style',
    'accent',
    'palette',
    'appearance',
    'dark',
    'light',
    'blur',
    'glass',
    'material',
    'font',
    'corner',
    'border',
    'motion',
    'spring',
    'shadow',
    '外观',
    '主题',
    '风格',
    '配色',
    '强调色',
    '模糊',
    '材质',
    '玻璃',
    '字体',
    '圆角',
    '边框',
    '动效',
    '阴影',
  ],
  icon: BarIcons.circleHalf,
  colour: Color(0xffbf5af2),
  // Inside the Shell group right after General/Appearance.
  order: 105,
  builder: _buildLookPage,
);

String _lookTitle(BuildContext context) => context.tr('Look Editor');

String _lookGroup(BuildContext context) => context.tr('Shell');

String _lookSubtitle(BuildContext context) => context.tr(
  'Tune colours, glass materials, fonts, corners and motion, then save as your own look.',
);

Widget _buildLookPage(BuildContext context) => const LookPage();

/// Offers the look editor to the shell's settings window. Safe to call
/// again.
void registerLookPage() =>
    kitSettingsPages.register(const <KitSettingsPage>[_lookPage]);

/// The look editor: pick a look to start from, change it value by value and
/// keep the result as a look of your own.
///
/// What is being edited is drawn at once, on the whole shell and on the
/// small scene at the top of the page, but it is kept only when it is saved:
/// leaving the page puts the chosen look back.
class LookPage extends StatefulWidget {
  const LookPage({super.key});

  @override
  State<LookPage> createState() => _LookPageState();
}

class _LookPageState extends State<LookPage> {
  /// The look as edited, and as it was when it was picked.
  late KitLook _draft = KitStyle.byId(kitStyle.chosen).look;
  late KitLook _origin = _draft;

  final TextEditingController _name = TextEditingController();
  final TextEditingController _hex = TextEditingController();
  final TextEditingController _family = TextEditingController();
  final TextEditingController _fill = TextEditingController();
  bool _naming = false;
  KitTier _tier = KitTier.popover;
  String? _message;
  bool _failed = false;

  /// Counts up to play the panel's entrance in the scene again.
  int _replay = 0;

  @override
  void initState() {
    super.initState();
    kitLooks.addListener(_changed);
  }

  Brightness? _seen;

  /// The fill field shows the dark or the light material, so it is filled
  /// here, where the theme may be read, and again when the system turns
  /// from one to the other.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final now = context.shellTheme.brightness;
    if (_seen == now) return;
    _seen = now;
    _fields();
  }

  @override
  void dispose() {
    kitLooks.removeListener(_changed);
    _name.dispose();
    _hex.dispose();
    _family.dispose();
    _fill.dispose();
    // After this frame: rebuilding the shell from inside a dispose is not
    // allowed.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => kitStyle.preview(null),
    );
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  bool get _dirty => _draft != _origin;

  /// The text fields as the draft has them.
  void _fields() {
    _hex.text = kitRgbText(_draft.accentRgb);
    _family.text = _draft.fontFamily ?? '';
    final fill = _material.fill;
    _fill.text = fill.fixed ? kitRgbText(fill.rgb) : '';
  }

  KitMaterial get _material => _draft.materials
      .tier(_tier)
      .of(dark: context.shellTheme.brightness == Brightness.dark);

  void _set(Map<String, Object?> changes) {
    setState(() {
      _draft = _draft.change(changes);
      _message = null;
    });
    kitStyle.preview(KitStyle(_draft));
  }

  /// Starts over from [style], which also becomes the look of the shell.
  void _pick(KitStyle style) {
    kitStyle.choose(style);
    setState(() {
      _draft = style.look;
      _origin = style.look;
      _naming = false;
      _message = null;
      _fields();
    });
  }

  void _revert() {
    kitStyle.preview(null);
    setState(() {
      _draft = _origin;
      _message = null;
      _fields();
    });
  }

  void _say(String message, {bool failed = false}) {
    if (!mounted) return;
    setState(() {
      _message = message;
      _failed = failed;
    });
  }

  void _saveAs() {
    final label = _name.text.trim();
    if (label.isEmpty) return;
    final saved = kitLooks.save(
      _draft.change(<String, Object?>{
        'id': kitLooks.freshId(),
        'label': label,
        // A look made from one of the user's own stands on the same look
        // that one stands on.
        'base': _draft.base ?? _draft.id,
      }),
    );
    if (saved == null) return;
    _pick(saved);
    _say(context.tr('Saved as “{}”.', saved.label));
  }

  void _saveChanges() {
    final saved = kitLooks.save(_draft);
    if (saved == null) return;
    _pick(saved);
    _say(context.tr('Saved “{}”.', saved.label));
  }

  void _delete() {
    final gone = _origin;
    kitLooks.remove(gone.id);
    _pick(KitStyle.byId(kitStyle.chosen));
    _say(context.tr('Deleted “{}”.', gone.label));
  }

  Future<void> _copy() async {
    final copied = await runDetached(
      'wl-copy',
      const <String>[],
      input: const JsonEncoder.withIndent('  ').convert(_draft.toJson()),
    );
    if (!mounted) return;
    copied.exitCode == 0
        ? _say(context.tr('Copied the look as JSON.'))
        : _say(context.tr('Could not reach the clipboard.'), failed: true);
  }

  Future<void> _paste() async {
    final pasted = await runDetached('wl-paste', const <String>[
      '-n',
      '-t',
      'text',
    ]);
    if (!mounted) return;
    Object? json;
    try {
      json = pasted.exitCode == 0 && pasted.stdout.length < 400000
          ? jsonDecode(pasted.stdout)
          : null;
    } on FormatException {
      json = null;
    }
    final Map<Object?, Object?> found = json is Map
        ? json
        : const <Object?, Object?>{};
    if (found.isEmpty) {
      _say(context.tr('The clipboard holds no look.'), failed: true);
      return;
    }
    // Over the look being edited, under its own name: what the text lacks
    // stays as it is, and nothing is kept until it is saved.
    setState(() {
      _draft = KitLook.fromJson(<String, Object?>{
        for (final entry in found.entries)
          if (entry.key is String) entry.key as String: entry.value,
        'id': _draft.id,
        'label': _draft.label,
        'base': _draft.base,
      }, base: _draft);
      _fields();
    });
    kitStyle.preview(KitStyle(_draft));
    _say(context.tr('Pasted. Save it to keep it.'));
  }

  /// A change to the material of the tier being edited, in both
  /// appearances.
  void _setMaterial(Map<String, Object?> changes) => _set(<String, Object?>{
    'materials': <String, Object?>{
      _tier.name: <String, Object?>{'dark': changes, 'light': changes},
    },
  });

  /// The fill of the tier being edited with [alpha] or [rgb] changed, each
  /// appearance keeping what the change does not name. [theme] goes back to
  /// the shell's own panel colour.
  void _setFill({double? alpha, int? rgb, bool theme = false}) {
    String tone(KitMaterial material) {
      final old = material.fill;
      final KitTone next;
      if (theme) {
        next = KitTone.of(
          _tier == KitTier.dock ? KitRole.surface : KitRole.panel,
        );
      } else if (rgb != null) {
        next = KitTone(rgb, old.alpha ?? 0.8);
      } else if (old.fixed) {
        next = KitTone(old.rgb, alpha ?? old.alpha ?? 1);
      } else {
        next = KitTone.of(old.role!, alpha: alpha);
      }
      return KitMaterialJson.tone(next);
    }

    final pair = _draft.materials.tier(_tier);
    _set(<String, Object?>{
      'materials': <String, Object?>{
        _tier.name: <String, Object?>{
          'dark': <String, Object?>{'fill': tone(pair.dark)},
          'light': <String, Object?>{'fill': tone(pair.light)},
        },
      },
    });
  }

  /// How lively the springs are, 0 to 1, read off the panel's.
  double get _bounce =>
      ((1 - _draft.panelGrow.dampingRatio) / 0.55).clamp(0.0, 1.0);

  void _setBounce(double bounce) {
    final toggle = KitStyle(_draft).toggle;
    _set(<String, Object?>{
      'motion': <String, Object?>{
        'panelGrow': <double>[_draft.panelGrow.stiffness, 1 - 0.55 * bounce],
        'press': <double>[_draft.pressTuning.stiffness, 1 - 0.6 * bounce],
        'switch': <double>[toggle.stiffness, 1 - 0.45 * bounce],
      },
    });
  }

  static const List<int> _swatches = <int>[
    0x0a84ff,
    0x30a46c,
    0xf5a524,
    0xff6b35,
    0xff453a,
    0xff4f9a,
    0xbf5af2,
    0x5e5ce6,
    0x63d0df,
    0x8e8e93,
  ];

  static String _times(double value) => '${SettingSlider.number(value)}×';
  static String _percent(double value) => '${(value * 100).round()}%';

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final style = KitStyle.of(context);
    final draft = _draft;
    final material = _material;
    final mine = _origin.base != null;
    final caption = BarType.caption.copyWith(
      fontSize: 12,
      height: 1.35,
      color: theme.colors.textSecondary,
    );

    Widget row(String label, Widget trailing) =>
        SettingRow(label: context.tr(label), trailing: trailing);

    Widget segments<T>(
      String label,
      T value,
      List<(T, String)> options,
      ValueChanged<T> set,
    ) => row(
      label,
      Segments<T>(
        value: value,
        options: <(T, String)>[
          for (final (option, name) in options) (option, context.tr(name)),
        ],
        onChanged: set,
      ),
    );

    Widget chips(List<Widget> children) => Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Wrap(spacing: 6, runSpacing: 6, children: children),
    );

    Widget shelf(String title, Iterable<KitStyle> looks) => Padding(
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 88,
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(context.tr(title), style: caption),
            ),
          ),
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: <Widget>[
                for (final look in looks)
                  SmallButton(
                    label: context.tr(look.label),
                    primary: look.id == _origin.id,
                    onTap: () => _pick(look),
                  ),
              ],
            ),
          ),
        ],
      ),
    );

    final custom =
        draft.fontFamily != null &&
        draft.fontFamily != 'Inter' &&
        draft.fontFamily != 'JetBrainsMono';
    final fontChoice = custom ? 'custom' : draft.fontFamily ?? '';
    final dock = draft.dock;
    final dockKin = KitLook.builtin(draft.dockKin) ?? KitLook.denial;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
          child: _Scene(
            replay: _replay,
            onReplay: () => setState(() => _replay++),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  SmallButton(
                    label: context.tr('Save as a new look…'),
                    primary: _dirty && !mine,
                    onTap: () => setState(() {
                      _naming = !_naming;
                      _name.text = '';
                    }),
                  ),
                  if (mine)
                    SmallButton(
                      label: context.tr('Save changes'),
                      primary: _dirty,
                      onTap: _dirty ? _saveChanges : null,
                    ),
                  SmallButton(
                    label: context.tr('Revert'),
                    onTap: _dirty ? _revert : null,
                  ),
                  SmallButton(label: context.tr('Copy JSON'), onTap: _copy),
                  SmallButton(label: context.tr('Paste JSON'), onTap: _paste),
                  if (mine)
                    SmallButton(
                      label: context.tr('Delete look'),
                      danger: true,
                      onTap: _delete,
                    ),
                ],
              ),
              if (_naming) ...<Widget>[
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: NameField(
                        controller: _name,
                        hint: context.tr('Name of the new look'),
                        onSubmitted: _saveAs,
                      ),
                    ),
                    const SizedBox(width: 6),
                    SmallButton(
                      label: context.tr('Save look'),
                      primary: true,
                      onTap: _saveAs,
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 6),
              Text(
                _message ??
                    (_dirty
                        ? context.tr(
                            'Not saved yet: leaving this page puts “{}” back.',
                            context.tr(_origin.label),
                          )
                        : context.tr(
                            'Editing “{}”.',
                            context.tr(_origin.label),
                          )),
                style: caption.copyWith(
                  color: _message != null && _failed
                      ? const Color(0xffff453a)
                      : theme.colors.textTertiary,
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 1, child: ColoredBox(color: theme.colors.hairline)),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                SettingGroup(
                  title: context.tr('Start from'),
                  note: context.tr(
                    'Picking a look makes it the look of the shell. A look of your own is kept as the changes it makes to the look it started from.',
                  ),
                  children: <Widget>[
                    shelf('Built-in', KitStyle.presets),
                    if (KitStyle.builtins.length > KitStyle.presets.length)
                      shelf(
                        'Reference styles',
                        KitStyle.builtins.skip(KitStyle.presets.length),
                      ),
                    if (KitStyle.user.isNotEmpty) shelf('Mine', KitStyle.user),
                  ],
                ),
                SettingGroup(
                  title: context.tr('Colour'),
                  children: <Widget>[
                    chips(<Widget>[
                      SmallButton(
                        label: context.tr('Shell colours'),
                        primary: draft.palette == null,
                        onTap: () => _set(<String, Object?>{
                          'palette': null,
                          if (draft.accentSource == KitAccentSource.palette)
                            'accent': 'wallpaper',
                        }),
                      ),
                      for (final palette in KitPalette.all)
                        SmallButton(
                          label: palette.label,
                          primary: draft.palette?.id == palette.id,
                          onTap: () => _set(<String, Object?>{
                            'palette': palette.id,
                            if (draft.accentSource != KitAccentSource.fixed)
                              'accent': 'palette',
                          }),
                        ),
                    ]),
                    segments<KitAppearance>(
                      'Light or dark',
                      draft.appearance,
                      const <(KitAppearance, String)>[
                        (KitAppearance.system, 'Follow the shell'),
                        (KitAppearance.dark, 'Always dark'),
                        (KitAppearance.light, 'Always light'),
                      ],
                      (value) => _set(<String, Object?>{
                        'appearance': value.name,
                      }),
                    ),
                    segments<KitAccentSource>(
                      'Accent colour',
                      draft.accentSource,
                      <(KitAccentSource, String)>[
                        (KitAccentSource.wallpaper, 'From the wallpaper'),
                        if (draft.palette != null)
                          (KitAccentSource.palette, 'From the palette'),
                        (KitAccentSource.fixed, 'Fixed'),
                      ],
                      (value) => _set(<String, Object?>{
                        'accent': value == KitAccentSource.fixed
                            ? kitRgbText(draft.accentRgb)
                            : value.name,
                      }),
                    ),
                    if (draft.accentSource == KitAccentSource.fixed)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                        child: Row(
                          children: <Widget>[
                            for (final rgb in _swatches)
                              Padding(
                                padding: const EdgeInsets.only(right: 7),
                                child: Pressable(
                                  onTap: () {
                                    _hex.text = kitRgbText(rgb);
                                    _set(<String, Object?>{
                                      'accent': kitRgbText(rgb),
                                    });
                                  },
                                  scale: Pressable.small,
                                  child: Container(
                                    width: 20,
                                    height: 20,
                                    decoration: BoxDecoration(
                                      color: Color(0xff000000 | rgb),
                                      borderRadius: style.disc(20),
                                      border: Border.all(
                                        width: 2,
                                        color: draft.accentRgb == rgb
                                            ? theme.colors.textPrimary
                                            : const Color(0x00000000),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            const Spacer(),
                            SizedBox(
                              width: 96,
                              child: NameField(
                                controller: _hex,
                                hint: '#rrggbb',
                                autofocus: false,
                                onSubmitted: () {
                                  if (kitParseRgb(_hex.text.trim()) != null) {
                                    _set(<String, Object?>{
                                      'accent': _hex.text.trim(),
                                    });
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    SettingSwitch(
                      label: context.tr('Fill the menu row under the pointer'),
                      value: draft.accentMenuRows,
                      onChanged: (value) => _set(<String, Object?>{
                        'accentMenuRows': value,
                      }),
                    ),
                  ],
                ),
                SettingGroup(
                  title: context.tr('Shape'),
                  children: <Widget>[
                    SettingSlider(
                      label: context.tr('Corner roundness'),
                      value: draft.cornerScale,
                      min: 0,
                      max: 2,
                      step: 0.05,
                      text: _times,
                      onChanged: (value) => _set(<String, Object?>{
                        'corners': <String, Object?>{'scale': value},
                      }),
                    ),
                    SettingSwitch(
                      label: context.tr('Follow the shell\'s roundness'),
                      value: draft.scaleCorners,
                      onChanged: (value) => _set(<String, Object?>{
                        'corners': <String, Object?>{'followShell': value},
                      }),
                    ),
                    SettingSlider(
                      label: context.tr('Outline width'),
                      value: draft.borderWidth,
                      min: 0,
                      max: 4,
                      step: 0.5,
                      onChanged: (value) => _set(<String, Object?>{
                        'border': <String, Object?>{'width': value},
                      }),
                    ),
                    segments<KitBorderTone>(
                      'Outline colour',
                      draft.borderTone,
                      const <(KitBorderTone, String)>[
                        (KitBorderTone.hairline, 'Hairline'),
                        (KitBorderTone.accent, 'Accent'),
                        (KitBorderTone.ink, 'Ink'),
                      ],
                      (value) => _set(<String, Object?>{
                        'border': <String, Object?>{'tone': value.name},
                      }),
                    ),
                    SettingSlider(
                      label: context.tr('Spacing'),
                      value: draft.density,
                      min: 0.8,
                      max: 1.4,
                      step: 0.05,
                      text: _times,
                      onChanged: (value) => _set(<String, Object?>{
                        'density': value,
                      }),
                    ),
                  ],
                ),
                SettingGroup(
                  title: context.tr('Material'),
                  note: context.tr(
                    'Each kind of surface has its own material. A change here is made to its light and its dark form alike.',
                  ),
                  children: <Widget>[
                    SettingSwitch(
                      label: context.tr('Solid panels, nothing blurred'),
                      value: draft.opaque,
                      onChanged: (value) => _set(<String, Object?>{
                        'opaque': value,
                      }),
                    ),
                    SettingSlider(
                      label: context.tr('Shadow strength'),
                      value: draft.shadow,
                      min: 0,
                      max: 1,
                      step: 0.05,
                      text: _percent,
                      onChanged: (value) => _set(<String, Object?>{
                        'shadow': value,
                      }),
                    ),
                    segments<KitTier>(
                      'Surface',
                      _tier,
                      const <(KitTier, String)>[
                        (KitTier.popover, 'Panel'),
                        (KitTier.menu, 'Menu'),
                        (KitTier.card, 'Card'),
                        (KitTier.dock, 'Dock'),
                      ],
                      (value) => setState(() {
                        _tier = value;
                        _fields();
                      }),
                    ),
                    row(
                      'Fill colour',
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          SmallButton(
                            label: context.tr('From the theme'),
                            primary: !material.fill.fixed,
                            onTap: () {
                              _fill.text = '';
                              _setFill(theme: true);
                            },
                          ),
                          const SizedBox(width: 6),
                          SizedBox(
                            width: 96,
                            child: NameField(
                              controller: _fill,
                              hint: '#rrggbb',
                              autofocus: false,
                              onSubmitted: () {
                                final rgb = kitParseRgb(_fill.text.trim());
                                if (rgb != null) _setFill(rgb: rgb);
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    SettingSlider(
                      label: context.tr('Fill opacity'),
                      value: material.fill.alpha ?? theme.panelOpacity,
                      min: 0,
                      max: 1,
                      step: 0.05,
                      text: (value) => material.fill.alpha == null
                          ? context.tr('Shell')
                          : _percent(value),
                      onChanged: (value) => _setFill(alpha: value),
                    ),
                    SettingSwitch(
                      label: context.tr('Blur as the shell is set'),
                      value: material.sigma == null,
                      onChanged: (value) => _setMaterial(<String, Object?>{
                        'sigma': value ? null : 10.0,
                      }),
                    ),
                    if (material.sigma == null)
                      SettingSlider(
                        label: context.tr('Share of the shell\'s blur'),
                        value: material.strength,
                        min: 0,
                        max: 1,
                        step: 0.05,
                        text: _percent,
                        onChanged: (value) => _setMaterial(<String, Object?>{
                          'strength': value,
                        }),
                      )
                    else
                      SettingSlider(
                        label: context.tr('Blur radius'),
                        value: material.sigma!,
                        min: 0,
                        max: 30,
                        step: 0.5,
                        onChanged: (value) => _setMaterial(<String, Object?>{
                          'sigma': value,
                        }),
                      ),
                    SettingSlider(
                      label: context.tr('Saturation behind'),
                      value: material.saturation,
                      min: 0,
                      max: 3,
                      step: 0.1,
                      text: _times,
                      onChanged: (value) => _setMaterial(<String, Object?>{
                        'saturation': value,
                      }),
                    ),
                    SettingSwitch(
                      label: context.tr('Own corner radius'),
                      value: material.radius != null,
                      onChanged: (value) => _setMaterial(<String, Object?>{
                        'radius': value ? 16.0 : null,
                      }),
                    ),
                    if (material.radius != null)
                      SettingSlider(
                        label: context.tr('Corner radius'),
                        value: material.radius!,
                        min: 0,
                        max: 40,
                        onChanged: (value) => _setMaterial(<String, Object?>{
                          'radius': value,
                        }),
                      ),
                    SettingSwitch(
                      label: context.tr('Smooth corners'),
                      value: material.continuous,
                      onChanged: (value) => _setMaterial(<String, Object?>{
                        'continuous': value,
                      }),
                    ),
                    SettingSwitch(
                      label: context.tr('Line inside the edge'),
                      value: material.inner != null,
                      onChanged: (value) => _setMaterial(<String, Object?>{
                        'inner': value
                            ? <String, Object?>{'tone': 'border'}
                            : null,
                      }),
                    ),
                    SettingSwitch(
                      label: context.tr('Shadow under it'),
                      value: material.shadow != null,
                      onChanged: (value) => _setMaterial(<String, Object?>{
                        'shadow': value
                            ? <String, Object?>{'byLook': true}
                            : null,
                      }),
                    ),
                    if (material.shadow != null)
                      SettingSlider(
                        label: context.tr('Shadow spread'),
                        value: material.shadow!.blur,
                        min: 0,
                        max: 60,
                        onChanged: (value) => _setMaterial(<String, Object?>{
                          'shadow': <String, Object?>{
                            'blur': value,
                            'dy': (value * 0.35).roundToDouble(),
                          },
                        }),
                      ),
                  ],
                ),
                SettingGroup(
                  title: context.tr('Text'),
                  note: context.tr(
                    'A family of your own is one installed on the system; a name the system does not know falls back to the shell\'s font.',
                  ),
                  children: <Widget>[
                    segments<String>(
                      'Font',
                      fontChoice,
                      const <(String, String)>[
                        ('', 'Shell'),
                        ('Inter', 'Inter'),
                        ('JetBrainsMono', 'JetBrains Mono'),
                        ('custom', 'Other'),
                      ],
                      (value) {
                        final family = switch (value) {
                          '' => null,
                          'custom' =>
                            _family.text.trim().isEmpty ||
                                    _family.text == 'Inter' ||
                                    _family.text == 'JetBrainsMono'
                                ? 'Noto Sans'
                                : _family.text.trim(),
                          _ => value,
                        };
                        _family.text = family ?? '';
                        _set(<String, Object?>{
                          'font': <String, Object?>{
                            'family': family,
                            'package': switch (value) {
                              'Inter' => 'denial_topbar',
                              'JetBrainsMono' => 'denial_flutter_sdk',
                              _ => null,
                            },
                          },
                        });
                      },
                    ),
                    if (custom)
                      row(
                        'Family name',
                        SizedBox(
                          width: 200,
                          child: NameField(
                            controller: _family,
                            hint: 'Noto Sans',
                            autofocus: false,
                            onSubmitted: () {
                              final family = _family.text.trim();
                              if (family.isEmpty) return;
                              _set(<String, Object?>{
                                'font': <String, Object?>{
                                  'family': family,
                                  'package': null,
                                },
                              });
                            },
                          ),
                        ),
                      ),
                    SettingSlider(
                      label: context.tr('Text size'),
                      value: draft.fontScale,
                      min: 0.8,
                      max: 1.3,
                      step: 0.01,
                      text: _percent,
                      onChanged: (value) => _set(<String, Object?>{
                        'font': <String, Object?>{'scale': value},
                      }),
                    ),
                    SettingSlider(
                      label: context.tr('Text weight'),
                      value: draft.weightShift.toDouble(),
                      min: -2,
                      max: 2,
                      text: (value) => value == 0
                          ? context.tr('As designed')
                          : '${value > 0 ? '+' : ''}${(value * 100).round()}',
                      onChanged: (value) => _set(<String, Object?>{
                        'font': <String, Object?>{'weight': value.round()},
                      }),
                    ),
                  ],
                ),
                SettingGroup(
                  title: context.tr('Motion'),
                  children: <Widget>[
                    segments<KitPanelEntry>(
                      'A panel appears by',
                      draft.entry,
                      const <(KitPanelEntry, String)>[
                        (KitPanelEntry.grow, 'Growing'),
                        (KitPanelEntry.slide, 'Sliding'),
                        (KitPanelEntry.fade, 'Fading'),
                        (KitPanelEntry.zoom, 'Zooming'),
                      ],
                      (value) {
                        _set(<String, Object?>{
                          'motion': <String, Object?>{'entry': value.name},
                        });
                        setState(() => _replay++);
                      },
                    ),
                    SettingSlider(
                      label: context.tr('Bounce'),
                      value: _bounce,
                      min: 0,
                      max: 1,
                      step: 0.05,
                      text: _percent,
                      onChanged: _setBounce,
                    ),
                    SettingSlider(
                      label: context.tr('Spring stiffness'),
                      value: draft.panelGrow.stiffness,
                      min: 150,
                      max: 1200,
                      step: 10,
                      onChanged: (value) => _set(<String, Object?>{
                        'motion': <String, Object?>{
                          'panelGrow': <double>[
                            value,
                            draft.panelGrow.dampingRatio,
                          ],
                          'panelShrink': <double>[
                            value * 1.6,
                            draft.panelShrink.dampingRatio,
                          ],
                        },
                      }),
                    ),
                    SettingSlider(
                      label: context.tr('Size a panel starts from'),
                      value: draft.beadWidth,
                      min: 0.5,
                      max: 1,
                      step: 0.02,
                      text: _percent,
                      onChanged: (value) => _set(<String, Object?>{
                        'motion': <String, Object?>{
                          // The height keeps its share of the width, so a
                          // bead that is flatter than it is wide stays so.
                          'bead': <double>[
                            value,
                            (value * draft.beadHeight / draft.beadWidth).clamp(
                              0.3,
                              1.0,
                            ),
                          ],
                        },
                      }),
                    ),
                    SettingSlider(
                      label: context.tr('Pace of timed transitions'),
                      value: draft.pace,
                      min: 0.5,
                      max: 2,
                      step: 0.05,
                      text: _times,
                      onChanged: (value) => _set(<String, Object?>{
                        'motion': <String, Object?>{'pace': value},
                      }),
                    ),
                    SettingSwitch(
                      label: context.tr('Liquid fills and stretch'),
                      value: draft.liquid,
                      onChanged: (value) => _set(<String, Object?>{
                        'motion': <String, Object?>{'liquid': value},
                      }),
                    ),
                  ],
                ),
                SettingGroup(
                  title: context.tr('Icons and Dock'),
                  note: context.tr(
                    'The Dock\'s own settings still win over what a look sets here.',
                  ),
                  children: <Widget>[
                    segments<KitIconTint>(
                      'Application icons',
                      draft.iconTint,
                      const <(KitIconTint, String)>[
                        (KitIconTint.original, 'Full colour'),
                        (KitIconTint.mono, 'Monochrome'),
                        (KitIconTint.accent, 'Tinted'),
                      ],
                      (value) => _set(<String, Object?>{
                        'icons': <String, Object?>{'tint': value.name},
                      }),
                    ),
                    segments<String>(
                      'Dock takes after',
                      draft.dockKin,
                      <(String, String)>[
                        for (final kin in KitLook.dockKins)
                          (kin, KitLook.builtin(kin)?.label ?? kin),
                      ],
                      (value) => _set(<String, Object?>{
                        'dock': <String, Object?>{'kin': value},
                      }),
                    ),
                    segments<String>(
                      'Running marker',
                      dock['indicator'] is String
                          ? dock['indicator'] as String
                          : '',
                      const <(String, String)>[
                        ('', 'As the Dock'),
                        ('dot', 'Dots'),
                        ('line', 'Line'),
                        ('pill', 'Pill'),
                        ('segments', 'Segments'),
                        ('none', 'None'),
                      ],
                      (value) => _set(<String, Object?>{
                        'dock': <String, Object?>{
                          'indicator': value.isEmpty ? null : value,
                        },
                      }),
                    ),
                    SettingSlider(
                      label: context.tr('Dock icon size'),
                      value: dock['iconSize'] is num
                          ? (dock['iconSize'] as num).toDouble()
                          : 0,
                      min: 30,
                      max: 72,
                      step: 2,
                      text: (value) => value < 32
                          ? context.tr('As “{}”', context.tr(dockKin.label))
                          : SettingSlider.number(value),
                      onChanged: (value) => _set(<String, Object?>{
                        // Below the smallest size the dock draws, the look
                        // sets none.
                        'dock': <String, Object?>{
                          'iconSize': value < 32 ? null : value,
                        },
                      }),
                    ),
                    SettingSlider(
                      label: context.tr('Dock corner radius'),
                      value: dock['radius'] is num
                          ? (dock['radius'] as num).toDouble()
                          : -1,
                      min: -1,
                      max: 40,
                      text: (value) => value < 0
                          ? context.tr('As “{}”', context.tr(dockKin.label))
                          : SettingSlider.number(value),
                      onChanged: (value) => _set(<String, Object?>{
                        'dock': <String, Object?>{
                          'radius': value < 0 ? null : value,
                        },
                      }),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// A small scene drawn with the kit's own surfaces and controls in the look
/// in force: a strip of bar, a panel with a switch, a menu row and two
/// buttons, and a piece of dock, over a backdrop with enough colour and
/// edge in it to show what a material does to what is behind.
class _Scene extends StatefulWidget {
  const _Scene({required this.replay, required this.onReplay});

  final int replay;
  final VoidCallback onReplay;

  @override
  State<_Scene> createState() => _SceneState();
}

class _SceneState extends State<_Scene> with SingleTickerProviderStateMixin {
  late final AnimationController _entry = AnimationController.unbounded(
    vsync: this,
    value: 1,
  );
  bool _on = true;

  @override
  void didUpdateWidget(_Scene old) {
    super.didUpdateWidget(old);
    if (widget.replay != old.replay) _play();
  }

  /// The panel comes on again, on the look's own spring.
  void _play() {
    final tuning = KitStyle.of(context).panelGrow;
    _entry.animateWith(
      SpringSimulation(
        SpringDescription.withDampingRatio(
          mass: 1,
          stiffness: tuning.stiffness,
          ratio: tuning.dampingRatio,
        ),
        0,
        1,
        0,
      ),
    );
  }

  @override
  void dispose() {
    _entry.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final style = KitStyle.of(context);
    final ink = theme.colors.textPrimary;
    final accent = style.accent(theme);
    final popover = kitMaterialOf(context, KitTier.popover);
    final dock = kitMaterialOf(context, KitTier.dock);
    final hot = style.menuRow(theme, hot: true);
    final bead = style.panelBead;

    final Widget panel = KitGlass(
      material: popover,
      radius: style.radius(theme, popover.radius ?? 16),
      child: Padding(
        padding: EdgeInsets.all(10 * style.density),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    context.tr('Wi-Fi'),
                    style: BarType.title.copyWith(color: ink),
                  ),
                ),
                Transform.scale(
                  scale: 0.8,
                  alignment: Alignment.centerRight,
                  child: MacSwitch(
                    value: _on,
                    onChanged: (value) => setState(() => _on = value),
                  ),
                ),
              ],
            ),
            SizedBox(height: 6 * style.density),
            Container(
              height: 24,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              alignment: Alignment.centerLeft,
              decoration: BoxDecoration(
                color: hot.fill,
                borderRadius: BorderRadius.circular(style.corner(6)),
              ),
              child: Text(
                context.tr('Network Settings…'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: BarType.menuRow.copyWith(color: hot.ink),
              ),
            ),
            SizedBox(height: 8 * style.density),
            Row(
              children: <Widget>[
                Expanded(
                  child: DialogButton(
                    label: context.tr('Cancel'),
                    onTap: () {},
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: DialogButton(
                    label: context.tr('Replay'),
                    primary: true,
                    onTap: widget.onReplay,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(style.corner(12)),
      child: SizedBox(
        height: 188,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            const CustomPaint(painter: _Backdrop()),
            // The bar: a plate in the panel colour from edge to edge.
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: 26,
              child: ColoredBox(
                color: style
                    .panelFill(theme.panelColor(theme.colors.panelBackground))
                    .withValues(alpha: style.opaque ? 1 : 0.72),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    children: <Widget>[
                      Icon(BarIcons.circleFill, size: 11, color: ink),
                      const SizedBox(width: 8),
                      Text(
                        context.tr('Files'),
                        style: BarType.appName.copyWith(
                          fontSize: 12,
                          color: ink,
                        ),
                      ),
                      const Spacer(),
                      for (var dot = 0; dot < 3; dot++)
                        Container(
                          width: dot == 0 ? 14 : 6,
                          height: 6,
                          margin: const EdgeInsets.only(right: 4),
                          decoration: BoxDecoration(
                            color: dot == 0
                                ? accent
                                : ink.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(style.pill(6)),
                          ),
                        ),
                      const Spacer(),
                      Icon(BarIcons.wifi, size: 12, color: ink),
                      const SizedBox(width: 8),
                      Text(
                        '9:41',
                        style: BarType.clock.copyWith(fontSize: 12, color: ink),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 14,
              top: 36,
              width: 232,
              child: AnimatedBuilder(
                animation: _entry,
                builder: (context, child) {
                  final grown = _entry.value;
                  final shown = Opacity(
                    opacity: grown.clamp(0.0, 1.0),
                    child: child,
                  );
                  return switch (style.entry) {
                    KitPanelEntry.fade => shown,
                    KitPanelEntry.slide => Transform.translate(
                      offset: Offset(0, -18 * (1 - grown)),
                      child: shown,
                    ),
                    KitPanelEntry.zoom => Transform.scale(
                      scale: bead.shortestSide +
                          (1 - bead.shortestSide) * grown,
                      child: shown,
                    ),
                    KitPanelEntry.grow => Transform.scale(
                      alignment: Alignment.topLeft,
                      scaleX: bead.width + (1 - bead.width) * grown,
                      scaleY: bead.height + (1 - bead.height) * grown,
                      child: shown,
                    ),
                  };
                },
                child: panel,
              ),
            ),
            // A piece of dock.
            Positioned(
              right: 14,
              bottom: 12,
              child: SizedBox(
                height: 46,
                child: KitGlass(
                  material: dock,
                  radius: style.corner(dock.radius ?? 20) * 0.7,
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: 7 * style.density,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        for (final (at, colour) in const <Color>[
                          Color(0xff3478f6),
                          Color(0xff34c759),
                          Color(0xffff9f0a),
                          Color(0xffaf52de),
                        ].indexed)
                          Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 3 * style.density,
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: <Widget>[
                                Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: switch (style.look.iconTint) {
                                      KitIconTint.original => colour,
                                      KitIconTint.mono => Color.lerp(
                                        const Color(0xff9a9a9f),
                                        const Color(0xff5c5c61),
                                        at / 3,
                                      ),
                                      KitIconTint.accent => Color.lerp(
                                        accent,
                                        const Color(0xff000000),
                                        at * 0.12,
                                      ),
                                    },
                                    borderRadius: BorderRadius.circular(
                                      style.corner(7),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Container(
                                  width: at == 0 ? 10 : 3,
                                  height: 3,
                                  decoration: BoxDecoration(
                                    color: at == 0
                                        ? accent
                                        : ink.withValues(
                                            alpha: at == 3 ? 0 : 0.5,
                                          ),
                                    borderRadius: BorderRadius.circular(
                                      style.pill(3),
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
            ),
          ],
        ),
      ),
    );
  }
}

/// A stand-in for a wallpaper: a sweep of colour with a few hard edges in
/// it.
class _Backdrop extends CustomPainter {
  const _Backdrop();

  @override
  void paint(Canvas canvas, Size size) {
    final area = Offset.zero & size;
    canvas.drawRect(
      area,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Color(0xff2b4a8f),
            Color(0xff8a4fbf),
            Color(0xffe07a5f),
            Color(0xfff2cc8f),
          ],
        ).createShader(area),
    );
    final paint = Paint();
    canvas
      ..drawCircle(
        Offset(size.width * 0.22, size.height * 0.62),
        size.height * 0.34,
        paint..color = const Color(0xfff4f1de),
      )
      ..drawRect(
        Rect.fromLTWH(size.width * 0.52, size.height * 0.2, 90, 54),
        paint..color = const Color(0xff1d3557),
      )
      ..drawCircle(
        Offset(size.width * 0.8, size.height * 0.7),
        size.height * 0.3,
        paint..color = const Color(0xff2a9d8f),
      );
  }

  @override
  bool shouldRepaint(_Backdrop oldDelegate) => false;
}
