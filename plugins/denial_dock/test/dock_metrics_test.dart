import 'package:denial_dock/src/dock_look.dart';
import 'package:denial_dock/src/dock_metrics.dart';
import 'package:denial_dock/src/dock_settings.dart';

/// What a look of the shell says about its panels, as the kit's presets
/// have it. The kit's own class needs Flutter, which these tests run
/// without, so its values are written out here.
class _Style {
  const _Style(
    this.id, {
    this.cornerScale = 1,
    this.borderWidth = 1,
    this.accentBorder = false,
    this.opaque = false,
    this.shadow = 1,
  });

  final String id;
  final double cornerScale;
  final double borderWidth;
  final bool accentBorder;
  final bool opaque;
  final double shadow;

  bool get square => cornerScale == 0;
}

const List<_Style> _styles = <_Style>[
  _Style('denial'),
  _Style('mac'),
  _Style('soft', cornerScale: 0.6, opaque: true, shadow: 0.6),
  _Style(
    'terminal',
    cornerScale: 0,
    borderWidth: 2,
    accentBorder: true,
    opaque: true,
    shadow: 0,
  ),
];

/// The capsule's preset under [style], put together as the dock does it.
DockLook _capsule(_Style style) {
  final metrics = DockMetrics.preset(style.id);
  return DockLook.styled(
    DockLook.fitted(
      DockLook.preset(style.id),
      padding: metrics.padding,
      gap: metrics.gap,
      endInset: metrics.endInset,
    ),
    borderWidth: style.borderWidth,
    accentBorder: style.accentBorder,
    opaque: style.opaque,
    shadow: style.shadow,
  );
}

bool _near(double a, double b) => (a - b).abs() < 1e-9;

