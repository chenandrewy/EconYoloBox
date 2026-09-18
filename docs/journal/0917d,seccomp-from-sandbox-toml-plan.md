# 0917d — plan: select seccomp from SANDBOX.toml via the host launcher

Discussion snapshot, 2026-09-17. Plan only; nothing in this entry has been
implemented. It follows the decision in
[0917c](0917c,bwrap-auto-review-friction.md) to use `seccomp=unconfined`, while
addressing the awkward fact that the current toggle lives in
`.devcontainer/devcontainer.json` instead of the user-facing `SANDBOX.toml`.

## goal

Make `SANDBOX.toml` the source of truth for the container's Docker seccomp
policy, alongside the existing firewall and path settings:

```toml
seccomp = "unconfined" # or "builtin"
```

Seccomp is a container-creation option, so an in-container startup hook cannot
apply it. A host-side launcher must read the setting before asking Docker to
create the container.

## chosen approach

Keep using the Dev Containers CLI rather than replacing it with a hand-written
`docker run`. The CLI must continue to own the build, mounts, named volumes,
labels, lifecycle hooks, user setup, and VS Code attachment behavior.

The repo already has the right host-side layer: `.host/devcontainer.zsh`
currently defines separate `dcu`, `dce`, and `dccode` commands. Consolidate
those paths behind one `bbox` dispatcher so every operation uses the same
setting resolution, container identity, and bring-up logic.

