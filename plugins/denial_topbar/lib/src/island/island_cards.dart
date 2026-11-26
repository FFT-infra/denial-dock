import 'dart:math' as math;

import 'package:denial_shell_kit/kit_motion.dart';
import 'package:denial_shell_kit/kit_springs.dart';
import 'package:denial_flutter_sdk/theme.dart';
import 'package:denial_shell_kit/kit_style.dart';
import 'package:flutter/widgets.dart';

import '../bar_icons.dart';
import '../bar_type.dart';
import '../panels/mac_kit.dart';
import 'island_motion.dart';
import 'island_skin.dart';

const List<FontFeature> _tabular = <FontFeature>[FontFeature.tabularFigures()];

class IslandRoundButton extends StatelessWidget {
  const IslandRoundButton({
    required this.icon,
    required this.onTap,
    this.fill,
    this.ink,
    this.size = 38,
    this.label,
    super.key,
  });

  final IconData icon;
  final VoidCallback? onTap;
  /// The plate and what is on it; the skin's own unless given.
  final Color? fill;
  final Color? ink;
  final double size;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final text = label;
    final skin = IslandSkin.of(context);
    final ink = this.ink ?? skin.ink;
    return Pressable(
      onTap: onTap,
      scale: 0.88,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: fill ?? skin.plate,
          borderRadius: skin.disc(size),
        ),
        child: text != null
            ? Text(
                text,
                style: BarType.islandLabel.copyWith(
                  color: ink,
                  fontWeight: FontWeight.w600,
                ),
              )
            : BarGlyph(icon, size: size * 0.42, color: ink),
      ),
    );
  }
}

/// A dot that breathes while something is being captured.
class IslandPulse extends StatefulWidget {
  const IslandPulse({this.size = 9, this.colour = macRed, super.key});

  final double size;
  final Color colour;

  @override
  State<IslandPulse> createState() => _IslandPulseState();
}

class _IslandPulseState extends State<IslandPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: KitMotion.now.scaled(KitMotion.pulse),
  )..repeat(reverse: true);

  // A repeat keeps the period it started with. The speed setting rebuilds
  // the tree, and this re-arms the same controller from its current value,
  // so the new pace applies without the widget being recreated.
  void _repace() =>
      _controller
        ..duration = KitMotion.now.scaled(KitMotion.pulse)
        ..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    kitSpeed.addListener(_repace);
  }

  @override
  void dispose() {
    kitSpeed.removeListener(_repace);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(
        begin: 1,
        end: 0.35,
      ).animate(CurvedAnimation(parent: _controller, curve: KitMotion.inOut)),
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(color: widget.colour, shape: BoxShape.circle),
      ),
    );
  }
}

/// A ring that fills clockwise from the top.
class IslandRing extends StatelessWidget {
  const IslandRing({
    required this.value,
    required this.colour,
    this.size = 16,
    this.stroke = 2.4,
    this.child,
    super.key,
  });

