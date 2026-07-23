# 0721a — `dccode` stale rebuild prompt for subfolders

2026-07-21 (NY)

## Symptom

Running `dccode .` from `Ref,JEconom/` opened the project in the root
`1-SANDBOX` devcontainer, but VS Code warned:

> Configuration file(s) changed. The container might need to be rebuilt to
> apply the changes.

This looked wrong because the root `.devcontainer` had just been rebuilt.

## Investigation

`dccode` behaved correctly. It walked upward to the enclosing
`.devcontainer/devcontainer.json` and generated a remote URI with:

- host/devcontainer root: `1-SANDBOX`
- container folder: `/workspace/Ref,JEconom`
- Docker context: `desktop-linux`

The Dev Containers log showed that VS Code found container `355aee178347`,
reported `Container already running`, and reused it. The container had been
created on July 20 at 9:21 PM from image `48e8d27b16de`. No new image was
built and no second project-specific container was selected.

The current Dockerfile SHA-256 was
`d46c2b51757fc6457df8bde7d99c072ad33bbb253ca2e91ac4e40a3ded974f42`,
which exactly matched the hash VS Code stored for the `Ref,JEconom` remote
workspace.

## Root cause

The warning is not based on a comparison between the current configuration
and the configuration used to build the running container.

The Dev Containers extension stores hashes of `devcontainer.json` and its
Dockerfile in VS Code's **per-workspace** state. Every container subfolder
opened as a folder—such as `/workspace/Ref,JEconom`—has separate state from
the `/workspace` root and from every other subfolder.

Recent root devcontainer changes and the subsequent rebuild refreshed the
root workspace's state, but not the older state associated with the
`Ref,JEconom` window. When that subfolder was opened again, VS Code compared
the current files with the subfolder's stale historical snapshot and emitted
the warning. It did not establish that the running container was stale.

## Resolution

Choose **Ignore** when the running root container is known to have been rebuilt
after the listed configuration changes. Ignore updates that subfolder's saved
hashes; for `Ref,JEconom`, the workspace state was updated at 8:09 AM on July
21. The warning should not recur there until the devcontainer files change
again.

Other infrequently opened subfolders may show the same one-time warning after
a root devcontainer change. A real rebuild is warranted only when the running
container predates a relevant configuration change, not merely because this
per-workspace tracker reports one.
