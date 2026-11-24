import 'dart:convert';

/// Names of the applications recording from a microphone, from
/// `pactl -f json list source-outputs`. Level meters that only peek at the
/// signal are left out.
List<String> parseMicUsers(String json) {
  final Object? decoded;
  try {
    decoded = jsonDecode(json);
  } on FormatException {
    return const <String>[];
  }
  if (decoded is! List) return const <String>[];
  final names = <String>{};
  for (final entry in decoded) {
    if (entry is! Map) continue;
    final properties = entry['properties'];
    if (properties is! Map) continue;
    String text(String key) {
      final value = properties[key];
      return value is String ? value : '';
    }

    if (text('application.id') == 'org.PulseAudio.pavucontrol') continue;
    if (text('media.name').toLowerCase().contains('peak detect')) continue;
    if (text('stream.monitor') == 'true') continue;
    final name = text('application.name');
    names.add(name.isEmpty ? text('application.process.binary') : name);
  }
  return names.toList();
}
