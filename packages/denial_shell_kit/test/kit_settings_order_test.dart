import 'package:denial_shell_kit/kit_settings_order.dart';

typedef _Page = ({String id, int order});

void _expect(bool ok, String what) {
  if (!ok) throw StateError(what);
}

String _ids(Iterable<_Page> pages) => pages.map((page) => page.id).join(',');

void main() {
  int orderOf(_Page page) => page.order;
  String idOf(_Page page) => page.id;

  // Lowest order first, whichever plugin registered first.
  final dockFirst = <_Page>[
    (id: 'dock.visibility', order: 200),
    (id: 'dock.layout', order: 260),
    (id: 'bar.appearance', order: 100),
    (id: 'bar.layout', order: 110),
  ];
  _expect(
    _ids(kitOrderPages(dockFirst, orderOf: orderOf)) ==
        'bar.appearance,bar.layout,dock.visibility,dock.layout',
    'sorted by order: ${_ids(kitOrderPages(dockFirst, orderOf: orderOf))}',
  );
  // The same order keeps the order of registration.
  final ties = <_Page>[
    (id: 'b', order: 5),
    (id: 'a', order: 5),
    (id: 'c', order: 1),
    (id: 'd', order: 5),
  ];
  _expect(
    _ids(kitOrderPages(ties, orderOf: orderOf)) == 'c,b,a,d',
    'ties keep their order',
  );
  _expect(kitOrderPages(<_Page>[], orderOf: orderOf).isEmpty, 'none is none');
  _expect(_ids(dockFirst).startsWith('dock.visibility'), 'the input is kept');

  // Finding the page to open.
  const ids = <String>['bar.appearance', 'bar.layout', 'dock.visibility'];
  _expect(kitPageIndex(ids, 'bar.layout') == 1, 'an exact id');
  _expect(kitPageIndex(ids, 'dock') == 2, "a plugin's first page");
  _expect(kitPageIndex(ids, 'bar') == 0, "the bar's first page");
  _expect(kitPageIndex(ids, 'dock.gone') == 0, 'a missing page');
  _expect(kitPageIndex(ids, null) == 0, 'no wish');
  _expect(kitPageIndex(const <String>[], 'dock') == 0, 'no pages');
  // With only the dock running its pages are all there is.
  _expect(
    kitPageIndex(const <String>['dock.visibility', 'dock.layout'], 'bar') == 0,
    'a plugin that is not running',
  );

  // Registering: new ids are added, known ids are replaced in place.
  final pages = <_Page>[(id: 'a', order: 1), (id: 'b', order: 2)];
  final same = pages[0];
  _expect(
    !kitMergePages(pages, <_Page>[same], idOf: idOf),
    'the same page again changes nothing',
  );
  // Records with equal fields are not identical objects in general, so a
  // rebuilt page counts as a change and takes the old one's place.
  kitMergePages(pages, <_Page>[(id: 'a', order: 9), (id: 'c', order: 0)], idOf: idOf);
  _expect(_ids(pages) == 'a,b,c', 'replaced in place, added at the end');
  _expect(pages[0].order == 9, 'the new page took the place');
  _expect(
    _ids(kitOrderPages(pages, orderOf: orderOf)) == 'c,b,a',
    'and the order follows',
  );
}
