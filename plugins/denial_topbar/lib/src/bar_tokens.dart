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
library;

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

  /// Control Centre: `width: 300`, `x: screen - width - 10`, `y: barH + 6`.
  ///
  /// shell27 lays it out as a 4-column bento grid (`ccLayout`): `ccCellH: 66`,
  /// `ccGap: 6` between columns, `ccRowGap: 12` between rows, and
  /// `ccSliderGap: 16` around a slider row. Tiles are radius 34, the two
  /// slider tiles 26, and a 1×1 control is drawn as a 63 pt circle centred in
  /// its cell. The macOS-style slab pads the 300 pt grid by 12.
  static const double controlCenterWidth = 300;
  static const double controlCenterInset = 10;
  static const double controlCenterMargin = 12;
  static const double ccCellHeight = 66;
  static const double ccGap = 6;
  static const double ccRowGap = 12;
  static const double ccSliderGap = 16;
  static const double ccTileRadius = 34;
  static const double ccSliderTileRadius = 26;
  static const double ccCircle = 63;
  static const double ccButtonSize = 40;
  static const double ccSmallGlyph = 21;
  static const double ccGlyphRatio = 0.46;
  static const double ccLabelInset = 15;
  static const double ccSliderTop = 28;
  static const double ccSliderTrackX = 28;
  static const double ccSliderTrackW = 26;
  static const double ccSliderTrackHeight = 4;
  static const double ccSliderKnobWidth = 21;
  static const double ccSliderKnobHeight = 14;

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

  /// Compact Now Playing is 133 wide (20 pt cover plus the waveform).
  static const double islandMediaMinWidth = 133;
  static const double islandMediaMaxWidth = 200;
  static const double islandMediaTextPad = 58;
  static const double islandNoticeMinWidth = 140;
  static const double islandNoticeMaxWidth = 240;
  static const double islandNoticeTextPad = 62;

  /// macOS 27 motion: expand `.spring(0.46, bounce 0.24)`, collapse 0.36 s.
  static const Duration islandWidth = Duration(milliseconds: 250);
  static const Duration islandBorder = Duration(milliseconds: 180);
  static const Duration islandExpand = Duration(milliseconds: 460);
  static const Duration islandCollapse = Duration(milliseconds: 360);

  static const double islandPopupWidth = 340;
  static const double islandPopupRadius = 32;
  static const double islandPopupPadding = 16;

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
