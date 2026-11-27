import 'dart:math' as math;

import 'package:denial_flutter_sdk/system_services.dart'
    show MprisPlaybackState;
import 'package:denial_shell_kit/kit_motion.dart';
import 'package:denial_shell_kit/kit_springs.dart';
import 'package:denial_shell_kit/kit_style.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../bar_icons.dart';
import '../bar_type.dart';
import '../media_art.dart';
import 'island_cards.dart' show IslandRoundButton;
import 'island_motion.dart';
import 'island_skin.dart';
import '../panels/mac_kit.dart' show Pressable;

const Color _green = Color(0xff30d158);

class IslandCover extends StatelessWidget {
  const IslandCover({
    required this.url,
    required this.size,
    required this.radius,
    super.key,
  });

  final String url;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final skin = IslandSkin.of(context);
    // A new track's cover takes the old one's place: the old one draws
    // back and the new one comes up from small, on the look's own curve.
    return SizedBox.square(
      dimension: size,
      child: IslandSwap(
        shrink: 0.35,
        child: MediaArtwork(
          key: ValueKey<String>(url),
          url: url,
          size: size,
          radius: radius,
          fallback: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: skin.plate,
              borderRadius: BorderRadius.circular(radius),
            ),
            child: BarGlyph(
              BarIcons.playFill,
              size: size * 0.45,
              color: skin.dim,
            ),
          ),
        ),
      ),
    );
  }
}

/// Bars that move while something plays and rest as dots when it does not.
/// The ticker only runs while playing.
class IslandEqualizer extends StatefulWidget {
  const IslandEqualizer({
    required this.playing,
    this.bars = 4,
    this.height = 14,
    this.colour,
    super.key,
  });

  /// The bars' colour; the skin's ink unless given.
  final Color? colour;
  final bool playing;
  final int bars;
  final double height;

  @override
  State<IslandEqualizer> createState() => _IslandEqualizerState();
}

