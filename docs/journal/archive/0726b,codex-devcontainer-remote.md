# Codex remote control in the devcontainer

Date: 2026-07-26 (NY)

Status: **reported working on Linux, not yet validated in this container.**

## Bottom line

The ChatGPT desktop app cannot run in this Ubuntu devcontainer. OpenAI supports
the desktop app on macOS and Windows, not Linux.

Inside the container, the available options are:

- the Codex CLI;
- the experimental `codex remote-control` daemon for direct Remote pairing.

For phone access to Codex running in this exact container, test
`codex remote-control`. Desktop-app/SSH is an outside-the-container alternative.

## What is already available

- The image installs `@openai/codex`.
- The running container has Codex CLI 0.145.0, including
  `codex remote-control`.
- Codex runs as `node` with `CODEX_HOME=/home/node/.codex`.
- A named Docker volume preserves that directory across container recreation.
- `gptchat-yolo` starts Codex with approvals and sandboxing bypassed.
- The firewall permits normal OpenAI authentication and API destinations.

## Test direct Remote control

Inside the container:

```zsh
codex login status
codex remote-control start
codex remote-control pair
codex remote-control stop
```

OpenAI marks this command experimental. `start` runs the local Codex app-server
daemon with Remote enabled; `pair` prints a short-lived manual pairing code.
Use the same ChatGPT account and workspace in the CLI and mobile app.

Validate that the phone accepts the pairing and that remote commands report
`DEVCONTAINER=true`, user `node`, and a path under `/workspace`. If startup
reports a blocked destination, review that exact destination before changing
the firewall.

This relay-based route should not require publishing a Docker port. Do not
expose `codex app-server` or an SSH listener publicly.

### What community reports add

The linked Reddit report got Linux CLI 0.130.0 working with ChatGPT login,
outbound internet, the same mobile account, and `codex remote-control`; the
machine then appeared by hostname in the mobile Codex/Remote view.

Its extra `codex features enable remote_control` step predates this container's
0.145.0 CLI, which exposes `remote-control` and `pair` directly. Do not copy the
old feature flag or its systemd service here: this devcontainer does not use
systemd. Test the foreground command first.

Reports are mixed. Users mention hosts disappearing after updates, WebSocket
timeouts, stale/offline enrollments, and slow or missing history. One recent
report says sending a mobile follow-up forked the thread instead of joining the
already-running CLI interaction. Test that behavior before relying on Remote to
supervise a long-running `/goal`.

These are community observations, not guarantees. The current `pair` command
also postdates a Linux issue filed against 0.142.5, whose main complaint was
that headless hosts had no pairing command.

## Normal CLI use

```zsh
codex
gptchat-yolo
```

The CLI is ready now and uses the container's tools, firewall, and persistent
Codex configuration.

## Sources

- [Codex CLI remote-control
  commands](https://learn.chatgpt.com/docs/developer-commands?surface=cli#cli-codex-remote-control)
- [ChatGPT desktop app](https://learn.chatgpt.com/docs/app)
- [Reddit: Linux CLI setup and user
  reports](https://redd.it/1tdizpl)
- [GitHub: older headless-Linux pairing
  gap](https://github.com/openai/codex/issues/31183)
- [OpenAI forum: WebSocket timeout after
  enrollment](https://community.openai.com/t/1384539)
