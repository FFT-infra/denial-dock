/// Where a tray item lives on the session bus, from the watcher's
/// `service/path` form. A bare service uses the default object path.
({String service, String path})? trayAddress(String id) {
  if (id.isEmpty) return null;
  final slash = id.indexOf('/');
  final service = slash < 0 ? id : id.substring(0, slash);
  final path = slash < 0 ? '/StatusNotifierItem' : id.substring(slash);
  final unique = RegExp(r'^:\d+\.\d+$').hasMatch(service);
  final named = RegExp(r'^[A-Za-z_][\w-]*(\.[A-Za-z_][\w-]*)+$')
      .hasMatch(service);
  if (!unique && !named) return null;
  return (service: service, path: path);
}

/// A readable stand-in for an id nothing could be learnt about.
String trayFallbackName(String id) {
  final tail = id.split('/').where((part) => part.isNotEmpty).lastOrNull ?? id;
  final name = tail.replaceFirst(RegExp(r'^org\.kde\.StatusNotifierItem-'), '');
  return name.length > 28 ? '${name.substring(0, 27)}…' : name;
}
