# The VS Code git credential helper — investigated, then kept

Date: 2026-07-24 (NY)

> **Update — decision reversed (later same day).** We are **not** closing the
> helper. On reflection the strict "no GitHub credentials / never push" stance
> was an overreaction to a single accidental push, and it diverges from the
> reference repo's *intent*: Anthropic leaves Git-credential forwarding on so the
> containerized agent can push branches and open PRs — a feature, not an
> oversight (the reference opens all GitHub ranges and ships `gh`). We're
> **loosening the repo's GitHub guidance** to match, and taking the simplest
> overall plan: **widen the firewall (allow Google; keep Sentry + GitHub) and
> leave everything else as-is** — keep the credential helper, don't build
> `scholar-fetch`, don't set `GIT_CONFIG_NOSYSTEM`. Everything below stands as
> the record of *what the helper is* and *how to close it if we ever change our
> minds* — we're choosing not to. See updated Status.

Spun out of the firewall discussion ([0724d]) because it's a **distinct problem**
on a different axis. Originally we planned to **close** it (superseded — see the
Update above). Surfaced while checking whether GitHub is a real exfil channel;
turned out the container had a git credential helper that, at the time, looked
like it violated our "no GitHub credentials" invariant.

**Where it came from: the VS Code default — not a user or agent action.** Checked
and the repo sets nothing (no `dev.containers.*`, no `credential.helper`, no
`copyGitConfig` anywhere). The helper string is VS Code's own auto-generated
forwarder — it invokes `.vscode-server/bin/<commit>/node` on a session-specific
`/tmp/vscode-remote-containers-<id>.js`, which only the Dev Containers extension
produces (nobody, and no agent, hand-writes that). Dev Containers forwards Git
credentials **on by default**, writing the helper to the system config
(`gitCredentialHelperConfigLocation` defaults to `system`) — which is why it's
root-owned and why upstream `anthropics/claude-code` is silent about it (same
thing happens there). So this isn't a mistake anyone made; it's default behavior
we need to opt out of.

## What was found

Effective git config in the container had:

```
credential.helper = !f() { … vscode-remote-containers-….js git-credential-helper $*; }
```

That's the **VS Code Dev Containers** git-credential forwarder. It proxies each
credential request from inside the container back to the host **on demand**, so
the host's GitHub token is retrievable whenever VS Code is connected — even
though the static picture looks clean (`gh` logged out, no `GH_TOKEN`, no
`~/.config/gh`).

## Why it's a distinct problem, not part of the firewall

Two orthogonal axes:
- **Firewall** = *which destinations* are reachable.
- **Credential forwarding** = *what secret exists in-container to send.*

They combine into a real risk only as a pair: `github.com` is an **allowed**
egress destination, so a forwarded credential exfiltrates (or pushes) straight
through the open door. Tightening egress can't touch this — the payload is a
credential to a host we *want* open. And **same-uid = same principal**: a rogue /
injected `node` process can just speak the git-credential protocol to the helper
and get the token back. There's no "only real git may ask" boundary (the same
wall the `scholar-fetch` design kept hitting).

## Why closing it costs us nothing we intended to have

`CLAUDE.md` states the invariant plainly: *"The container has no GitHub
credentials by design… the user reviews everything before it goes public…
Prepare commits locally and hand off."* The helper **quietly violates** exactly
that. So this isn't a tradeoff — it's realigning the container with a security
posture we already chose. Disabling it stops authenticated `git push` / `gh`
from inside the container, which is **precisely** the intended behavior.

## What the reference repo says about it: nothing

Pulled `anthropics/claude-code` `.devcontainer/{devcontainer.json,Dockerfile}`:
it forwards **no** credentials — mounts only bash-history + `.claude` volumes,
sets no token env vars, installs `gh` but never authenticates it, configures no
credential helper. The helper is injected by **VS Code**, not the repo. Upstream
is silent, so there's no precedent either way — this is our call, and it's an
easy one given our stated invariant.

## The wrinkle we found while closing it

