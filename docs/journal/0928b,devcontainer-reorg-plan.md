# Devcontainer reorganization plan

2026-09-28. Proposed, not implemented. Based on `cleanup/reorg-rename` at
`628f9db` and the changes since `main`.

The branch has already moved host support, provisioning, and credentials into
`infra/`, exposed agent configuration in `agents/`, and exposed work utilities
in `tools/`. Continue that organization rather than treating this as an isolated
cleanup of `.devcontainer/`.

## Recommended boundary

- `.devcontainer/`: container definitions and a short navigation README.
- `infra/`: implementation that builds, starts, configures, and checks the environment.
- `agents/`: visible guidance, skills, settings, managed policy, and their closely
  related helpers. Keep the seed script and status line here with their inputs.
- `tools/`: utilities used to do work: PDF processing, citations, LaTeX, and the
  existing session commands. Being a script does not make something infrastructure.
- Tests live beside the infrastructure component they verify, following the
  existing `infra/host/tests/` and `infra/credentials/tests/` convention.

Keep the two config paths, Dockerfile, and Dockerfile-specific ignore file in
`.devcontainer/`. Moving the Dockerfile is possible, but keeping the image recipe
beside the two configs gives the small directory a clear purpose. Existing host
launcher discovery and config identity can remain stable.

## File moves

All sources below are relative to `.devcontainer/`; filenames stay unchanged.

| Current files | Destination directory |
| --- | --- |
| `post-start.sh`, `check-checkout.sh`, `check-yolo-boundaries.sh` | `infra/container/` |
| `init-firewall.sh`, `posture.sh`, `package-mode.sh` | `infra/container/` |
| `shellrc.sh`, `tex-refresh.sh` | `infra/container/` |
| `home/Rprofile` | `infra/container/home/` |
| `find-python.sh`, `write-local-env.sh` | `infra/host/` |
| `inject-credentials.py` | `infra/credentials/` |
| `tests/test_inject_credentials.py` | `infra/credentials/tests/` |
| `tests/test-packages.sh`, `tests/test-optional.sh` | `infra/setup/tests/` |
| `tests/test-posture.sh`, `tests/test_config_twins.py` | `infra/container/tests/` |
| `test-firewall.sh`, `test-agent-policy.sh` | `infra/container/tests/` |

The remaining `.devcontainer/` contains only `devcontainer.json`,
`normie/devcontainer.json`, `Dockerfile`, `Dockerfile.dockerignore`, and `README.md`.
Use one flat `infra/container/` implementation directory initially; more categories
such as `runtime/`, `security/`, and `bin/` would add navigation without much benefit.

`test-agent-policy.sh` is also an operational startup diagnostic. Preserve its
image-installed `/usr/local/bin/test-agent-policy.sh` command, ownership, and
`--warn-only` startup invocation even though its source joins the other tests.
Similarly, retain the installed `tex-refresh` and firewall command paths.

Keep `tex-refresh.sh` with container runtime support: it configures the consumer's
LyX state at startup, whereas `infra/setup/` provisions shared software volumes.
Keep `package-mode.sh` with posture reporting for the same reason.

## Documentation

Replace the long `.devcontainer/README.md` with a short explanation of the two
configurations, image recipe, and links to implementation documentation.
Put the container operations material in `infra/container/README.md`, credential
material in `infra/credentials/README.md`, and agent configuration/seeding material
in `agents/README.md`. Preserve useful section anchors at their destinations and
update current inbound links. Add a short `infra/README.md` directory map.

Update root README, component READMEs, current docs, script run instructions,
and agent guidance/status-line paths together. Leave existing journal entries
as historical snapshots, including their old paths.

## Implementation sequence and dependencies

1. Move the files and update their callers in one coherent change. In both JSONC
   configs, update `initializeCommand` and `postStartCommand`. Update Dockerfile
   COPY paths and the baked shell source line. Update status-line and shell
   references, test fixtures/assertions, imports, and relative root calculations.
   In particular, `write-local-env.sh` must still emit the checkout root as
   `LOCAL_CONTAINER_FOLDER`, not `infra/`; `post-start.sh` must still change to
   the checkout root before running its relative commands.
2. Update `Dockerfile.dockerignore` to allow only the new image inputs and existing
   managed policy/base installer inputs. Avoid a blanket `!infra/` inclusion.
   Host credential helpers, tests not installed in the image, and user content
   should stay outside the build context. Verify needed ancestor directories
   and the specific files are included correctly.
3. Redistribute documentation and update all maintained references. Ensure every
   touched script documents how to run it, inputs, and outputs at the top.
4. Run the existing host-runnable config-twin, posture, credential-injection,
   credential-resolution, and host-launcher tests. Use the garage environment
   for host Python checks. Check shell syntax and the final diff. Search tracked
   maintained files for old moved paths; `.devcontainer/` references to retained
   definitions are expected. No new test framework is needed.
5. During an authorized rebuild, verify image COPY inputs and both modes' startup:
   firewall/posture, checkout marker, agent seeding and policy diagnostic, shell
   setup/status line, R profile, and TeX refresh. Run the package acceptance tests
   in both modes; optional package tests require an already provisioned optional
   stack. Firewall acceptance tests target YOLO, since normie intentionally allows
   destinations that the test expects blocked. Do not install missing packages
   merely to complete this reorganization's validation without permission.

Existing containers contain baked references to the old shellrc path. Document
that a rebuild is needed before calling the migration complete; a source-file
move alone does not update those references. Avoid leaving permanent forwarding
scripts at the old locations. Keep volume names, mounts, security settings,
installed command names, and startup ordering unchanged in this pass.

## Utilities outside this pass

Keep `tools/pdf/`, `tools/lit/`, and `tools/latex/` in the foreground as working
tools. `tools/ai-sesh/` is the borderline case: it supports the environment but
also exposes user commands and holds ignored per-machine session data. Leave it
where it is for this pass. A later decision to move it into `infra/` should plan
data and existing home-symlink migration explicitly, not just move tracked scripts.

Success means that `.devcontainer/` explains how to select/build the container,
`infra/` holds its implementation and checks, and `agents/` remains easy to find,
with the existing behavior preserved.
