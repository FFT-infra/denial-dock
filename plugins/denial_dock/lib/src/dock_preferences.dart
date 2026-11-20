import 'package:flutter/foundation.dart';

enum DockVisibilityMode { always, smart, handle }

@immutable
class DockPreferences {
  const DockPreferences({
    this.iconSize = 48.0,
    this.maxScale = 1.6,
    this.magnificationRadius = 140.0,
    this.liftRatio = 0.25,
    this.capsulePadding = 8.0,
    this.itemSpacing = 8.0,
    this.pinnedAppIds = const <String>[
      'org.gnome.Nautilus.desktop',
      'org.gnome.Terminal.desktop',
      'firefox.desktop',
      'google-chrome.desktop',
      'code.desktop',
      'org.kde.dolphin.desktop',
      'org.kde.konsole.desktop',
    ],
    this.visibilityMode = DockVisibilityMode.always,
  });

  final double iconSize;
  final double maxScale;
  final double magnificationRadius;
  final double liftRatio;
  final double capsulePadding;
  final double itemSpacing;
  final List<String> pinnedAppIds;
  final DockVisibilityMode visibilityMode;

  /// Total resting thickness of the dock capsule including vertical padding.
  double get restingThickness => iconSize + (capsulePadding * 2);

  /// Maximum visual excursion headroom for hover magnification and bounce.
  double get visualHeadroom {
    final grow = iconSize * (maxScale - 1.0);
    final lift = iconSize * liftRatio;
    final bounce = iconSize * 0.4;
    return grow + lift + bounce + 48.0; // Extra room for continuous name label
  }

  DockPreferences copyWith({
    double? iconSize,
    double? maxScale,
    double? magnificationRadius,
    double? liftRatio,
    double? capsulePadding,
    double? itemSpacing,
    List<String>? pinnedAppIds,
    DockVisibilityMode? visibilityMode,
  }) {
    return DockPreferences(
      iconSize: iconSize ?? this.iconSize,
      maxScale: maxScale ?? this.maxScale,
      magnificationRadius: magnificationRadius ?? this.magnificationRadius,
      liftRatio: liftRatio ?? this.liftRatio,
      capsulePadding: capsulePadding ?? this.capsulePadding,
      itemSpacing: itemSpacing ?? this.itemSpacing,
      pinnedAppIds: pinnedAppIds ?? this.pinnedAppIds,
      visibilityMode: visibilityMode ?? this.visibilityMode,
    );
  }
}
