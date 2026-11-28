import 'package:denial_shell_kit/kit_requests.dart';
import 'package:denial_topbar/src/bar_settings.dart';
import 'package:denial_topbar/src/tray_usage.dart';

void _expect(bool condition, String message) {
  if (!condition) {
    throw StateError('Assertion failed: $message');
  }
}

void _expectList(List<String> actual, List<String> expected, String label) {
  if (actual.length != expected.length) {
    throw StateError('$label: expected $expected, got $actual');
  }
  for (var i = 0; i < actual.length; i++) {
    if (actual[i] != expected[i]) {
      throw StateError('$label: expected $expected, got $actual');
    }
  }
}

Map<String, dynamic> _encode(BarSettings settings) {
  final map = <String, dynamic>{};
  settings.writeJson(map);
  return map;
}

Future<void> main() async {
  // 1. overviewCardWidth defaults, clamps, and round-trips JSON.
  const def = BarSettings.defaults;
  _expect(def.overviewCardWidth == 300, 'default overviewCardWidth is 300');

  final customWidth = def.copyWith(overviewCardWidth: 380);
  final restoredWidth = BarSettings.fromJson(_encode(customWidth));
  _expect(restoredWidth.overviewCardWidth == 380, 'overviewCardWidth round-trips');

  final tooSmall = BarSettings.fromJson(<String, Object?>{
    'overviewCardWidth': 80,
  });
  final tooLarge = BarSettings.fromJson(<String, Object?>{
    'overviewCardWidth': 900,
  });
  _expect(tooSmall.overviewCardWidth == 200, 'overviewCardWidth lower clamp');
  _expect(tooLarge.overviewCardWidth == 420, 'overviewCardWidth upper clamp');

  // 2. trayAutoHideByFreq and threshold clamp & round-trip JSON.
  _expect(!def.trayAutoHideByFreq, 'trayAutoHideByFreq defaults false');
  _expect(def.trayAutoHideThreshold == 3, 'trayAutoHideThreshold defaults 3');

  final editedTray = def.copyWith(
    trayAutoHideByFreq: true,
    trayAutoHideThreshold: 6,
  );
  final restoredTray = BarSettings.fromJson(_encode(editedTray));
  _expect(restoredTray.trayAutoHideByFreq, 'trayAutoHideByFreq round-trips');
  _expect(
    restoredTray.trayAutoHideThreshold == 6,
    'trayAutoHideThreshold round-trips',
  );

  final clampedLow = BarSettings.fromJson(<String, Object?>{
    'trayAutoHideThreshold': 0,
  });
  final clampedHigh = BarSettings.fromJson(<String, Object?>{
    'trayAutoHideThreshold': 99,
  });
  _expect(clampedLow.trayAutoHideThreshold == 1, 'threshold lower clamp');
  _expect(clampedHigh.trayAutoHideThreshold == 20, 'threshold upper clamp');

  // 3. TrayUsageTracker records, persists, sanitizes, and clears cleanly.
  Map<String, int>? persisted;
  final tracker = TrayUsageTracker(
    reader: () => parseTrayUsageMap(<String, Object?>{
      'discord': 2,
      'bad': -4,
      '': 5,
      'str': 'nope',
    }),
    writer: (counts) => persisted = Map<String, int>.of(counts),
  );
  _expect(tracker.countOf('discord') == 2, 'reads positive count');
  _expect(tracker.countOf('bad') == 0, 'ignores negative count');
  _expect(!tracker.counts.containsKey(''), 'ignores empty key');

  tracker.record('discord');
  _expect(tracker.countOf('discord') == 3, 'increments count');
  _expect(persisted?['discord'] == 3, 'persists increment');

  tracker.record('   ');
  _expect(tracker.counts.length == 1, 'ignores whitespace key');

  tracker.clear();
  _expect(tracker.counts.isEmpty, 'clear empties counts');
  _expect(persisted != null && persisted!.isEmpty, 'clear persists empty');

  // 4. partitionTrayIds folds low-frequency items while respecting explicit rules.
  const freqSettings = BarSettings(
    trayAutoHideByFreq: true,
    trayAutoHideThreshold: 3,
    trayHidden: <String>['forced_hidden'],
    trayNever: <String>['blocked'],
  );
  final freqPart = partitionTrayIds(
    const <String>['frequent', 'rare', 'forced_hidden', 'blocked'],
    settings: freqSettings,
    resolveKey: (id) => id,
    usageCounts: const <String, int>{
      'frequent': 5,
      'rare': 1,
      'forced_hidden': 10,
      'blocked': 20,
    },
  );
  _expectList(freqPart.visible, const <String>['frequent'], 'freq visible');
  _expectList(
    freqPart.folded,
    const <String>['rare', 'forced_hidden'],
    'freq folded',
  );

  const offSettings = BarSettings(
    trayAutoHideByFreq: false,
    trayAutoHideThreshold: 3,
    trayHidden: <String>['forced_hidden'],
  );
  final offPart = partitionTrayIds(
    const <String>['frequent', 'rare', 'forced_hidden'],
    settings: offSettings,
    resolveKey: (id) => id,
    usageCounts: const <String, int>{'frequent': 5, 'rare': 1},
  );
  _expectList(
    offPart.visible,
    const <String>['frequent', 'rare'],
    'off visible',
  );
  _expectList(offPart.folded, const <String>['forced_hidden'], 'off folded');

  // 5. KitRequests.triggerSearch invokes custom handler or falls back + broadcasts.
  try {
    int? receivedMonitor;
    var fallbackCalls = 0;
    KitRequests.registerSearchHandler((monitorId) {
      receivedMonitor = monitorId;
      return true;
    });
    KitRequests.triggerSearch(
      monitorId: 42,
      fallback: () => fallbackCalls++,
    );
    _expect(receivedMonitor == 42, 'handler receives monitorId');
    _expect(fallbackCalls == 0, 'handled search skips fallback');

    KitRequests.registerSearchHandler((_) => false);
    KitRequests.triggerSearch(
      monitorId: 7,
      fallback: () => fallbackCalls++,
    );
    _expect(fallbackCalls == 1, 'unhandled search invokes fallback once');
  } finally {
    KitRequests.registerSearchHandler(null);
  }
}