  final double value;
  final Color colour;
  final double size;
  final double stroke;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Sprung(
      target: value.clamp(0.0, 1.0),
      tuning: IslandFeel.of(KitStyle.of(context)).level,
      builder: (context, shown, _) => CustomPaint(
        painter: _RingPainter(
          shown.clamp(0.0, 1.0),
          colour,
          IslandSkin.of(context).faint,
          stroke,
        ),
        child: SizedBox.square(
          dimension: size,
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter(this.value, this.colour, this.track, this.stroke);

  final double value;
  final Color colour;
  final Color track;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = track;
    canvas.drawArc(rect, 0, math.pi * 2, false, paint);
    if (value <= 0) return;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * value,
      false,
      paint..color = colour,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value ||
      old.colour != colour ||
      old.track != track ||
      old.stroke != stroke;
}

/// A level bar that only reports: [value] of the way along, in [colour].
class IslandBar extends StatelessWidget {
  const IslandBar({
    required this.value,
    required this.colour,
    this.height = 6,
    super.key,
  });

  final double value;
  final Color colour;
  final double height;

  @override
  Widget build(BuildContext context) {
    final skin = IslandSkin.of(context);
    final radius = BorderRadius.circular(skin.corner(height / 2, height));
    return ClipRRect(
      borderRadius: radius,
      child: SizedBox(
        height: height,
        child: Stack(
          children: <Widget>[
            Positioned.fill(child: ColoredBox(color: skin.faint)),
            Sprung(
              target: value.clamp(0.0, 1.0),
              tuning: IslandFeel.of(skin.style).level,
              builder: (context, shown, _) => FractionallySizedBox(
                widthFactor: shown.clamp(0.0, 1.0),
                heightFactor: 1,
                alignment: Alignment.centerLeft,
                child: ColoredBox(color: colour),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The frame the one-activity cards share: what the activity is on the
/// left, its caption, its figure and a line of detail in the middle, and
/// what can be done about it on the right.
class _BigCard extends StatelessWidget {
  const _BigCard({
    required this.leading,
    required this.caption,
    required this.figure,
    required this.actions,
    this.figureColour,
    this.detail = '',
  });

  final Widget leading;
  final String caption;
  final String figure;
  final String detail;
  final List<Widget> actions;
  final Color? figureColour;

  @override
  Widget build(BuildContext context) {
    final skin = IslandSkin.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 20, 0),
      child: Row(
        children: <Widget>[
          leading,
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: BarType.islandCaption.copyWith(
                    fontSize: 12,
                    color: skin.dim,
                  ),
                ),
                Text(
                  figure,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.fade,
                  style: BarType.display.copyWith(
                    fontSize: 34,
                    height: 1.15,
                    color: figureColour ?? skin.ink,
                    fontFeatures: _tabular,
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
          for (final action in actions) ...<Widget>[
            const SizedBox(width: 10),
            action,
          ],
        ],
      ),
    );
  }
}

class IslandTimerCard extends StatelessWidget {
  const IslandTimerCard({
    required this.remaining,
    required this.fraction,
    required this.paused,
    required this.caption,
    required this.detail,
    required this.onToggle,
    required this.onAdd,
    required this.onCancel,
    super.key,
  });

  final String remaining;
  final double fraction;
  final bool paused;
  final String caption;

  /// The length it was set to.
  final String detail;
  final VoidCallback onToggle;
  final VoidCallback onAdd;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final skin = IslandSkin.of(context);
    final colour = skin.tone(macOrange);
    return _BigCard(
      leading: IslandRing(
        value: fraction,
        colour: paused ? skin.dim : colour,
        size: 64,
        stroke: 5,
        child: BarGlyph(BarIcons.timer, size: 22, color: colour),
      ),
      caption: caption,
      figure: remaining,
      figureColour: paused ? skin.dim : colour,
      detail: detail,
      actions: <Widget>[
        IslandRoundButton(icon: BarIcons.plus, label: '+1', onTap: onAdd),
        IslandRoundButton(
          icon: paused ? BarIcons.playFill : BarIcons.pauseFill,
          fill: colour.withValues(alpha: 0.32),
          ink: colour,
          size: 46,
          onTap: onToggle,
        ),
        IslandRoundButton(icon: BarIcons.xmark, onTap: onCancel),
      ],
    );
  }
}

class IslandRecordingCard extends StatelessWidget {
  const IslandRecordingCard({
    required this.elapsed,
    required this.caption,
    required this.detail,
    required this.onStop,
    super.key,
  });

  final String elapsed;
  final String caption;

  /// Who is using the microphone, when anything is.
  final String detail;
  final VoidCallback? onStop;

  @override
  Widget build(BuildContext context) {
    final skin = IslandSkin.of(context);
    final colour = skin.tone(macRed);
    return _BigCard(
      leading: SizedBox.square(
        dimension: 64,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colour.withValues(alpha: 0.18),
            borderRadius: skin.disc(64),
          ),
          child: Center(child: IslandPulse(size: 22, colour: colour)),
        ),
      ),
      caption: caption,
      figure: elapsed,
      detail: detail,
      actions: <Widget>[
        IslandRoundButton(
          icon: BarIcons.stopFill,
          fill: colour,
          ink: const Color(0xffffffff),
          size: 50,
          onTap: onStop,
        ),
      ],
    );
  }
}

/// One application's reported progress.
class IslandProgressEntry {
  const IslandProgressEntry({
    required this.icon,
    required this.name,
    required this.value,
  });

  final Widget icon;
  final String name;
  final double value;
}

/// Everything that reports a progress, a row each.
class IslandProgressCard extends StatelessWidget {
  const IslandProgressCard({required this.entries, super.key});

  /// The height of one row, for the card's size.
  static const double row = 50;

  final List<IslandProgressEntry> entries;

  @override
  Widget build(BuildContext context) {
    final skin = IslandSkin.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 18),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          for (final entry in entries)
            SizedBox(
              height: row,
              child: Row(
                children: <Widget>[
                  SizedBox.square(dimension: 34, child: entry.icon),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                entry.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: BarType.islandTitle.copyWith(
                                  color: skin.ink,
                                ),
                              ),
                            ),
                            Text(
                              '${(entry.value * 100).round()}%',
                              style: BarType.islandLabel.copyWith(
                                color: skin.dim,
                                fontFeatures: _tabular,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        IslandBar(
                          value: entry.value,
                          colour: skin.tone(macBlue),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class IslandHomeAction {
  const IslandHomeAction({
    required this.icon,
    required this.onTap,
    this.label,
    this.on = false,
  });

  final IconData icon;
  final String? label;
  final VoidCallback onTap;

  /// A switch that is on is filled.
  final bool on;
}

/// The latest notification, as the home panel sums it up.
class IslandDigest {
  const IslandDigest({
    required this.icon,
    required this.title,
    required this.body,
    required this.unread,
  });

  final Widget icon;
  final String title;
  final String body;
  final int unread;
}

/// What the resting pill opens into: the time and date, the battery, the
/// workspaces when the island carries them, the latest notification, and a
/// row of shortcuts.
class IslandHomeCard extends StatelessWidget {
  const IslandHomeCard({
    required this.time,
    required this.date,
    required this.trailing,
    required this.actions,
    required this.nothing,
    this.workspace,
    this.digest,
    this.onDigest,
    super.key,
  });

  final String time;
  final String date;
  final Widget? trailing;
  final List<IslandHomeAction> actions;

  /// The workspace switcher, when the island carries it.
  final Widget? workspace;

  /// The latest notification, or null when there is none; [nothing] says so.
  final IslandDigest? digest;
  final String nothing;
  final VoidCallback? onDigest;

  @override
  Widget build(BuildContext context) {
    final skin = IslandSkin.of(context);
    final news = digest;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                time,
                style: BarType.display.copyWith(
                  fontSize: 40,
                  height: 1,
                  color: skin.ink,
                  fontFeatures: _tabular,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    date,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: BarType.islandCaption.copyWith(
                      fontSize: 13,
                      color: skin.dim,
                    ),
                  ),
                ),
              ),
              if (workspace != null) ...<Widget>[
                workspace!,
                const SizedBox(width: 12),
              ],
              ?trailing,
            ],
          ),
          Expanded(
            child: Pressable(
              onTap: onDigest,
              scale: Pressable.large,
              child: Row(
                children: <Widget>[
                  if (news != null) ...<Widget>[
                    SizedBox.square(dimension: 30, child: news.icon),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: news == null
                        ? Text(
                            nothing,
                            style: BarType.islandCaption.copyWith(
                              fontSize: 13,
                              color: skin.dim,
                            ),
                          )
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                news.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: BarType.islandTitle.copyWith(
                                  fontSize: 13,
                                  color: skin.ink,
                                ),
                              ),
                              if (news.body.isNotEmpty)
                                Text(
                                  news.body,
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
                  if (news != null && news.unread > 0) ...<Widget>[
                    const SizedBox(width: 10),
                    Container(
                      constraints: const BoxConstraints(minWidth: 20),
                      height: 20,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: skin.tone(macRed),
                        borderRadius: skin.disc(20),
                      ),
                      child: Text(
                        '${news.unread}',
                        style: BarType.islandCaption.copyWith(
                          fontWeight: FontWeight.w600,
                          color: const Color(0xffffffff),
                          fontFeatures: _tabular,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              for (final action in actions)
                IslandRoundButton(
                  icon: action.icon,
                  label: action.label,
                  size: 46,
                  fill: action.on ? skin.accent : null,
                  ink: action.on ? skin.style.onAccent(context.shellTheme) : null,
                  onTap: action.onTap,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The dots under an open card when it has more than one page. A dot turns
/// to its page.
class IslandPageDots extends StatelessWidget {
  const IslandPageDots({
    required this.count,
    required this.index,
    this.onPick,
    super.key,
  });

  final int count;
  final int index;
  final ValueChanged<int>? onPick;

  @override
  Widget build(BuildContext context) {
    final skin = IslandSkin.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (var i = 0; i < count; i++)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onPick == null ? null : () => onPick!(i),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2.5, vertical: 4),
              // The lit dot stretches and the one it leaves draws in, each
              // on the spring the island's other levels use.
              child: Sprung(
                target: i == index ? 1 : 0,
                tuning: IslandFeel.of(skin.style).level,
                builder: (context, lit, _) => Container(
                  width: 5 + 7 * lit.clamp(0.0, 1.3),
                  height: 5,
                  decoration: BoxDecoration(
                    color: Color.lerp(skin.faint, skin.ink, lit.clamp(0.0, 1.0)),
                    borderRadius: BorderRadius.circular(skin.corner(2.5, 5)),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
