import 'dart:convert';
import 'dart:io';

/// How a command run by [runDetached] ended. A program that is missing ends
/// with the shell's 127.
typedef DetachedResult = ({int exitCode, String stdout});

/// Runs [program] to its end without an attached child.
///
/// The plugins live in the compositor's own process. For an attached child
/// dart:io keeps a thread in `wait()` until the child ends, and that thread
/// reaps any child of the process: the lock screen's password helper then has
/// no exit status left to collect and the check fails. A detached child is
/// never waited on, so the exit code comes back as the last line a small `sh`
/// wrapper prints.
Future<DetachedResult> runDetached(
  String program,
  List<String> arguments, {
  String? input,
  Map<String, String>? environment,
}) async {
  final Process process;
  try {
    process = await Process.start(
      'sh',
      <String>['-c', r'"$@"; printf "\n%s" $?', 'sh', program, ...arguments],
      environment: environment,
      mode: ProcessStartMode.detachedWithStdio,
    );
  } on ProcessException {
    return (exitCode: 127, stdout: '');
  }
  process.stderr.drain<void>().ignore();
  if (input != null) process.stdin.add(utf8.encode(input));
  process.stdin.close().ignore();
  final output = await process.stdout
      .transform(const Utf8Decoder(allowMalformed: true))
      .join();
  final cut = output.lastIndexOf('\n');
  return (
    exitCode: cut < 0 ? 1 : int.tryParse(output.substring(cut + 1)) ?? 1,
    stdout: cut < 0 ? '' : output.substring(0, cut),
  );
}
