# Tracing Anthropic's current agent-containment guidance to its sources

Date: 2026-08-21 (NY)

Companion to [0821a,pre-publication-security-audit.md]. That entry audits the
EconYoloBox publication checkout; this one establishes **what Anthropic actually
publishes, where each statement lives, and how much weight each source can
carry**. Written because `docs/features.md` in that checkout rests its safety
argument on inherited upstream design, and I wanted the provenance of that claim
to be checkable rather than remembered.

## Method

Everything below was retrieved 2026-08-21, not recalled:

- Repo files fetched directly over the allowlisted GitHub ranges
  (`raw.githubusercontent.com`, `api.github.com`), HTTP 200, quoted by line
  number.
- Docs pages retrieved through the model provider's fetch path, since
  `code.claude.com` is not on the container allowlist. Prose is quoted verbatim
  from the page body.

Where I am inferring rather than quoting, it says so.

## The headline: the framing is not in the repo

The assumption worth checking was "the reference devcontainer exists to make
YOLO mode safe." That is **correct in substance but absent from the repository**.

`anthropics/claude-code` contains, under `.devcontainer/`, exactly three files —
`Dockerfile`, `devcontainer.json`, `init-firewall.sh`. There is no
`.devcontainer/README.md`. The repo `README.md` never mentions it: zero matches
for `container`, `devcontainer`, `dangerously`, `skip-permissions`, `sandbox`, or
`yolo` across `README.md` and `SECURITY.md`. `SECURITY.md` is 12 lines of
HackerOne vulnerability-reporting policy and nothing else.

The only framing anywhere in the repo is a single string in `devcontainer.json`:

```json
"name": "Claude Code Sandbox",
```

All of the actual doctrine lives on the docs site. That matters for source
hygiene: the repo is an artifact, not a specification, and reading it tells you
nothing about intended use.

## Source inventory

