import 'package:flutter/widgets.dart';

import 'l10n/tables.dart';

extension BarL10n on BuildContext {
  /// The label for [en] in the shell's language; `{}` takes [arg].
  String tr(String en, [Object? arg]) {
    final code = Localizations.maybeLocaleOf(this)?.languageCode;
    final text = barLabels[code]?[en] ?? en;
    return arg == null ? text : text.replaceAll('{}', '$arg');
  }
}
