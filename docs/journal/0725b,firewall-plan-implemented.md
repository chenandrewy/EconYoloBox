# Implemented: widened firewall + stack installs moved out of the image

Date: 2026-07-25 (NY)

Implements the plan in [0725a]. All three parts landed, plus the doc loosening
that was sitting in its "To do". Firewall changes are **inert until rebuild**
(the installed script is root-owned and `COPY`'d); the install script and doc
changes are live now.

## What changed

**1. `init-firewall.sh` — widened**

- New `goog.json` block, wired exactly like the existing GitHub-meta block
  (fetch → validate each CIDR against the same regex → `ipset add`), with the
  `cloud.json` exclusion stated inline. Verified the `jq`/`aggregate` pipeline
  (`.prefixes[].ipv4Prefix | select(. != null)`) against a sample payload;
  couldn't fetch the real one, since `www.gstatic.com` is exactly what's still
  blocked.
- Added `rspm-sync.rstudio.com` and `cran.r-project.org` to the domain list,
  with a comment saying both exist only for runtime R installs, and that the
  list is permanently reactive to redirect hosts.

**2. `.devcontainer/install-packages.sh` — new**

`install-packages.sh [python|r|all] [--force]`. Same package sets as the old
Dockerfile layers, same special cases (archived `pryr` tarball,
`OpenSourceAP.DownloadR` pinned by commit), verification check preserved at the
end of the R half so a partial install fails loudly. Two changes worth noting:

- **Idempotent, not chunked.** The Dockerfile's chunking existed for layer
  caching, which is meaningless in a script. Instead it filters to what's
  actually missing (`requireNamespace`), so a re-run costs seconds. That's what
  makes "recovery is just re-running it" true rather than aspirational.
- **Verifies Python by distribution name**, via `importlib.metadata`, avoiding a
  dist→module mapping table (scikit-learn/sklearn, PyMuPDF/fitz, ...).

**3. Dockerfile — stripped.** All `pip install` and `Rscript -e
"install.packages(...)"` layers gone, along with the build-time verification
block and the late `requests` layer. Kept: system `-dev` deps, R itself,
`Rprofile.site` (still the snapshot pin), an empty node-owned `/opt/venv`, and
`chmod a+w` on the R site library. Net −60 lines.

**4. Discoverability.** `shellrc.sh` prints a one-line nudge when either stack is
absent, so a post-rebuild container doesn't just look broken. Uses `find`, not a
glob — an unmatched glob is a hard error under zsh's `nomatch`. Measured at 6ms,
silent once the stack is present.

**5. Docs loosened** (the [0724e] TODOs):
- `SANDBOX-CLAUDE.md`: package installs from allowlisted sources no longer need
  permission — only *system* packages do. GitHub language now says the container
  **can** push (credential forwarding is deliberate) and that not pushing is a
  habit, not an enforced wall. Also corrected the stale "a blocked host hangs
  until timeout" line: there's been an explicit `REJECT` rule for a while.
- `.devcontainer/README.md`: new "Analysis stacks" section; the "no GitHub
  credentials by design" claim replaced with what's actually true, including the
  host-side `dev.containers.gitCredentialHelperConfigLocation` switch for anyone
  who wants it off.

## The good part: the diagnosis reproduced live

Running the R half in the *current* (un-rebuilt) container reproduced [0725a]'s
central claim on the first try. `tictoc` was the only package it tried to
install — i.e. the only one actually missing, the casualty of the earlier failed
reinstall — and it died with:

```
URL 'https://rspm-sync.rstudio.com/v4/1/packages/8fcdb7...tar.gz':
  status was 'Couldn't connect to server'
MISSING (R): tictoc
```

So: the redirect-host diagnosis is confirmed, the skip-what's-installed logic
works, and the verification check fails loudly as designed. The same run is the
regression test after rebuild — it should install `tictoc` and print `R stack
OK`.

## Open item measured: `rspm-sync` IP stability

[0725a] wanted one `dig`. Result: `rspm-sync.rstudio.com` → **CloudFront**
(`18.160.10.{29,31,74,78}`), and five queries a second apart returned the
identical four. So a start-time resolution is stable enough in the short run,
and it's re-resolved on every container start anyway — same deal as every other
domain in the list. The residual risk is rotation *during* a long-lived
container, which is not specific to this host. No escape hatch built; if it
starts biting, the additive `ipset add` helper is the answer, and it needs a
sudoers entry, so it's a user decision.

## Also noted

The empty-string `credential.helper` override from [0724e]'s session is already
gone — this is a fresh container and VS Code re-injected the helper into both
the system and global configs. Nothing to undo.

## Still open

- Fine-grained PATs via `.credentials/` instead of forwarding the host's full
  credential — still deferred.
- More redirect hosts on the install script's first full post-rebuild run. The
  `tictoc` failure above only proves the path up to the *first* blocked host.

[0724e]: 0724e,credential-helper-close.md
[0725a]: 0725a,firewall-plan-update.md