Use the project-specific name `bbox` (Big ol' Sandbox), not the generic name
`dc` or the overly broad `sandbox`. Once the command reads `SANDBOX.toml`,
selects a security policy, and owns this repo's creation workflow, it is no
longer a general Dev Containers navigation helper. `bbox` is short enough for
routine use, distinctive in this context, and easy to discover with `bb<Tab>`.

The intended interface is:

```text
bbox [--rebuild|--rebuild-without-cache] [--shell|--code] [DIRECTORY]
```

- `bbox` brings the sandbox dev container up, building the image if necessary.
- `bbox --rebuild` matches VS Code's **Dev Containers: Rebuild Container**:
  remove and recreate the container while retaining normal Docker build caching.
  Use this after changing a creation-time setting.
- `bbox --rebuild-without-cache` matches VS Code's **Dev Containers: Rebuild
  Container Without Cache**: remove and recreate the container and also pass
  `--build-no-cache`.
- `bbox --shell [DIRECTORY]` brings the container up and opens a shell in the
  corresponding container-side directory.
- `bbox --code [DIRECTORY]` brings the container up and opens that directory
  in VS Code attached to the same container.
- `--shell` and `--code` are mutually exclusive. Other flags compose, so
  `bbox --rebuild --code My-Project` applies new settings and then opens the
  project. The two rebuild flags are mutually exclusive.

The old short commands may remain temporarily as thin compatibility wrappers
(`dcu -> bbox`, `dce -> bbox --shell`, `dccode -> bbox --code`), but they must
contain no independent creation or
resolution logic and should be documented as deprecated if retained.

### zsh completion

Ship a native `_bbox` completion function with the host toolkit and register it
with `compdef _bbox bbox` when zsh completion is available. It should:

- complete `--rebuild`, `--rebuild-without-cache`, `--shell`, and `--code`, with
  short descriptions matching the VS Code terminology;
- suppress the other rebuild option after either rebuild flag is selected;
- suppress `--code` after `--shell`, and vice versa;
- complete the optional positional argument as a directory;
- remain side-effect free: completion must never invoke Docker or bring up the
  container.

Do not run `compinit` from the toolkit. The user's zsh framework or shell setup
owns completion initialization; document that this file should be sourced after
completion setup if `compdef` is not yet available.

Implement the shared path as follows:

1. Add the flat string setting `seccomp = "builtin"|"unconfined"` to
   `SANDBOX.toml`.
2. Add a shared strict seccomp reader alongside the existing
   `.devcontainer/sandbox-setting.sh` helper, usable on the host and in the
   container. The existing helper's line extraction alone is insufficient:
   it accepts keys inside tables and silently selects the first duplicate.
   Validate the document's supported flat syntax before extracting the root
   string setting. Reject duplicate keys, malformed lines, and table headers
   or other unsupported TOML constructs rather than interpreting them as flat
   settings. Preserve the existing helper's behavior for its other callers.
   Document the supported syntax and use tools already available on both
   platforms; do not assume the host has Python's `tomllib`.
3. Validate the value strictly. Accept only `builtin` and `unconfined`. If the
   setting is absent or malformed, warn and use `builtin` as the fail-closed
   default; never pass arbitrary text through to Docker. Unreadable files and
   rejected document syntax also warn and resolve to `builtin`. A key under
   `[other]` must never authorize `unconfined`, and duplicate keys must never
   select either occurrence. Host and container checks must use this same
   validation and fallback logic.
4. Add the `bbox` dispatcher. It resolves the sandbox root once, exports the
   validated value for one CLI invocation, constructs the permitted Dev
   Containers CLI flags, and runs `devcontainer up` before any requested shell
   or editor action.
5. Replace the two literal seccomp alternatives in `devcontainer.json` with
   one host-environment substitution, conceptually:

   ```jsonc
   "--security-opt=seccomp=${localEnv:SANDBOX_SECCOMP:builtin}",
   ```

6. Route shell entry and editor attachment through the state produced by that
   same invocation. Neither action may contain a separate bring-up path.

This gives the intended flow:

```text
SANDBOX.toml
    -> host launcher validates `seccomp`
    -> Dev Containers CLI resolves `${localEnv:SANDBOX_SECCOMP}`
    -> Docker receives `--security-opt=seccomp=...` at container creation
```

## creation, reuse, and recreation

Changing `SANDBOX.toml` cannot alter a running container's seccomp policy.
Ordinary `devcontainer up` may reuse an existing container, so the host toolkit
must make recreation explicit rather than implying that another plain `bbox`
invocation applied the change. `bbox --rebuild` passes
`--remove-existing-container` after showing the selected policy.
`bbox --rebuild-without-cache` passes both
`--remove-existing-container` and `--build-no-cache`. Do not remove an existing
container merely because the TOML file was read; rebuilding remains an
intentional user action.

After every successful `devcontainer up`, including reuse, capture its returned
container ID and inspect that exact container in the same Docker context before
opening a shell or editor. Compare the requested policy with Docker's recorded
security options. Explicit `seccomp=builtin` and `seccomp=unconfined` are the
supported cases; custom profiles, absent options, and failed inspection must
be reported as unverified unless additional evidence establishes the policy.
Do not infer the live policy from the TOML file or the launcher's environment.

On reuse, a mismatch must produce a prominent warning showing the requested
and actual policies and instructing the user to run `bbox --rebuild` on the
host for the resolved sandbox root. In particular, requesting `builtin` must
not silently reuse `unconfined`. Continue the requested attachment after the
warning, without automatic recreation. If inspection fails, warn that
consistency could not be verified. After an explicit recreation, a mismatch
or unverifiable policy is a failed validation: return nonzero before attachment.

After recreation, validate the live result rather than trusting configuration
text:

```text
grep '^Seccomp:' /proc/1/status
bwrap --unshare-user --ro-bind / / /bin/true
codex sandbox linux /bin/true
```

For `unconfined`, also repeat the native workspace edit and denied-outside-root
checks from 0917c.

## in-container shell consistency check

Every new interactive container shell must read the current
`/workspace/SANDBOX.toml` through the shared strict reader and compare the
requested seccomp policy with `/proc/1/status`. Wire this into the interactive
startup path in `.devcontainer/shellrc.sh`, including VS Code terminals and
`bbox --shell`. Read PID 1's state rather than the checking process's state,
which may include filters added by an inner agent sandbox.

`Seccomp: 0` means PID 1 has no seccomp filter; `Seccomp: 2` means it is
filtered. Warn when `builtin` is requested but PID 1 is unfiltered, or when
`unconfined` is requested but PID 1 is filtered. A filtered PID 1 does not prove
that Docker's exact builtin profile is installed: this is a runtime mode check,
with exact policy verification performed by the host inspection above. Missing,
unreadable, or unexpected proc status must produce an unverified-state warning,
not a claim of consistency.

Warnings must show the requested policy and observed mode, explain that seccomp
is fixed at container creation, and direct the user to run `bbox --rebuild` on
the host from the sandbox root. Invalid configuration must still warn even if
the fallback `builtin` is compatible with the observed mode. Keep the check
read-only and nonblocking; do not invoke Docker, recreate the container, or run
Bubblewrap/Codex probes during shell startup. Emit diagnostics to stderr and
remain silent for valid, compatible filtered settings and for noninteractive
shells. Always display `Warning: Seccomp Unconfined` when PID 1 is unfiltered,
even when it matches TOML, with instructions to select `builtin` and run
`bbox --rebuild` on the host. This posture warning is separate from mismatch
diagnostics and must remain visible when both apply.
Recheck on each new interactive shell so edits to the bind-mounted TOML are
noticed; already-open shells need not poll for changes.

This check concerns the seccomp creation setting, not general image-build
consistency. Firewall and path settings have separate application rules and
must not be reported as validated by this check.

## VS Code caveat

VS Code's direct **Rebuild Container** path does not necessarily inherit an
environment variable established by a shell wrapper, especially when the
`code` command forwards to an already-running desktop process. Therefore the
supported creation, recreation, and attachment path for this design is the
host toolkit through `bbox`, including `bbox --code`.

Documentation must say this plainly. A direct VS Code rebuild would resolve the
substitution's safe `builtin` default, which is secure but could surprise a user
who selected `unconfined` in `SANDBOX.toml`. Do not claim the TOML setting is
universal unless a later implementation provides a persistent generated config
or another mechanism that VS Code itself can read before container creation.

## files expected to change

- `SANDBOX.toml` — add the active `seccomp` setting and creation-time warning.
- `.host/devcontainer.zsh` — add the `bbox` flag parser and the shared
  reader/validator, resolution, bring-up, shell, and editor paths; optionally
  retain the old names only as compatibility wrappers, and register completion.
- `.host/_bbox` — define side-effect-free zsh option and directory completion.
- `.host/README.md` — document the authoritative host workflow.
- `.devcontainer/devcontainer.json` — consume the validated host variable in
  the Docker security option.
- `.devcontainer/` — add the shared strict seccomp reader and a runtime mode
  check; wire the latter into interactive startup in `shellrc.sh`.
- `.devcontainer/README.md`, root `README.md`, and `docs/features.md` — replace
  the manual commented-line toggle with the TOML-driven workflow and preserve
  the security tradeoff from 0917c.
- Host-tool tests — cover both accepted values, missing/malformed values, safe
  fallback, flag combinations and conflicts, both rebuild modes, and command
  construction without actually creating a container. Include table-scoped
  keys, duplicate keys in both orders, unsupported syntax, and unreadable
  input. Mock inspection of the returned container ID to cover matching and
  mismatching reuse in both directions, inspection failure, custom/unknown
  policies, and failed validation after recreation.
- Container-shell tests — cover both requested values against filtered and
  unfiltered PID 1 fixtures, invalid TOML fallback diagnostics, unavailable or
  unexpected proc status, silence on compatible filtered settings, the posture
  warning for unfiltered PID 1 with or without a mismatch, and no output
  for noninteractive shells. Verify the startup wiring and rechecking after a
  TOML edit without recreating the container.

## non-goals and security boundary

- Do not implement a raw `docker run` replacement for the Dev Containers CLI.
- Do not silently weaken to `unconfined` on a missing or invalid setting.
- Do not auto-delete/recreate an existing container unless the user passes
  `--rebuild` or `--rebuild-without-cache`.
- Do not treat the firewall setting as coupled to seccomp.
- Preserve the warning that `unconfined` removes Docker's outer syscall filter
  for every container process, including Claude, YOLO sessions, and commands
  approved outside Codex's inner sandbox.

## acceptance criteria

- Both allowed TOML values produce the matching Docker security option through
  the host launcher.
- Missing, malformed, or unknown values warn and resolve to `builtin`.
- Table-scoped keys, duplicate keys, unsupported syntax, and unreadable files
  cannot authorize `unconfined`; host and shell share the same strict reader.
- The selected value is displayed before an explicit recreation.
- Every bring-up inspects the returned container's actual policy. Reuse warns
  on mismatch or unverifiable state without recreating; explicit recreation
  fails validation before attachment if its policy cannot be confirmed.
- Every new interactive container shell checks current TOML against PID 1's
  seccomp mode and warns on mismatch or unverifiable state with host rebuild
  instructions. It does not equate filtered mode with proof of the builtin
  profile, and does not claim to validate other settings or the image build.
- Every `bbox` mode identifies and uses the same dev container, and any
  retained compatibility wrappers delegate to `bbox` without duplicating
  logic.
- Zsh completion describes all supported flags, respects both mutual-exclusion
  pairs, and completes the optional directory without running Docker.
- Existing mounts, volumes, initialization, post-start hooks, and folder URI
  behavior remain unchanged.
- Documentation no longer instructs the user to edit commented seccomp lines in
  `devcontainer.json`.
- Runtime checks pass after recreating with `unconfined`; no implementation is
  called complete before that validation.
