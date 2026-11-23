/// Measured constants for the macOS-style bar.
///
/// Every value is transcribed from shell27 `panels/MacBar.qml` (the closest
/// reference), cross-checked against 0-ss/MacShell `MacBar.qml`, darkshadow
/// `Bar.qml` and Apple's HIG. Changing one here changes the whole bar; nothing
/// below is invented per widget.
///
/// Sources:
/// - shell27 `panels/MacBar.qml`: bar 28, `leftRow.x: 8`, item `width + 20`,
///   hover plate `width - 2` × `height - 6` radius 12, menu 260 wide at
///   `barH + 3`, rows 26 high radius 12, Control Centre 300 wide at
///   `screen - 300 - 10`, popovers `barH + 6`, `fullW` 320/330/250
/// - 0-ss/MacShell `MacBar.qml` (MIT): item hover `height - 6`, radius 6
/// - Apple HIG "The menu bar": active app name in bold
/// - NextKDE `ControlCenterPanel.qml`, `ControlCenterCard.qml` and
///   `bar/controlcenter/*.qml`: the panel's card grid and its card geometry
library;

import 'dart:math' as math;

abstract final class BarTokens {
  // ── Strip ────────────────────────────────────────────────────────────────
  /// Bar height. shell27 ships `barHeight: 28`; MacShell matches. The HIG's
  /// 24 pt is the macOS system value, but this bar follows the reference.
  static const double height = 28;

  /// Left row inset. shell27 `leftRow.x: 8`.
  static const double insetLeft = 8;

  /// Right row inset. shell27 `rightRow.anchors.rightMargin: 6`.
  static const double insetRight = 6;

  /// Space below the strip the surface reserves for the floating shadow.
  static const double shadowExtent = 12;

  /// Gap between a floating capsule and the screen edge.
  static const double floatingMargin = 6;

  /// Radius of the floating capsule.
  static const double floatingRadius = height / 2;

  /// Attached: the content row keeps the bar's own insets.
  static const double insetAttached = insetLeft;
  static const double insetFloating = insetLeft + floatingMargin;

  // ── Type ─────────────────────────────────────────────────────────────────
  /// Menu titles and the clock: shell27 `font.pixelSize: 14`.
  static const double menuFontSize = 14;

  /// Menu rows: shell27 dropdown `font.pixelSize: 13`.
  static const double menuRowFontSize = 13;

  /// Shortcut column: shell27 `font.pixelSize: 12`.
  static const double shortcutFontSize = 12;

  /// Captions inside cards.
  static const double captionFontSize = 11;

  // ── Items ────────────────────────────────────────────────────────────────
  /// The logo slot. shell27 `width: 30` with a 15 pt mark.
  static const double systemMenuWidth = 30;
  static const double systemMenuGlyph = 15;

  /// Item box: `height: 28`, title width `implicitWidth + 20`.
  static const double itemHeight = height;
  static const double itemPadding = 10;

  /// Hover plate inside an item: `width - 2`, `height - 6`, radius 12.
  static const double itemInsetX = 1;
  static const double itemInsetY = 3;
  static const double itemRadius = 12;

  /// Hover fills, from shell27 `bpal.hover`: black 0.09 on a light bar,
  /// white 0.14 on a dark one.
  static const double itemHoverAlphaLight = 0.09;
  static const double itemHoverAlphaDark = 0.14;

  /// Right row spacing. shell27 `spacing: 6`.
  static const double clusterGap = 6;

  /// Status items. shell27: tray 26, Wi-Fi / bell / volume / Bluetooth 28,
  /// Control Centre 38.
  static const double statusSpacing = 6;
  static const double statusIconSize = 16;
  static const double statusGlyphSize = 16;
  static const double statusCellWidth = 28;
  static const double trayCellWidth = 26;
  static const double controlCentreWidth = 38;

  /// The clock is `clockText.implicitWidth + 16`.
  static const double clockPadding = 8;

  // ── Menus ────────────────────────────────────────────────────────────────
  /// Dropdown: shell27 `width: 260`, `height: menuCol.height + 14`, radius 14,
  /// column at `x: 6; y: 7` with `width: parent.width - 12`.
  static const double menuWidth = 260;
  static const double menuRadius = 14;
  static const double menuColumnInsetX = 6;
  static const double menuColumnInsetY = 7;

  /// Dropdown position: `x: menuDropX - 4`, `y: barH + 3`.
  static const double menuDropOffsetX = -4;
  static const double menuDropOffsetY = 3;

  /// A dropdown row: `height: 26`, hover radius 12, label at `x: 12`
  /// (`x: 28` when the menu has a leading glyph column), shortcut right 12.
  static const double menuRowHeight = 26;
  static const double menuRowRadius = 12;
  static const double menuRowTextInset = 12;
  static const double menuRowLeadInset = 28;
  static const double menuRowGlyphInset = 10;
  static const double menuRowGlyphSize = 15;
  static const double menuRowShortcutInset = 12;

