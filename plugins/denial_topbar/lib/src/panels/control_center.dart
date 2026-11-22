import 'package:denial_flutter_sdk/models.dart';
import 'package:denial_flutter_sdk/services.dart';
import 'package:denial_flutter_sdk/settings.dart';
import 'package:denial_flutter_sdk/state.dart';
import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bar_icons.dart';
import '../bar_tokens.dart';
import '../bar_type.dart';
import '../cc_layout.dart';
import '../island.dart' show IslandExpandedBody, IslandMode;
import '../media_art.dart';
import 'network_panels.dart';

/// Control Centre.
///
/// Transcribes shell27 `MacBar.qml`'s Control Centre: a 300 pt slab at
/// `screen - 300 - 10`, `barH + 6`, holding a four-column bento grid of 66 pt
/// cells — 6 pt between columns, 12 between rows, 16 around a slider row.
/// Tiles are radius 34 (the two sliders 26) and a one-cell control is a 63 pt
/// circle centred in its cell. The panel itself is the frosted slab
/// (`ccStyle: "macos"`), so each tile only keeps a faint shape on top of it
/// instead of its own blur.
class ControlCenterPanel extends ConsumerStatefulWidget {
  const ControlCenterPanel({
    required this.services,
    required this.monitorId,
    required this.output,
    required this.onOpenSettings,
    required this.onOpenNotifications,
    required this.onOpenIsland,
    required this.onOpenDisplaySettings,
    required this.onOpenNowPlaying,
    super.key,
  });

  final ShellServices services;
  final int monitorId;
  final DisplayOutput output;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenNotifications;
  final VoidCallback onOpenIsland;
  final VoidCallback onOpenDisplaySettings;

  /// Opens the Now Playing card. shell27's media tile is not clickable; macOS
  /// opens the full card from it, so the tile's body does that here.
  final VoidCallback onOpenNowPlaying;

  @override
  ConsumerState<ControlCenterPanel> createState() => _ControlCenterPanelState();
}

class _ControlCenterPanelState extends ConsumerState<ControlCenterPanel> {
  /// shell27's `ui.ccPage`: an empty string is the grid, `wifi` and `bt` are the
  /// list pages the Wi-Fi and Bluetooth chevrons open inside the panel.
  String _page = '';

  ShellServices get services => widget.services;
  DisplayOutput get output => widget.output;
  VoidCallback get onOpenSettings => widget.onOpenSettings;
  VoidCallback get onOpenNotifications => widget.onOpenNotifications;
  VoidCallback get onOpenIsland => widget.onOpenIsland;
  VoidCallback get onOpenDisplaySettings => widget.onOpenDisplaySettings;
  VoidCallback get onOpenNowPlaying => widget.onOpenNowPlaying;

  /// shell27's `ccCatalog` restricted to what Denial can actually drive.
  ///
  /// The sizes are the reference's: Wi-Fi, Bluetooth and Focus are two cells
  /// wide, Now Playing is 2×2, the one-cell switches are circles, and Display
  /// and Sound are full-width sliders. A control Denial cannot act on is left
  /// out rather than drawn dead.
  static const List<CcControl> _controls = <CcControl>[
    CcControl(id: 'wifi', columns: 2),
    CcControl(id: 'nowplaying', columns: 2, rows: 2),
    CcControl(id: 'bluetooth', columns: 2),
    CcControl(id: 'focus', columns: 2),
    CcControl(id: 'darkmode'),
    CcControl(id: 'notifications'),
    CcControl(id: 'island'),
    CcControl(id: 'settings'),
    CcControl(id: 'display', columns: 4),
    CcControl(id: 'sound', columns: 4),
  ];

  static const Set<String> _sliders = <String>{'display', 'sound'};