class _IslandEqualizerState extends State<IslandEqualizer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: KitMotion.now.scaled(KitMotion.wave),
  );

  static const List<double> _rates = <double>[3, 5, 2, 4, 3, 5];
  static const List<double> _phases = <double>[0, 1.7, 0.9, 2.6, 0.4, 2.1];

  /// A repeat keeps the period it started with, so a speed change re-arms the
  /// running controller from its current value instead of restarting it.
  void _repace() {
    _controller.duration = KitMotion.now.scaled(KitMotion.wave);
    if (_controller.isAnimating) _controller.repeat();
  }

  @override
  void initState() {
    super.initState();
    kitSpeed.addListener(_repace);
    if (widget.playing) _controller.repeat();
  }

  @override
  void dispose() {
    kitSpeed.removeListener(_repace);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(IslandEqualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.playing == oldWidget.playing) return;
    widget.playing ? _controller.repeat() : _controller.stop();
  }

  @override
  Widget build(BuildContext context) {
    const bar = 3.0;
    const gap = 2.0;
    final skin = IslandSkin.of(context);
    final feel = IslandFeel.of(skin.style);
    final colour = widget.colour ?? skin.ink;
    return SizedBox(
      width: widget.bars * bar + (widget.bars - 1) * gap,
      height: widget.height,
      // The bars rise out of their dots and sink back into them on a
      // spring; the wave itself is already continuous and needs no easing
      // laid over it.
      child: Sprung(
        target: widget.playing ? 1 : 0,
        tuning: feel.level,
        builder: (context, energy, _) => AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              for (var index = 0; index < widget.bars; index++)
                Container(
                  width: bar,
                  height: math.max(
                    bar,
                    bar +
                        (widget.height - bar) *
                            energy.clamp(0.0, 1.2) *
                            (0.2 +
                                0.8 *
                                    (0.5 +
                                        0.5 *
                                            math.sin(
                                              _controller.value *
                                                      math.pi *
                                                      2 *
                                                      _rates[index % 6] +
                                                  _phases[index % 6],
                                            ))),
                  ),
                  decoration: BoxDecoration(
                    color: colour,
                    borderRadius: BorderRadius.circular(
                      skin.corner(bar / 2, bar),
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

class IslandLevel extends StatelessWidget {
  const IslandLevel({
    required this.level,
    this.height = 6,
    this.colour,
    this.edgeBump = 0,
    super.key,
  });

  final double level;
  final double height;

  /// The fill's colour; the skin's ink unless given.
  final Color? colour;

  /// Elastic boundary stretch (-1 at 0%, +1 at 100%).
  final double edgeBump;

  @override
  Widget build(BuildContext context) {
    final skin = IslandSkin.of(context);
    final radius = BorderRadius.circular(skin.corner(height / 2, height));
    final fill = colour ?? skin.ink;
    final stretchX = 1.0 + edgeBump.abs().clamp(0.0, 1.5) * 0.045;
    final squashY = 1.0 - edgeBump.abs().clamp(0.0, 1.5) * 0.09;
    final align = edgeBump < 0 ? Alignment.centerRight : Alignment.centerLeft;
    return Transform(
      alignment: align,
      transform: Matrix4.diagonal3Values(stretchX, squashY, 1),
      child: LayoutBuilder(
        builder: (context, constraints) => Container(
          height: height,
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(color: skin.faint, borderRadius: radius),
          // The fill follows its level on a spring, so a level that keeps
          // changing is one motion and not a run of restarted eases.
          child: Sprung(
            target: level.clamp(0.0, 1.0),
            tuning: IslandFeel.of(skin.style).level,
            builder: (context, shown, _) => Container(
              width: math.max(
                height,
                constraints.maxWidth * shown.clamp(0.0, 1.0),
              ),
              height: height,
              decoration: BoxDecoration(
                color: shown <= 0.001 ? const Color(0x00000000) : fill,
                borderRadius: radius,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A battery drawn to the level: body, cap, fill, and a bolt while charging.
class BatteryGlyph extends StatelessWidget {
  const BatteryGlyph({
    required this.level,
    required this.colour,
    this.charging = false,
    this.width = 25,
    this.fill,
    super.key,
  });

  final double level;
  final Color colour;
  final bool charging;
  final double width;

  /// Colour of the charge inside; defaults to [colour].
  final Color? fill;

  @override
  Widget build(BuildContext context) {
    final weight = KitStyle.of(context).look.iconWeight;
    return CustomPaint(
      size: Size(width, width * 0.48),
      painter: _BatteryPainter(level, colour, fill ?? colour, charging, weight),
    );
  }
}

class _BatteryPainter extends CustomPainter {
  const _BatteryPainter(
    this.level,
    this.colour,
    this.fill,
    this.charging,
    this.weight,
  );

  final double level;
  final Color colour;
  final Color fill;
  final bool charging;
  final double weight;

  @override
  void paint(Canvas canvas, Size size) {
    // The bolt is cut out of the charge with dstOut, which would otherwise
    // eat into whatever the battery is drawn over.
    if (charging) canvas.saveLayer(Offset.zero & size, Paint());
    final cap = size.width * 0.07;
    final body = Rect.fromLTWH(
      0.5,
      0.5,
      size.width - cap - 1.5,
      size.height - 1,
    );
    final radius = Radius.circular(size.height * 0.28);
    canvas.drawRRect(
      RRect.fromRectAndRadius(body, radius),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1 * weight
        ..color = colour.withValues(alpha: 0.5),
    );
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTWH(
          size.width - cap,
          size.height * 0.32,
          cap,
          size.height * 0.36,
        ),
        topRight: Radius.circular(cap),
        bottomRight: Radius.circular(cap),
      ),
      Paint()..color = colour.withValues(alpha: 0.5),
    );
    final inner = body.deflate(1.6);
    final charge = Rect.fromLTWH(
      inner.left,
      inner.top,
      math.max(2, inner.width * level.clamp(0.0, 1.0)),
      inner.height,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(charge, Radius.circular(size.height * 0.16)),
      Paint()..color = fill,
    );
    if (!charging) return;
    final c = body.center;
    final s = size.height * 0.42;
    final bolt = Path()
      ..moveTo(c.dx + s * 0.25, c.dy - s)
      ..lineTo(c.dx - s * 0.6, c.dy + s * 0.12)
      ..lineTo(c.dx - s * 0.05, c.dy + s * 0.12)
      ..lineTo(c.dx - s * 0.25, c.dy + s)
      ..lineTo(c.dx + s * 0.6, c.dy - s * 0.12)
      ..lineTo(c.dx + s * 0.05, c.dy - s * 0.12)
      ..close();
    canvas.drawPath(
      bolt,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..color = const Color(0xff000000)
        ..blendMode = BlendMode.dstOut,
    );
    canvas.drawPath(bolt, Paint()..color = colour);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BatteryPainter old) =>
      old.level != level ||
      old.colour != colour ||
      old.fill != fill ||
      old.charging != charging ||
      old.weight != weight;
}

String _clock(Duration value) {
  final total = value.inSeconds.clamp(0, 359999);
  return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
}

class _Control extends StatelessWidget {
  const _Control(
    this.icon,
    this.size,
    this.onTap, {
    this.enabled = true,
    this.plate = false,
  });

  final IconData icon;
  final double size;
  final VoidCallback onTap;
  final bool enabled;

  /// The main control sits on a plate.
  final bool plate;

  @override
  Widget build(BuildContext context) {
    final skin = IslandSkin.of(context);
    final extent = plate ? 46.0 : 42.0;
    return Pressable(
      onTap: enabled ? onTap : null,
      scale: 0.86,
      child: Container(
        width: extent,
        height: extent,
        alignment: Alignment.center,
        decoration: plate
            ? BoxDecoration(color: skin.plate, borderRadius: skin.disc(extent))
            : null,
        child: IslandSwap(
          shrink: 0.5,
          child: BarGlyph(
            icon,
            key: ValueKey<int>(icon.codePoint),
            size: size,
            color: skin.ink.withValues(alpha: enabled ? 1 : 0.3),
          ),
        ),
      ),
    );
  }
}

/// Now Playing, opened: the cover (drawn by the island so it can travel from
/// the pill), title and artist, the elapsed bar, the transport, and where
/// the sound comes from and goes to.
///
/// The elapsed bar only reports. The shell's media commands are previous,
/// play or pause, and next; there is no seek to send a drag to.
class IslandMediaCard extends StatelessWidget {
  const IslandMediaCard({
    required this.playback,
    required this.onPrevious,
    required this.onPlayPause,
    required this.onNext,
    required this.coverSlot,
    required this.padding,
    required this.nothing,
    this.turn = 1,
    this.subline,
    this.output = '',
    this.outputIcon,
    this.onSwitchOutput,
    super.key,
  });

  final MprisPlaybackState? playback;
  final VoidCallback onPrevious;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;
  final double coverSlot;
  final double padding;
  final String nothing;

  /// Which way the track last changed: 1 forward, -1 back. The new title
  /// comes in from that side.
  final int turn;

  /// A second line under the title, shown in the artist's place whenever
  /// its source has one.
  final ValueListenable<String?>? subline;

  /// The output the sound plays on, when the shell knows it.
  final String output;
  final IconData? outputIcon;

  /// Cycles to the next available audio output device when tapped.
  final VoidCallback? onSwitchOutput;

  Widget _second(IslandSkin skin, String artist) {
    Widget line(String text, {bool sung = false}) => Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: BarType.islandCaption.copyWith(
        fontSize: 13,
        color: sung ? skin.ink.withValues(alpha: 0.86) : skin.dim,
      ),
    );
    final source = subline;
    if (source == null) return line(artist);
    return ValueListenableBuilder<String?>(
      valueListenable: source,
      builder: (context, value, _) {
        final sung = value != null && value.isNotEmpty;
        final text = sung ? value : artist;
        return IslandSwap(
          from: const Offset(0, 1),
          distance: 6,
          alignment: Alignment.centerLeft,
          child: KeyedSubtree(
            key: ValueKey<String>(text),
            child: line(text, sung: sung),
          ),
        );
      },
    );
  }

  Widget _chip(IslandSkin skin, IconData? icon, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      if (icon != null) ...<Widget>[
        BarGlyph(icon, size: 11, color: skin.dim),
        const SizedBox(width: 5),
      ],
      Flexible(
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: BarType.islandCaption.copyWith(color: skin.dim),
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final skin = IslandSkin.of(context);
    final state = playback;
    final playing = state?.playing ?? false;
    final length = state?.length ?? Duration.zero;
    final position = state?.positionAt(DateTime.now()) ?? Duration.zero;
    final progress = length <= Duration.zero
        ? 0.0
        : (position.inMilliseconds / length.inMilliseconds).clamp(0.0, 1.0);
    final title = state != null && state.title.isNotEmpty
        ? state.title
        : nothing;
    final artist = state == null
        ? ''
        : (state.artists.isEmpty ? state.album : state.artistLabel);
    final player = state?.identity ?? '';
    final time = BarType.islandCaption.copyWith(
      fontSize: 10,
      fontWeight: FontWeight.w500,
      color: skin.dim,
      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(padding, padding, padding, 14),
      child: Column(
        children: <Widget>[
          SizedBox(
            height: coverSlot,
            child: Row(
              children: <Widget>[
                SizedBox(width: coverSlot + 14),
                Expanded(
                  child: IslandSwap(
                    from: Offset(turn.toDouble(), 0),
                    distance: 14,
                    alignment: Alignment.centerLeft,
                    child: Column(
                      key: ValueKey<String>('$title\n$artist'),
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: BarType.islandTitle.copyWith(
                            fontSize: 16,
                            color: skin.ink,
                          ),
                        ),
                        if (artist.isNotEmpty || subline != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: _second(skin, artist),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                IslandEqualizer(
                  playing: playing,
                  bars: 6,
                  height: 22,
                  colour: skin.tone(skin.ink),
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              SizedBox(width: 36, child: Text(_clock(position), style: time)),
              Expanded(
                child: IslandLevel(
                  level: progress,
                  height: 5,
                  colour: skin.tone(skin.ink),
                ),
              ),
              SizedBox(
                width: 40,
                child: Text(
                  length > Duration.zero ? '−${_clock(length - position)}' : '',
                  textAlign: TextAlign.right,
                  style: time,
                ),
              ),
            ],
          ),
          const Spacer(),
          Row(
            children: <Widget>[
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: player.isEmpty
                      ? null
                      : _chip(skin, BarIcons.playFill, player),
                ),
              ),
              _Control(
                BarIcons.backward,
                20,
                onPrevious,
                enabled: state?.canGoPrevious ?? false,
              ),
              const SizedBox(width: 14),
              _Control(
                playing ? BarIcons.pauseFill : BarIcons.playFill,
                22,
                onPlayPause,
                enabled: state?.available ?? false,
                plate: true,
              ),
              const SizedBox(width: 14),
              _Control(
                BarIcons.forward,
                20,
                onNext,
                enabled: state?.canGoNext ?? false,
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: output.isEmpty
                      ? null
                      : onSwitchOutput == null
                      ? _chip(skin, outputIcon, output)
                      : Pressable(
                          onTap: onSwitchOutput,
                          scale: 0.92,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: skin.plate,
                              borderRadius: skin.disc(22),
                            ),
                            child: _chip(skin, outputIcon, output),
                          ),
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A notification, opened: who it is from, what it says, and the answers
/// it offers.
class IslandNoticeCard extends StatelessWidget {
  const IslandNoticeCard({
    required this.icon,
    required this.app,
    required this.summary,
    required this.body,
    required this.onOpen,
    required this.onDismiss,
    this.actions = const <(String, VoidCallback)>[],
    super.key,
  });

  /// The card's height without, and with, a row of answers.
  static const double plain = 96;
  static const double answered = 140;

  final Widget icon;
  final String app;
  final String summary;
  final String body;
  final VoidCallback? onOpen;
  final VoidCallback? onDismiss;

  /// The notification's own actions, by label.
  final List<(String, VoidCallback)> actions;

  @override
  Widget build(BuildContext context) {
    final skin = IslandSkin.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 16, 16),
        child: Column(
          children: <Widget>[
            Expanded(
              child: Row(
                children: <Widget>[
                  SizedBox(width: 44, height: 44, child: icon),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        if (app.isNotEmpty && summary.isNotEmpty)
                          Text(
                            app,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: BarType.islandCaption.copyWith(
                              color: skin.dim,
                            ),
                          ),
                        Text(
                          summary.isEmpty ? app : summary,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: BarType.islandTitle.copyWith(color: skin.ink),
                        ),
                        if (body.isNotEmpty)
                          Text(
                            body,
                            maxLines: app.isNotEmpty && summary.isNotEmpty
                                ? 1
                                : 2,
                            overflow: TextOverflow.ellipsis,
                            style: BarType.islandCaption.copyWith(
                              fontSize: 12,
                              color: skin.dim,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  IslandRoundButton(
                    icon: BarIcons.xmark,
                    size: 28,
                    onTap: onDismiss,
                  ),
                ],
              ),
            ),
            if (actions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(
                  children: <Widget>[
                    for (final (index, action) in actions.indexed) ...<Widget>[
                      if (index > 0) const SizedBox(width: 8),
                      Expanded(
                        child: Pressable(
                          onTap: action.$2,
                          scale: Pressable.large,
                          child: Container(
                            height: 32,
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(
                              color: skin.plate,
                              borderRadius: skin.disc(32),
                            ),
                            child: Text(
                              action.$1,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: BarType.islandLabel.copyWith(
                                color: skin.ink,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class IslandChargeCard extends StatelessWidget {
  const IslandChargeCard({
    required this.percent,
    required this.plugged,
    required this.label,
    this.detail = '',
    super.key,
  });

  final int percent;
  final bool plugged;
  final String label;

  /// How long until it is full, or empty, when the battery says.
  final String detail;

  @override
  Widget build(BuildContext context) {
    final skin = IslandSkin.of(context);
    final colour = plugged ? skin.tone(_green, meaning: true) : skin.ink;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  style: BarType.islandCaption.copyWith(
                    fontSize: 12,
                    color: skin.dim,
                  ),
                ),
                Text(
                  '$percent%',
                  style: BarType.display.copyWith(
                    fontSize: 34,
                    height: 1.15,
                    color: colour,
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
                if (detail.isNotEmpty)
                  Text(
                    detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: BarType.islandCaption.copyWith(
                      fontSize: 12,
                      color: skin.dim,
                    ),
                  ),
              ],
            ),
          ),
          BatteryGlyph(
            level: percent / 100,
            colour: colour,
            charging: plugged,
            width: 72,
          ),
        ],
      ),
    );
  }
}
