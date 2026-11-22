import 'package:denial_flutter_sdk/models.dart';
import 'package:denial_flutter_sdk/services.dart';
import 'package:denial_flutter_sdk/state.dart';
import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bar_icons.dart';
import 'panel_parts.dart';

/// The sound popover.
///
/// Ports shell27 `MacBar.qml`'s `volPop` body: an `Output` label at 12
/// DemiBold, a 32 pt volume track, one 46 pt row per output device, then the
/// `Apps` section with a 54 pt row per stream (a `name · 42%` line over its own
/// track). shell27 follows that with an `Input` section; Denial exposes no
/// microphone device, so the section is left out rather than drawn dead.
class SoundPopover extends ConsumerWidget {
  const SoundPopover({required this.services, super.key});

  final ShellServices services;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.shellTheme;
    final outputs = ref.watch(audioDevicesProvider);
    final outputsController = ref.read(audioDevicesProvider.notifier);
    final apps = ref.watch(appAudioProvider);
    final appsController = ref.read(appAudioProvider.notifier);
    final volume = ref.watch(services.volume);
    final label = PanelText.detail(theme).copyWith(
      fontWeight: FontWeight.w600,
      color: theme.colors.textSecondary,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 3),
          child: Text('Output', style: label),
        ),
        SizedBox(
          height: 32,
          child: VolumeSlider(
            value: volume,
            onChangeStart: services.beginVolumeInteraction,
            onChanged: services.setVolume,
            onChangeEnd: services.commitVolume,
          ),
        ),
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
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
            child: Text('No output devices', style: PanelText.detail(theme)),
          ),
        const SizedBox(height: 5),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 2),
          child: Text('Apps', style: label),
        ),
        for (final stream in apps.streams)
          _AppRow(
            stream: stream,
            onChanged: (value) =>
                appsController.setVolume(stream.id, value),
            onChangeEnd: (value) =>
                appsController.commitVolume(stream.id, value),
          ),
        if (apps.streams.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 2, 4, 4),
            child: Text(
              'No apps are playing audio',
              style: PanelText.detail(theme).copyWith(fontSize: 11),
            ),
          ),
        const SizedBox(height: 5),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 0),
          child: PanelDivider(color: theme.colors.hairlineSoft),
        ),
        const SizedBox(height: 5),
        PanelAction(
          label: 'Sound Settings…',
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

/// One device: 46 high, a 32 pt disc at `x: 8` that fills with the accent when
/// it is the default, the title at `x: 50` and the detail under it.
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
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: SizedBox(
          height: 46,
          child: Stack(
            children: <Widget>[
              Positioned.fill(
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 90),
                  opacity: _hovered ? 1 : 0,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: theme.colors.textPrimary.withValues(alpha: 0.09),
                      borderRadius: theme.borderRadius(12),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 8,
                top: 0,
                bottom: 0,
                child: Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.selected
                          ? theme.accent
                          : theme.colors.tileOff,
                    ),
                    child: Center(
                      child: BarGlyph(
                        BarIcons.volumeUp,
                        size: 16,
                        color: widget.selected
                            ? const Color(0xffffffff)
                            : theme.colors.textPrimary,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 50,
                right: 14,
                top: 0,
                bottom: 0,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PanelText.body(theme).copyWith(
                        fontWeight: widget.selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                    if (widget.sub.isNotEmpty)
                      Text(
                        widget.sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: PanelText.detail(theme).copyWith(fontSize: 11),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One app stream: 54 high, `name · 42%` at 12 over its own track at `y: 20`.
class _AppRow extends StatelessWidget {
  const _AppRow({
    required this.stream,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final AppAudioStream stream;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    return SizedBox(
      height: 54,
      child: Stack(
        children: <Widget>[
          Positioned(
            left: 4,
            right: 4,
            top: 0,
            child: Text(
              '${stream.name}  ·  ${(stream.level * 100).round()}%',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: PanelText.detail(
                theme,
              ).copyWith(color: theme.colors.textPrimary),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 20,
            height: 32,
            child: VolumeSlider(
              value: stream.level,
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            ),
          ),
        ],
      ),
    );
  }
}
