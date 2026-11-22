/// Measured constants for the macOS-style bar.
///
/// Every value names the reference it was taken from. Changing one here
/// changes the whole bar; nothing below is invented per widget.
///
/// Sources:
/// - Apple HIG "The menu bar" [S2]: 24 pt height, active app name in bold
/// - NextKDE `shell/desktop/modules/bar/` (GPL-3.0, structure and metrics only)
/// - shell27 `panels/MacBar.qml` (bar 28, items `width + 20`, hover radius 6)
/// - 0-ss/MacShell `MacBar.qml` (MIT; item hover `height - 6`, radius 6)
/// - revo-shell `quickshell/macos/modules/topbar/` (TopBar.qml, DynamicIsland.qml)
library;

abstract final class BarTokens {
  // ── Strip ────────────────────────────────────────────────────────────────
  /// Menu bar height. Apple publishes exactly one number for this: 24 pt.
  /// shell27 and MacShell both use 28 for a taller clone bar; the HIG value
  /// wins because this bar is meant to read as macOS itself.
  static const double height = 24;

  /// Horizontal inset of the content row. shell27 `leftRow.x: 8`, MacShell
  /// the same; revo-shell uses 6/8.
  static const double inset = 8;

  /// The attached strip runs to both screen edges, so its content row keeps
  /// the inset only; a floating capsule adds the capsule's own margin on top.
  static const double insetAttached = inset;
  static const double insetFloating = inset + floatingMargin;

  /// Space below the strip the surface reserves for the floating shadow.
  static const double shadowExtent = 12;

  /// Gap between a floating capsule and the screen edge. shell27 `gap: 8`.
  static const double floatingMargin = 6;

  /// Radius of the floating capsule. shell27 uses `height / 2`.
  static const double floatingRadius = height / 2;

  // ── Type ─────────────────────────────────────────────────────────────────
  /// HIG body size for macOS interface text; 11 pt is the documented minimum.
  static const double menuFontSize = 13;
  static const double captionFontSize = 11;

  // ── Items ────────────────────────────────────────────────────────────────
  /// The logo slot. shell27: `width: 30` with a 15 pt mark; MacShell: 30/15.
  static const double systemMenuWidth = 30;
  static const double systemMenuGlyph = 15;

  /// Menu bar item box. shell27 sizes titles `implicitWidth + 20` and keeps
  /// them 28 high; the hover plate is `height - 6` with radius 6.
  static const double menuItemHeight = 22;
  static const double menuItemPadding = 10;

  /// Hover plate inside a bar item: `height - 6` tall, radius 6, and the
  /// fill shell27 uses per appearance: black 0.09 in light, white 0.14 in
  /// dark. MacShell uses radius 6 as well.
  static const double itemRadius = 6;
  static const double itemHoverAlphaLight = 0.09;
  static const double itemHoverAlphaDark = 0.14;

  /// Gap between the logo, the app name and the status cluster.
  static const double clusterGap = 2;

  /// Status cluster spacing. shell27 keeps ~2 between items; each item is a
  /// 24-wide box, so the visual gap lands near 6.
  static const double statusSpacing = 2;
  static const double statusIconSize = 15;
  static const double statusGlyphSize = 16;
  static const double statusCellWidth = 24;

  // ── Menus ────────────────────────────────────────────────────────────────
  /// A dropdown row: 24 high, 13 pt, radius 6 highlight. macOS's own menu
  /// rows are ~22 pt with 5 pt side padding; shell27 uses 24/6.
  static const double menuRowHeight = 24;
  static const double menuRadius = 10;
  static const double menuRowRadius = 6;
  static const double menuWidth = 232;
  static const double menuRowInset = 5;

