# Devcontainer npm and Codex versioning

We reviewed how the root `.devcontainer` installs npm and Codex during a
rebuild.

The Dockerfile starts from:

```dockerfile
FROM node:20
```

That base image provides Node.js and npm. The devcontainer does not
explicitly install or pin npm, so the npm version comes from whatever the
`node:20` image contains when the image layer is built.

The Codex CLI is installed later with:

```dockerfile
ARG CODEX_CLI_VERSION=latest

RUN npm install -g \
  @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION} \
  @openai/codex@${CODEX_CLI_VERSION}
```

Because `CODEX_CLI_VERSION` defaults to `latest`, a fresh uncached build
installs whatever version is currently behind npm's `@openai/codex`
`latest` dist-tag. If Docker reuses the cached `RUN npm install -g ...`
layer, the existing installed Codex version can persist instead of being
resolved again.

The suspected downgrade from a `0.130+` Codex version to `0.128.0` is
unlikely to be caused directly by npm 10 versus npm 11. For a global
install of `@openai/codex@latest`, npm should install the version targeted
by the registry's `latest` dist-tag. More plausible explanations are:

- Docker reused an older cached layer.
- `CODEX_CLI_VERSION` was overridden during the build.
- The package's `latest` dist-tag pointed to `0.128.0` at build time.
- The observed version came from a different container/image than expected.

The pragmatic fix is to pin Codex explicitly if reproducibility matters:

```json
"CODEX_CLI_VERSION": "0.x.y"
```

Likewise, pinning npm explicitly would make sense only if we want npm 11
behavior for a concrete reason. Updating just because npm prints a newer
major-version notice adds moving parts without fixing the Codex versioning
issue. The larger reproducibility issue is the use of `latest` for the AI
CLI packages.
