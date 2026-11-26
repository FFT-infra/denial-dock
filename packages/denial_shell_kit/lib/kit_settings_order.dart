/// The order of the pages in the shell's settings window, kept free of
/// Flutter so it runs as an ordinary Dart test.
///
/// Pages are sorted by [orderOf], lowest first. Pages with the same order
/// stay as they were given, which is the order their plugins registered
/// them in.
List<T> kitOrderPages<T>(
  Iterable<T> pages, {
  required int Function(T page) orderOf,
}) {
  final indexed = <(int, T)>[
    for (final (index, page) in pages.indexed) (index, page),
  ];
  indexed.sort((a, b) {
    final byOrder = orderOf(a.$2).compareTo(orderOf(b.$2));
    return byOrder != 0 ? byOrder : a.$1.compareTo(b.$1);
  });
  return <T>[for (final (_, page) in indexed) page];
}

/// Where the page called [wanted] is among [ids]. A page that is not there,
/// because its plugin is not running, opens the first one instead; an id
/// that names only a plugin, such as `dock`, opens that plugin's first page.
int kitPageIndex(List<String> ids, String? wanted) {
  if (wanted == null || ids.isEmpty) return 0;
  final exact = ids.indexOf(wanted);
  if (exact >= 0) return exact;
  final group = ids.indexWhere((id) => id.startsWith('$wanted.'));
  return group >= 0 ? group : 0;
}

/// Adds [added] to [pages], each replacing the page that has its id and
/// keeping that page's place. Returns whether anything changed.
bool kitMergePages<T>(
  List<T> pages,
  Iterable<T> added, {
  required String Function(T page) idOf,
}) {
  var changed = false;
  for (final page in added) {
    final at = pages.indexWhere((existing) => idOf(existing) == idOf(page));
    if (at < 0) {
      pages.add(page);
      changed = true;
    } else if (!identical(pages[at], page)) {
      pages[at] = page;
      changed = true;
    }
  }
  return changed;
}

/// Keeps only the pages in [pages] matching every word in [query] against
/// their title, group, or search keywords. Empty queries keep everything.
List<T> kitFilterPages<T>(
  Iterable<T> pages,
  String query, {
  required String Function(T page) titleOf,
  String Function(T page)? groupOf,
  Iterable<String> Function(T page)? keywordsOf,
}) {
  final terms = query
      .trim()
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((term) => term.isNotEmpty)
      .toList();
  if (terms.isEmpty) return List<T>.of(pages);
  return <T>[
    for (final page in pages)
      if (_matchesPage(
        terms,
        title: titleOf(page),
        group: groupOf?.call(page) ?? '',
        keywords: keywordsOf?.call(page) ?? const <String>[],
      ))
        page,
  ];
}

bool _matchesPage(
  List<String> terms, {
  required String title,
  required String group,
  required Iterable<String> keywords,
}) {
  final haystack = <String>[title, group, ...keywords].join(' ').toLowerCase();
  for (final term in terms) {
    if (!haystack.contains(term)) return false;
  }
  return true;
}
