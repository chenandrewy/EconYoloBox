# Workspace Sandbox

This repository root is a shared sandbox for active projects plus the harness used to build and run agentic tooling around them.

Current active projects:

- `Ref-JF`
- `Singularity`

The rest of the root-level files and directories are primarily support infrastructure.

Root-level dot folders:

- `.agent-guidelines/`: agent operating guidance
- `.agents/`: agent/plugin configuration
- `.claude/`: Claude-related local config
- `.credentials/`: local credential and environment support
- `.devcontainer/`: shared root devcontainer for the sandbox environment
- `.git/`: repository metadata

Other root-level support files:

- `SANDBOX-CLAUDE.md` and related files: sandbox-specific operating notes

Project-specific setup can still live inside individual project directories. The root `.devcontainer` is the shared workspace container used for the overall sandbox and build/tooling flow.

## Devcontainer Image Size Notes

The shared workspace devcontainer is built locally from `.devcontainer/Dockerfile`, which starts from the official `node:20` image. When VS Code or the Dev Containers tooling builds it, Docker tags the resulting image with an auto-generated local name like `vsc-sandbox-<hash>:latest`.

Docker may report different sizes for the same image depending on which command is used:

- `docker image inspect` reported about `7.08GB`
- `docker system df -v` reported about `21.6GB`
- `docker history` underreported some large steps
- `docker buildx du --verbose` best explained the larger `21.6GB` figure because it showed the unpacked BuildKit snapshot sizes for the build steps

The image is genuinely very large. The main contributors are:

- the large `apt-get install ... texlive-full ...` layer in `.devcontainer/Dockerfile`
- the Python environment and `pip install` layer
- recursive metadata-changing layers such as `chown -R node:node /opt/venv`
- recursive metadata-changing layers such as `chmod -R a+w /usr/local/lib/R/site-library`
- the global AI CLI installs, plus LyX, Pandoc, and related tooling

In one measured build, BuildKit accounting showed roughly:

- `13.09GB` for the `apt-get install` layer that includes `texlive-full`
- `1.33GB` for the Python `pip install` layer
- `1.37GB` for `chown -R node:node /opt/venv`
- `762MB` for `chmod -R a+w /usr/local/lib/R/site-library`
- `852MB` for the global npm AI CLIs

So the large image size is mostly expected from the TeX toolchain, but the recursive `chown` and `chmod` steps also add substantial avoidable weight.
