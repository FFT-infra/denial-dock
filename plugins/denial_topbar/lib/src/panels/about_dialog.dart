import 'dart:io';

import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/widgets.dart';

import '../l10n.dart';
import 'dialogs.dart';
import '../bar_type.dart';

/// What the machine says about itself, read once when the dialog opens.
class SystemSummary {
  const SystemSummary({
    required this.model,
    required this.os,
    required this.chip,
    required this.cores,
    required this.memory,
    required this.kernel,
    required this.host,
  });

  final String model;
  final String os;
  final String chip;
  final int cores;
  final String memory;
  final String kernel;
  final String host;

  static String _read(String path) {
    try {
      return File(path).readAsStringSync().replaceAll('\u0000', '').trim();
    } on FileSystemException {
      return '';
    }
  }

  static String _field(String text, String key) {
    for (final line in text.split('\n')) {
      final at = line.indexOf(key);
      if (at != 0) continue;
      final value = line.substring(key.length).trim();
      return value.replaceFirst(RegExp(r'^[:=]\s*'), '').replaceAll('"', '');
    }
    return '';
  }

  static SystemSummary read() {
    var model = _read('/sys/firmware/devicetree/base/model');
    if (model.isEmpty) {
      model = _read('/sys/devices/virtual/dmi/id/product_name');
    }
    final cpuinfo = _read('/proc/cpuinfo');
    final cores = RegExp(
      r'^processor\s*:',
      multiLine: true,
    ).allMatches(cpuinfo).length;
    var chip = _field(cpuinfo, 'model name');
    if (chip.isEmpty) chip = _field(cpuinfo, 'Hardware');
    if (chip.isEmpty) {
      final family = _read('/sys/devices/soc0/family');
      final soc = _read('/sys/firmware/devicetree/base/compatible')
          .split(',')
          .last
          .toUpperCase();
      chip = <String>[family, soc].where((part) => part.isNotEmpty).join(' ');
    }
    if (chip.isEmpty) chip = _read('/proc/sys/kernel/arch');
    final kilobytes =
        int.tryParse(
          _field(_read('/proc/meminfo'), 'MemTotal').split(' ').first,
        ) ??
        0;
    return SystemSummary(
      model: model,
      os: _field(_read('/etc/os-release'), 'PRETTY_NAME'),
      chip: chip,
      cores: cores,
      memory: kilobytes == 0 ? '' : '${(kilobytes / 1048576).ceil()} GB',
      kernel: _read('/proc/sys/kernel/osrelease'),
      host: _read('/proc/sys/kernel/hostname'),
    );
  }
}

/// About This System: the mark, the machine's name and a short table.
class AboutSystemDialog extends StatefulWidget {
  const AboutSystemDialog({
    required this.mark,
    required this.onClose,
    super.key,
  });

  static const double width = 340;

  final Widget mark;
  final VoidCallback onClose;

  @override
  State<AboutSystemDialog> createState() => _AboutSystemDialogState();
}

class _AboutSystemDialogState extends State<AboutSystemDialog> {
  late final SystemSummary _summary = SystemSummary.read();

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final summary = _summary;
    final rows = <(String, String)>[
      (
        context.tr('Chip'),
        summary.cores > 0
            ? '${summary.chip} · ${context.tr('{} cores', summary.cores)}'
            : summary.chip,
      ),
      (context.tr('Memory'), summary.memory),
      (context.tr('System'), summary.os),
      (context.tr('Kernel'), summary.kernel),
      (context.tr('Name'), summary.host),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(width: 64, height: 64, child: widget.mark),
          const SizedBox(height: 14),
          Text(
            summary.model.isEmpty ? summary.host : summary.model,
            textAlign: TextAlign.center,
            style: BarType.display.copyWith(
              fontSize: 20,
              color: theme.colors.textPrimary,
            ),
          ),
          const SizedBox(height: 18),
          for (final (label, value) in rows)
            if (value.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      flex: 2,
                      child: Text(
                        label,
                        textAlign: TextAlign.right,
                        style: BarType.caption.copyWith(
                          fontSize: 12,
                          color: theme.colors.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 3,
                      child: Text(
                        value,
                        style: BarType.caption.copyWith(
                          fontSize: 12,
                          color: theme.colors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          const SizedBox(height: 18),
          DialogButton(label: context.tr('OK'), onTap: widget.onClose),
        ],
      ),
    );
  }
}
