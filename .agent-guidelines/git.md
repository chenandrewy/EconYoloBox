# Git Conventions

## Merge Strategy
- Default merges should not fast-forward (`merge.ff = false`).
- `git merge --squash` requires `--ff` to override: `git merge --squash --ff <branch>`.

## Worktrees
- On host: create worktrees under `../worktrees/<branch-name>/` (sibling to the repo).
- In containers: create under `/workspace/worktrees/`.
- Always clean up worktrees when done.