  @override
  Widget build(BuildContext context) {
    final network = ref.watch(networkConnectivityProvider);
    final wifi = ref.watch(services.connectedWifi);
    final bluetooth = ref.watch(bluetoothProvider);
    final brightness = ref.watch(displayBrightnessProvider);
    final level = brightness.levels[output.monitorId] ?? 1;
    final volume = ref.watch(services.volume);
    final unread = ref.watch(
      desktopNotificationsProvider.select((state) => state.unreadCount),
    );
    final focus = ref.watch(
      desktopNotificationsProvider.select((state) => state.doNotDisturb),
    );
    final appearance = ref.watch(
      shellSettingsProvider.select(
        (settings) => settings.appearance.colorSchemePreference,
      ),
    );
    final playing = ref.watch(
      services.media.select((media) => media.value?.playing ?? false),
    );

    final plan = ccLayout(
      _controls,
      cellHeight: BarTokens.ccCellHeight,
      gap: BarTokens.ccGap,
      rowGap: BarTokens.ccRowGap,
      sliderGap: BarTokens.ccSliderGap,
      sliderIds: _sliders,
    );
    final gridWidth = BarTokens.controlCenterWidth - BarTokens.controlCenterMargin * 2;
    final cellWidth =
        (gridWidth - (4 - 1) * BarTokens.ccGap) / 4;

    if (_page.isNotEmpty) {
      return SizedBox(
        width: BarTokens.controlCenterWidth,
        child: Padding(
          padding: const EdgeInsets.all(BarTokens.controlCenterMargin),
          child: _page == 'wifi'
              ? WifiContent(
                  showBack: true,
                  onBack: () => setState(() => _page = ''),
                  onOpenSettings: onOpenSettings,
                )
              : BluetoothContent(
                  showBack: true,
                  onBack: () => setState(() => _page = ''),
                  onOpenSettings: onOpenSettings,
                ),
        ),
      );
    }

    return SizedBox(
      width: BarTokens.controlCenterWidth,
      child: Padding(
        padding: const EdgeInsets.all(BarTokens.controlCenterMargin),
        child: SizedBox(
          height: plan.total,
          child: Stack(
            children: <Widget>[
              for (final slot in plan.items)
                Positioned(
                  left: slot.x(cellWidth, BarTokens.ccGap),
                  top: slot.y,
                  width: slot.width(cellWidth, BarTokens.ccGap),
                  height: slot.height,
                  child: _tile(
                    context,
                    slot,
                    network: network,
                    ssid: wifi?.ssid,
                    bluetooth: bluetooth,
                    brightness: level,
                    volume: volume,
                    unread: unread,
                    focus: focus,
                    dark: appearance == DesktopColorSchemePreference.preferDark,
                    playing: playing,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tile(
    BuildContext context,
    CcSlot slot, {
    required NetworkConnectivityState network,
    required String? ssid,
    required BluetoothState bluetooth,
    required double brightness,
    required double volume,
    required int unread,
    required bool focus,
    required bool dark,
    required bool playing,
  }) {
    final small = slot.columns == 1 && slot.rows == 1;
    final wifiOn = network.snapshot.wirelessEnabled;
    final btOn = bluetooth.available && bluetooth.powered;

    switch (slot.id) {
      case 'wifi':
        return _CcTile(
          on: wifiOn,
          onTap: () => ref
              .read(networkConnectivityProvider.notifier)
              .setWirelessEnabled(!wifiOn),
          leading: _CcIcon(
            icon: wifiOn ? BarIcons.wifi : BarIcons.wifiSlash,
            on: wifiOn,
          ),
          title: services.strings(context).wifiTitle,
          detail: !wifiOn
              ? 'Off'
              : ssid ?? services.strings(context).notConnected,
          trailing: _CcChevron(onTap: () => setState(() => _page = 'wifi')),
        );
      case 'bluetooth':
        return _CcTile(
          on: btOn,
          onTap: () => ref.read(bluetoothProvider.notifier).togglePower(),
          leading: _CcIcon(icon: BarIcons.bluetooth, on: btOn),
          title: 'Bluetooth',
          detail: !bluetooth.available
              ? 'Unavailable'
              : btOn
              ? 'On'
              : 'Off',
          trailing: _CcChevron(onTap: () => setState(() => _page = 'bt')),
        );
      case 'focus':
        return _CcTile(
          on: focus,
          onTap: () => ref
              .read(desktopNotificationsProvider.notifier)
              .toggleDoNotDisturb(),
          leading: _CcIcon(
            icon: focus ? BarIcons.moonFill : BarIcons.moon,
            on: focus,
          ),
          title: 'Focus',
          detail: focus ? 'On' : 'Off',
        );
      case 'darkmode':
        return _CcTile(
          on: dark,
          onTap: () => ref
              .read(shellSettingsProvider.notifier)
              .setColorSchemePreference(
                dark
                    ? DesktopColorSchemePreference.preferLight
                    : DesktopColorSchemePreference.preferDark,
              ),
          // shell27 draws a `contrast` mark; the vendored font has no
          // half-filled circle, so the moon carries the same meaning.
          leading: _CcIcon(
            icon: dark ? BarIcons.moonFill : BarIcons.moon,
            on: dark,
            small: small,
          ),
        );
      case 'notifications':
        return _CcTile(
          on: unread > 0,
          onTap: onOpenNotifications,
          leading: _CcIcon(
            icon: unread > 0 ? BarIcons.bellFill : BarIcons.bell,
            on: unread > 0,
            small: small,
          ),
        );
      case 'island':
        // shell27 has no island tile; this one stands in for Stage Manager's
        // slot and opens the pill's own card.
        return _CcTile(
          on: playing,
          onTap: onOpenIsland,
          leading: _CcIcon(
            icon: playing ? BarIcons.playFill : BarIcons.play,
            on: playing,
            small: small,
          ),
        );
      case 'settings':
        return _CcTile(
          on: false,
          onTap: onOpenSettings,
          leading: _CcIcon(icon: BarIcons.gear, on: false, small: small),
        );
      case 'nowplaying':
        return _CcMediaTile(services: services, onOpen: onOpenNowPlaying);
      case 'display':
        return _CcSliderTile(
          label: 'Display',
          value: brightness,
          left: BarIcons.sunMax,
          right: BarIcons.sunMaxFill,
          onChangeStart: () {},
          onChanged: (value) => ref
              .read(displayBrightnessProvider.notifier)
              .setLevel(output, value),
          onChangeEnd: (value) => ref
              .read(displayBrightnessProvider.notifier)
              .commitLevel(output, value),
        );
      case 'sound':
        return _CcSliderTile(
          label: 'Sound',
          value: volume,
          left: BarIcons.volumeUp,
          right: BarIcons.volumeUp,
          onChangeStart: services.beginVolumeInteraction,
          onChanged: services.setVolume,
          onChangeEnd: services.commitVolume,
          // shell27 puts a 28 pt speaker button at the tile's right edge that
          // mutes; the SDK has no mute call, so it drops the level to zero.
          trailing: _CcMuteButton(
            muted: volume <= 0.001,
            onTap: () {
              services.beginVolumeInteraction();
              services.setVolume(volume <= 0.001 ? 0.5 : 0);
              services.commitVolume(volume <= 0.001 ? 0.5 : 0);
            },
          ),
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

/// The tile shell: `CCTile`'s faint glass shape, the hover wash, and the
/// whole-tile white fill that a one-cell switch gets while it is on.
class _CcTile extends StatefulWidget {
  const _CcTile({
    required this.on,
    this.leading,
    this.title,
    this.detail,
    this.trailing,
    this.onTap,
    this.radius = BarTokens.ccTileRadius,
    this.wholeWidthLimit = 110,
    this.child,
  });

  final bool on;
  final Widget? leading;
  final String? title;
  final String? detail;
  final Widget? trailing;
  final VoidCallback? onTap;
  final double radius;

  /// shell27 turns the whole tile white only for tiles up to 110 pt wide, so a
  /// wide tile keeps its glass and its text colours.
  final double wholeWidthLimit;
  final Widget? child;

  @override
  State<_CcTile> createState() => _CcTileState();
}

class _CcTileState extends State<_CcTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final dark = theme.colors.brightness == Brightness.dark;
    final shape = BorderRadius.circular(widget.radius);
    return LayoutBuilder(
      builder: (context, constraints) {
        final whole = widget.on && constraints.maxWidth <= widget.wholeWidthLimit;
        final ink = whole ? const Color(0xff121216) : theme.colors.textPrimary;
        final dim = whole
            ? const Color(0xff121216).withValues(alpha: 0.55)
            : theme.colors.textSecondary;
        Widget body = DecoratedBox(
          decoration: BoxDecoration(
            color: (dark ? const Color(0xffffffff) : const Color(0xffffffff))
                .withValues(alpha: whole ? 1 : (dark ? 0.10 : 0.42)),
            borderRadius: shape,
            border: Border.all(
              color: const Color(0xffffffff).withValues(
                alpha: whole ? 0 : (dark ? 0.16 : 0.70),
              ),
              width: 0.8,
            ),
          ),
          child: Stack(
            children: <Widget>[
              if (widget.on && !whole)
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xffffffff).withValues(
                        alpha: dark ? 0.0 : 0.0,
                      ),
                      borderRadius: shape,
                    ),
                  ),
                ),
              Positioned.fill(
                child: AnimatedContainer(
                  duration: Motion.cardSettle,
                  curve: Curves.easeOut,
                  decoration: BoxDecoration(
                    color: _hovered && widget.onTap != null
                        ? (dark
                              ? const Color(0xffffffff).withValues(alpha: 0.025)
                              : const Color(0xffffffff).withValues(alpha: 0.07))
                        : const Color(0x00000000),
                    borderRadius: shape,
                  ),
                ),
              ),
              if (widget.child != null)
                Positioned.fill(child: widget.child!)
              else
                _tileBody(ink, dim),
            ],
          ),
        );
        if (widget.onTap != null) {
          body = GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              onEnter: (_) => setState(() => _hovered = true),
              onExit: (_) => setState(() => _hovered = false),
              child: body,
            ),
          );
        }
        return body;
      },
    );
  }

  Widget _tileBody(Color ink, Color dim) {
    final wide = widget.title != null;
    if (!wide) {
      return Center(child: widget.leading ?? const SizedBox.shrink());
    }
    return Stack(
      children: <Widget>[
        Positioned(
          left: 12,
          top: 0,
          bottom: 0,
          child: Center(child: widget.leading ?? const SizedBox.shrink()),
        ),
        Positioned(
          left: 62,
          right: widget.trailing == null ? 24 : 62,
          top: 0,
          bottom: 0,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                widget.title!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: BarType.title.copyWith(color: ink),
              ),
              const SizedBox(height: 1),
              Text(
                widget.detail ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: BarType.section.copyWith(color: dim),
              ),
            ],
          ),
        ),
        if (widget.trailing != null)
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: widget.trailing!,
          ),
      ],
    );
  }
}

