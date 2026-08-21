# Credential injection: the auto-delete is theatre, and why

Date: 2026-07-25 (NY)

Came out of a side question while implementing [0725a]: does deleting
`/tmp/devcontainer-credentials.env` actually accomplish anything? Mostly no.
Nothing implemented — this is the analysis and the option ladder.

## What the current mechanism actually does

`inject-credentials.py` runs on the host at `initializeCommand`, resolves
credentials from the Keychain, writes them to `/tmp/devcontainer-credentials.env`
(0600), and the container picks them up via `runArgs --env-file`. A detached
`sleep` then "deletes" the file.

Three things are not what they look like:

1. **It truncates, doesn't delete.** `: > $ENV_FILE`. The file stays, empty.
2. **It's 20 minutes, not 10.** `DELETE_AFTER_SECONDS = 1200`; the README says 10.
3. **The window it closes isn't the window that matters.** Verified in this
   container: `WRDS_USERNAME`, `WRDS_PASSWORD`, `MISTRAL_API_KEY` are all in
   **PID 1's `environ`**. `--env-file` values also become `Config.Env`, so
   `docker inspect` prints them and they sit in the daemon's `config.v2.json`
   for the container's life, surviving stop/start. So there is a second at-rest
   copy, longer-lived than the one being truncated, reachable by anyone who can
   talk to the Docker socket — on Docker Desktop, *you*, the same principal the
   0600 file was guarding against.

Two smaller things. The truncation is a detached `sleep`, so a reboot or a killed
process inside the window leaves plaintext indefinitely — it fails open. And the
20 minutes is arbitrary even on its own terms: the file's only consumer is
`docker run --env-file`, seconds after it is written.

Unrelated, noticed while reading: `os.open(ENV_FILE, O_WRONLY|O_CREAT|O_TRUNC,
0o600)` has no `O_NOFOLLOW` in a world-writable `/tmp`. On a shared Linux host
another user can pre-create that path as a symlink and have the credentials
written somewhere they can read. Moot on a single-user Mac.

## Would `keyring` inside the container help? No

Asked directly; the answer is essentially zero benefit, for three reasons.

- **No backend.** Python `keyring` is a front-end over a store. The candidates
  here are SecretService (needs `gnome-keyring-daemon` + a D-Bus session, not
  present — the `libsecret-1-dev` in the Dockerfile is headers for R's `keyring`,
  not a daemon) or `keyrings.alt`'s encrypted file. You'd be adding a daemon
  before getting anything.
- **Circular.** Any container-side store must be unlocked, by a passphrase that
  has to arrive from outside at start — the injection problem one level down. A
  store auto-unlocked at boot is a plaintext file with extra steps.
- **Wrong trust boundary.** The container isn't a boundary against either threat:
  anything running as `node` reads it, and the host user can `docker exec -u
  root`. Keychain works because the OS enforces per-app ACLs and prompts; nothing
  in a Linux container enforces an equivalent. The store belongs on the host,
  which is what `get-credentials.py` already assumes (`_read_from_store` returns
  `""` on Linux — in-container resolution is env-only by design).

## The reframe: it's not file vs. env, it's file vs. file-plus-env

Pushback in conversation, and a fair one: isn't keeping credentials *out* of
files the whole point? Yes — but that maxim is really "keep them out of the
source tree and out of anything that syncs" (`.env` in git, config in Dropbox,
files swept into backups). It is not an argument against this change, because
**the file already exists**. Today's setup writes it to `/tmp` and *then* also
passes it through `--env-file`. Dropping `--env-file` for a bind mount is a
subtraction: same file, minus the copies.

What the env copies specifically cost:

- **Docker metadata** — `Config.Env`, `docker inspect`, `config.v2.json`. A
  second at-rest copy in a place you don't manage.
- **Ambient inheritance** — every child process gets `WRDS_PASSWORD` whether or
  not it needs it: every `pip install`, every R package build script, every npm
  postinstall, every tool an agent spawns. In a container that routinely executes
  third-party install scripts, this is the part worth caring about. A file has to
  be deliberately opened.
- **Diagnostics serialize environments, not arbitrary files.** Crash reporters
  commonly attach env vars, and `sentry.io` is allowlisted here. Nothing
  auto-vacuums a file at a path it has never heard of.
- **Env can't be revoked.** Fixed at exec for the process lifetime. This is
  exactly why the truncation is theatre today.

## The nice detail: `: >` preserves the inode

A bind-mounted *single file* maps an inode. Truncating in place propagates into
the container, so under a mount the 20-minute truncation stops being decorative
and becomes a **real lease** — access actually ends. Had the script used `rm` +
recreate, the container would keep reading the old inode and see the credentials
forever (the same reason editing a bind-mounted config with an atomic-replace
editor doesn't show up inside a container).

So the existing truncate-don't-delete choice is accidentally exactly right for
the design we'd want. The lease length would then need to match a working
session, or need a re-inject command, since a long session would otherwise lose
access mid-flight.

## Option ladder (cheapest first)

1. **Fix the docs.** "Emptied after 20 minutes; the credentials remain in the
   container's environment for its lifetime." Retires the false claim at zero
   cost.
2. **Mount a file instead of `--env-file`.** Host side stays in `/tmp` (on macOS
   `/private/tmp`: excluded from Time Machine, purged periodically — good for a
   lease). Mount read-only at `/run/secrets/credentials.env`, matching Docker's
   own secrets convention; `/run` is tmpfs and never persists. Callers don't
   change: `get_credential(env_var, target)` gains a middle tier (env → mounted
   file → host store), ~10 lines in `get-credentials.py`. Nothing lands in
   `/workspace`, so git never sees it.
3. **Narrow what's forwarded.** `credentials-map.json` is per project — a LaTeX
   project needn't receive WRDS plus every API key. Pair with scoped, rotatable
   keys with spend caps. Usually buys more than plumbing, for less work.
4. **Keep the secret out entirely.** Run WRDS pulls on the host, land parquet in
   the bind mount. Cheap if pulls are occasional.
5. **On-demand helper** — host daemon, container asks per use, secret lives only
   in the requesting process's memory. Architecturally right, same shape as the
   VS Code git credential helper we kept. **Recommend against**: custom unix
   socket forwarding into Docker Desktop on macOS is awkward (the supported path
   is the special `/run/host-services/ssh-auth.sock`), TCP over
   `host.docker.internal` needs its own auth token — back to injection unless the
   host prompts per request — and [0724e]'s same-uid argument defeats it anyway,
   since a rogue `node` process can just speak the protocol. This is
   `scholar-fetch` again, killed for the same cost-versus-value reason.

## What none of this buys

Anything running as `node` in the container reads a mounted file as easily as it
reads the environment — same uid, same principal, the wall [0724e] kept hitting.
The win is narrower than it sounds: no metadata copy, no ambient inheritance,
revocability. Against in-container code, no arrangement of files or env helps;
only not having the secret present does.

## Caveats to check before building

- **Bind-mounted file ownership** is presented differently across Docker Desktop
  (uid translation) and Linux hosts (real uids must line up). `node` readability
  needs verifying on each host actually used.
- **Lease vs. long sessions** — see above; needs a re-inject path or a
  session-length lease.

## Status

Agreed the auto-delete is near-worthless as written; nothing changed yet.
Leaning 1 + 2 + 3 (~30 lines total). Decision pending.

[0724e]: 0724e,credential-helper-close.md
[0725a]: 0725a,firewall-plan-update.md
[0725b]: 0725b,firewall-plan-implemented.md