  /// Separator: `height: 11`, line `x: 8`, `width: parent.width - 16`.
  static const double menuSeparatorHeight = 11;
  static const double menuSeparatorInset = 8;

  // ── Popovers ─────────────────────────────────────────────────────────────
  /// Every popover hangs at `barH + 6`; the dropdown sits at `barH + 3`.
  static const double popoverGap = 6;
  static const double popoverRadius = 26;

  /// shell27 `fullW`: Wi-Fi 320, volume 330, Bluetooth 320, keyboard 250.
  static const double wifiPopoverWidth = 320;
  static const double volumePopoverWidth = 330;
  static const double bluetoothPopoverWidth = 320;
  static const double keyboardPopoverWidth = 250;

  /// Control Centre, from NextKDE `ControlCenterPanel.qml`.
  ///
  /// The panel is `max(296, min(336, screenW - 24))` wide with 20 pt of inset
  /// on every side, so the content is `width - 40`. The cards sit on a fixed
  /// coordinate grid rather than a packer: the connectivity pills take
  /// `round((content - 8) * 137 / 288)` of the top-left, the media card takes
  /// the rest of that row, five 52 pt squares share the next row at 9 pt
  /// spacing, and the two sliders span the full width underneath.
  static double controlCenterWidthFor(double screenWidth) =>
      math.max(296, math.min(336, screenWidth - 24));
  static const double controlCenterWidth = 336;
  static const double controlCenterInset = 10;
  static const double controlCenterMargin = 20;

  /// Content width the card grid is laid out against.
  static const double ccContentWidth = controlCenterWidth - controlCenterMargin * 2;

  /// Connectivity pill width: `round((content - 8) * 137 / 288)`.
  static const double ccConnectivityWidth = 137;
  static const double ccSquareGap = 9;

  /// Card geometry. The pills are near-circles at 59 high; the media card is
  /// 25; a square is 26; a slider card is 19.
  static const double ccPillHeight = 59;
  static const double ccPillRadius = 29.5;
  static const double ccMediaHeight = 127;
  static const double ccMediaRadius = 25;
  static const double ccSquareRadius = 26;
  static const double ccSliderHeight = 57;
  static const double ccSliderRadius = 19;

  /// Row tops: the pills at 20 and 87, the squares at 155, brightness at 217,
  /// sound at 282. The panel is 359 high.
  static const double ccPillTop = 20;
  static const double ccPillSecondTop = 87;
  static const double ccSquareTop = 155;
  static const double ccBrightnessTop = 217;
  static const double ccSoundTop = 282;
  static const double ccPanelHeight = 359;

  /// Pill contents: a 39 pt disc 10 in from the left, 20 pt glyph, text at 58,
  /// a 14 pt chevron 8 in from the right.
  static const double ccDisc = 39;
  static const double ccDiscInset = 10;
  static const double ccDiscGlyph = 20;
  static const double ccPillTextLeft = 58;
  static const double ccPillTextRight = 22;
  static const double ccChevronInset = 8;
  static const double ccChevronSize = 14;

  /// Square contents: a 22 pt glyph, hover 1.06, press 0.91.
  static const double ccSquareGlyph = 22;

  /// Slider card: label at (14, 8), percent 9 pt at right 30, chevron 15 pt at
  /// right 13 / top 5, the track 5 pt tall with a 30 × 16 thumb.
  static const double ccSliderLabelLeft = 14;
  static const double ccSliderLabelTop = 8;
  static const double ccSliderPercentRight = 30;
  static const double ccSliderChevronRight = 13;
  static const double ccSliderChevronTop = 5;
  static const double ccSliderChevronSize = 15;
  static const double ccSliderHeight2 = 30;
  static const double ccSliderTrackHeight = 5;
  static const double ccSliderThumbWidth = 30;
  static const double ccSliderThumbHeight = 16;
  static const double ccBrightnessTrackLeft = 31;
  static const double ccBrightnessTrackRight = 31;
  static const double ccSoundTrackLeft = 36;
  static const double ccSoundTrackRight = 17;
  static const double ccSliderTrackBottom = 8;

  /// Sub-pages, from NextKDE `SubmenuCard.qml` and its page files.
  static const double ccSubmenuHeaderHeight = 28;
  static const double ccSubmenuDividerGap = 9;
  static const double ccWifiPageHeight = 360;
  static const double ccBluetoothPageHeight = 340;
  static const double ccBrightnessPageHeight = 280;
  static const double ccSoundPageHeight = 420;

  /// Generic panel card.
  static const double panelGap = 6;
  static const double panelRadius = 14;
  static const double panelMaxWidth = 380;
  static const double panelPadding = 14;

