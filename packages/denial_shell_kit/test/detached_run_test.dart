import 'package:denial_shell_kit/detached_run.dart';

void expect(Object? actual, Object? matcher, String what) {
  if (actual != matcher) throw StateError('$what: $actual is not $matcher');
}

Future<void> main() async {
  final plain = await runDetached('sh', <String>['-c', 'printf hi; exit 3']);
  expect(plain.exitCode, 3, 'exit code');
  expect(plain.stdout, 'hi', 'stdout');

  final lines = await runDetached('printf', <String>[r'a\nb\n']);
  expect(lines.exitCode, 0, 'exit code of printf');
  expect(lines.stdout, 'a\nb\n', 'stdout keeps its own newlines');

  final echoed = await runDetached('cat', const <String>[], input: 'in');
  expect(echoed.stdout, 'in', 'stdin reaches the program');

  final missing = await runDetached('no-such-program-here', const <String>[]);
  expect(missing.exitCode, 127, 'a missing program');
}