/// The round control inside a tile (`CCBtn` with `plain: true`).
///
/// A wide tile gets a 40 pt disc at `x: 12` with a grey fill while off; a
/// one-cell tile drops the disc and draws a 21 pt glyph centred in its cell.
class _CcIcon extends StatelessWidget {
  const _CcIcon({required this.icon, required this.on, this.small = false});

  final IconData icon;
  final bool on;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final dark = theme.colors.brightness == Brightness.dark;
    final accent = theme.accent;
    if (small) {
      return BarGlyph(
        icon,
        size: BarTokens.ccSmallGlyph,
        color: on ? accent : theme.colors.textPrimary,
      );
    }
    return Container(
      width: BarTokens.ccButtonSize,
      height: BarTokens.ccButtonSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: on
            ? const Color(0xffffffff)
            : (dark
                  ? const Color(0xffffffff).withValues(alpha: 0.16)
                  : const Color(0xff000000).withValues(alpha: 0.14)),
      ),
      child: BarGlyph(
        icon,
        size: BarTokens.ccButtonSize * BarTokens.ccGlyphRatio,
        color: on ? accent : theme.colors.textPrimary,
      ),
    );
  }
}

/// The arrow end of a wide tile, which opens the detail page instead of
/// toggling the radio.
class _CcChevron extends StatelessWidget {
  const _CcChevron({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: SizedBox(
          width: 48,
          child: Center(
            child: BarGlyph(
              BarIcons.chevronRight,
              size: 15,
              color: theme.colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Now Playing: `cNowPlaying`'s 45 pt cover at `x: 15; y: 12`, the title block
/// at `y: 72`, and a transport row 38 from the bottom.
class _CcMediaTile extends ConsumerWidget {
  const _CcMediaTile({required this.services, required this.onOpen});

  final ShellServices services;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.shellTheme;
    final playback = ref.watch(services.media).value;
    final commands = ref.watch(services.mediaCommands);
    final available = playback?.available ?? false;
    return _CcTile(
      on: false,
      radius: BarTokens.ccTileRadius,
      wholeWidthLimit: 0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onOpen,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(15, 12, 15, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    MediaArtwork(
                      url: playback?.artUrl ?? '',
                      size: 45,
                      radius: 10,
                      fallback: Container(
                        width: 45,
                        height: 45,
                        decoration: BoxDecoration(
                          color: theme.colors.textPrimary.withValues(
                            alpha: 0.10,
                          ),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: theme.colors.textPrimary.withValues(
                              alpha: 0.10,
                            ),
                            width: 1,
                          ),
                        ),
                        child: BarGlyph(
                          BarIcons.playFill,
                          size: 22,
                          color: theme.colors.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            playback?.title.isNotEmpty == true
                                ? playback!.title
                                : services.strings(context).mediaNowPlaying,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: BarType.title.copyWith(
                              color: playback == null
                                  ? theme.colors.textSecondary
                                  : theme.colors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          if (playback != null &&
                              playback.artistLabel.isNotEmpty)
                            Text(
                              playback.artistLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: BarType.section.copyWith(
                                color: theme.colors.textSecondary,
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
          const Spacer(),
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                _CcTransport(
                  icon: BarIcons.backward,
                  enabled: playback?.canGoPrevious ?? false,
                  onTap: commands.previous,
                ),
                const SizedBox(width: 14),
                _CcTransport(
                  icon: playback?.playing == true
                      ? BarIcons.pauseFill
                      : BarIcons.playFill,
                  enabled: available,
                  onTap: commands.playPause,
                  size: 26,
                ),
                const SizedBox(width: 14),
                _CcTransport(
                  icon: BarIcons.forward,
                  enabled: playback?.canGoNext ?? false,
                  onTap: commands.next,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CcTransport extends StatelessWidget {
  const _CcTransport({
    required this.icon,
    required this.enabled,
    required this.onTap,
    this.size = 22,
  });

  final IconData icon;
  final bool enabled;
  final Future<void> Function() onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? () => onTap() : null,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        child: SizedBox(
          width: 32,
          height: 30,
          child: Center(
            child: BarGlyph(
              icon,
              size: size,
              color: enabled
                  ? theme.colors.textPrimary
                  : theme.colors.textTertiary.withValues(alpha: 0.45),
            ),
          ),
        ),
      ),
    );
  }
}

/// A full-width slider tile: `cDisplay` / `cSound` — a 12 pt DemiBold label at
/// `x: 15; y: 15` and a `CCSlider` at `x: 12; y: 28`.
class _CcSliderTile extends StatelessWidget {
  const _CcSliderTile({
    required this.label,
    required this.value,
    required this.left,
    required this.right,
    required this.onChangeStart,
    required this.onChanged,
    required this.onChangeEnd,
    this.trailing,
  });

  final String label;
  final double value;
  final IconData left;
  final IconData right;
  final VoidCallback onChangeStart;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  /// shell27's `cSound` ends the slider 36 pt early for a 28 pt button.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    return _CcTile(
      on: false,
      radius: BarTokens.ccSliderTileRadius,
      wholeWidthLimit: 0,
      child: Stack(
        children: <Widget>[
          Positioned(
            left: 15,
            top: 15,
            child: Text(
              label,
              style: BarType.section.copyWith(color: theme.colors.textPrimary),
            ),
          ),
          Positioned(
            left: 12,
            right: trailing == null ? 12 : 12 + 36,
            top: BarTokens.ccSliderTop,
            height: 28,
            child: _CcSlider(
              value: value,
              left: left,
              right: right,
              onChangeStart: onChangeStart,
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            ),
          ),
          if (trailing != null)
            Positioned(
              right: 12,
              top: BarTokens.ccSliderTop,
              width: 28,
              height: 28,
              child: trailing!,
            ),
        ],
      ),
    );
  }
}

/// shell27's `cSound` mute button: a 28 pt circle that fills with the accent
/// while the output is muted.
class _CcMuteButton extends StatelessWidget {
  const _CcMuteButton({required this.muted, required this.onTap});

  final bool muted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: muted
                ? theme.accent
                : theme.colors.textPrimary.withValues(alpha: 0.10),
          ),
          child: Center(
            child: BarGlyph(
              muted ? BarIcons.volumeMute : BarIcons.volumeUp,
              size: 15,
              color: muted
                  ? const Color(0xffffffff)
                  : theme.colors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

/// `CCSlider`: a 16 pt glyph at `x: 4`, the track at `x: 28` and
/// `width - 28 - 26` wide, a 4 pt bar with a 2 pt radius, and a 21 × 14 knob
/// that only appears while the tile is hovered.
class _CcSlider extends StatefulWidget {
  const _CcSlider({
    required this.value,
    required this.left,
    required this.right,
    required this.onChangeStart,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final double value;
  final IconData left;
  final IconData right;
  final VoidCallback onChangeStart;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  State<_CcSlider> createState() => _CcSliderState();
}

class _CcSliderState extends State<_CcSlider> {
  bool _hovered = false;
  bool _dragging = false;
  double? _pending;

  double get _value => (_pending ?? widget.value).clamp(0.0, 1.0).toDouble();

  void _update(Offset position, double width) {
    if (width <= 0) return;
    final next = (position.dx / width).clamp(0.0, 1.0).toDouble();
    if (_pending == null) widget.onChangeStart();
    setState(() => _pending = next);
    widget.onChanged(next);
  }

  void _end() {
    final value = _pending;
    setState(() {
      _pending = null;
      _dragging = false;
    });
    if (value != null) widget.onChangeEnd(value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final ink = theme.colors.textPrimary;
    final active = _hovered || _dragging;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final trackX = BarTokens.ccSliderTrackX;
        final trackW = (width - trackX - BarTokens.ccSliderTrackW).clamp(
          1.0,
          width,
        );
        final knobLeft =
            trackX + _value * trackW - BarTokens.ccSliderKnobWidth / 2;
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) {
              widget.onChangeStart();
              _update(
                Offset(details.localPosition.dx - trackX, 0),
                trackW,
              );
            },
            onTapUp: (_) => _end(),
            onHorizontalDragStart: (details) {
              setState(() => _dragging = true);
              widget.onChangeStart();
              _update(
                Offset(details.localPosition.dx - trackX, 0),
                trackW,
              );
            },
            onHorizontalDragUpdate: (details) => _update(
              Offset(details.localPosition.dx - trackX, 0),
              trackW,
            ),
            onHorizontalDragEnd: (_) => _end(),
            onHorizontalDragCancel: _end,
            child: Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                Positioned(
                  left: 4,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: BarGlyph(widget.left, size: 16, color: ink),
                  ),
                ),
                Positioned(
                  left: trackX,
                  width: trackW,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: Container(
                      height: BarTokens.ccSliderTrackHeight,
                      decoration: BoxDecoration(
                        color: ink.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: trackX,
                  width: trackW * _value,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: Container(
                      height: BarTokens.ccSliderTrackHeight,
                      decoration: BoxDecoration(
                        color: ink,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: width - 20,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: BarGlyph(
                      widget.right,
                      size: 16,
                      color: theme.colors.textSecondary,
                    ),
                  ),
                ),
                Positioned(
                  left: knobLeft,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: AnimatedOpacity(
                      duration: Motion.pill,
                      opacity: active ? 1 : 0,
                      child: AnimatedContainer(
                        duration: Motion.pill,
                        curve: Curves.easeOut,
                        width: _dragging
                            ? BarTokens.ccSliderKnobWidth + 6
                            : BarTokens.ccSliderKnobWidth,
                        height: _dragging
                            ? BarTokens.ccSliderKnobHeight + 3
                            : BarTokens.ccSliderKnobHeight,
                        decoration: BoxDecoration(
                          color: ink,
                          borderRadius: BorderRadius.circular(
                            _dragging ? 11 : 8,
                          ),
                          boxShadow: <BoxShadow>[
                            BoxShadow(
                              color: const Color(0xff000000).withValues(
                                alpha: 0.28,
                              ),
                              blurRadius: 6,
                              offset: const Offset(0, 1),
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
      },
    );
  }
}

/// The island's expanded card, shown from Control Centre and from the pill.
class IslandPanel extends ConsumerWidget {
  const IslandPanel({
    required this.mode,
    required this.services,
    required this.notification,
    required this.onDismiss,
    this.chargePercent,
    super.key,
  });

  final IslandMode mode;
  final ShellServices services;
  final DesktopNotification? notification;
  final VoidCallback onDismiss;
  final int? chargePercent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playback = ref.watch(services.media).value;
    return IslandExpandedBody(
      mode: mode,
      notification: notification,
      playback: playback,
      artworkUrl: playback?.artUrl ?? '',
      commands: ref.watch(services.mediaCommands),
      onDismissNotice: onDismiss,
      onActivateNotice: onDismiss,
      chargePercent: chargePercent,
    );
  }
}
