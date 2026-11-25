import 'dart:async';

import 'package:denial_shell_kit/kit_requests.dart';

Future<void> main() async {
  // Nobody listening: a sender can tell, and sending is harmless.
  _expect(!KitRequests.answered, 'no listener at first');
  KitRequests.send(KitRequests.about);

  final seen = <KitRequest>[];
  final subscription = KitRequests.stream.listen(seen.add);
  _expect(KitRequests.answered, 'a listener answers');
  KitRequests.send(KitRequests.about, monitorId: 2);
  KitRequests.send('other');
  await Future<void>.delayed(Duration.zero);
  _expect(seen.length == 2, 'both requests arrive: ${seen.length}');
  _expect(
    seen[0].name == KitRequests.about && seen[0].monitorId == 2,
    'a request carries its name and output',
  );
  _expect(seen[1].monitorId == null, 'the output is optional');

  await subscription.cancel();
  _expect(!KitRequests.answered, 'cancelling stops the answer');
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
