import 'package:denial_flutter_sdk/models.dart';
import 'package:denial_flutter_sdk/services.dart';
import 'package:denial_flutter_sdk/settings.dart';
import 'package:denial_flutter_sdk/state.dart';
import 'package:denial_flutter_sdk/system_services.dart' show WifiNetwork;
import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bar_icons.dart';
import '../bar_tokens.dart';
import '../bar_type.dart';
import '../island.dart' show IslandExpandedBody, IslandMode;
import '../media_art.dart';
import 'cc_card.dart';
import 'network_panels.dart';

/// Control Centre.
///
/// Ports NextKDE `ControlCenterPanel.qml`: a `max(296, min(336, screenW - 24))`
/// slab with 20 pt of inset, holding a fixed card grid — the Wi-Fi and
/// Bluetooth pills down the left, the media card beside them, five 52 pt
/// squares under that, and the brightness and sound sliders across the bottom.
/// Each card is a `CcCard`, which carries the reference's fill, rim, hover wash
/// and press scale.
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
    required this.onJoinNetwork,
    super.key,
  });

  final ShellServices services;
  final int monitorId;
  final DisplayOutput output;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenNotifications;
  final VoidCallback onOpenIsland;
  final VoidCallback onOpenDisplaySettings;

  /// Opens the Wi-Fi join dialog for a secured network with no saved profile.
  final ValueChanged<WifiNetwork> onJoinNetwork;

  /// Opens the Now Playing card. shell27's media tile is not clickable; macOS
  /// opens the full card from it, so the tile's body does that here.
  final VoidCallback onOpenNowPlaying;

  @override
  ConsumerState<ControlCenterPanel> createState() => _ControlCenterPanelState();
}

class _ControlCenterPanelState extends ConsumerState<ControlCenterPanel> {
  /// The open sub-page: `''` is the grid, then `wifi`, `bt`, `display` or
  /// `sound`. NextKDE keeps one `activeSubmenu` string for the same reason.
  String _page = '';

  ShellServices get services => widget.services;
  DisplayOutput get output => widget.output;
  VoidCallback get onOpenSettings => widget.onOpenSettings;
  VoidCallback get onOpenNotifications => widget.onOpenNotifications;
  VoidCallback get onOpenIsland => widget.onOpenIsland;
  VoidCallback get onOpenDisplaySettings => widget.onOpenDisplaySettings;
  VoidCallback get onOpenNowPlaying => widget.onOpenNowPlaying;

