# 0915c — codex .devcontainer removed upstream

Messy notes. Snapshot, don't tidy.

## trigger
Docs page https://learn.chatgpt.com/docs/agent-approvals-security#run-codex-in-dev-containers
links `github.com/openai/codex/tree/main/.devcontainer` — 404s now. Went digging.

## finding
Folder wasn't lost — deliberately deleted from openai/codex.

- removal commit `f419c3214` — "Remove the repository devcontainer configurations (#43915)", 2026-09-08
  - deleted whole `.devcontainer/` tree + Dependabot devcontainers entry + some codex-rs/.gitignore rules
  - PR opened by bot `copyberry`, ZERO review comments, no stated why beyond "what changed"
- last-good commit (parent) = `900b1e4cec1c4eada106a8071fc89c11c50de9a6`
  - browse: https://github.com/openai/codex/tree/900b1e4cec1c4eada106a8071fc89c11c50de9a6/.devcontainer

## what was in there at 900b1e4c (11 files, docs only mentioned 3)
Dockerfile, Dockerfile.secure, devcontainer.json, devcontainer.secure.json,
init-firewall.sh, post-start.sh, post_install.py, README.md,
codex-install/{package.json, pnpm-lock.yaml, pnpm-workspace.yaml}

## why (inferred, NOT stated in removal PR)
Timeline is the story:
- 2026-08-18 PR #39283 "Document secure devcontainer DNS exfiltration risk"
  - Why: "secure devcontainer's firewall does not apply its domain allowlist to
    DNS traffic, so it does not provide secure DNS resolution for untrusted code"
  - downgraded guidance: trusted repos only; DNS-via-restricted-resolver = partial
    mitigation only; allowlisted HTTPS still an exfil path
- 2026-09-08 removed the whole thing (#43915)
- read: the "secure" profile couldn't actually contain untrusted code; pulling it
  avoids handing out a config that implies more security than it delivers.
  (my inference — no human wrote this down in the PR)

## relevance to us
Our init-firewall.sh (the one I'm host-switching in SANDBOX.toml, branch
firewall-host-switch) descends from a config OpenAI flagged as leaky then retired.
DNS not filtered; allowlisted HTTPS still exfiltrable. Bears on what our sandbox
actually guarantees. See also memory: devcontainer-firewall-rerun-brick.

## todo maybe
- pull files at 900b1e4c locally before they're annoying to find
- read the removed README.md — might say more than the PR did