void main() {
  _expect(
    DockMetrics.presets.keys.toSet().containsAll(_styles.map((s) => s.id)) &&
        DockMetrics.presets.length == _styles.length,
    'every look has metrics, and no look is left over',
  );
  _expect(
    identical(DockMetrics.preset(null), DockMetrics.denial) &&
        identical(DockMetrics.preset('someday'), DockMetrics.denial),
    'an unknown look takes Denial\'s',
  );

  for (final style in _styles) {
    final look = _capsule(style);
    for (final shape in DockShape.values) {
      final m = DockMetrics.preset(style.id).shaped(shape);
      final at = '${style.id}/${shape.name}';

      _expect(
        m.iconSize >= DockMetrics.minIconSize &&
            m.iconSize <= DockMetrics.maxIconSize &&
            m.baseIconSize == m.iconSize,
        '$at icon size',
      );
      _expect(
        m.padding >= DockLook.minPadding &&
            m.padding <= DockLook.maxPadding &&
            m.gap >= DockLook.minGap &&
            m.gap <= DockLook.maxGap &&
            m.endInset >= 0,
        '$at spacing',
      );
      _expect(
        m.magnifyAmount >= 0 &&
            m.magnifyAmount <= 1 &&
            m.maxScale >= 1 &&
            m.maxScale <= DockSettings.maxScale &&
            (m.magnify || m.maxScale == 1),
        '$at magnification',
      );
      // The marker lies between the plate's edge and the icon.
      _expect(
        m.markerSize > 0 &&
            m.markerLength >= m.markerSize &&
            m.markerFrontStretch >= 1 &&
            m.markerInset - m.markerSize / 2 >= 0 &&
            m.markerInset + m.markerSize / 2 <= m.padding,
        '$at marker',
      );
      for (final dark in const [true, false]) {
        final shade = dark ? 'dark' : 'light';
        final rest = m.markerAlphaFor(dark: dark);
        final front = m.markerAlphaFor(dark: dark, front: true);
        _expect(
          rest > 0 && rest <= 1 && front >= rest && front <= 1,
          '$at marker opacity, $shade',
        );
        final divider = m.dividerAlphaFor(dark: dark);
        _expect(
          divider == null || (divider > 0 && divider <= 1),
          '$at divider opacity, $shade',
        );
      }
      _expect(
        m.dividerSpan >= 1 && m.dividerLength > 0 && m.dividerLength <= 1,
        '$at divider',
      );
      _expect(
        m.pressScale > 0.8 && m.pressScale <= 1,
        '$at press',
      );
      final size = m.labelFontSize;
      _expect(
        m.labelGap >= 0 &&
            (size == null || (size >= 10 && size <= 16)) &&
            m.labelWeight >= 100 &&
            m.labelWeight <= 900 &&
            m.labelWeight % 100 == 0,
        '$at label',
      );
      _expect(
        m.menuWidth >= 160 &&
            m.menuRowHeight >= 20 &&
            m.menuRadius >= 0 &&
            m.menuRowRadius >= 0 &&
            m.menuSeparator >= 1,
        '$at menu',
      );
      _expect(m.taskWidth > m.iconSize, '$at task button');

      // A look of square corners has none anywhere, and nothing with a
      // tail.
      if (style.square) {
        _expect(
          m.menuRadius == 0 &&
              m.menuRowRadius == 0 &&
              !m.menuTail &&
              m.label != DockLabelShape.bubble &&
              look.effectiveRadius * style.cornerScale == 0,
          '$at square corners',
        );
      }
      // A look of opaque panels blurs nothing, fills solid, and does not
      // grow its icons: it lights them up.
      if (style.opaque) {
        _expect(look.blur == 0 && look.opacity == 1, '$at solid plate');
        _expect(!m.magnify && m.highlight, '$at lights icons up');
      }
      // A bar is a taskbar under every look.
      if (shape == DockShape.bar) {
        _expect(
          !m.magnify &&
              m.highlight &&
              m.activePlate &&
              m.indicator == DockIndicatorStyle.segments &&
              _near(m.markerInset, m.markerSize / 2),
          '$at taskbar',
        );
      } else {
        _expect(
          identical(m, DockMetrics.preset(style.id)),
          '$at a floating dock keeps the preset',
        );
      }
    }

    // The capsule takes its spacing from the metrics and its plate holds
    // the icons with room to spare.
    final m = DockMetrics.preset(style.id);
    _expect(
      look.padding == m.padding &&
          look.gap == m.gap &&
          look.endInset == m.endInset &&
          look.endPadding >= look.padding,
      '${style.id} capsule spacing',
    );
    _expect(
      look.borderWidth >= DockLook.minBorderWidth &&
          look.borderWidth <= DockLook.maxBorderWidth &&
          look.shadow >= 0 &&
          look.shadow <= 1 &&
          look.accentBorder == style.accentBorder,
      '${style.id} capsule line and shadow',
    );
  }

  // The macOS look, as measured on the real Dock: a 65 pt plate, icons on
  // a 48.5 pt pitch, 35.5 pt between the icons either side of a divider, a
  // 4 pt marker 6 pt above the plate's edge, a 47 pt divider.
  const mac = DockMetrics.mac;
  _expect(_near(mac.iconSize + mac.padding * 2, 65), 'mac plate');
  _expect(_near(mac.iconSize + mac.gap, 48.5), 'mac pitch');
  _expect(_near(mac.gap * 2 + mac.dividerSpan, 35.5), 'mac divider room');
  _expect(mac.markerSize == 4 && mac.markerInset == 6, 'mac marker');
  _expect(
    (65 * mac.dividerLength - 47).abs() < 0.5,
    'mac divider length',
  );
  _expect(
    mac.markerAlphaFor(dark: true, front: true) ==
        mac.markerAlphaFor(dark: true),
    'mac marks the application in front like any other',
  );
  _expect(
    mac.label == DockLabelShape.capsule && !mac.menuTail,
    'mac draws no tails',
  );
  _expect(
    mac.menuRowHeight == 24 && mac.menuRadius == 11 && mac.menuSeparator == 11,
    'mac menu',
  );
  // Its spacing follows its icons; the others keep theirs.
  _expect(
    _near(mac.spacingScale(18), 0.5) && mac.spacingScale(36) == 1,
    'mac spacing scales',
  );
  _expect(
    DockMetrics.denial.spacingScale(24) == 1 &&
        DockMetrics.soft.spacingScale(24) == 1 &&
        DockMetrics.terminal.spacingScale(24) == 1,
    'the other looks keep their spacing',
  );

  // With nothing set, every value is the look's.
  const defaults = DockSettings.defaults;
  for (final style in _styles) {
    final preset = DockMetrics.preset(style.id);
    final now = defaults.metricsFor(style.id);
    _expect(
      now.iconSize == preset.iconSize &&
          now.magnify == preset.magnify &&
          now.magnifyAmount == preset.magnifyAmount &&
          now.indicator == preset.indicator &&
          now.highlight == preset.highlight &&
          now.taskTitles == preset.taskTitles,
      '${style.id} follows its look',
    );
  }

  // What the user sets holds under every look, and only that.
  final sized = defaults.copyWith(iconSize: 56);
  _expect(
    sized.chosen.length == 1 && sized.chosen.contains(DockMetrics.iconSizeKey),
    'setting the size chooses the size alone',
  );
  for (final style in _styles) {
    final preset = DockMetrics.preset(style.id);
    final now = sized.metricsFor(style.id);
    _expect(now.iconSize == 56, '${style.id} keeps the chosen size');
    _expect(
      now.magnify == preset.magnify &&
          now.magnifyAmount == preset.magnifyAmount &&
          now.indicator == preset.indicator &&
          now.highlight == preset.highlight &&
          now.padding == preset.padding &&
          now.gap == preset.gap &&
          now.markerSize == preset.markerSize &&
          now.menuRowHeight == preset.menuRowHeight &&
          now.baseIconSize == preset.iconSize,
      '${style.id} leaves the rest on the look',
    );
  }
  final still = defaults.copyWith(magnification: false);
  final marked = defaults.copyWith(indicatorStyle: DockIndicatorStyle.dashes);
  for (final style in _styles) {
    final preset = DockMetrics.preset(style.id);
    _expect(
      !still.metricsFor(style.id).magnify &&
          still.metricsFor(style.id).iconSize == preset.iconSize &&
          still.metricsFor(style.id).indicator == preset.indicator,
      '${style.id} magnification off, the rest follows',
    );
    _expect(
      marked.metricsFor(style.id).indicator == DockIndicatorStyle.dashes &&
          marked.metricsFor(style.id).magnify == preset.magnify &&
          marked
                  .metricsFor(style.id, shape: DockShape.bar)
                  .indicator ==
              DockIndicatorStyle.dashes,
      '${style.id} keeps the chosen marker, on a bar too',
    );
  }
  // A change elsewhere chooses nothing, and a choice can be given back.
  _expect(
    defaults.copyWith(showTrash: false).chosen.isEmpty &&
        sized.copyWith(showTrash: false).chosen.length == 1,
    'other settings choose nothing',
  );
  final back = sized.following(DockMetrics.iconSizeKey);
  _expect(
    back.chosen.isEmpty &&
        back.metricsFor('mac').iconSize == DockMetrics.mac.iconSize &&
        back.metricsFor('soft').iconSize == DockMetrics.soft.iconSize,
    'a value given back follows the look again',
  );

  // The overrides kept with the capsule's: one key moves one value.
  final lit = defaults.copyWith(
    look: const {DockMetrics.highlightKey: true, 'radius': 12},
  );
  _expect(
    lit.metricsFor('denial').highlight &&
        lit.metricsFor('denial').magnify == DockMetrics.denial.magnify &&
        lit.metricsFor('denial').iconSize == DockMetrics.denial.iconSize &&
        lit.lookFor('denial').radius == 12 &&
        lit.lookFor('denial').gap == DockLook.denial.gap,
    'a highlight override changes the highlight alone',
  );
  final titled = defaults.copyWith(
    look: const {DockMetrics.taskTitlesKey: true, 'shape': 'bar'},
  );
  _expect(
    titled.metricsFor('soft').taskTitles &&
        titled.metricsFor('soft').activePlate &&
        !defaults.metricsFor('soft').taskTitles,
    'titles are off until asked for',
  );
  // Values of the wrong kind keep the look's; numbers are clamped.
  final wild = DockMetrics.resolve(DockMetrics.mac, const {
    'iconSize': 'big',
    'magnify': 1,
    'magnifyAmount': double.nan,
    'indicator': 7,
    'highlight': 'yes',
    'taskTitles': null,
  });
  _expect(
    wild.iconSize == DockMetrics.mac.iconSize &&
        wild.magnify == DockMetrics.mac.magnify &&
        wild.magnifyAmount == DockMetrics.mac.magnifyAmount &&
        wild.indicator == DockMetrics.mac.indicator &&
        wild.highlight == DockMetrics.mac.highlight &&
        !wild.taskTitles,
    'garbage keeps the look',
  );
  final clamped = DockMetrics.resolve(DockMetrics.mac, const {
    'iconSize': 400,
    'magnifyAmount': -3,
    'indicator': 'someday',
  });
  _expect(
    clamped.iconSize == DockMetrics.maxIconSize &&
        clamped.magnifyAmount == 0 &&
        clamped.maxScale == 1 &&
        clamped.indicator == DockMetrics.mac.indicator,
    'numbers are clamped, unknown names ignored',
  );

  // A file from before the looks had metrics: what is still the old
  // default follows the look, what differs is the user's.
  final old = DockSettings.fromJson(const {
    'iconSize': 48,
    'magnification': true,
    'magnificationAmount': 0.6,
    'indicatorStyle': 'dot',
  });
  _expect(old.chosen.isEmpty, 'old defaults follow the look');
  _expect(
    old.metricsFor('terminal').iconSize == DockMetrics.terminal.iconSize &&
        !old.metricsFor('terminal').magnify,
    'and take the look\'s values',
  );
  final older = DockSettings.fromJson(const {
    'iconSize': 56,
    'magnification': false,
    'magnificationAmount': 0.3,
    'showIndicators': false,
  });
  _expect(
    older.chosen.length == 4 &&
        older.metricsFor('mac').iconSize == 56 &&
        !older.metricsFor('mac').magnify &&
        older.metricsFor('mac').magnifyAmount == 0.3 &&
        older.metricsFor('mac').indicator == DockIndicatorStyle.none,
    'old choices stay chosen',
  );
  // A file that names its choices is believed, default-valued or not.
  final named = DockSettings.fromJson(const {
    'iconSize': 48,
    'chosen': ['iconSize', 7],
  });
  _expect(
    named.chosen.length == 1 && named.metricsFor('mac').iconSize == 48,
    'a named choice holds at the old default too',
  );
  _expect(
    DockSettings.fromJson(const {'iconSize': 56, 'chosen': <String>[]})
            .metricsFor('mac')
            .iconSize ==
        DockMetrics.mac.iconSize,
    'and an empty list means none',
  );

  // A bar asked for through the layout is a taskbar at once.
  final bar = defaults.withLayout(const {'shape': 'bar'});
  _expect(
    !bar.metricsFor('denial').magnify &&
        bar.metricsFor('denial').activePlate &&
        bar.layoutJson('denial')['magnification'] == false &&
        defaults.layoutJson('denial')['magnification'] == true &&
        defaults.layoutJson('soft')['magnification'] == false,
    'the layout reports what the look and the shape give',
  );

  _expect(
    DockIndicatorStyle.parse(DockIndicatorStyle.pill.key) ==
        DockIndicatorStyle.pill,
    'the pill marker is stored by name',
  );
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
