import 'package:denial_shell_kit/kit_material.dart';

void _expect(bool ok, String what) {
  if (!ok) throw StateError(what);
}

bool _near(double a, double b, [double by = 1e-9]) => (a - b).abs() <= by;

void main() {
  // The shell snaps backdrop strength to one of 32 steps with one step as the least.
  _expect(_near(KitBlurMath.sigmaAt(1, 14), 14), 'full strength');
  _expect(
    _near(KitBlurMath.sigmaAt(1.6 / 6, 6), 6 * 9 / 32),
    '1.6 of 6 snaps to 9/32',
  );
  _expect(_near(KitBlurMath.sigmaAt(0.001, 6), 6 / 32), 'one step at least');
  _expect(KitBlurMath.sigmaAt(0, 6) == 0, 'nothing stays nothing');

  const menu = KitMaterial(fill: KitTone(0x494b53, 0.63), sigma: 13);
  const shell = KitMaterial(fill: KitTone.of(KitRole.panel));

  // Blur mode: a material with a sigma gets exactly it, whatever the level.
  for (final base in const <double>[6, 14]) {
    final plan = KitBlurMath.plan(
      menu,
      enabled: true,
      glass: false,
      base: base,
    );
    _expect(plan.direct && plan.sigma == 13, 'direct at $base');
  }
  _expect(
    KitBlurMath.plan(menu, enabled: true, glass: false, base: 6, scale: 0.5)
            .sigma ==
        6.5,
    'a caller scales the sigma',
  );

  // Glass mode: a measured material keeps its own sigma, uncapped.
  for (final base in const <double>[0, 10, 26]) {
    final lens = KitBlurMath.plan(menu, enabled: true, glass: true, base: base);
    _expect(
      lens.direct && lens.sigma == menu.sigma,
      'glass at $base leaves a measured sigma alone',
    );
  }

  // Liquid Glass mode produces a direct plan with tier-scaled strength & sigma.
  final lg = KitBlurMath.plan(
    shell,
    enabled: true,
    glass: true,
    base: 10,
    mode: KitSurfaceMode.liquidGlass,
    tier: KitTier.popover,
  );
  _expect(
    lg.direct && lg.blurs && lg.mode == KitSurfaceMode.liquidGlass && lg.sigma > 0,
    'liquid glass direct plan',
  );

  // Solid mode disables blur even when system transparency is enabled.
  final solid = KitBlurMath.plan(
    menu,
    enabled: true,
    glass: true,
    base: 14,
    mode: KitSurfaceMode.solid,
  );
  _expect(!solid.blurs && solid.sigma == 0, 'solid mode never blurs');

  // Transparency off: nothing blurs, whatever the material asks.
  for (final material in const <KitMaterial>[menu, shell]) {
    for (final glass in const <bool>[false, true]) {
      final plan = KitBlurMath.plan(
        material,
        enabled: false,
        glass: glass,
        base: 6,
      );
      _expect(!plan.blurs && plan.sigma == 0, 'off is off');
    }
  }

  // A material without a sigma follows the shell, as it always did.
  final follow = KitBlurMath.plan(shell, enabled: true, glass: false, base: 14);
  _expect(
    !follow.direct && follow.strength == 1 && follow.sigma == 14,
    'the shell blur at full',
  );
  final part = KitBlurMath.plan(
    shell,
    enabled: true,
    glass: false,
    base: 6,
    scale: 0.65,
  );
  _expect(!part.direct && part.strength == 0.65, 'a share of the shell blur');
  _expect(
    !KitBlurMath.plan(shell, enabled: true, glass: false, base: 6, scale: 0)
        .blurs,
    'a share of nothing',
  );

  // Every table has every tier in both appearances, with numbers that draw.
  for (final table in KitMaterials.all) {
    for (final tier in KitTier.values) {
      for (final dark in const <bool>[true, false]) {
        final m = table.tier(tier).of(dark: dark);
        final what = '$tier dark=$dark';
        final alpha = m.fill.alpha;
        _expect(m.fill.fixed == (alpha != null), 'fill of $what');
        _expect(alpha == null || (alpha > 0 && alpha <= 1), 'alpha of $what');
        _expect(m.sigma == null || m.sigma! > 0, 'sigma of $what');
        _expect(m.saturation >= 1 && m.saturation <= 3, 'saturation of $what');
        _expect(m.solid > 0 && m.solid <= 1, 'solid of $what');
        for (final line in <KitLine?>[m.outer, m.inner]) {
          _expect(line == null || (line.width ?? 1) > 0, 'line of $what');
        }
      }
    }
    final layout = table.cardLayout;
    _expect(
      layout.width > 0 && layout.dim > 0 && layout.dim < 1 && layout.peek > 0,
      'card layout',
    );
  }

  // The shell's table leaves everything to the theme and the look.
  for (final tier in KitTier.values) {
    final pair = KitMaterials.shell.tier(tier);
    _expect(identical(pair.dark, pair.light), 'shell $tier is one material');
    _expect(
      pair.dark.sigma == null &&
          pair.dark.strength == 1 &&
          pair.dark.saturation == 1 &&
          !pair.dark.fill.fixed &&
          pair.dark.outer == null,
      'shell $tier follows the shell',
    );
  }
  final panel = KitMaterials.shell.popover.dark;
  _expect(
    panel.radius == null &&
        panel.inner!.width == null &&
        panel.inner!.tone.role == KitRole.border &&
        panel.shadow!.byLook &&
        panel.shadow!.tone.alpha == 0.30 &&
        panel.shadow!.blur == 36 &&
        panel.shadow!.dy == 14,
    'the shell popover keeps the old card',
  );

  // The measured table, spot checked against the report it came from.
  const mac = KitMaterials.mac;
  _expect(
    mac.dock.dark.sigma == 1.6 &&
        mac.dock.dark.fill.rgb == 0x222222 &&
        mac.dock.dark.fill.alpha == 0.36 &&
        mac.dock.light.fill.rgb == 0x979797 &&
        mac.dock.light.fill.alpha == 0.25 &&
        mac.dock.dark.radius == 22 &&
        mac.dock.dark.shadow == null &&
        mac.dock.dark.inner!.edges == KitEdges.topBottom &&
        mac.dock.dark.outer!.edges == KitEdges.ends,
    'mac dock',
  );
  _expect(
    mac.popover.dark.fill.rgb == 0x454545 &&
        mac.popover.dark.sigma == 10 &&
        mac.popover.dark.outer!.width == 0.5 &&
        mac.popover.dark.inner!.width == 1 &&
        mac.popover.dark.shadow!.dy == 7 &&
        mac.menu.dark.sigma == 13 &&
        mac.menu.dark.radius == 11 &&
        mac.card.light.sigma == 12 &&
        mac.card.dark.radius == 19,
    'mac popover, menu and card',
  );
  final cards = mac.cardLayout;
  _expect(
    cards.width == 344 &&
        cards.gap == 6 &&
        cards.edge == 16 &&
        cards.peek == 8 &&
        cards.inset == 10 &&
        cards.dim == 0.20,
    'mac card layout',
  );

  // A box shadow's radius and the sigma the engine blurs it with.
  _expect(
    _near(const KitShadow(KitTone(0, 1), blur: 13, dy: 0).sigma, 8, 0.01),
    'a radius of 13 is a sigma of 8',
  );

  // copyWith replaces what it is given and can clear a line.
  final bare = mac.dock.dark.copyWith(sigma: 3, outer: () => null);
  _expect(
    bare.sigma == 3 &&
        bare.outer == null &&
        bare.inner == mac.dock.dark.inner &&
        bare.saturation == 2.0,
    'copyWith',
  );

  // Five-mode surface material resolution.
  final sysPlan = KitBlurMath.plan(
    mac.popover.dark,
    enabled: true,
    glass: true,
    base: 10,
    mode: KitSurfaceMode.system,
  );
  _expect(
    !sysPlan.direct && sysPlan.mode == KitSurfaceMode.system && sysPlan.blurs,
    'system mode delegates to ShellBackdropBlur even for sigma materials',
  );
  final lgDock = KitBlurMath.plan(
    mac.dock.dark,
    enabled: true,
    glass: true,
    base: 10,
    mode: KitSurfaceMode.liquidGlass,
    tier: KitTier.dock,
  );
  final lgPop = KitBlurMath.plan(
    mac.popover.dark,
    enabled: true,
    glass: true,
    base: 10,
    mode: KitSurfaceMode.liquidGlass,
    tier: KitTier.popover,
  );
  _expect(
    lgDock.direct &&
        lgDock.mode == KitSurfaceMode.liquidGlass &&
        lgDock.blurs &&
        lgDock.sigma < lgPop.sigma &&
        lgDock.strength < lgPop.strength,
    'liquidGlass scales blur and refraction strength by tier',
  );
  final blurPlan = KitBlurMath.plan(
    shell,
    enabled: true,
    glass: false,
    base: 12,
    mode: KitSurfaceMode.blur,
  );
  _expect(
    blurPlan.direct &&
        blurPlan.mode == KitSurfaceMode.blur &&
        blurPlan.sigma == 12,
    'pure blur mode builds direct blur filter',
  );
  final solidPlan = KitBlurMath.plan(
    mac.popover.dark,
    enabled: true,
    glass: true,
    base: 10,
    mode: KitSurfaceMode.solid,
  );
  _expect(
    !solidPlan.blurs && solidPlan.mode == KitSurfaceMode.solid,
    'solid mode builds no filter',
  );
  final sysOffLg = KitBlurMath.plan(
    mac.popover.dark,
    enabled: false,
    glass: true,
    base: 10,
    mode: KitSurfaceMode.liquidGlass,
  );
  _expect(
    !sysOffLg.blurs && sysOffLg.mode == KitSurfaceMode.solid,
    'system transparency off forces solid even under liquidGlass',
  );
}
