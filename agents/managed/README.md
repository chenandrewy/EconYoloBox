# Managed agent policy

These files are baked into the image, not seeded at container start. The
Dockerfile `COPY`s each one to a root-owned, read-only system path, so a change
takes effect only after a rebuild (`ybox --rebuild` on the host).

| File | Installed as | Role |
| --- | --- | --- |
| `YOLOBOX-claude-managed-settings.json` | `/etc/claude-code/managed-settings.json` | Claude Code policy; user and project settings cannot override it |
| `YOLOBOX-codex-requirements.toml` | `/etc/codex/requirements.toml` | Codex policy; outranks user config, profiles and CLI overrides |
| `YOLOBOX-codex-config.toml` | `/etc/codex/config.toml` | Codex system defaults; user config can override them |

Agents in the container can read these files here but cannot change the
installed copies. `.devcontainer/test-agent-policy.sh` checks that the
installed policy is in force. See "Agent Config" in the
[devcontainer README](../../.devcontainer/README.md#agent-config).
