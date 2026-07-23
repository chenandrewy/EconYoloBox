# Codex CLI: remove Skills from `@` autocomplete

2026-07-17, New York time

## Problem

With the `mentions_v2` feature enabled, Codex CLI mixes Skills into the `@` autocomplete menu. The desired behavior is to keep `@` dedicated to file search while accessing Skills separately through `$`.

## Recommended fix

Disable `mentions_v2`:

```zsh
codex features disable mentions_v2
```

Then fully quit and restart Codex CLI. This restores the older behavior:

- `@` searches for files.
- Skills are no longer mixed into the `@` autocomplete menu.
- Skills remain separately accessible through `$`.

## Verify the setting

```zsh
codex features list | grep mentions_v2
```

## Manual configuration

The setting can also be changed directly in `~/.codex/config.toml`:

```zsh
code ~/.codex/config.toml
```

Add `mentions_v2 = false` under the existing `[features]` section:

```toml
[features]
mentions_v2 = false
```

Do **not** create a second `[features]` section if one already exists.

## Re-enable later

```zsh
codex features enable mentions_v2
```

## Avoid

Do not rely on undocumented bundled-Skill settings such as:

```toml
[skills.bundled]
enabled = false
```

There have been reports of unstable behavior involving the bundled Skills directory. Disabling `mentions_v2` is the cleaner solution when the goal is to make `@` file-only again.
