import 'package:denial_flutter_sdk/services.dart';
import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class TopBarBatteryPanel extends ConsumerWidget {
  const TopBarBatteryPanel({required this.services, super.key});

  final ShellServices services;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final battery = ref.watch(services.battery);
    final theme = context.shellTheme;
    final capacity = battery.capacity;
    final accent = battery.charging ? theme.accent : theme.colors.textPrimary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                battery.charging
                    ? Icons.battery_charging_full
                    : Icons.battery_full,
                size: 20,
                color: accent,
              ),
              const SizedBox(width: 8),
              Text(
                'Battery',
                style: theme.text.systemBarValue.copyWith(
                  color: theme.colors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            capacity == null ? 'Unavailable' : '$capacity%',
            style: theme.text.statusClock.copyWith(
              color: theme.colors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: capacity == null ? 0 : capacity / 100,
              minHeight: 5,
              backgroundColor: theme.colors.textPrimary.withValues(alpha: 0.1),
              valueColor: AlwaysStoppedAnimation<Color>(
                capacity != null && capacity <= 15 && !battery.charging
                    ? theme.colors.performanceBad
                    : theme.accent,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            battery.charging ? 'Charging' : 'On battery',
            style: theme.text.systemBarCaption.copyWith(
              color: theme.colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
