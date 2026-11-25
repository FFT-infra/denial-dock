import 'dart:math' as math;

import 'package:denial_shell_kit/kit_motion.dart';
import 'package:denial_shell_kit/kit_springs.dart';
import 'package:denial_shell_kit/kit_style.dart';
import 'package:flutter/widgets.dart';

import '../bar_icons.dart';
import '../bar_type.dart';
import '../panels/mac_kit.dart';
import 'island_motion.dart';

const Color _ink = Color(0xffffffff);
const Color _dim = Color(0x99ffffff);
const Color _track = Color(0x33ffffff);

const List<FontFeature> _tabular = <FontFeature>[FontFeature.tabularFigures()];

class IslandRoundButton extends StatelessWidget {
  const IslandRoundButton({
    required this.icon,
    required this.onTap,
    this.fill = const Color(0x29ffffff),
    this.ink = _ink,
    this.size = 38,
    this.label,
    super.key,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final Color fill;
  final Color ink;
  final double size;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final text = label;
    return Pressable(
      onTap: onTap,
      scale: 0.88,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
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
        painter: _RingPainter(shown.clamp(0.0, 1.0), colour, stroke),
        child: SizedBox.square(
          dimension: size,
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter(this.value, this.colour, this.stroke);

  final double value;
  final Color colour;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = _track;
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
      old.value != value || old.colour != colour || old.stroke != stroke;
}

class _CardRow extends StatelessWidget {
  const _CardRow({
    required this.leading,
    required this.title,
    required this.caption,
    required this.actions,
    this.titleColour = _ink,
  });

  final Widget leading;
  final String title;
  final String caption;
  final List<Widget> actions;
  final Color titleColour;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 16, 0),
      child: Row(
        children: <Widget>[
          leading,
          const SizedBox(width: 12),
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
                    color: _dim,
                  ),
                ),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: BarType.display.copyWith(
                    fontSize: 24,
                    color: titleColour,
                    fontFeatures: _tabular,
                  ),
                ),
              ],
            ),
          ),
          for (final action in actions) ...<Widget>[
            const SizedBox(width: 8),
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
    required this.onToggle,
    required this.onAdd,
    required this.onCancel,
    super.key,
  });

  final String remaining;
  final double fraction;
  final bool paused;
  final String caption;
  final VoidCallback onToggle;
  final VoidCallback onAdd;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return _CardRow(
      leading: IslandRing(
        value: fraction,
        colour: macOrange,
        size: 40,
        stroke: 4,
        child: const BarGlyph(BarIcons.timer, size: 16, color: macOrange),
      ),
      caption: caption,
      title: remaining,
      titleColour: paused ? _dim : macOrange,
      actions: <Widget>[
        IslandRoundButton(icon: BarIcons.plus, label: '+1', onTap: onAdd),
        IslandRoundButton(
          icon: paused ? BarIcons.playFill : BarIcons.pauseFill,
          fill: const Color(0x52ff9f0a),
          ink: macOrange,
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
    required this.onStop,
    super.key,
  });

  final String elapsed;
  final String caption;
  final VoidCallback? onStop;

  @override
  Widget build(BuildContext context) {
    return _CardRow(
      leading: const SizedBox.square(
        dimension: 40,
        child: Center(child: IslandPulse(size: 16)),
      ),
      caption: caption,
      title: elapsed,
      actions: <Widget>[
        IslandRoundButton(
          icon: BarIcons.stopFill,
          fill: macRed,
          size: 42,
          onTap: onStop,
        ),
      ],
    );
  }
}

class IslandProgressCard extends StatelessWidget {
  const IslandProgressCard({
    required this.icon,
    required this.name,
    required this.value,
    super.key,
  });

  final Widget icon;
  final String name;
  final double value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
      child: Row(
        children: <Widget>[
          SizedBox.square(dimension: 40, child: icon),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: BarType.islandTitle.copyWith(
                          fontSize: 13,
                          color: _ink,
                        ),
                      ),
                    ),
                    Text(
                      '${(value * 100).round()}%',
                      style: BarType.islandLabel.copyWith(
                        color: _dim,
                        fontFeatures: _tabular,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 9),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: SizedBox(
                    height: 6,
                    child: Stack(
                      children: <Widget>[
                        const Positioned.fill(child: ColoredBox(color: _track)),
                        Sprung(
                          target: value.clamp(0.0, 1.0),
                          tuning: IslandFeel.of(KitStyle.of(context)).level,
                          builder: (context, shown, _) => FractionallySizedBox(
                            widthFactor: shown.clamp(0.0, 1.0),
                            heightFactor: 1,
                            alignment: Alignment.centerLeft,
                            child: const ColoredBox(color: macBlue),
                          ),
                        ),
                      ],
                    ),
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
  const IslandHomeAction({required this.icon, required this.onTap, this.label});

  final IconData icon;
  final String? label;
  final VoidCallback onTap;
}

/// What the resting pill opens into: the time and date, the battery, the
/// workspaces, and a row of shortcuts.
class IslandHomeCard extends StatelessWidget {
  const IslandHomeCard({
    required this.time,
    required this.date,
    required this.trailing,
    required this.actions,
    this.workspace,
    this.agenda,
    super.key,
  });

  final String time;
  final String date;
  final Widget? trailing;
  final List<IslandHomeAction> actions;

  /// The workspace switcher, when the island carries it.
  final Widget? workspace;

  /// What comes next in the day. Nothing provides it yet; the row keeps the
  /// place for it.
  final Widget? agenda;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                time,
                style: BarType.display.copyWith(
                  fontSize: 34,
                  height: 1,
                  color: _ink,
                  fontFeatures: _tabular,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    date,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: BarType.islandCaption.copyWith(
                      fontSize: 13,
                      color: _dim,
                    ),
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
          Expanded(
            child: Row(
              children: <Widget>[
                ?workspace,
                if (workspace != null) const SizedBox(width: 12),
                Expanded(child: agenda ?? const SizedBox.shrink()),
              ],
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              for (final action in actions)
                IslandRoundButton(
                  icon: action.icon,
                  label: action.label,
                  size: 44,
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
                tuning: IslandFeel.of(KitStyle.of(context)).level,
                builder: (context, lit, _) => Container(
                  width: 5 + 7 * lit.clamp(0.0, 1.3),
                  height: 5,
                  decoration: BoxDecoration(
                    color: Color.lerp(_track, _ink, lit.clamp(0.0, 1.0)),
                    borderRadius: BorderRadius.circular(2.5),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
