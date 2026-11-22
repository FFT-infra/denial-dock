import 'package:denial_flutter_sdk/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'workspace_dots.dart';

/// Workspace dots bound to the shell's workspace service.
class WorkspaceSwitcher extends ConsumerWidget {
  const WorkspaceSwitcher({
    required this.services,
    required this.monitorId,
    required this.ink,
    this.dotSize = 6,
    this.spacing = 6,
    super.key,
  });

  final ShellServices services;
  final int monitorId;
  final Color ink;
  final double dotSize;
  final double spacing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(services.workspacesEnabled);
    if (!enabled) return const SizedBox.shrink();
    final status = ref.watch(services.workspace(monitorId));
    // WorkspaceStatus numbers workspaces from 1; the dots index from 0.
    return WorkspaceDots(
      count: status.count,
      active: status.active - 1,
      occupied: <int>{for (final workspace in status.occupied) workspace - 1},
      ink: ink,
      dotSize: dotSize,
      spacing: spacing,
      onSelect: (index) => services.switchWorkspace(
        monitorId: monitorId,
        workspaceId: index + 1,
      ),
    );
  }
}
