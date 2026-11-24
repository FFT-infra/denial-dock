import 'dart:io';

/// Starts a long-running [command] that ends when this process does, and at
/// most one per [name]. A child started directly outlives a shell restart;
/// here a small `sh` wrapper holds our end of a pipe and stops the command
/// when the pipe closes.
///
/// The compositor restarts the interface inside one process, and then the
/// pipe stays open. So the wrapper runs in a session of its own and leaves
/// that session's id in the runtime directory; the next start under the same
/// [name] ends whatever is left of the previous one.
Future<Process> startTethered(String name, List<String> command) =>
    Process.start('setsid', <String>[
      'sh',
      '-c',
      r'f="${XDG_RUNTIME_DIR:-/tmp}/$0-$1.sid"; shift; '
          r'old=$(cat "$f" 2>/dev/null); '
          r'case "$old" in *[!0-9]*|"") ;; *) '
          r'grep -qs "$0" "/proc/$old/cmdline" && pkill -s "$old";; esac; '
          r'echo $$ > "$f"; '
          r'exec 3<&0; "$@" & pid=$!; '
          r'{ cat <&3 >/dev/null; kill $pid 2>/dev/null; } & wait $pid',
      _marker,
      name,
      ...command,
    ]);

const String _marker = 'denial_topbar-tether';

/// Stops a process started by [startTethered].
void stopTethered(Process process) {
  process.stdin.close().ignore();
}
