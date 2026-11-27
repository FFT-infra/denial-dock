import 'package:denial_dock/src/dock_look.dart';

void _expect(bool ok, String what) {
  if (!ok) throw StateError(what);
}

void main() {
  final fixedBar = DockLook.resolve(DockLook.denial, const <String, Object?>{
    'shape': 'bar',
    'edgeMargin': 8,
    'radius': 10,
    'defloatOnTouch': false,
  });
  _expect(fixedBar.effectiveEdgeMargin == 0, 'normal bar sits flush');
  _expect(fixedBar.effectiveRadius == 0, 'normal bar has square corners');

  final floatingBar = DockLook.resolve(DockLook.denial, const <String, Object?>{
    'shape': 'bar',
    'edgeMargin': 6,
    'radius': 8,
    'defloatOnTouch': true,
  });
  _expect(
    floatingBar.effectiveEdgeMargin == 6,
    'defloatOnTouch bar preserves edgeMargin while floating',
  );
  _expect(
    floatingBar.effectiveRadius == 8,
    'defloatOnTouch bar preserves radius while floating',
  );

  final borderless = DockLook.resolve(DockLook.denial, const <String, Object?>{
    'opacity': 0,
    'border': false,
    'shadow': 0,
  });
  _expect(
    borderless.opacity == 0 && !borderless.border && borderless.shadow == 0,
    'borderless transparent dock retains 0 opacity without border/shadow',
  );
}
