# 0725d — Launching a remote from an agent: the window launcher can't, a pty can

2026-07-25 (NY)

Asked Claude (running in the Dropbox remote) to start the 1-SANDBOX remote for
me. It got there, but not by either path in `.host/host-aliases.zsh`. Recording
what failed and the one-line trick that worked, plus a sketch for a third mode
so next time it's just a function call.

## What happened

Container was already up (`vsc-1-sandbox-…`, ~1h). `_cc_sandbox window`
(`host-aliases.zsh:111` path) ran `devcontainer up` fine — credentials injected,
`openalex-api-key` warned as missing as usual — and then died at the launcher:

```
137:153: execution error: Terminal got an error: AppleEvent timed out. (-1712)
```

`ccsessions` showed nothing new, so `do script` never ran. No Terminal window,
no session.

`_cc_open_window` (`host-aliases.zsh:37-50`) drives Terminal.app over
AppleEvents, which needs TCC **Automation** permission held by the process
issuing the event — here a subprocess of the agent's shell, not my interactive
Terminal. Unapproved automation targets don't error cleanly; they hang until the
60-second AppleEvent timeout, which is exactly the `-1712` shape. Caveat: this is
inference, not a confirmed diagnosis — the check that would have settled it
(`osascript -e 'tell application "Terminal" to count windows'`) never ran, I
declined it mid-flight. Worth running once from an agent shell to know for sure.

So `mode=window` is unavailable to anything but a permission-approved
interactive shell. And `mode=here` (`cc-remote-sandbox`) is worse from an agent:
it's a foreground TUI in the *calling* terminal, which for a tool-call subprocess
means no TTY and no window a human can see.

## What worked

```zsh
script -q /dev/null devcontainer exec --workspace-folder "$CC_SANDBOX_DIR" \
  claude --dangerously-skip-permissions --remote-control 1-SANDBOX \
  > /path/to/cc-sandbox.log 2>&1 &
```

`script -q /dev/null` allocates a pty. That's the whole fix, and it fixes two
things at once: Claude's TUI can enter raw mode, and `devcontainer exec` sees a
TTY on stdin so it passes `-it` through to `docker exec`. Without it the exec is
non-interactive and the TUI has nothing to attach to.

Result: session live in `exciting_blackburn`, `/remote-control is active`, URL
printed in the log (`https://claude.ai/code/session_…`) — which is the point,
since with `--remote-control` the local TUI is a formality; the session is driven
from the phone or the web. A headless launch loses nothing that matters here.

`ccsessions` (`host-aliases.zsh:116`) discovered it normally — it scans
`docker exec ps` per container, so it doesn't care how the process was started.
`cckill` reaches it the same way.

The one real cost: the process is parented to the agent's process tree rather
than a Terminal window, so it dies with that session. `nohup … & disown` fixes
that.

## Sketch: a third mode

`_cc_remote` already keys the yolo flag off `target_env`, not off the mode
(`host-aliases.zsh:79`) — the invariant the header comment insists on — so adding
a mode costs nothing on the safety side. It stays a container-only path
regardless.

```zsh
  case "$mode" in
    here|window|headless) ;;
```

and in the `container` branch:

```zsh
      elif [[ "$mode" == headless ]]; then
        local log="${TMPDIR:-/tmp}/cc-$name.log"
        nohup script -q /dev/null devcontainer exec --workspace-folder "$folder" \
          claude "${flags[@]}" --remote-control "$name" >"$log" 2>&1 &
        disown
        print -r -- "$name: headless (pid $!), log: $log"
```

Then `cc-headless-sandbox() { _cc_sandbox headless; }` and an agent — or a cron
job, or a login hook — can start a remote with no GUI, no Automation grant, and
no terminal to keep open. Grab the session URL out of `$log`.

Two notes if this gets written for real:

- `script -q /dev/null cmd args` is the BSD/macOS calling convention. GNU
  `script` wants `script -qec "cmd args" /dev/null`. This file is host-side and
  macOS-only today, but the launcher override section in the README invites
  portability, so the difference deserves a comment.
- The log holds a live session URL. `${TMPDIR}` is per-user and fine; don't
  default it into the workspace, where it would sync and land near git.

## Status

Nothing changed in `.host/`. The headless mode is a ~8-line addition and I think
it's worth it — it's the only one of the three modes that works unattended, which
is increasingly how these get started. Separately: if `mode=window` is meant to
stay usable from agent shells, the Automation permission has to be granted to
whatever hosts them, and `_cc_open_window` should get a comment saying so
instead of letting the next person read a 60-second hang as a broken script.
