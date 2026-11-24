import 'dart:io';

/// Starts a long-running [command] that ends when this process does. A child
/// started directly outlives a shell restart; here a small `sh` wrapper holds
/// our end of a pipe and stops the command when the pipe closes.
///
/// The compositor starts its children with SIGTERM blocked, so the wrapper
/// has to use SIGKILL: a plain `kill` is never delivered.
Future<Process> startTethered(List<String> command) =>
    Process.start('sh', <String>[
      '-c',
      r'exec 3<&0; "$@" & pid=$!; '
          r'{ cat <&3 >/dev/null; kill -KILL $pid 2>/dev/null; } & wait $pid',
      'sh',
      ...command,
    ]);

/// Stops a process started by [startTethered].
void stopTethered(Process process) {
  process.stdin.close().ignore();
}