| Source | Type | Authority | Governs |
|---|---|---|---|
| [Development containers](https://code.claude.com/docs/en/devcontainer) | Docs | Normative | Intended use, limits, the reference container's status |
| [Security](https://code.claude.com/docs/en/security) | Docs | Normative | Permission model, prompt injection, best practices |
| [Sandboxing](https://code.claude.com/docs/en/sandboxing) | Docs | Normative | Filesystem/network isolation for Bash |
| [Sandbox environments](https://code.claude.com/docs/en/sandbox-environments) | Docs | Normative | Comparison of isolation approaches |
| [Permission modes](https://code.claude.com/docs/en/permission-modes) | Docs | Normative | Plan / auto / bypass |
| `anthropics/claude-code` `.devcontainer/` | Code | **Example only** (see below) | Nothing; it is an illustration |
| `SECURITY.md`, `README.md` | Repo docs | Irrelevant here | Vuln reporting; installation |

## The status of the reference container, in its own words

> It is provided as a working example rather than a maintained base image; use it
> to see how the pieces fit together before applying them to your own
> configuration.

and:

> The reference configuration consists of three files. None of them are required
> when you add Claude Code to your own dev container through the feature, but
> they show one way to combine the pieces.

**This is weaker than the warrant `features.md` claims.** That file currently
says keeping the upstream shape is deliberate because "It is a design many
people have reviewed, and it means the safety argument does not rest on this
repo's own judgment." Anthropic describes the same artifact as an illustration,
explicitly not maintained as a base image. Combined with [0821a] §1 — the two
open ports are original code from the initial commit, untouched across ten
subsequent commits to that file — "many people have reviewed this" is not
supportable. It should be softened before publication. Prose change, no code.

Note also that the **supported** install path is now a Dev Container Feature,
`ghcr.io/anthropics/devcontainer-features/claude-code:1.0`, added to any base
image. Copying `.devcontainer/` is presented as the alternative for people who
want the hardened example. Our box descends from the copy, which is a legitimate
choice, but it means we inherit an artifact that upstream does not treat as a
supported surface.

## Where the docs corroborate 0821a, verbatim

The useful discovery is that Anthropic already documents, in plain language,
three of the things that entry found independently.

**On §2 (host-executed config / bind-mount writes):**

> Skipping permission prompts removes your opportunity to review tool calls
> before they run. Claude can still modify any file in the bind-mounted
> workspace, which appears directly on your host, and reach anything the
> container's network policy allows.

That is the structural half of §2, stated by the vendor. It strengthens the
framing arrived at last session: this is a platform property, not a local defect,
and documenting it is defensible.

And separately, on repository-resident policy:

> Because the Dockerfile lives in the repository, anyone with write access can
> change or remove this step. For policy that engineers cannot bypass by editing
> repository files, deliver managed settings through server-managed settings or
> your MDM instead.

This is the same argument applied to `/etc/claude-code/managed-settings.json`,
which our Dockerfile bakes in from a repo file. `features.md` already hedges
correctly ("like the rest of the agent configuration, it is not the sandbox
boundary"), but the docs supply both the precise reason and the named
alternative — server-managed settings or MDM — which we do not currently
mention.

**On §1 (the open ports):**

> The reference container includes an `init-firewall.sh` script that blocks all
> outbound traffic except the domains Claude Code and your development tools
> need.

The script does not do this — TCP/22 and UDP/53 are permitted to every
destination ([0821a] §1). So the docs describe the reference script more
strongly than the script behaves, which is worth knowing: our `features.md`
inherited an overclaim that originates upstream rather than with us.

The same page also designates the firewall as the specific mitigation for
bypass mode:

> Pair this flag with the network egress restrictions above to limit what a
> bypassed session can reach.

That makes the port-22 gap more pointed, not less: egress restriction is the
named compensating control for exactly the mode we run in.

**On §4 (telemetry):** there are documented switches we do not set —
`CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1` and `DISABLE_AUTOUPDATER=1` via
`containerEnv`. Relevant to the `sentry.io` / `collector.github.com` entries in
our allowlist. Caveat from the same page: the first also disables feature-flag
evaluation, which Remote Control depends on — and we run every session under
`--remote-control`, so setting it would break `ccsessions`/`cckill`. Not a free
win.

## A guideline we appear to contradict

New, and not in [0821a]. From the warning block on the devcontainer page:

> Avoid mounting host secrets such as `~/.ssh` or cloud credential files into
> the container; prefer repository-scoped or short-lived tokens.

Our entire credential design does the opposite: host Keychain secrets resolved
on the host and bind-mounted to `/run/secrets/credentials.env`. The WRDS
password in particular is long-lived, host-scoped, and neither
repository-scoped nor short-lived.

Being fair to the design: `features.md` argues a narrower claim carefully — that
the secret exists in one file read on demand, rather than spread across every
process environment and into Docker's `Config.Env` — and that argument is sound
and unaffected by this. The tension is at a level above it. Anthropic's advice is
*do not bring the long-lived host credential into a bypass-mode container at
all*; our design assumes it must be there and minimises its spread once inside.

For WRDS there may be no short-lived alternative, which would make this an
accepted risk rather than a fixable defect — but it is currently accepted
silently. The honest move at publication is a sentence in `features.md` naming
the divergence and why.

The same warning also says:

> Only use dev containers when developing with trusted repositories, and monitor
> Claude's activities.

Worth quoting in our docs, because "trusted repositories" is doing real work: the
threat model assumes the *repo* is trusted and the container guards against
mistakes and untrusted *inputs*, not against a hostile codebase.

## What the surrounding guidance now looks like

The devcontainer is no longer the only sanctioned answer, which is context our
README does not have:

- **Auto mode** — a classifier model reviews actions instead of the user;
  offered on the devcontainer page as the alternative to bypass ("If you want
  fewer prompts without disabling safety checks").
- **Sandboxed Bash tool** — OS-level filesystem/network isolation, configured
  with `/sandbox`.
- **Sandbox environments** — a whole page comparing dev containers against the
  built-in Bash sandbox, custom containers, and VMs.
- **`permissions.disableBypassPermissionsMode: "disable"`** — managed-settings
  key to forbid bypass entirely. The existence of an org control to *ban* what
  we do by default is worth knowing when describing the box to others.
- The security page files dev containers under best practices as "additional
  isolation" — a layer, not the boundary.

None of this obsoletes the box. It does mean the accurate pitch is "one option,
tuned for economics research," not "the way to run agents safely."

## Out of scope of all the above

Anthropic's guidance says nothing about **Codex**, which we run in the same
container under `--dangerously-bypass-approvals-and-sandbox`. The
`/etc/codex/requirements.toml` layer is our own construction validated by our own
`test-agent-policy.sh`. No inherited warrant applies to that half of the box, and
`features.md` should not let the Anthropic lineage implicitly cover it.

## Consequences for publication

Ordered by cost, all prose:

1. Soften the "many people have reviewed" warrant in `features.md` to match what
   Anthropic actually claims for the reference container.
2. Name the divergence from "avoid mounting host secrets," with the reasoning
   for accepting it.
3. Quote "only use dev containers when developing with trusted repositories" —
   it states the threat model more crisply than we do.
4. Say that the Anthropic lineage covers the Claude half only, not Codex.
5. Note that the reference config is an example and the supported path is now
   the Dev Container Feature, so a reader knows what they are adopting.

Nothing here is a code change, and none of it is blocked by the deadline that
put [0821a] on ice.

[0821a,pre-publication-security-audit.md]: 0821a,pre-publication-security-audit.md
[0821a]: 0821a,pre-publication-security-audit.md
