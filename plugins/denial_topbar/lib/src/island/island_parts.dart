import 'dart:math' as math;

import 'package:denial_flutter_sdk/services.dart';
import 'package:denial_flutter_sdk/system_services.dart'
    show MprisPlaybackState;
import 'package:denial_shell_kit/kit_motion.dart';
import 'package:denial_shell_kit/kit_style.dart';
import 'package:flutter/widgets.dart';

import '../bar_icons.dart';
import '../bar_type.dart';
import '../media_art.dart';
import '../panels/mac_kit.dart' show Pressable;

const Color _ink = Color(0xffffffff);
const Color _dim = Color(0x99ffffff);
const Color _track = Color(0x33ffffff);
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
    return MediaArtwork(
      url: url,
      size: size,
      radius: radius,
      fallback: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: const Color(0xff2c2c2e),
          borderRadius: BorderRadius.circular(radius),
        ),
        child: BarGlyph(BarIcons.playFill, size: size * 0.45, color: _dim),
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
    super.key,
  });

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
    return SizedBox(
      width: widget.bars * bar + (widget.bars - 1) * gap,
      height: widget.height,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            for (var index = 0; index < widget.bars; index++)
              AnimatedContainer(
                duration: KitMotion.loop(context, KitMotion.fade),
                width: bar,
                height: widget.playing
                    ? widget.height *
                          (0.28 +
                              0.72 *
                                  (0.5 +
                                      0.5 *
                                          math.sin(
                                            _controller.value *
                                                    math.pi *
                                                    2 *
                                                    _rates[index % 6] +
                                                _phases[index % 6],
                                          )))
                    : bar,
                decoration: BoxDecoration(
                  color: _ink,
                  borderRadius: BorderRadius.circular(bar / 2),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class IslandLevel extends StatelessWidget {
  const IslandLevel({required this.level, this.height = 6, super.key});

  final double level;
  final double height;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => Container(
        height: height,
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: _track,
          borderRadius: BorderRadius.circular(height / 2),
        ),
        child: AnimatedContainer(
          duration: KitMotion.duration(context, KitMotion.ease),
          curve: KitMotion.out,
          width: math.max(height, constraints.maxWidth * level.clamp(0.0, 1.0)),
          height: height,
          decoration: BoxDecoration(
            color: level <= 0.001 ? const Color(0x00000000) : _ink,
            borderRadius: BorderRadius.circular(height / 2),
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
    return CustomPaint(
      size: Size(width, width * 0.48),
      painter: _BatteryPainter(level, colour, fill ?? colour, charging),
    );
  }
}

class _BatteryPainter extends CustomPainter {
  const _BatteryPainter(this.level, this.colour, this.fill, this.charging);

  final double level;
  final Color colour;
  final Color fill;
  final bool charging;

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
        ..strokeWidth = 1
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
      old.charging != charging;
}

String _clock(Duration value) {
  final total = value.inSeconds.clamp(0, 359999);
  return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
}

class _Control extends StatelessWidget {
  const _Control(this.icon, this.size, this.onTap, {this.enabled = true});

  final IconData icon;
  final double size;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: enabled ? onTap : null,
      scale: 0.86,
      child: SizedBox(
        width: 46,
        height: 40,
        child: BarGlyph(
          icon,
          size: size,
          color: _ink.withValues(alpha: enabled ? 1 : 0.3),
        ),
      ),
    );
  }
}

/// Now Playing, opened: the cover (drawn by the island so it can travel from
/// the pill), title and artist, the elapsed bar, and the transport.
class IslandMediaCard extends StatelessWidget {
  const IslandMediaCard({
    required this.playback,
    required this.commands,
    required this.coverSlot,
    required this.padding,
    required this.nothing,
    super.key,
  });

  final MprisPlaybackState? playback;
  final MediaCommands commands;
  final double coverSlot;
  final double padding;
  final String nothing;

  @override
  Widget build(BuildContext context) {
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
    final time = BarType.islandCaption.copyWith(
      fontSize: 10,
      fontWeight: FontWeight.w500,
      color: _dim,
      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(padding, padding, padding, 8),
      child: Column(
        children: <Widget>[
          SizedBox(
            height: coverSlot,
            child: Row(
              children: <Widget>[
                SizedBox(width: coverSlot + 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: BarType.islandTitle.copyWith(
                          fontSize: 15,
                          color: _ink,
                        ),
                      ),
                      if (artist.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: BarType.islandCaption.copyWith(
                              fontSize: 13,
                              color: _dim,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                IslandEqualizer(playing: playing, bars: 6, height: 20),
                const SizedBox(width: 4),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              SizedBox(width: 34, child: Text(_clock(position), style: time)),
              Expanded(child: IslandLevel(level: progress, height: 5)),
              SizedBox(
                width: 38,
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
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              _Control(
                BarIcons.backward,
                20,
                commands.previous,
                enabled: state?.canGoPrevious ?? false,
              ),
              const SizedBox(width: 18),
              _Control(
                playing ? BarIcons.pauseFill : BarIcons.playFill,
                30,
                commands.playPause,
                enabled: state?.available ?? false,
              ),
              const SizedBox(width: 18),
              _Control(
                BarIcons.forward,
                20,
                commands.next,
                enabled: state?.canGoNext ?? false,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class IslandNoticeCard extends StatelessWidget {
  const IslandNoticeCard({
    required this.icon,
    required this.app,
    required this.summary,
    required this.body,
    required this.onOpen,
    required this.onDismiss,
    super.key,
  });

  final Widget icon;
  final String app;
  final String summary;
  final String body;
  final VoidCallback? onOpen;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
        child: Row(
          children: <Widget>[
            SizedBox(width: 42, height: 42, child: icon),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    summary.isEmpty ? app : summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: BarType.islandTitle.copyWith(
                      fontSize: 13,
                      color: _ink,
                    ),
                  ),
                  if (body.isNotEmpty)
                    Text(
                      body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: BarType.islandCaption.copyWith(
                        fontSize: 12,
                        color: _dim,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Pressable(
              onTap: onDismiss,
              scale: 0.85,
              child: Container(
                width: 26,
                height: 26,
                decoration: const BoxDecoration(
                  color: Color(0x24ffffff),
                  shape: BoxShape.circle,
                ),
                child: const BarGlyph(BarIcons.xmark, size: 10, color: _ink),
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
    super.key,
  });

  final int percent;
  final bool plugged;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colour = plugged ? _green : _ink;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22),
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
                    color: _dim,
                  ),
                ),
                Text(
                  '$percent%',
                  style: BarType.display.copyWith(
                    fontSize: 24,
                    color: colour,
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
              ],
            ),
          ),
          BatteryGlyph(
            level: percent / 100,
            colour: colour,
            charging: plugged,
            width: 54,
          ),
        ],
      ),
    );
  }
}
