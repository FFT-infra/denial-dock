import 'dart:async';

import 'package:denial_flutter_sdk/models.dart';
import 'package:denial_flutter_sdk/services.dart';
import 'package:denial_flutter_sdk/settings.dart';
import 'package:denial_flutter_sdk/state.dart';
import 'package:denial_flutter_sdk/system_services.dart'
    show PowerProfile, WifiNetwork, systemActionsServiceProvider;
import 'package:denial_flutter_sdk/theme.dart';
import 'package:denial_shell_kit/kit_control_math.dart';
import 'package:denial_shell_kit/kit_entrance.dart';
import 'package:denial_shell_kit/kit_layer.dart' show KitLayer;
import 'package:denial_shell_kit/kit_morph.dart';
import 'package:denial_shell_kit/kit_motion.dart';
import 'package:denial_shell_kit/kit_springs.dart';
import 'package:denial_shell_kit/kit_style.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bar_icons.dart';
import '../bar_preferences.dart';
import '../bar_settings.dart';
import '../bar_tokens.dart';
import '../bar_type.dart';
import '../debug_remote.dart';
import '../island/island_timer.dart';
import '../l10n.dart';
import '../media_art.dart';
import '../night_light.dart';
import 'mac_kit.dart';
import 'popovers.dart';
import 'tile_grid.dart';

const double controlCenterWidth = 320;

abstract final class _C {
  static const double inset = 14;
  static const double gap = 12;
  static const double row = 64;
  static const double sliderRadius = 22;
}

/// Control Centre: connectivity capsules beside Now Playing, the round
/// switches, then the display and sound sliders. A capsule's disc toggles;
/// the rest of it opens the detail page in place.
class ControlCenterPanel extends ConsumerStatefulWidget {
  const ControlCenterPanel({
    required this.services,
    required this.output,
    required this.onSettings,
    required this.onJoinNetwork,
    required this.onConfirmPower,
    required this.onClose,
    super.key,
  });

  final ShellServices services;
  final DisplayOutput output;
  final VoidCallback onSettings;
  final ValueChanged<WifiNetwork> onJoinNetwork;

  /// Asks the bar to put the confirmation up for a power action. The bar owns
  /// the dialog because the sheet closes behind it.
  final ValueChanged<SessionPowerAction> onConfirmPower;
  final VoidCallback onClose;

  @override
  ConsumerState<ControlCenterPanel> createState() => _ControlCenterPanelState();
}

