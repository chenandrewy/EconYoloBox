# Devcontainer consolidation

2026-09-28. Implemented the layout agreed after 0928b; that earlier plan is
superseded, left unchanged as a snapshot.

- `infra/credentials/` -> root `credentials/`, including its tests.
- `infra/host/` -> `.devcontainer/host/`, including its tests.
- `infra/setup/` -> `.devcontainer/setup/`.
- Host Python discovery and local environment capture join `.devcontainer/host/`.
- Package acceptance tests join `.devcontainer/setup/tests/`.
- Firewall and agent policy tests join `.devcontainer/tests/`.
- Credential injection stays in `.devcontainer/`, with its test there too.
- `agents/` and `tools/` remain visible and in place. Removed the retired `infra/`.

Updated config initialization commands, Dockerfile inputs, script paths, imports,
test paths, and maintained documentation. The build-context allowlist names only
the scripts and managed policy inputs the Dockerfile consumes. Installed command
paths stay the same. Host setup recognizes the former `infra/host/` registration.
The host environment writer still records the checkout root after moving one
directory deeper; added a temporary-fixture regression check for this.

Passed: 18 Python unittest cases (config twins, injection, credential retrieval,
host setup), 15 posture checks, 19 mocked launcher checks, R credential checks,
Python parsing, shell syntax, and diff whitespace checks. Maintained path audit
leaves only intentional legacy references in migration code/docs/tests. Two
pre-existing documentation links to archived journal files remain unresolved.

No live credential retrieval, package installation, real shell-registration
changes, or container recreation was performed. Docker client is available but
the socket reports permission denied in this session; no workaround attempted.
Live build, firewall, policy, and package acceptance checks remain unverified.

To activate on the host, from the checkout root: rerun
`bash .devcontainer/host/setup.sh`, open a fresh shell, then `ybox --rebuild`.
The rebuild updates config initialization paths and image scripts while retaining
the existing package and authentication volumes.