Unsetting `credential.helper` in `~/.gitconfig` (node-writable) revealed a
**second** copy: VS Code had also injected the helper into the **root-owned
system config** `/usr/local/etc/gitconfig` (`root:root`, 0644). Its full contents:

```
[merge] ff = false
[pager] branch = cat
[core]  editor = nano
[credential] helper = "!f() { … /tmp/vscode-remote-containers-<session>.js … }; f"
```

Two consequences:
1. **`node` can't remove the system copy** (root-owned, and general `sudo` is
   blocked). So the in-container unset only clears the global copy.
2. The helper references a **session-specific `/tmp/...js`** path → it's written
   by the **VS Code client at connect time**, not baked into the image. So a
   **rebuild cannot own this**: a fresh image gets the helper re-injected on the
   next connect anyway. This is why the fix can't live in `.devcontainer`.

## Fixes we rejected, and the one that works

- **`.devcontainer` + rebuild** — can't remove a client-injected, root-owned,
  per-session artifact. Rejected as insufficient (this is what motivated the
  question in the first place).
- **`GIT_CONFIG_NOSYSTEM=1` in `containerEnv`** — makes git ignore the system
  config (verified), survives rebuilds. But the helper is still physically
  present, so a rogue `node` just runs `env -u GIT_CONFIG_NOSYSTEM git …` or
  calls the helper directly. **Reversible by the very threat we're defending
  against → cosmetic. Rejected.**
- **Host VS Code setting (the real fix):**
  ```json
  "dev.containers.gitCredentialHelperConfigLocation": "none"
  ```
  Default is `"system"` (exactly why it landed in the root system config).
  `"none"` stops the client writing the helper into *any* scope → nothing to
  invoke, no host-credential channel. Independent of `copyGitConfig`, so
  **identity is still copied in and local commits are unaffected** (verified:
  identity lives in `.git/config` + global, not the system config; a fresh
  `git init` + commit succeeds with the helper gone).
- Verify after reopening: `git config --show-origin --get-all credential.helper`
  prints nothing.

## Do local commits need the helper? No.

Confirmed explicitly: commits need only **identity** (`user.name` +
`user.email`, both set). `git add/commit/branch/merge/rebase/log/diff` are all
local — they never invoke the credential helper, which is only for *remote* auth
(`push`, `fetch`/`pull`/`clone` of private repos, `gh`). Removing the helper
loses exactly the "reach GitHub with a token" capability we don't want — the
"commit locally, hand off" posture is preserved.

## Status / next (updated — decision reversed)

- **Decision: keep the helper.** Loosen the repo's GitHub guidance instead. The
  helper is the VS Code default and matches the reference's intent (agent can
  push / open PRs). **No host setting to change** — we are *not* setting
  `gitCredentialHelperConfigLocation: none`.
- **Firewall:** proceed with [0724d] — widen to allow Google, keep Sentry +
  GitHub. That is the whole infra change. "Keep other things as is."
- **Doc edits (loosening the guidance):**
  - `.devcontainer/README.md` — reverted the "host setting required to hold this
    invariant" callout I'd added (it argued for closing the helper). The older
    "the container has no GitHub credentials" line still reads strict; soften it
    to say credential forwarding is intentionally left on. [TODO]
  - `CLAUDE.md` / user guidance — the "no GitHub credentials by design; prepare
    commits locally and hand off" language is the overreaction; loosen when
    ready. [TODO]
- **This session:** I earlier neutralized the helper via an empty-string global
  override (`git config --global credential.helper ""`). Since we're keeping the
  helper, undo it (`git config --global --unset credential.helper`) to restore
  push capability in-session — say the word.
- **Standing behavior unchanged for now:** capability ≠ auto-push. The "ask
  before pushing" habit and the ralph private-branch guard stay until explicitly
  relaxed — loosening *credentials* isn't the same as "push without asking."
- Pairs with the egress decision in [0724d] (data here is low-sensitivity;
  referee reports at worst).

[0724d]: 0724d,google-firewall-open.md