class _ControlCenterPanelState extends ConsumerState<ControlCenterPanel>
    with SingleTickerProviderStateMixin {
  /// The page the panel is heading for; empty is the grid.
  String _page = '';

  /// The detail page on screen, kept while it shrinks back into its tile.
  String _shown = '';
  bool _editing = false;

  /// One spring carries a detail page out of its tile and back: the frame,
  /// its corners, the hand-over between the two faces and the panel's height
  /// all read this value, so they cannot come apart. A new target keeps the
  /// velocity, so turning back half way does not jump.
  late final KitSpring _grow = KitSpring(0, _plainGrow);
  late final KitSprings _springs = KitSprings(this, <KitSpring>[_grow])
    ..onRest = _rested;

  /// Denial lets the page pass its size by a hair; the other look lands
  /// without overshoot.
  static const KitSpringTuning _liquidGrow = KitSpringTuning(300, 0.8);
  static const KitSpringTuning _plainGrow = KitSpringTuning(322, 1);

  /// A look whose transitions run brisker than written takes its own popup
  /// spring for the page as well, and lands as dead-beat as its popups do.
  static KitSpringTuning _growTuning(KitStyle style) => style.liquid
      ? _liquidGrow
      : style.pace > 1
      ? style.panelGrow
      : _plainGrow;

  final GlobalKey _morphKey = GlobalKey();
  final Map<String, GlobalKey> _tileKeys = <String, GlobalKey>{};
  Rect? _from;
  double _fromRadius = 0;

  /// Its own scope, so Tab and the arrows stay inside the panel. Keys it
  /// does not use, Escape above all, still travel up to the layer.
  final FocusScopeNode _root = FocusScopeNode(debugLabel: 'control centre');
  final FocusNode _detailFocus = FocusNode(
    debugLabel: 'control centre detail',
    skipTraversal: true,
  );

  /// The tile a detail page was opened from with the keyboard, which takes
  /// the focus back when the page closes.
  FocusNode? _opener;
  ValueChanged<bool Function()?>? _intercept;

  /// Tab walks the controls and the arrows jump to the nearest one that
  /// way. A control that uses a key itself (a slider its arrows, a text
  /// field everything) has already taken it by the time it gets here.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final focus = FocusManager.instance.primaryFocus;
    final at = focus?.context;
    if (focus == null || at == null) return KeyEventResult.ignored;
    if (at.widget is EditableText ||
        at.findAncestorWidgetOfExactType<EditableText>() != null) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.tab) {
      HardwareKeyboard.instance.isShiftPressed
          ? focus.previousFocus()
          : focus.nextFocus();
      return KeyEventResult.handled;
    }
    final direction = key == LogicalKeyboardKey.arrowLeft
        ? TraversalDirection.left
        : key == LogicalKeyboardKey.arrowRight
        ? TraversalDirection.right
        : key == LogicalKeyboardKey.arrowUp
        ? TraversalDirection.up
        : key == LogicalKeyboardKey.arrowDown
        ? TraversalDirection.down
        : null;
    if (direction == null) return KeyEventResult.ignored;
    focus.focusInDirection(direction);
    return KeyEventResult.handled;
  }

  ShellServices get services => widget.services;

  @override
  void initState() {
    super.initState();
    NightLight.sync();
    debugCommand.addListener(_debug);
    // The keys land here first, so Tab and the arrows have somewhere to
    // start from; Escape still travels up to the layer.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _root.requestFocus();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final hook = context
        .dependOnInheritedWidgetOfExactType<KitLayer>()
        ?.interceptBack;
    if (hook != _intercept) {
      _intercept?.call(null);
      _intercept = hook;
    }
    hook?.call(_back);
  }

  @override
  void dispose() {
    _intercept?.call(null);
    debugCommand.removeListener(_debug);
    _springs.dispose();
    _root.dispose();
    _detailFocus.dispose();
    super.dispose();
  }

  void _debug() {
    final words = debugWords();
    if (words.length < 2 || words.first != 'ccpage') return;
    final editing = words[1] == 'edit';
    _go(editing || words[1] == 'home' ? '' : words[1]);
    setState(() => _editing = editing);
  }

  /// Escape and a press outside come here before they close the panel: a
  /// detail page goes back to the grid first, an edit ends first, and only a
  /// panel at rest lets the layer close it.
  bool _back() {
    final step = panelBackStep(detail: _page.isNotEmpty, editing: _editing);
    switch (step) {
      case PanelBackStep.leaveDetail:
        _go('');
      case PanelBackStep.endEditing:
        setState(() => _editing = false);
      case PanelBackStep.close:
        return false;
    }
    return true;
  }

  /// Where the tile [id] sits in the panel, for its page to grow out of.
  void _measure(String id) {
    final style = KitStyle.of(context);
    final tile = _tileKeys[id]?.currentContext?.findRenderObject();
    final panel = _morphKey.currentContext?.findRenderObject();
    if (tile is RenderBox && panel is RenderBox && tile.hasSize) {
      _from = tile.localToGlobal(Offset.zero, ancestor: panel) & tile.size;
      _fromRadius = id == 'sound'
          ? style.corner(_C.sliderRadius)
          : style.pill(tile.size.height);
    } else {
      _from = null;
      _fromRadius = BarTokens.popoverRadius * style.cornerScale;
    }
  }

  void _go(String page) {
    if (page == _page) return;
    final keys = keyboardInput.value;
    if (page.isNotEmpty) {
      // A page opened while another shrinks keeps growing from that tile.
      if (_shown.isEmpty) _measure(page);
      _opener = keys ? FocusManager.instance.primaryFocus : null;
    }
    setState(() {
      _page = page;
      if (page.isNotEmpty) _shown = page;
    });
    _grow
      ..tune(_growTuning(KitStyle.of(context)))
      ..target = page.isEmpty ? 0 : 1;
    _springs.kick(reduceMotion: KitMotion.reduced(context));
    // Focus follows only someone who is using the keys; a pointer leaves it
    // where it was and no ring appears.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_page.isEmpty) {
        final opener = _opener;
        _opener = null;
        if (keys && opener != null && opener.context != null) {
          opener.requestFocus();
        }
      } else if (keys) {
        _detailFocus.traversalDescendants.firstOrNull?.requestFocus();
      }
    });
  }

  void _rested() {
    if (_grow.target == 0 && _shown.isNotEmpty && mounted) {
      setState(() => _shown = '');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final style = KitStyle.of(context);
    final ink = theme.colors.textPrimary;
    final Widget? detail = switch (_shown) {
      'wifi' => WifiPopover(
        onBack: () => _go(''),
        onJoin: widget.onJoinNetwork,
        onSettings: widget.onSettings,
      ),
      'bluetooth' => BluetoothPopover(
        onBack: () => _go(''),
        onSettings: widget.onSettings,
      ),
      'sound' => SoundPopover(
        services: services,
        onBack: () => _go(''),
        onSettings: widget.onSettings,
      ),
      'timer' => _TimerPage(onBack: () => _go('')),
      _ => null,
    };
    final home = KeyedSubtree(
      key: const ValueKey<String>('home'),
      child: ExcludeFocus(
        excluding: _page.isNotEmpty,
        child: KitEntrance(child: _grid(context)),
      ),
    );
    final page = detail == null
        ? null
        : Focus(
            key: ValueKey<String>(_shown),
            focusNode: _detailFocus,
            skipTraversal: true,
            child: detail,
          );
    return SizedBox(
      width: controlCenterWidth,
      child: FocusScope(
        node: _root,
        onKeyEvent: _onKey,
        child: FocusTraversalGroup(
          child: AnimatedBuilder(
            animation: _springs,
            builder: (context, _) => KitMorph(
              key: _morphKey,
              progress: _grow.value,
              from: _from,
              fromRadius: _fromRadius,
              toRadius: BarTokens.popoverRadius * style.cornerScale,
              plate: ink.withValues(alpha: 0.07),
              rim: style.flat
                  ? theme.colors.hairline
                  : ink.withValues(alpha: 0.08),
              home: home,
              detail: page,
            ),
          ),
        ),
      ),
    );
  }

  static const List<TileChoice> _library = <TileChoice>[
    TileChoice(id: 'wifi', icon: BarIcons.wifi, label: 'Wi-Fi'),
    TileChoice(id: 'bluetooth', icon: BarIcons.bluetooth, label: 'Bluetooth'),
    TileChoice(id: 'media', icon: BarIcons.playFill, label: 'Now Playing'),
    TileChoice(id: 'focus', icon: BarIcons.moonFill, label: 'Focus'),
    TileChoice(id: 'dark', icon: BarIcons.circleHalf, label: 'Dark Mode'),
    TileChoice(id: 'night', icon: BarIcons.sunMax, label: 'Night Light'),
    TileChoice(id: 'screenshot', icon: BarIcons.camera, label: 'Screenshot'),
    TileChoice(id: 'power', icon: BarIcons.bolt, label: 'Power Mode'),
    TileChoice(
      id: 'recording',
      icon: BarIcons.circleFill,
      label: 'Screen Recording',
    ),
    TileChoice(id: 'display', icon: BarIcons.sunMaxFill, label: 'Display'),
    TileChoice(id: 'sound', icon: BarIcons.speaker3Fill, label: 'Sound'),
    TileChoice(id: 'battery', icon: BarIcons.batteryFull, label: 'Battery'),
    TileChoice(id: 'lock', icon: BarIcons.lockFill, label: 'Lock Screen'),
    TileChoice(
      id: 'desktop',
      icon: BarIcons.desktopcomputer,
      label: 'Show Desktop',
    ),
    TileChoice(id: 'search', icon: BarIcons.search, label: 'Search'),
    TileChoice(id: 'settings', icon: BarIcons.gear, label: 'Settings'),
    TileChoice(id: 'timer', icon: BarIcons.timer, label: 'Timer'),
  ];

  void _saveControls(List<String> controls) => ref
      .read(barSettingsProvider.notifier)
      .save((s) => s.copyWith(controls: controls));

  Tile? _tile(BuildContext context, String id) {
    final sizes = parseTileSizes(
      ref.watch(
        barSettingsProvider.select(
          (state) => state.value?.tileSizes ?? const <String>[],
        ),
      ),
    );
    final key = 'cc.$id';
    // A toggle is either a capsule with its name or a bare disc; the user
    // picks, and each kind knows how to draw itself as the other.
    Tile sized(TileSize natural, Widget child) {
      final wide = (sizes[key] ?? natural).w > 1;
      return Tile(
        id: id,
        size: TileSize(wide ? 2 : 1, 1),
        child: child,
        onResize: () => ref
            .read(barSettingsProvider.notifier)
            .save(
              (s) => s.copyWith(
                tileSizes: writeTileSizes(<String, TileSize>{
                  ...parseTileSizes(s.tileSizes),
                  key: TileSize(wide ? 1 : 2, 1),
                }),
              ),
            ),
      );
    }

    final label = context.tr(
      _library.where((choice) => choice.id == id).firstOrNull?.label ?? id,
    );
    Widget fit(Widget control, TileSize natural) {
      final wide = (sizes[key] ?? natural).w > 1;
      if (control is _Capsule && !wide) {
        return _Round(
          icon: control.icon,
          on: control.on,
          colour: control.colour,
          onTap: control.onToggle,
        );
      }
      if (control is _Round && wide) {
        return _Capsule(
          icon: control.icon,
          on: control.on,
          colour: control.colour,
          title: label,
          detail: control.stateless
              ? ''
              : context.tr(control.on ? 'On' : 'Off'),
          onToggle: control.onTap,
        );
      }
      return control;
    }

    Tile capsule(Widget child) =>
        sized(const TileSize(2, 1), fit(child, const TileSize(2, 1)));
    Tile round(Widget child) =>
        sized(const TileSize(1, 1), fit(child, const TileSize(1, 1)));
    void act(VoidCallback action) {
      widget.onClose();
      action();
    }

    switch (id) {
      case 'wifi':
        final on = ref.watch(
          networkConnectivityProvider.select(
            (state) => state.snapshot.wirelessEnabled,
          ),
        );
        final wifi = ref.watch(services.connectedWifi);
        return capsule(
          _Capsule(
            icon: on ? BarIcons.wifi : BarIcons.wifiSlash,
            on: on,
            title: 'Wi-Fi',
            detail: !on
                ? context.tr('Off')
                : (wifi?.ssid ?? context.tr('Not Connected')),
            onToggle: () => ref
                .read(networkConnectivityProvider.notifier)
                .setWirelessEnabled(!on),
            onOpen: () => _go('wifi'),
          ),
        );
      case 'bluetooth':
        final bluetooth = ref.watch(bluetoothProvider);
        final on = bluetooth.available && bluetooth.powered;
        final connected = <String>[
          for (final device in bluetooth.devices)
            if (device.connected) device.name,
        ];
        return capsule(
          _Capsule(
            icon: BarIcons.bluetooth,
            on: on,
            title: context.tr('Bluetooth'),
            detail: !bluetooth.available
                ? context.tr('Unavailable')
                : !on
                ? context.tr('Off')
                : connected.isEmpty
                ? context.tr('On')
                : connected.join(', '),
            onToggle: bluetooth.available
                ? () => ref.read(bluetoothProvider.notifier).togglePower()
                : null,
            onOpen: () => _go('bluetooth'),
          ),
        );
      case 'media':
        return Tile(
          id: id,
          size: const TileSize(2, 2),
          child: _MediaTile(services: services),
        );
      case 'focus':
        final focus = ref.watch(
          desktopNotificationsProvider.select((state) => state.doNotDisturb),
        );
        return capsule(
          _Capsule(
            icon: BarIcons.moonFill,
            on: focus,
            colour: macPurple,
            title: context.tr('Focus'),
            detail: context.tr(focus ? 'On' : 'Off'),
            onToggle: () => ref
                .read(desktopNotificationsProvider.notifier)
                .toggleDoNotDisturb(),
          ),
        );
      case 'dark':
        final dark = ref.watch(
          shellSettingsProvider.select(
            (state) =>
                state.appearance.colorSchemePreference.effectiveBrightness ==
                Brightness.dark,
          ),
        );
        return round(
          _Round(
            icon: BarIcons.circleHalf,
            on: dark,
            colour: const Color(0xff636366),
            onTap: () => ref
                .read(shellSettingsProvider.notifier)
                .setColorSchemePreference(
                  dark
                      ? DesktopColorSchemePreference.preferLight
                      : DesktopColorSchemePreference.preferDark,
                ),
          ),
        );
      case 'night':
        return round(
          ValueListenableBuilder<bool>(
            valueListenable: NightLight.enabled,
            builder: (context, night, _) => fit(
              _Round(
                icon: night ? BarIcons.sunMaxFill : BarIcons.sunMax,
                on: night,
                colour: macOrange,
                onTap: NightLight.toggle,
              ),
              const TileSize(1, 1),
            ),
          ),
        );
      case 'screenshot':
        return round(
          _Round(
            icon: BarIcons.camera,
            on: false,
            stateless: true,
            onTap: () => act(
              () => ref.read(systemActionsServiceProvider).takeScreenshot(),
            ),
          ),
        );
      case 'power':
        final power = ref.watch(desktopPowerModesProvider);
        final saving = power.systemProfile == PowerProfile.powerSave;
        final fast = power.systemProfile == PowerProfile.performance;
        return round(
          _Round(
            icon: fast ? BarIcons.boltFill : BarIcons.bolt,
            on: power.systemAvailable && (saving || fast),
            colour: saving ? macYellow : macBlue,
            onTap: power.systemAvailable
                ? () => ref
                      .read(desktopPowerModesProvider.notifier)
                      .selectSystemProfile(
                        PowerProfile.next(power.systemProfile),
                      )
                : null,
          ),
        );
      case 'recording':
        final recording = ref.watch(screenRecordingProvider);
        return capsule(
          _Capsule(
            icon: BarIcons.circleFill,
            on: recording.recording,
            colour: macRed,
            title: context.tr('Screen Recording'),
            detail: context.tr(recording.recording ? 'On' : 'Off'),
            onToggle: recording.available
                ? () => act(
                    () => ref.read(screenRecordingProvider.notifier).toggle(),
                  )
                : null,
          ),
        );
      case 'display':
        final level = ref.watch(
          displayBrightnessProvider.select(
            (state) => state.levels[widget.output.monitorId] ?? 1.0,
          ),
        );
        final brightness = ref.read(displayBrightnessProvider.notifier);
        return Tile(
          id: id,
          size: const TileSize(4, 1),
          child: _SliderTile(
            label: context.tr('Display'),
            value: level,
            leading: BarIcons.sunMax,
            trailing: BarIcons.sunMaxFill,
            onChanged: (value) => brightness.setLevel(widget.output, value),
            onChangeEnd: (value) =>
                brightness.commitLevel(widget.output, value),
          ),
        );
      case 'sound':
        final volume = ref.watch(services.volume);
        return Tile(
          id: id,
          size: const TileSize(4, 1),
          child: _SliderTile(
            label: context.tr('Sound'),
            value: volume,
            leading: volume <= 0.001
                ? BarIcons.speakerSlashFill
                : BarIcons.speaker1Fill,
            trailing: BarIcons.speaker3Fill,
            onOpen: () => _go('sound'),
            onChangeStart: services.beginVolumeInteraction,
            onChanged: services.setVolume,
            onChangeEnd: services.commitVolume,
          ),
        );
      case 'battery':
        final battery = ref.watch(services.battery);
        if (battery.capacity == null) return null;
        final plugged =
            battery.charging ||
            ref.watch(
              upowerProvider.select(
                (state) => state.snapshot?.onBattery == false,
              ),
            );
        return capsule(
          _Capsule(
            icon: plugged ? BarIcons.boltFill : BarIcons.batteryFull,
            on: plugged,
            colour: macGreen,
            title: context.tr('Battery'),
            detail: plugged
                ? '${battery.capacity}% · ${context.tr('Charging')}'
                : '${battery.capacity}%',
            onToggle: widget.onSettings,
          ),
        );
      case 'timer':
        return capsule(
          _TimerWatch(
            builder: (context, now) => fit(
              _Capsule(
                icon: BarIcons.timer,
                on: islandTimer.active,
                colour: macOrange,
                title: context.tr('Timer'),
                detail: islandTimer.active
                    ? clockSpan(islandTimer.remaining(now))
                    : context.tr('Off'),
                ticking: islandTimer.active,
                onToggle: () => islandTimer.active
                    ? islandTimer.cancel()
                    : islandTimer.start(const Duration(minutes: 5), now),
                onOpen: () => _go('timer'),
              ),
              const TileSize(2, 1),
            ),
          ),
        );
      case 'lock':
        return round(
          _Round(
            icon: BarIcons.lockFill,
            on: false,
            stateless: true,
            onTap: () => act(
              () => ref
                  .read(sessionPowerProvider.notifier)
                  .request(SessionPowerAction.lock),
            ),
          ),
        );
      case 'desktop':
        return round(
          _Round(
            icon: BarIcons.desktopcomputer,
            on: ref.watch(services.desktopVisible),
            onTap: () => act(services.toggleDesktop),
          ),
        );
      case 'search':
        return round(
          _Round(
            icon: BarIcons.search,
            on: false,
            stateless: true,
            onTap: () => act(services.toggleLauncher),
          ),
        );
      case 'settings':
        return round(
          _Round(
            icon: BarIcons.gear,
            on: false,
            stateless: true,
            onTap: widget.onSettings,
          ),
        );
    }
    return null;
  }

  Widget _grid(BuildContext context) {
    final theme = context.shellTheme;
    final order = ref.watch(
      barSettingsProvider.select(
        (state) => state.value?.controls ?? defaultControls,
      ),
    );
    final tiles = <Tile>[
      for (final id in order)
        if (_tile(context, id) case final tile?)
          // Keyed so a detail page can find the tile it grows out of.
          Tile(
            id: tile.id,
            size: tile.size,
            onResize: tile.onResize,
            child: KeyedSubtree(
              key: _tileKeys.putIfAbsent(id, GlobalKey.new),
              child: tile.child,
            ),
          ),
    ];
    final spare = <TileChoice>[
      for (final choice in _library)
        if (!order.contains(choice.id))
          TileChoice(
            id: choice.id,
            icon: choice.icon,
            label: context.tr(choice.label),
          ),
    ];
    return Padding(
      padding: const EdgeInsets.all(_C.inset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TileGrid(
            tiles: tiles,
            columns: 4,
            cell: const Size.square(_C.row),
            gap: _C.gap,
            editing: _editing,
            onReorder: _saveControls,
            onRemove: (id) => _saveControls(<String>[
              for (final other in order)
                if (other != id) other,
            ]),
          ),
          Reveal(
            open: _editing,
            child: Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(2, 0, 0, 8),
                    child: Text(
                      context.tr('Add Controls'),
                      style: BarType.section.copyWith(
                        color: theme.colors.textSecondary,
                      ),
                    ),
                  ),
                  TileLibrary(
                    choices: spare,
                    empty: context.tr('Everything is already here.'),
                    onAdd: (id) => _saveControls(<String>[...order, id]),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Session actions live here rather than in the bar's system menu:
          // this is the panel that is open when someone wants to stop work.
          KitEntranceItem(
            row: 4,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: _PowerRow(
                onSleep: () => widget.onClose(),
                confirm: (action) {
                  widget.onClose();
                  widget.onConfirmPower(action);
                },
                request: (action) {
                  widget.onClose();
                  ref.read(sessionPowerProvider.notifier).request(action);
                },
              ),
            ),
          ),
          KitEntranceItem(
            row: 5,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                if (_editing) ...<Widget>[
                  TileEditButton(
                    label: context.tr('Reset'),
                    onTap: () => _saveControls(defaultControls),
                  ),
                  const SizedBox(width: 8),
                ],
                TileEditButton(
                  label: context.tr(_editing ? 'Done' : 'Edit Controls'),
                  strong: _editing,
                  onTap: () => setState(() => _editing = !_editing),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Sleep, restart, shut down and lock, in one row at the foot of the panel.
///
/// Lock and sleep go at once; the three that end the session ask first,
/// because none of them can be undone. An action the session cannot take is
/// dimmed rather than hidden, so the row does not change shape.
class _PowerRow extends ConsumerWidget {
  const _PowerRow({
    required this.onSleep,
    required this.confirm,
    required this.request,
  });

  /// Called before any action so the sheet is out of the way.
  final VoidCallback onSleep;
  final ValueChanged<SessionPowerAction> confirm;
  final ValueChanged<SessionPowerAction> request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionPowerProvider);
    final power = ref.read(sessionPowerProvider.notifier);
    bool can(SessionPowerAction action) =>
        session.busyAction == null && session.availabilityFor(action).enabled;
    final theme = context.shellTheme;
    final style = KitStyle.of(context);
    final ink = theme.colors.textPrimary;
    final shape = theme.borderRadius(14) * style.cornerScale;

    Widget button(String label, IconData icon, VoidCallback? onTap) => Expanded(
      child: Pressable(
        onTap: onTap,
        scale: Pressable.large,
        wash: true,
        shape: shape,
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            borderRadius: shape,
            color: ink.withValues(alpha: 0.07),
            border: style.controlLine(theme),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              BarGlyph(
                icon,
                size: 17,
                color: onTap == null
                    ? ink.withValues(alpha: 0.35)
                    : ink.withValues(alpha: 0.9),
              ),
              const SizedBox(height: 3),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: BarType.caption.copyWith(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: onTap == null
                      ? ink.withValues(alpha: 0.35)
                      : ink.withValues(alpha: 0.9),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    VoidCallback? at(SessionPowerAction action, VoidCallback run) =>
        can(action) ? run : null;

    return Row(
      children: <Widget>[
        button(
          context.tr('Sleep'),
          BarIcons.moonFill,
          at(SessionPowerAction.suspend, () {
            onSleep();
            power.request(SessionPowerAction.suspend);
          }),
        ),
        const SizedBox(width: 8),
        button(
          context.tr('Restart'),
          BarIcons.arrowClockwise,
          at(
            SessionPowerAction.reboot,
            () => confirm(SessionPowerAction.reboot),
          ),
        ),
        const SizedBox(width: 8),
        button(
          context.tr('Shut Down'),
          BarIcons.power,
          at(
            SessionPowerAction.powerOff,
            () => confirm(SessionPowerAction.powerOff),
          ),
        ),
        const SizedBox(width: 8),
        button(
          context.tr('Lock'),
          BarIcons.lockFill,
          at(SessionPowerAction.lock, () {
            onSleep();
            request(SessionPowerAction.lock);
          }),
        ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.radius,
    required this.child,
    this.hovered = false,
    this.pressed = false,
  });

  /// The corner radius as drawn: the caller has taken it through the look.
  final double radius;
  final Widget child;

  /// A tile that can be pressed as a whole lifts a shade under the pointer
  /// and another under a press.
  final bool hovered;
  final bool pressed;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    return AnimatedContainer(
      duration: KitMotion.duration(
        context,
        pressed ? KitMotion.wash : KitMotion.enter,
      ),
      decoration: BoxDecoration(
        color: theme.colors.textPrimary.withValues(
          alpha: pressed
              ? 0.17
              : hovered
              ? 0.10
              : 0.07,
        ),
        borderRadius: BorderRadius.circular(radius),
        border:
            KitStyle.of(context).controlLine(theme) ??
            Border.all(color: theme.colors.textPrimary.withValues(alpha: 0.08)),
      ),
      child: child,
    );
  }
}

class _Capsule extends StatefulWidget {
  const _Capsule({
    required this.icon,
    required this.on,
    required this.title,
    required this.detail,
    required this.onToggle,
    this.onOpen,
    this.colour = macBlue,
    this.ticking = false,
  });

  final IconData icon;
  final bool on;
  final String title;
  final String detail;
  final VoidCallback? onToggle;
  final VoidCallback? onOpen;
  final Color colour;

  /// The detail is a running clock: it changes every second, and a fade on
  /// each change would never finish.
  final bool ticking;

  @override
  State<_Capsule> createState() => _CapsuleState();
}

class _CapsuleState extends State<_Capsule> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final style = KitStyle.of(context);
    final action = widget.onOpen ?? widget.onToggle;
    final detail = Text(
      widget.detail,
      key: widget.ticking ? null : ValueKey<String>(widget.detail),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: BarType.caption.copyWith(
        fontSize: 12,
        color: theme.colors.textSecondary,
      ),
    );
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: _Tile(
        radius: style.pill(_C.row),
        hovered: _hovered && action != null,
        pressed: _pressed,
        child: Row(
          children: <Widget>[
            const SizedBox(width: 11),
            Opacity(
              opacity: widget.onToggle == null ? 0.45 : 1,
              child: Pressable(
                onTap: widget.onToggle,
                scale: Pressable.small,
                wash: true,
                shape: style.disc(42),
                child: MacDisc(
                  icon: widget.icon,
                  on: widget.on,
                  size: 42,
                  colour: widget.colour,
                ),
              ),
            ),
            Expanded(
              child: Pressable(
                onTap: action,
                scale: Pressable.large,
                shape: BorderRadius.horizontal(
                  left: Radius.circular(style.corner(10)),
                  right: Radius.circular(style.pill(_C.row)),
                ),
                onHighlight: (_, pressed) {
                  if (pressed != _pressed) setState(() => _pressed = pressed);
                },
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(9, 0, 12, 0),
                  child: SizedBox(
                    height: _C.row,
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                widget.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: BarType.title.copyWith(
                                  color: theme.colors.textPrimary,
                                ),
                              ),
                              if (widget.detail.isNotEmpty)
                                AnimatedSwitcher(
                                  duration: KitMotion.duration(
                                    context,
                                    KitMotion.swap,
                                  ),
                                  switchInCurve: KitMotion.outCubic,
                                  switchOutCurve: KitMotion.inCubic,
                                  layoutBuilder: (current, previous) => Stack(
                                    alignment: Alignment.centerLeft,
                                    children: <Widget>[...previous, ?current],
                                  ),
                                  child: detail,
                                ),
                            ],
                          ),
                        ),
                        if (widget.onOpen != null) _OpenHint(hovered: _hovered),
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

/// The arrow that says a capsule opens a page. A pointer sees it slide in
/// on hover; a finger cannot hover, so for touch it is always there, dimmer.
class _OpenHint extends StatelessWidget {
  const _OpenHint({required this.hovered});

  final bool hovered;

  @override
  Widget build(BuildContext context) {
    final colour = context.shellTheme.colors.textSecondary;
    return ValueListenableBuilder<bool>(
      valueListenable: touchInput,
      builder: (context, touch, child) {
        final duration = KitMotion.duration(context, KitMotion.fill);
        return AnimatedOpacity(
          duration: duration,
          opacity: hovered
              ? 1
              : touch
              ? 0.55
              : 0,
          child: AnimatedSlide(
            duration: duration,
            curve: KitMotion.outCubic,
            offset: hovered || touch ? Offset.zero : const Offset(-0.5, 0),
            child: child,
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.only(left: 4),
        child: BarGlyph(BarIcons.chevronRight, size: 11, color: colour),
      ),
    );
  }
}

class _Round extends StatelessWidget {
  const _Round({
    required this.icon,
    required this.on,
    required this.onTap,
    this.colour = macBlue,
    this.stateless = false,
  });

  final IconData icon;
  final bool on;
  final VoidCallback? onTap;
  final Color colour;

  /// An action rather than a switch: it has no On or Off to report.
  final bool stateless;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final style = KitStyle.of(context);
    final shape = style.disc(_C.row);
    return Opacity(
      opacity: onTap == null ? 0.45 : 1,
      child: Pressable(
        onTap: onTap,
        scale: Pressable.small,
        wash: true,
        shape: shape,
        // The same fill as a capsule's disc, so every switch in the panel
        // turns on the same way.
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            borderRadius: shape,
            border:
                style.controlLine(theme) ??
                Border.all(
                  color: theme.colors.textPrimary.withValues(alpha: 0.08),
                ),
          ),
          child: LiquidFill(
            level: on ? 1 : 0,
            color: style.plate(theme, colour),
            base: theme.colors.textPrimary.withValues(alpha: 0.07),
            radius: shape,
            child: Center(
              child: MacGlyph(
                icon,
                size: 24,
                color: on ? style.onPlate(theme) : theme.colors.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MediaTile extends ConsumerWidget {
  const _MediaTile({required this.services});

  final ShellServices services;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.shellTheme;
    final playback = ref.watch(services.media).value;
    final commands = ref.watch(services.mediaCommands);
    final has = playback != null && playback.title.isNotEmpty;
    final ink = theme.colors.textPrimary;
    final style = KitStyle.of(context);

    Widget control(IconData icon, bool enabled, VoidCallback onTap, double s) =>
        Pressable(
          onTap: enabled ? onTap : null,
          scale: Pressable.small,
          wash: true,
          shape: BorderRadius.circular(style.pill(32)),
          child: SizedBox(
            width: 36,
            height: 32,
            child: BarGlyph(
              icon,
              size: s,
              color: ink.withValues(alpha: enabled ? 1 : 0.3),
            ),
          ),
        );

    return _Tile(
      radius: style.corner(26),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(13, 13, 13, 7),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            MediaArtwork(
              url: playback?.artUrl ?? '',
              size: 42,
              radius: style.corner(10),
              fallback: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: ink.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(style.corner(10)),
                ),
                child: BarGlyph(
                  BarIcons.playFill,
                  size: 18,
                  color: theme.colors.textSecondary,
                ),
              ),
            ),
            const SizedBox(height: 7),
            Text(
              has ? playback.title : context.tr('Not Playing'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: BarType.title.copyWith(
                color: has ? ink : theme.colors.textSecondary,
              ),
            ),
            if (has && playback.artistLabel.isNotEmpty)
              Text(
                playback.artistLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: BarType.caption.copyWith(
                  color: theme.colors.textSecondary,
                ),
              ),
            const Spacer(),
            if (has && playback.length > Duration.zero)
              _MediaProgress(
                playing: playback.playing,
                length: playback.length,
                positionAt: playback.positionAt,
              ),
            const SizedBox(height: 3),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                control(
                  BarIcons.backward,
                  playback?.canGoPrevious ?? false,
                  commands.previous,
                  18,
                ),
                control(
                  playback?.playing == true
                      ? BarIcons.pauseFill
                      : BarIcons.playFill,
                  playback?.available ?? false,
                  commands.playPause,
                  24,
                ),
                control(
                  BarIcons.forward,
                  playback?.canGoNext ?? false,
                  commands.next,
                  18,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A hairline of how far the track has played. The system reports a position
/// and when it was read; the line works out the rest from the clock, twice a
/// second while something plays.
class _MediaProgress extends StatefulWidget {
  const _MediaProgress({
    required this.playing,
    required this.length,
    required this.positionAt,
  });

  final bool playing;
  final Duration length;
  final Duration Function(DateTime now) positionAt;

  @override
  State<_MediaProgress> createState() => _MediaProgressState();
}

class _MediaProgressState extends State<_MediaProgress> {
  late final Timer _tick = Timer.periodic(const Duration(milliseconds: 500), (
    _,
  ) {
    if (widget.playing) setState(() {});
  });

  @override
  void initState() {
    super.initState();
    _tick;
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ink = context.shellTheme.colors.textPrimary;
    final ends = BorderRadius.circular(KitStyle.of(context).pill(3));
    final played = mediaProgress(
      widget.positionAt(DateTime.now()).inMicroseconds,
      widget.length.inMicroseconds,
    );
    return SizedBox(
      height: 3,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: ink.withValues(alpha: 0.14),
          borderRadius: ends,
        ),
        child: FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: played,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: ink.withValues(alpha: 0.6),
              borderRadius: ends,
            ),
          ),
        ),
      ),
    );
  }
}

class _SliderTile extends StatelessWidget {
  const _SliderTile({
    required this.label,
    required this.value,
    required this.leading,
    required this.trailing,
    required this.onChanged,
    required this.onChangeEnd,
    this.onChangeStart,
    this.onOpen,
  });

  final String label;
  final double value;
  final IconData leading;
  final IconData trailing;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;
  final VoidCallback? onChangeStart;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    return _Tile(
      radius: KitStyle.of(context).corner(_C.sliderRadius),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 7, 8, 1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Pressable(
              onTap: onOpen,
              scale: Pressable.large,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 7),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        label,
                        style: BarType.section.copyWith(
                          color: theme.colors.textPrimary,
                        ),
                      ),
                    ),
                    if (onOpen != null)
                      BarGlyph(
                        BarIcons.chevronRight,
                        size: 11,
                        color: theme.colors.textSecondary,
                      ),
                  ],
                ),
              ),
            ),
            const Spacer(),
            MacSlider(
              value: value,
              leading: leading,
              trailing: trailing,
              onChangeStart: onChangeStart,
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            ),
          ],
        ),
      ),
    );
  }
}

/// Rebuilds once a second while the timer runs, and whenever it changes.
class _TimerWatch extends StatefulWidget {
  const _TimerWatch({required this.builder});

  final Widget Function(BuildContext context, DateTime now) builder;

  @override
  State<_TimerWatch> createState() => _TimerWatchState();
}

class _TimerWatchState extends State<_TimerWatch> {
  late final Timer _tick = Timer.periodic(const Duration(seconds: 1), (_) {
    if (islandTimer.active && !islandTimer.paused) setState(() {});
  });

  void _changed() => setState(() {});

  @override
  void initState() {
    super.initState();
    _tick;
    islandTimer.addListener(_changed);
  }

  @override
  void dispose() {
    _tick.cancel();
    islandTimer.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, DateTime.now());
}

class _TimerPage extends StatelessWidget {
  const _TimerPage({required this.onBack});

  final VoidCallback onBack;

  static const List<int> _minutes = <int>[1, 3, 5, 10, 15, 20, 25, 30, 45, 60];

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final ink = theme.colors.textPrimary;
    final style = KitStyle.of(context);
    Widget chip(String label, VoidCallback onTap, {Color? fill, Color? text}) =>
        Pressable(
          onTap: onTap,
          scale: Pressable.large,
          wash: true,
          shape: BorderRadius.circular(style.pill(34)),
          child: Container(
            constraints: const BoxConstraints(minWidth: 50),
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: fill ?? ink.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(style.pill(34)),
              border: style.controlLine(theme),
            ),
            child: Text(
              label,
              maxLines: 1,
              style: BarType.caption.copyWith(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: text ?? ink,
              ),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.all(8),
      child: _TimerWatch(
        builder: (context, now) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            MacHeader(title: context.tr('Timer'), onBack: onBack),
            const MacDivider(),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Center(
                child: Text(
                  islandTimer.active
                      ? clockSpan(islandTimer.remaining(now))
                      : '0:00',
                  style: BarType.display.copyWith(
                    fontSize: 40,
                    color: islandTimer.active && !islandTimer.paused
                        ? KitStyle.of(context).plate(theme, macOrange)
                        : theme.colors.textSecondary,
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
              ),
            ),
            if (islandTimer.active)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  children: <Widget>[
                    chip(
                      '+1',
                      () => islandTimer.add(const Duration(minutes: 1), now),
                    ),
                    chip(
                      context.tr(islandTimer.paused ? 'Resume' : 'Pause'),
                      () => islandTimer.toggle(now),
                      fill: style.plate(theme, macOrange),
                      text: style.onPlate(theme),
                    ),
                    chip(context.tr('Cancel'), islandTimer.cancel),
                  ],
                ),
              ),
            MacSection(context.tr('Start a Timer')),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final minutes in _minutes)
                    chip(
                      context.tr('{}m', minutes),
                      () => islandTimer.start(Duration(minutes: minutes), now),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
