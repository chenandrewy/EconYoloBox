# Workspace Sandbox

This repository root is a shared sandbox for active projects plus the harness used to build and run agentic tooling around them.

The rest of the root-level files and directories are primarily support infrastructure.

Root-level dot folders:

- `.credentials/`: local credential and environment support
- `.devcontainer/`: shared root devcontainer for the sandbox environment
- `.devcontainer/agents/`: canonical agent guidance and enforced agent settings (see `.devcontainer/README.md`)
- `.git/`: repository metadata
- `.tools/`: local utility scripts for workspace maintenance and document processing

Project-specific setup can still live inside individual project directories. The root `.devcontainer` is the shared workspace container used for the overall sandbox and build/tooling flow.

## Devcontainer build cache

Set Docker's BuildKit garbage-collection budget to `35GB` on each host. The
default `20GB` budget is smaller than this devcontainer's build cache and causes
expensive layers to be evicted between rebuilds. See
[Devcontainer image size and build cache](docs/image-size.md) for setup and
diagnostic details.

## Plans for eventual public release.

We will **eventually** clean up the git history in a way that allows for public release. But our immediate goal is a quality sandbox for AI powered econ research.
