import 'package:denial_flutter_sdk/models.dart';
import 'package:denial_flutter_sdk/services.dart';
import 'package:denial_flutter_sdk/state.dart';
import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bar_icons.dart';
import '../bar_type.dart';
import 'cc_card.dart';

/// The sound popover.
///
/// Ports NextKDE `SoundPage.qml`: a 62 pt master section with the volume
/// slider, the output devices as 30 pt radius-8 pills with the active one on
/// a blue wash, then one 58 pt row per application stream with a 28 pt mute
/// button and its own slider, and a 38 pt settings footer.
class SoundPopover extends ConsumerWidget {
  const SoundPopover({required this.services, super.key});

  final ShellServices services;

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
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SizedBox(
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
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: Text('Output devices', style: sectionStyle),
        ),
        const SizedBox(height: 4),
        for (final device in outputs.devices)
          _AudioRow(
            title: audioSplit(device.description.isEmpty
                ? device.name
                : device.description).$1,
            sub: audioSplit(device.description.isEmpty
                ? device.name
                : device.description).$2,
            selected: device.active,
            onTap: () => outputsController.select(device.name),
          ),
        if (outputs.devices.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              'No available output devices',
              style: BarType.caption.copyWith(
                fontSize: 10,
                color: theme.colors.textPrimary.withValues(alpha: 0.45),
              ),
            ),
          ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Application Volume',
            style: sectionStyle.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 5),
        for (final stream in apps.streams)
          _AppRow(
            stream: stream,
            dark: dark,
            onChanged: (value) => appsController.setVolume(stream.id, value),
            onChangeEnd: (value) =>
                appsController.commitVolume(stream.id, value),
          ),
        if (apps.streams.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              'No active audio applications',
              style: BarType.caption.copyWith(
                fontSize: 10,
                color: theme.colors.textPrimary.withValues(alpha: 0.45),
              ),
            ),
          ),
        CcFooter(
          label: 'Sound settings…',
          icon: BarIcons.sliderHorizontal3,
          labelSize: 11,
          onTap: () => services.openPowerSettings(),
        ),
      ],
    );
  }
}

/// shell27's `audioSplit`: `"Family 17h HD Audio Controller Analog Stereo"`
/// becomes the controller name over `"Analog Stereo"`, so the row has a bold
/// title and a quieter detail line. A description without that tail stays one
/// line.
(String, String) audioSplit(String description) {
  final text = description.trim();
  final match = RegExp(
    r'^(.*?)\s+((?:Analog|Digital|Pro|Stereo|Mono|Speaker|Headphones|Headset|'
    r'Microphone|Line|HDMI|DisplayPort|S/PDIF|Surround)\b.*)$',
    caseSensitive: false,
  ).firstMatch(text);
  if (match != null && match.group(1)!.length > 2) {
    return (match.group(1)!, match.group(2)!);
  }
  return (text, '');
}

/// One output device: NextKDE `SoundPage.qml`'s 30 pt radius-8 pill, blue while
/// it is the default and grey otherwise, with a check 10 in from the left.
class _AudioRow extends StatefulWidget {
  const _AudioRow({
    required this.title,
    required this.sub,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String sub;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_AudioRow> createState() => _AudioRowState();
}

class _AudioRowState extends State<_AudioRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final dark = theme.colors.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 90),
            height: 30,
            decoration: BoxDecoration(
              color: widget.selected
                  ? ccBlue.withValues(alpha: 0.20)
                  : (dark
                        ? Colors.white.withValues(
                            alpha: _hovered ? 0.16 : 0.10,
                          )
                        : Colors.black.withValues(
                            alpha: _hovered ? 0.12 : 0.08,
                          )),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: <Widget>[
                const SizedBox(width: 10),
                SizedBox(
                  width: 11,
                  child: widget.selected
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
                    widget.sub.isEmpty
                        ? widget.title
                        : '${widget.title} · ${widget.sub}',
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
      ),
    );
  }
}

/// One application stream: 58 high, the mute button at 4, the name and
/// percentage on the top line, its own slider under them.
class _AppRow extends StatefulWidget {
  const _AppRow({
    required this.stream,
    required this.dark,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final AppAudioStream stream;
  final bool dark;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  State<_AppRow> createState() => _AppRowState();
}

class _AppRowState extends State<_AppRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final muted = widget.stream.muted || widget.stream.level <= 0.001;
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
                      widget.stream.name,
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
                    '${(widget.stream.level * 100).round()}%',
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
                value: widget.stream.level,
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