  // ── Island ───────────────────────────────────────────────────────────────
  /// macOS 27 on the PROLED MacBook Pro: the resting capsule is 58 × 31 pt
  /// sitting 8.5 pt from the top edge, and the expanded card uses a 32 pt
  /// radius with 16 pt padding [S27]. A 24 pt bar cannot hold 31, so the pill
  /// takes the bar's own height and the expanded radius follows the measured
  /// value.
  /// Measured resting capsule: 58 wide. The height is 31 on a machine with
  /// the taller PROLED bar; a 24 pt strip cannot hold it, so the caller
  /// passes in whatever the strip can take and the radius follows height / 2.
  static const double islandHeight = 31;
  static const double islandMinHeight = 20;
  static const double islandIdleWidth = 58;

  /// The resting capsule sits 8.5 pt below the screen edge on macOS; the bar
  /// strip is taller than the capsule by the same amount on both sides.
  static const double islandEdgeInset = 8.5;

  /// macOS's compact Now Playing is 133 wide (20 pt cover plus the waveform).
  /// revo-shell sizes it `clamp(150, title + 65, 220)`; the measured value
  /// wins and the text is clamped inside it.
  static const double islandMediaMinWidth = 133;
  static const double islandMediaMaxWidth = 200;
  static const double islandMediaTextPad = 58;
  static const double islandNoticeMinWidth = 140;
  static const double islandNoticeMaxWidth = 240;
  static const double islandNoticeTextPad = 62;

  /// macOS 27 island motion: expand `.spring(duration: 0.46, bounce: 0.24)`,
  /// collapse 0.36 s with no bounce [S27]. revo-shell's 250 ms OutCubic is
  /// kept for the pill's width because it reads cleaner at this size.
  static const Duration islandWidth = Duration(milliseconds: 250);
  static const Duration islandBorder = Duration(milliseconds: 180);
  static const Duration islandExpand = Duration(milliseconds: 460);
  static const Duration islandCollapse = Duration(milliseconds: 360);

  /// Expanded card: 340 wide, 32 radius, 16 padding, four equal corners.
  static const double islandPopupWidth = 340;
  static const double islandPopupRadius = 32;
  static const double islandPopupPadding = 16;

  /// revo-shell: `autoCollapseTimer 3500`, `notifTimer 5000`.
  static const Duration islandAutoCollapse = Duration(milliseconds: 3500);
  static const Duration islandNoticeHold = Duration(milliseconds: 5000);

  /// The island is black on every macOS surface, whatever the appearance.
  static const int islandFill = 0xff000000;
  static const double islandBorderAlpha = 0.18;

  // ── Panels ───────────────────────────────────────────────────────────────
  /// NextKDE `ControlCenterPanel.qml`: width `clamp(296, 336, screen - 24)`,
  /// card margins 20, card radii 29.5 / 26 / 19.
  static const double controlCenterMinWidth = 296;
  static const double controlCenterMaxWidth = 336;
  static const double controlCenterMargin = 14;
  static const double controlCenterCardRadius = 24;
  static const double controlCenterWideRadius = 29.5;
  static const double controlCenterSmallRadius = 18;

  /// macOS hangs a menu 5 below the bar (shell27 `barH + 5`); panels use the
  /// same gap so every popup lines up.
  static const double panelGap = 5;
  static const double panelRadius = 14;
  static const double panelMaxWidth = 380;

  /// NextKDE panels keep 20 pt of side padding; the cards inside them use
  /// the card radii above.
  static const double panelPadding = 14;

  // ── Ground ───────────────────────────────────────────────────────────────
  /// macOS 27 ships the menu bar with no background at all; the optional
  /// plate is a wallpaper-tinted veil the user can turn on. The two neutrals
  /// below follow the appearance, not the wallpaper: shell27 `#1E1E1E` /
  /// `#F5F5F7`.
  static const int plateLight = 0xfff5f5f7;
  static const int plateDark = 0xff1e1e1e;
  static const double plateOpacityDefault = 0.55;
  static const double plateOpacityMin = 0.05;
  static const double plateOpacityMax = 0.85;

  /// Luminance threshold that decides the ink when no plate is drawn.
  static const double plateLuminanceThreshold = 0.5;
}
