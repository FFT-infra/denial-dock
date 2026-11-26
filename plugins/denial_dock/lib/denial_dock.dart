@Plugin()
library;

import 'package:denial_flutter_sdk/actions.dart';
import 'package:denial_flutter_sdk/surfaces.dart';
import 'package:denial_sdk/composition.dart';
import 'package:denial_shell_kit/kit_style.dart';
import 'package:flutter/widgets.dart';

import 'src/dock_container.dart';
import 'src/dock_hotkeys.dart';

/// A floating, macOS-style dock for Denial.
///
/// The compositor reserves only the top bar, so the dock sits above windows and
/// retracts while a window covers its strip. Magnification uses the NextKDE
/// smootherstep wave with real layout growth.
@Provides(ShellSurface)
final class DockPlugin implements ShellSurface {
  const DockPlugin();

  @override
  String get id => 'denial_dock.panel';

  @override
  ShellSurfaceLayer get layer => ShellSurfaceLayer.aboveWindows;

  @override
  ShellSurfacePlacement? place(ShellSurfaceEnvironment environment) {
    // A dock switched off in the shell's settings stays placed and draws
    // nothing. Returning null here would drop the surface, and the host
    // places surfaces again only when its own environment changes, so the
    // dock would not come back until then.
    if (environment.output.inputOnly) {
      return null;
    }

    return ShellSurfacePlacement(
      bounds: environment.output.logicalRect,
      // The capsule is glass, so it fades its backdrop and foreground through
      // ShellBackdropBlur.opacity instead of the SDK's whole-surface fade.
      fade: ShellSurfaceFade.custom,
      occupiesDesktop: false,
      visible:
          !environment.locked &&
          !environment.wallpaperSelectorVisible &&
          (!environment.fullscreen ||
              environment.overview ||
              environment.desktopVisible),
    );
  }

  @override
  Widget build(BuildContext context, {required ShellSurfaceContext surface}) {
    // Switched off, the surface holds no widget and so no input region:
    // nothing shows and every touch falls through to the windows.
    return ValueListenableBuilder<bool>(
      key: ValueKey(surface.environment.output.monitorId),
      valueListenable: kitDockEnabled,
      builder: (context, shown, _) => shown
          ? KitThemed(
              child: DockContainer(
                monitorId: surface.environment.output.monitorId,
                services: surface.services,
                environment: surface.environment,
              ),
            )
          : const SizedBox.shrink(),
    );
  }
}

/// Shortcut targets for the dock's first applications, the way Windows binds
/// Win+1 to Win+9. They do nothing until the user gives one a shortcut.
abstract base class _ActivateDockApp implements ShellAction {
  const _ActivateDockApp(this.slot);

  final int slot;

  @override
  String get id => 'denial_dock.activate_$slot';

  @override
  String get provider => 'Dock';

  bool _chinese(BuildContext context) =>
      Localizations.localeOf(context).languageCode == 'zh';

  @override
  String label(BuildContext context) => _chinese(context)
      ? '激活 Dock 第 $slot 个应用'
      : 'Activate Dock application $slot';

  @override
  String description(BuildContext context) => _chinese(context)
      ? '相当于点击 Dock 上从头数第 $slot 个应用图标'
      : 'Acts as a click on application icon $slot of the Dock';

  @override
  void invoke(ShellActionContext context) =>
      DockHotkeys.activate(slot, monitorId: context.monitorId);
}

@Provides(ShellAction)
final class ActivateDockAppOne extends _ActivateDockApp {
  const ActivateDockAppOne() : super(1);
}

@Provides(ShellAction)
final class ActivateDockAppTwo extends _ActivateDockApp {
  const ActivateDockAppTwo() : super(2);
}

@Provides(ShellAction)
final class ActivateDockAppThree extends _ActivateDockApp {
  const ActivateDockAppThree() : super(3);
}

@Provides(ShellAction)
final class ActivateDockAppFour extends _ActivateDockApp {
  const ActivateDockAppFour() : super(4);
}

@Provides(ShellAction)
final class ActivateDockAppFive extends _ActivateDockApp {
  const ActivateDockAppFive() : super(5);
}

@Provides(ShellAction)
final class ActivateDockAppSix extends _ActivateDockApp {
  const ActivateDockAppSix() : super(6);
}

@Provides(ShellAction)
final class ActivateDockAppSeven extends _ActivateDockApp {
  const ActivateDockAppSeven() : super(7);
}

@Provides(ShellAction)
final class ActivateDockAppEight extends _ActivateDockApp {
  const ActivateDockAppEight() : super(8);
}

@Provides(ShellAction)
final class ActivateDockAppNine extends _ActivateDockApp {
  const ActivateDockAppNine() : super(9);
}