  @override
  Widget build(BuildContext context) {
    final width = BarTokens.controlCenterWidthFor(
      MediaQuery.sizeOf(context).width,
    );
    if (_page.isNotEmpty) {
      return AnimatedSize(
        duration: Motion.cardSettle,
        curve: Curves.easeOut,
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: width,
          height: _pageHeight,
          child: _submenu(width),
        ),
      );
    }
    return SizedBox(
      width: width,
      height: BarTokens.ccPanelHeight,
      child: _grid(width),
    );
  }

  /// NextKDE gives each sub-page card a fixed height (Wi-Fi 360, Bluetooth 340,
  /// brightness 280, sound 420); the 20 pt inset this panel draws around it is
  /// added on top so the card itself keeps the reference's size.
  double get _pageHeight =>
      switch (_page) {
        'wifi' => BarTokens.ccWifiPageHeight,
        'bt' => BarTokens.ccBluetoothPageHeight,
        'display' => BarTokens.ccBrightnessPageHeight,
        'sound' => BarTokens.ccSoundPageHeight,
        _ => BarTokens.ccPanelHeight - BarTokens.controlCenterMargin,
      } +
      BarTokens.controlCenterMargin * 2;

  Widget _submenu(double width) {
    final network = ref.watch(networkConnectivityProvider);
    final bluetooth = ref.watch(bluetoothProvider);
    final (title, toggle) = switch (_page) {
      'wifi' => (
        'Wi‑Fi',
        CcSwitch(
          value: network.snapshot.wirelessEnabled,
          busy: network.radioChanging,
          onChanged: () => ref
              .read(networkConnectivityProvider.notifier)
              .setWirelessEnabled(!network.snapshot.wirelessEnabled),
        ),
      ),
      'bt' => (
        'Bluetooth',
        CcSwitch(
          value: bluetooth.available && bluetooth.powered,
          busy: bluetooth.powerChanging,
          onChanged: bluetooth.available
              ? () => ref.read(bluetoothProvider.notifier).togglePower()
              : null,
        ),
      ),
      'display' => ('Display Brightness', null),
      'sound' => ('Sound', null),
      _ => ('', null),
    };

    return Padding(
      padding: const EdgeInsets.all(BarTokens.controlCenterMargin),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          CcSubmenuHeader(
            title: title,
            onBack: () => setState(() => _page = ''),
            trailing: toggle,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: switch (_page) {
                'wifi' => WifiContent(
                  onOpenSettings: onOpenSettings,
                  onJoinNetwork: widget.onJoinNetwork,
                  onClose: () => setState(() => _page = ''),
                ),
                'bt' => BluetoothContent(
                  onOpenSettings: onOpenSettings,
                  onClose: () => setState(() => _page = ''),
                ),
                'display' => _BrightnessPage(
                  monitorId: widget.monitorId,
                  output: output,
                  onOpenSettings: onOpenDisplaySettings,
                  onClose: () => setState(() => _page = ''),
                ),
                'sound' => _SoundPage(
                  services: services,
                  onOpenSettings: onOpenSettings,
                  onClose: () => setState(() => _page = ''),
                ),
                _ => const SizedBox.shrink(),
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _grid(double width) {
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
    final dark = ref.watch(
      shellSettingsProvider.select(
        (state) =>
            state.appearance.colorSchemePreference ==
            DesktopColorSchemePreference.preferDark,
      ),
    );
    final playing = ref.watch(
      services.media.select((media) => media.value?.playing ?? false),
    );

    // The grid is authored against a 296 pt content width; a narrower screen
    // shrinks every card by the same factor so the layout never reflows.
    final content = width - BarTokens.controlCenterMargin * 2;
    final scale = content / BarTokens.ccContentWidth;
    final pill = BarTokens.ccConnectivityWidth * scale;
    final media = content - pill - 8;
    final square = (content - 36) / 5;
    final wifiOn = network.snapshot.wirelessEnabled;
    final btOn = bluetooth.available && bluetooth.powered;
    final strings = services.strings(context);

    Widget at(double left, double top, double w, double h, Widget child) =>
        Positioned(left: left, top: top, width: w, height: h, child: child);

    return Padding(
      padding: const EdgeInsets.all(BarTokens.controlCenterMargin),
      child: Stack(
        children: <Widget>[
          at(
            0,
            0,
            pill,
            BarTokens.ccPillHeight,
            _CcPill(
              icon: wifiOn ? BarIcons.wifi : BarIcons.wifiSlash,
              on: wifiOn,
              busy: network.radioChanging,
              title: strings.wifiTitle,
              detail: !wifiOn
                  ? 'Off'
                  : (wifi?.ssid ?? strings.notConnected),
              onToggle: () => ref
                  .read(networkConnectivityProvider.notifier)
                  .setWirelessEnabled(!wifiOn),
              onOpen: () => setState(() => _page = 'wifi'),
            ),
          ),
          at(
            0,
            BarTokens.ccPillSecondTop - BarTokens.ccPillTop,
            pill,
            BarTokens.ccPillHeight,
            _CcPill(
              icon: BarIcons.bluetooth,
              on: btOn,
              busy: bluetooth.powerChanging,
              title: 'Bluetooth',
              detail: !bluetooth.available
                  ? 'Unavailable'
                  : btOn
                  ? 'On'
                  : 'Off',
              onToggle: bluetooth.available
                  ? () => ref.read(bluetoothProvider.notifier).togglePower()
                  : null,
              onOpen: () => setState(() => _page = 'bt'),
            ),
          ),
          at(
            pill + 8,
            0,
            media,
            BarTokens.ccMediaHeight,
            _CcMediaCard(services: services, onOpen: onOpenNowPlaying),
          ),
          for (var index = 0; index < 5; index++)
            at(
              index * (square + BarTokens.ccSquareGap),
              BarTokens.ccSquareTop - BarTokens.ccPillTop,
              square,
              square,
              _square(index, square, unread: unread, focus: focus, dark: dark, playing: playing),
            ),
          at(
            0,
            BarTokens.ccBrightnessTop - BarTokens.ccPillTop,
            content,
            BarTokens.ccSliderHeight,
            _CcSliderCard(
              label: 'Display',
              percent: (level * 100).round(),
              value: level,
              icon: BarIcons.sunMax,
              trackLeft: BarTokens.ccBrightnessTrackLeft,
              trackRight: BarTokens.ccBrightnessTrackRight,
              iconBottom: 12,
              iconSize: 13,
              onOpen: () => setState(() => _page = 'display'),
              onChanged: (value) => ref
                  .read(displayBrightnessProvider.notifier)
                  .setLevel(output, value),
              onChangeEnd: (value) => ref
                  .read(displayBrightnessProvider.notifier)
                  .commitLevel(output, value),
            ),
          ),
          at(
            0,
            BarTokens.ccSoundTop - BarTokens.ccPillTop,
            content,
            BarTokens.ccSliderHeight,
            _CcSliderCard(
              label: 'Sound',
              percent: (volume * 100).round(),
              value: volume,
              icon: volume <= 0.001 ? BarIcons.volumeMute : BarIcons.volumeUp,
              trackLeft: BarTokens.ccSoundTrackLeft,
              trackRight: BarTokens.ccSoundTrackRight,
              iconBottom: 15,
              iconSize: 16,
              onOpen: () => setState(() => _page = 'sound'),
              onChangeStart: services.beginVolumeInteraction,
              onChanged: services.setVolume,
              onChangeEnd: services.commitVolume,
            ),
          ),
        ],
      ),
    );
  }

  Widget _square(
    int index,
    double size, {
    required int unread,
    required bool focus,
    required bool dark,
    required bool playing,
  }) {
    final blue = ccBlue.withValues(alpha: 0.28);
    return switch (index) {
      0 => _CcSquare(
        icon: focus ? BarIcons.moonFill : BarIcons.moon,
        active: focus,
        activeFill: blue,
        activeInk: ccBlue,
        onTap: () => ref
            .read(desktopNotificationsProvider.notifier)
            .toggleDoNotDisturb(),
      ),
      1 => _CcSquare(
        icon: dark ? BarIcons.moonFill : BarIcons.sunMax,
        active: dark,
        activeFill: const Color(0xffffffff),
        activeInk: const Color(0xff000000),
        onTap: () => ref
            .read(shellSettingsProvider.notifier)
            .setColorSchemePreference(
              dark
                  ? DesktopColorSchemePreference.preferLight
                  : DesktopColorSchemePreference.preferDark,
            ),
      ),
      2 => _CcSquare(
        icon: unread > 0 ? BarIcons.bellFill : BarIcons.bell,
        active: unread > 0,
        activeFill: blue,
        activeInk: ccBlue,
        onTap: onOpenNotifications,
      ),
      3 => _CcSquare(
        icon: playing ? BarIcons.playFill : BarIcons.play,
        active: false,
        onTap: onOpenIsland,
      ),
      _ => _CcSquare(
        icon: BarIcons.gear,
        active: false,
        onTap: onOpenSettings,
      ),
    };
  }
}

/// A connectivity pill: a 39 pt disc that toggles the radio, the title and its
/// state beside it, and a chevron that opens the sub-page.
///
/// NextKDE `WifiCard.qml` splits the two targets exactly this way — the disc's
/// own `MouseArea` sets the radio, the rest of the pill opens the page.
class _CcPill extends StatelessWidget {
  const _CcPill({
    required this.icon,
    required this.on,
    required this.busy,
    required this.title,
    required this.detail,
    required this.onToggle,
    required this.onOpen,
  });

  final IconData icon;
  final bool on;
  final bool busy;
  final String title;
  final String detail;
  final VoidCallback? onToggle;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    return CcCard(
      radius: BarTokens.ccPillRadius,
      onTap: onOpen,
      child: Stack(
        children: <Widget>[
          Positioned(
            left: BarTokens.ccDiscInset,
            top: 0,
            bottom: 0,
            child: Center(
              child: _CcDisc(
                icon: icon,
                on: on,
                busy: busy,
                onTap: onToggle,
              ),
            ),
          ),
          Positioned(
            left: BarTokens.ccPillTextLeft,
            right: BarTokens.ccPillTextRight,
            top: 0,
            bottom: 0,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: BarType.caption.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: theme.colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: BarType.caption.copyWith(
                    fontSize: 10,
                    color: theme.colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            right: BarTokens.ccChevronInset,
            top: 0,
            bottom: 0,
            child: Center(
              child: Opacity(
                opacity: 0.6,
                child: BarGlyph(
                  BarIcons.chevronRight,
                  size: BarTokens.ccChevronSize,
                  color: theme.colors.textSecondary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The 39 pt disc inside a pill. Blue while the radio is on, a faint wash
/// while off, and a 21 pt arc while the toggle is in flight.
class _CcDisc extends StatefulWidget {
  const _CcDisc({
    required this.icon,
    required this.on,
    required this.busy,
    required this.onTap,
  });

  final IconData icon;
  final bool on;
  final bool busy;
  final VoidCallback? onTap;

  @override
  State<_CcDisc> createState() => _CcDiscState();
}

class _CcDiscState extends State<_CcDisc> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final dark = theme.colors.brightness == Brightness.dark;
    final ink = widget.on ? const Color(0xffffffff) : theme.colors.textPrimary;
    final scale = _pressed ? 0.92 : (_hovered ? 1.04 : 1.0);
    return MouseRegion(
      cursor: widget.onTap == null
          ? MouseCursor.defer
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: widget.onTap == null
            ? null
            : (_) => setState(() => _pressed = true),
        onTapUp: widget.onTap == null
            ? null
            : (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.busy ? null : widget.onTap,
        child: AnimatedScale(
          scale: scale,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: AnimatedOpacity(
            duration: Motion.cardSettle,
            opacity: widget.busy ? 0.55 : 1,
            child: AnimatedContainer(
              duration: Motion.cardSettle,
              curve: Curves.easeOut,
              width: BarTokens.ccDisc,
              height: BarTokens.ccDisc,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.on
                    ? ccBlue
                    : Colors.white.withValues(alpha: dark ? 0.22 : 0.05),
              ),
              child: Stack(
                children: <Widget>[
                  Center(
                    child: AnimatedOpacity(
                      duration: Motion.cardSettle,
                      opacity: widget.busy ? 0 : 1,
                      child: BarGlyph(
                        widget.icon,
                        size: BarTokens.ccDiscGlyph,
                        color: ink,
                      ),
                    ),
                  ),
                  if (widget.busy)
                    Center(child: CcBusyArc(color: ink)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A 52 pt square: one 22 pt glyph, a hover wash, and an optional status fill.
class _CcSquare extends StatelessWidget {
  const _CcSquare({
    required this.icon,
    required this.active,
    required this.onTap,
    this.activeFill,
    this.activeInk,
  });

  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  final Color? activeFill;
  final Color? activeInk;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    return CcCard(
      radius: BarTokens.ccSquareRadius,
      onTap: onTap,
      active: active,
      activeFill: active ? activeFill : null,
      child: Center(
        child: BarGlyph(
          icon,
          size: BarTokens.ccSquareGlyph,
          color: active ? (activeInk ?? theme.colors.textPrimary) : theme.colors.textPrimary,
        ),
      ),
    );
  }
}

/// The media card: a 43 pt cover at (13, 13), the title and artist beside it,
/// and the transport row 15 from the bottom.
class _CcMediaCard extends ConsumerWidget {
  const _CcMediaCard({required this.services, required this.onOpen});

  final ShellServices services;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.shellTheme;
    final dark = theme.colors.brightness == Brightness.dark;
    final playback = ref.watch(services.media).value;
    final commands = ref.watch(services.mediaCommands);
    final available = playback?.available ?? false;
    return CcCard(
      radius: BarTokens.ccMediaRadius,
      child: Stack(
        children: <Widget>[
          Positioned(
            left: 13,
            top: 13,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onOpen,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: MediaArtwork(
                  url: playback?.artUrl ?? '',
                  size: 43,
                  radius: 13,
                  fallback: Container(
                    width: 43,
                    height: 43,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: dark ? 0.18 : 0.08),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Center(
                      child: Opacity(
                        opacity: 0.86,
                        child: BarGlyph(
                          BarIcons.playFill,
                          size: 21,
                          color: theme.colors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 64,
            right: 10,
            top: 13,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onOpen,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      playback?.title.isNotEmpty == true
                          ? playback!.title
                          : services.strings(context).mediaNowPlaying,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: BarType.caption.copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: theme.colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      playback != null && playback.artistLabel.isNotEmpty
                          ? playback.artistLabel
                          : services.strings(context).mediaControls,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: BarType.caption.copyWith(
                        fontSize: 10,
                        color: theme.colors.textSecondary.withValues(
                          alpha: 0.70,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 15,
            height: 40,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                _CcTransport(
                  icon: BarIcons.backward,
                  enabled: playback?.canGoPrevious ?? false,
                  onTap: commands.previous,
                ),
                const SizedBox(width: 12),
                _CcTransport(
                  icon: playback?.playing == true
                      ? BarIcons.pauseFill
                      : BarIcons.playFill,
                  enabled: available,
                  onTap: commands.playPause,
                  primary: true,
                ),
                const SizedBox(width: 12),
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
    this.primary = false,
  });

  final IconData icon;
  final bool enabled;
  final Future<void> Function() onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final size = primary ? 40.0 : 32.0;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? () => onTap() : null,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        child: SizedBox(
          width: size,
          height: size,
          child: Center(
            child: BarGlyph(
              icon,
              size: primary ? 24 : 18,
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

/// A slider card: the label and percentage on the top line, the chevron that
/// opens the sub-page, and the track along the bottom.
///
/// NextKDE `BrightnessCard.qml` / `SoundCard.qml`. The track is a 5 pt bar with
/// a filled progress segment and a 30 × 16 thumb that is always visible.
class _CcSliderCard extends StatefulWidget {
  const _CcSliderCard({
    required this.label,
    required this.percent,
    required this.value,
    required this.icon,
    required this.trackLeft,
    required this.trackRight,
    required this.iconBottom,
    required this.iconSize,
    required this.onOpen,
    required this.onChanged,
    required this.onChangeEnd,
    this.onChangeStart,
  });

  final String label;
  final int percent;
  final double value;
  final IconData icon;
  final double trackLeft;
  final double trackRight;
  /// Distance from the card's bottom edge to the glyph's baseline box. The
  /// reference centres the sound glyph on the slider and drops the brightness
  /// one to 12.
  final double iconBottom;
  final double iconSize;
  final VoidCallback onOpen;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;
  final VoidCallback? onChangeStart;

  @override
  State<_CcSliderCard> createState() => _CcSliderCardState();
}

class _CcSliderCardState extends State<_CcSliderCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final dark = theme.colors.brightness == Brightness.dark;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: CcCard(
        radius: BarTokens.ccSliderRadius,
        active: _hovered,
        child: Stack(
          children: <Widget>[
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: 27,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onOpen,
                child: MouseRegion(cursor: SystemMouseCursors.click),
              ),
            ),
            Positioned(
              left: BarTokens.ccSliderLabelLeft,
              top: BarTokens.ccSliderLabelTop,
              child: Text(
                widget.label,
                style: BarType.caption.copyWith(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: theme.colors.textPrimary,
                ),
              ),
            ),
            Positioned(
              right: BarTokens.ccSliderPercentRight,
              top: BarTokens.ccSliderLabelTop,
              child: Text(
                '${widget.percent}%',
                style: BarType.caption.copyWith(
                  fontSize: 9,
                  color: theme.colors.textPrimary.withValues(alpha: 0.50),
                ),
              ),
            ),
            Positioned(
              right: BarTokens.ccSliderChevronRight,
              top: BarTokens.ccSliderChevronTop,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onOpen,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: BarGlyph(
                    BarIcons.chevronRight,
                    size: BarTokens.ccSliderChevronSize,
                    color: theme.colors.textPrimary,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: BarTokens.ccSliderTrackBottom,
              height: BarTokens.ccSliderHeight2,
              child: CcSlider(
                value: widget.value,
                left: widget.trackLeft,
                right: widget.trackRight,
                dark: dark,
                onChangeStart: widget.onChangeStart ?? () {},
                onChanged: widget.onChanged,
                onChangeEnd: widget.onChangeEnd,
              ),
            ),
            Positioned(
              left: 12,
              bottom: widget.iconBottom,
              child: BarGlyph(
                widget.icon,
                size: widget.iconSize,
                color: theme.colors.textPrimary.withValues(alpha: 0.65),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The brightness sub-page: one 82 pt row per display with its own slider.
///
/// NextKDE `BrightnessPage.qml`. Denial exposes a level per monitor, so the
/// row names the output and keeps the reference's 11 pt label, 10 pt value and
/// 9 pt "Built-in display" / "External display" line.
class _BrightnessPage extends ConsumerWidget {
  const _BrightnessPage({
    required this.monitorId,
    required this.output,
    required this.onOpenSettings,
    required this.onClose,
  });

  final int monitorId;
  final DisplayOutput output;
  final VoidCallback onOpenSettings;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.shellTheme;
    final dark = theme.colors.brightness == Brightness.dark;
    final state = ref.watch(displayBrightnessProvider);
    final level = state.levels[output.monitorId] ?? 1;
    final label = output.name;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            children: <Widget>[
              SizedBox(
                height: 82,
                child: Stack(
                  children: <Widget>[
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: BarType.caption.copyWith(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: theme.colors.textPrimary,
                              ),
                            ),
                          ),
                          Text(
                            '${(level * 100).round()}%',
                            style: BarType.caption.copyWith(
                              fontSize: 10,
                              color: theme.colors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      left: 0,
                      top: 20,
                      child: Text(
                        'Display',
                        style: BarType.caption.copyWith(
                          fontSize: 9,
                          color: theme.colors.textSecondary,
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 3,
                      height: BarTokens.ccSliderHeight2,
                      child: CcSlider(
                        value: level,
                        left: 0,
                        right: 0,
                        dark: dark,
                        onChangeStart: () {},
                        onChanged: (value) => ref
                            .read(displayBrightnessProvider.notifier)
                            .setLevel(output, value),
                        onChangeEnd: (value) => ref
                            .read(displayBrightnessProvider.notifier)
                            .commitLevel(output, value),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        CcFooter(
          label: 'Display settings…',
          icon: BarIcons.display,
          onTap: onOpenSettings,
        ),
      ],
    );
  }
}

/// The sound sub-page: master volume, the output devices, then one row per app
/// stream.
///
/// NextKDE `SoundPage.qml`: a 62 pt master section, 30 pt output rows on a
/// radius-8 pill, 58 pt application rows with a 28 pt mute button, and a 38 pt
/// settings footer.
class _SoundPage extends ConsumerWidget {
  const _SoundPage({
    required this.services,
    required this.onOpenSettings,
    required this.onClose,
  });

  final ShellServices services;
  final VoidCallback onOpenSettings;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.shellTheme;
    final dark = theme.colors.brightness == Brightness.dark;
    final outputs = ref.watch(audioDevicesProvider);
    final outputsController = ref.read(audioDevicesProvider.notifier);
    final apps = ref.watch(appAudioProvider);
    final appsController = ref.read(appAudioProvider.notifier);
    final volume = ref.watch(services.volume);
    final muted = volume <= 0.001;

    final sectionStyle = BarType.caption.copyWith(
      fontSize: 10,
      color: theme.colors.textPrimary.withValues(alpha: 0.60),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: SizedBox(
            height: 62,
            child: Stack(
              children: <Widget>[
                Positioned(
                  left: 0,
                  top: 2,
                  child: Text(
                    'Master Volume',
                    style: BarType.caption.copyWith(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: theme.colors.textPrimary,
                    ),
                  ),
                ),
                Positioned(
                  right: 0,
                  top: 2,
                  child: Text(
                    '${(volume * 100).round()}%',
                    style: BarType.caption.copyWith(
                      fontSize: 10,
                      color: theme.colors.textPrimary.withValues(alpha: 0.65),
                    ),
                  ),
                ),
                Positioned(
                  left: 2,
                  bottom: 4 + (28 - 16) / 2,
                  child: BarGlyph(
                    muted ? BarIcons.volumeMute : BarIcons.volumeUp,
                    size: 16,
                    color: theme.colors.textPrimary,
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 4,
                  height: 28,
                  child: CcSlider(
                    value: volume,
                    left: 26,
                    right: 2,
                    dark: dark,
                    height: 28,
                    onChangeStart: services.beginVolumeInteraction,
                    onChanged: services.setVolume,
                    onChangeEnd: services.commitVolume,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('Output devices', style: sectionStyle),
          ),
        ),
        const SizedBox(height: 4),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 3 * 30 + 2 * 3),
          child: ListView.separated(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            itemCount: outputs.devices.length,
            separatorBuilder: (_, _) => const SizedBox(height: 3),
            itemBuilder: (context, index) {
              final device = outputs.devices[index];
              final name = device.description.isEmpty
                  ? device.name
                  : device.description;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => outputsController.select(device.name),
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Container(
                    height: 30,
                    decoration: BoxDecoration(
                      color: device.active
                          ? ccBlue.withValues(alpha: 0.20)
                          : (dark
                                ? Colors.white.withValues(alpha: 0.10)
                                : Colors.black.withValues(alpha: 0.08)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: <Widget>[
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 11,
                          child: device.active
                              ? BarGlyph(
                                  BarIcons.checkmark,
                                  size: 11,
                                  color: theme.colors.textPrimary,
                                )
                              : null,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: BarType.caption.copyWith(
                              fontSize: 11,
                              color: theme.colors.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (outputs.devices.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
            child: Text(
              'No available output devices',
              style: BarType.caption.copyWith(
                fontSize: 10,
                color: theme.colors.textPrimary.withValues(alpha: 0.45),
              ),
            ),
          ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Application Volume',
              style: sectionStyle.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(height: 5),
        Expanded(
          child: apps.streams.isEmpty
              ? Center(
                  child: Text(
                    'No active audio applications',
                    style: BarType.caption.copyWith(
                      fontSize: 10,
                      color: theme.colors.textPrimary.withValues(alpha: 0.45),
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  itemCount: apps.streams.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 3),
                  itemBuilder: (context, index) {
                    final stream = apps.streams[index];
                    return _AppVolumeRow(
                      name: stream.name,
                      level: stream.level,
                      dark: dark,
                      onChanged: (value) =>
                          appsController.setVolume(stream.id, value),
                      onChangeEnd: (value) =>
                          appsController.commitVolume(stream.id, value),
                    );
                  },
                ),
        ),
        CcFooter(
          label: 'Sound settings…',
          icon: BarIcons.sliderHorizontal3,
          labelSize: 11,
          onTap: onOpenSettings,
        ),
      ],
    );
  }
}

/// One application stream: 58 high, a 28 pt mute-style button, the name and
/// percentage on the top line, its own slider under them.
class _AppVolumeRow extends StatefulWidget {
  const _AppVolumeRow({
    required this.name,
    required this.level,
    required this.dark,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final String name;
  final double level;
  final bool dark;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  State<_AppVolumeRow> createState() => _AppVolumeRowState();
}

class _AppVolumeRowState extends State<_AppVolumeRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final muted = widget.level <= 0.001;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: SizedBox(
        height: 58,
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: _hovered
                      ? (widget.dark
                            ? Colors.white.withValues(alpha: 0.10)
                            : Colors.black.withValues(alpha: 0.055))
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            Positioned(
              left: 4,
              top: (58 - 28) / 2,
              width: 28,
              height: 28,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => widget.onChangeEnd(muted ? 0.5 : 0),
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: muted
                          ? const Color(0xffff453a).withValues(
                              alpha: widget.dark ? 0.30 : 0.18,
                            )
                          : (widget.dark
                                ? Colors.white.withValues(alpha: 0.12)
                                : Colors.black.withValues(alpha: 0.07)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: BarGlyph(
                        muted ? BarIcons.volumeMute : BarIcons.volumeUp,
                        size: muted ? 15 : 13,
                        color: muted
                            ? const Color(0xffff453a)
                            : theme.colors.textPrimary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 40,
              right: 5,
              top: 5,
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      widget.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: BarType.caption.copyWith(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: theme.colors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${(widget.level * 100).round()}%',
                    style: BarType.caption.copyWith(
                      fontSize: 9,
                      color: theme.colors.textPrimary.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 40,
              right: 4,
              bottom: 3,
              height: 27,
              child: CcSlider(
                value: widget.level,
                left: 0,
                right: 0,
                dark: widget.dark,
                height: 27,
                onChangeStart: () {},
                onChanged: widget.onChanged,
                onChangeEnd: widget.onChangeEnd,
              ),
            ),
          ],
        ),
      ),
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
