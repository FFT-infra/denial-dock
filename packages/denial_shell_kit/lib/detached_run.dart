import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// How a command run by [runDetached] ended. A program that is missing ends
/// with the shell's 127.
typedef DetachedResult = ({int exitCode, String stdout});

bool? _envSupportsDefaultSignal;

Future<Process?> _startDetachedWrapper(
  String program,
  List<String> arguments, {
  required bool useEnv,
  Map<String, String>? environment,
}) async {
  try {
    if (useEnv) {
      return await Process.start(
        'env',
        <String>[
          '--default-signal=TERM',
          'sh',
          '-c',
          r'"$@"; printf "\n%s" $?',
          'sh',
          program,
          ...arguments,
        ],
        environment: environment,
        mode: ProcessStartMode.detachedWithStdio,
      );
    }
    return await Process.start(
      'sh',
      <String>['-c', r'"$@"; printf "\n%s" $?', 'sh', program, ...arguments],
      environment: environment,
      mode: ProcessStartMode.detachedWithStdio,
    );
  } on ProcessException {
    return null;
  }
}

/// Runs [program] to its end without an attached child.
///
/// The plugins live in the compositor's own process. For an attached child
/// dart:io keeps a thread in `wait()` until the child ends, and that thread
/// reaps any child of the process: the lock screen's password helper then has
/// no exit status left to collect and the check fails. A detached child is
/// never waited on, so the exit code comes back as the last line a small `sh`
/// wrapper prints.
///
/// When [timeout] or [maxOutputBytes] is provided, the child is terminated if
/// it exceeds either bound, preventing runaway commands from stalling or
/// exhausting compositor memory.
Future<DetachedResult> runDetached(
  String program,
  List<String> arguments, {
  String? input,
  Map<String, String>? environment,
  Duration? timeout,
  int? maxOutputBytes,
  void Function(int pid)? onStart,
}) async {
  final tryEnv = _envSupportsDefaultSignal != false;
  var usedEnv = tryEnv;
  Process? process = await _startDetachedWrapper(
    program,
    arguments,
    useEnv: tryEnv,
    environment: environment,
  );
  if (process == null && tryEnv) {
    _envSupportsDefaultSignal = false;
    usedEnv = false;
    process = await _startDetachedWrapper(
      program,
      arguments,
      useEnv: false,
      environment: environment,
    );
  }
  if (process == null) return (exitCode: 127, stdout: '');

  final result = await _collectDetached(
    process,
    input: input,
    timeout: timeout,
    maxOutputBytes: maxOutputBytes,
    onStart: onStart,
  );
  // If `env --default-signal=TERM` itself failed (e.g., BusyBox / old
  // coreutils), it exits non-zero with no trailing status line on stdout.
  // Remember that and retry once with plain `sh`.
  if (usedEnv && result.wrapperFailed) {
    _envSupportsDefaultSignal = false;
    final retry = await _startDetachedWrapper(
      program,
      arguments,
      useEnv: false,
      environment: environment,
    );
    if (retry == null) return (exitCode: 127, stdout: '');
    final retryResult = await _collectDetached(
      retry,
      input: input,
      timeout: timeout,
      maxOutputBytes: maxOutputBytes,
      onStart: onStart,
    );
    return (exitCode: retryResult.exitCode, stdout: retryResult.stdout);
  }
  if (usedEnv && !result.wrapperFailed) {
    _envSupportsDefaultSignal = true;
  }
  return (exitCode: result.exitCode, stdout: result.stdout);
}

Future<({int exitCode, String stdout, bool wrapperFailed})> _collectDetached(
  Process process, {
  String? input,
  Duration? timeout,
  int? maxOutputBytes,
  void Function(int pid)? onStart,
}) async {
  onStart?.call(process.pid);
  process.stderr.drain<void>().catchError((_) {});
  if (input != null) {
    try {
      process.stdin.add(utf8.encode(input));
    } catch (_) {
      // Short-lived child may close stdin immediately.
    }
  }
  unawaited(process.stdin.close().catchError((_) {}));

  final bytes = BytesBuilder(copy: false);
  final completer = Completer<({int exitCode, String stdout, bool wrapperFailed})>();
  var finished = false;
  var timedOut = false;
  var overflowed = false;
  Timer? timer;
  StreamSubscription<List<int>>? sub;

  void killChild() {
    try {
      Process.killPid(process.pid, ProcessSignal.sigterm);
    } catch (_) {}
    Timer(const Duration(milliseconds: 400), () {
      try {
        Process.killPid(process.pid, ProcessSignal.sigkill);
      } catch (_) {}
    });
  }

  void complete() {
    if (finished) return;
    finished = true;
    timer?.cancel();
    unawaited(sub?.cancel());
    final raw = utf8.decode(bytes.takeBytes(), allowMalformed: true);
    if (timedOut) {
      completer.complete((exitCode: 124, stdout: raw, wrapperFailed: false));
      return;
    }
    if (overflowed) {
      completer.complete((exitCode: 0, stdout: raw, wrapperFailed: false));
      return;
    }
    final cut = raw.lastIndexOf('\n');
    if (cut < 0) {
      completer.complete((exitCode: 1, stdout: '', wrapperFailed: true));
      return;
    }
    completer.complete((
      exitCode: int.tryParse(raw.substring(cut + 1)) ?? 1,
      stdout: raw.substring(0, cut),
      wrapperFailed: false,
    ));
  }

  if (timeout != null) {
    timer = Timer(timeout, () {
      if (finished) return;
      timedOut = true;
      killChild();
      complete();
    });
  }

  sub = process.stdout.listen(
    (chunk) {
      if (finished) return;
      if (maxOutputBytes != null && bytes.length + chunk.length > maxOutputBytes) {
        final take = maxOutputBytes - bytes.length;
        if (take > 0) bytes.add(chunk.sublist(0, take));
        overflowed = true;
        killChild();
        complete();
        return;
      }
      bytes.add(chunk);
    },
    onError: (_) => complete(),
    onDone: complete,
    cancelOnError: true,
  );

  return completer.future;
}

/// Launches [program] fire-and-forget with no stdio pipes attached, suitable
/// for GUI shortcuts so the compositor never waits on long-lived child apps.
Future<bool> spawnDetachedFireAndForget(
  String program,
  List<String> arguments, {
  Map<String, String>? environment,
}) async {
  try {
    await Process.start(
      program,
      arguments,
      environment: environment,
      mode: ProcessStartMode.detached,
    );
    return true;
  } on ProcessException {
    return false;
  }
}
