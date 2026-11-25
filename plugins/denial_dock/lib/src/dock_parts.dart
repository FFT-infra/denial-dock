import 'package:denial_shell_kit/kit_part.dart';
import 'package:flutter/widgets.dart';

import 'dock_zones.dart';

/// The dock's own parts under the names a layout editor shows. The dock
/// draws them itself, so their builders draw nothing; registering them is
/// what lets an editor in another plugin list and place them.
final List<KitPart> _dockParts = <KitPart>[
  for (final (id, label) in const <(String, String)>[
    (DockPart.launcher, 'Launcher'),
    (DockPart.stacks, 'Folders and files'),
    (DockPart.trash, 'Trash'),
    (DockPart.divider, 'Separator'),
  ])
    KitPart(
      id: id,
      label: label,
      single: !DockPart.repeats(id),
      hosts: const <KitHostKind>{KitHostKind.dock},
      densities: const <KitDensity>{KitDensity.tile},
      build: (context, part) => const SizedBox.shrink(),
    ),
];

/// Safe to call from every dock.
void registerDockParts() => kitParts.register(_dockParts);