  // ── Island ───────────────────────────────────────────────────────────────
  /// macOS 27: resting capsule 58 × 31 at 8.5 pt from the edge, expanded
  /// radius 32 with 16 pt padding [S27]. A 28 pt strip cannot hold 31, so the
  /// pill takes what the strip can take and keeps the expanded geometry.
  static const double islandHeight = 31;
  static const double islandMinHeight = 20;
  static const double islandIdleWidth = 58;
  static const double islandEdgeInset = 8.5;

  /// The notice keeps its summary, so the pill widens with the text between
  /// these bounds; the text sits beside a 14 pt dot and a close chip.
  static const double islandNoticeMinWidth = 140;
  static const double islandNoticeMaxWidth = 240;

  /// macOS 27 motion: expand `.spring(0.46, bounce 0.24)`, collapse 0.36 s.
  static const Duration islandWidth = Duration(milliseconds: 250);
  static const Duration islandBorder = Duration(milliseconds: 180);
  static const Duration islandExpand = Duration(milliseconds: 460);
  static const Duration islandCollapse = Duration(milliseconds: 360);

  /// meniscus `Motion.swift` [S35]: the pointer has to rest 180 ms before the
  /// island opens, so a cursor crossing the notch cannot flash it open, and
  /// leaving gives 120 ms of grace before it closes.
  static const Duration islandHoverIntent = Duration(milliseconds: 180);
  static const Duration islandLeaveGrace = Duration(milliseconds: 120);

  /// Content enters at `.smooth(0.32)` after a 0.14 s wait, fading up from a
  /// 12 pt blur and 0.94 scale; it leaves at `.smooth(0.14)` [S35].
  static const Duration islandContentIn = Duration(milliseconds: 320);
  static const Duration islandContentOut = Duration(milliseconds: 140);
  static const Duration islandContentDelay = Duration(milliseconds: 140);
  static const double islandContentBlur = 12;
  static const double islandContentScale = 0.94;

  /// Compact Now Playing: a 20 pt cover at the 24% radius every island
  /// element uses, then the waveform, 133 wide overall [S27].
  static const double islandCompactCover = 20;
  static const double islandCompactMediaWidth = 133;

  /// Expanded card. macOS 27 measures 32 pt continuous corners, identical on
  /// all four sides, with 16 pt of content padding [S27]. meniscus
  /// `IslandMetrics` puts its player cover at 44 [S36]. The media card takes
  /// darkshadow `DynIsland.qml`'s 470 and the banner takes meniscus's 360
  /// banner width, so each type keeps the width its own content was measured
  /// at.
  static const double islandPopupRadius = 32;
  static const double islandPopupPadding = 16;
  static const double islandPlayerCover = 44;
  static const double islandMediaWidth = 470;

  /// darkshadow fixes each card's size so the shape can morph to a known
  /// rect: the player is 470 × 184, a notification 440 × 96, the charge face
  /// 340 wide. meniscus caps the content height at 132 [S36]; the media card
  /// spends its extra height on the transport row at `y: 134`.
  static const double islandMediaHeight = 184;
  static const double islandBannerWidth = 360;
  static const double islandBannerHeight = 96;

  /// darkshadow's charge face is 340 wide with the bolt, the number and the
  /// fill; the expanded card keeps that width.
  static const double islandChargeWidth = 340;
  static const double islandChargeHeight = 96;

  /// meniscus's banner: 8 pt inset, 30 pt app tile, 10 pt gap [S36].
  static const double islandBannerInset = 8;
  static const double islandBannerTile = 30;
  static const double islandBannerGap = 10;

  /// Gap between the strip and the card, darkshadow `bh + 8`.
  static const double islandCardGap = 8;

  static const Duration islandAutoCollapse = Duration(milliseconds: 3500);
  static const Duration islandNoticeHold = Duration(milliseconds: 5000);

  static const int islandFill = 0xff000000;
  static const double islandBorderAlpha = 0.18;

  // ── Palette ──────────────────────────────────────────────────────────────
  /// shell27 `bpal`: the bar's ink and washes, light / dark.
  static const int inkLight = 0xff1d1d1f;
  static const int inkDark = 0xffffffff;
  static const double inkSecondaryLight = 0.55;
  static const double inkSecondaryDark = 0.62;
  static const double inkTertiaryLight = 0.32;
  static const double inkTertiaryDark = 0.34;

  /// Separators and tracks: black 0.12 / white 0.14.
  static const double separatorLight = 0.12;
  static const double separatorDark = 0.14;

  /// The optional plate, from shell27 `bpal.content`.
  static const int plateLight = 0xfff5f5f7;
  static const int plateDark = 0xff1e1e1e;
  static const double plateOpacityDefault = 0.55;
  static const double plateOpacityMin = 0.05;
  static const double plateOpacityMax = 0.85;

  /// Luminance threshold that decides the ink when no plate is drawn.
  static const double plateLuminanceThreshold = 0.5;

  /// The feather under a clear bar is `barH + 14` tall.
  static const double featherExtent = 14;
}
