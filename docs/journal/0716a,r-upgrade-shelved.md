# 0716a — R upgrade + econometrics packages: shelved, with a better plan

**Status: implemented 2026-07-18** — the preferred plan below (r-builds R 4.5.3 + P3M snapshot 2026-07-15 via a single `Rprofile.site`, econometrics packages, `OpenSourceAP.DownloadR` pinned to commit `689db7d`) now lives in `.devcontainer/Dockerfile`, plus `packagemanager.posit.co` added to the firewall allowlist. Simplifications vs. the sketch below: no `ENV MAKEFLAGS` (would leak into runtime shells; `Ncpus=2` in `Rprofile.site` covers it), one merged verification block, node:22/trixie bump left out of scope. **Pending: rebuild verification on both machines** — in the build log, confirm `installing *binary* package` (not `*source*`) in the R layers; arm64 P3M binary coverage is the one unverified assumption, and a silent source fallback is undetectable except by build speed/log.

*(Original note follows; "shelved" framing is historical.)*

**Status: shelved.** A working Dockerfile change (CRAN Debian repo + new R packages) was implemented, verified with `docker build --check`, then **reverted** — too big a change for right now, and investigation surfaced a strictly better design (Posit r-builds + Package Manager snapshots) worth doing properly later. This note records everything needed to pick it back up.

## Motivation

The mp-rep replication (`Live,Risk-vs-Writing/dev/mp-rep/mp-rep.R`) needs `fixest` (blocking) and `OpenSourceAP.DownloadR` (Chen–Zimmermann data download), plus a set of optional publication/econometrics helpers. Installing them fails or fights CRAN because the container's R is **4.2.2 (Oct 31, 2022)** — Debian bookworm's frozen `r-base`, which current CRAN packages increasingly no longer support ("not available for this version").

## Version landscape (verified 2026-07-16)

| Source | R version | Notes |
|---|---|---|
| Debian bookworm archive (current container) | 4.2.2 (2022-10-31) | frozen forever; the problem |
| Debian trixie archive | 4.5.0 (2025-04-11) | newer freeze, same aging dynamic |
| CRAN Debian repo, `bookworm-cran40` | 4.5.3 (2026-03-11) | tracks CRAN's Debian builds; **not pinned** |
| CRAN Debian repo, `trixie-cran40` | 4.5.3 | identical — no gain from switching base |
| Upstream R releases | 4.6.1 (2026-06-24); 4.6.0 (2026-04-24) | CRAN's Debian builds lag upstream by months |

Other facts gathered:

- `bookworm-cran40` means "R 4.x series for bookworm," not 4.5 specifically — a rebuild picks up whatever CRAN currently serves. apt-pinning against it is brittle: the repo deletes old builds when a new one lands.
- Both Debian sources are the same upstream R with essentially the same packaging; they differ in policy (frozen vs. tracking) and trust anchor (Debian archive keys vs. Johannes Ranke's personal CRAN key `95C0FAF38DB3CCAD0C080A7BDC78B2DDEABC47B7`, fetched from `keyserver.ubuntu.com`).
- `node:20-trixie` images exist, but a trixie move breaks the LyX pin `2.4.3-1~bpo12+1` (bookworm-backports build) and gains no R currency. Node 20 hit EOL April 2026 — the natural moment to migrate the Debian base is a future `node:22`+ bump.
- Package version requirements are modest: `fixest`/`sandwich`/`lmtest`/`car` want R ≥ 3.5–4.0; `modelsummary`/`marginaleffects`/`arrow`/`kableExtra` roughly ≥ 4.1–4.3. Any R ≥ 4.4 is comfortable; currency is not the requirement — **stability across machines is**.

## Packages to add (when un-shelved)

Required by mp-rep.R:

- `fixest` — the regressions; blocking
- `remotes` + `OpenSourceAP.DownloadR` from GitHub: **`tomz23/OpenSourceAP.DownloadR`** (not on CRAN). Install at image build time — the runtime firewall allowlist doesn't apply during `docker build` (see `0715a,firewall-fails-open.md`)

Optional helpers (install in late layers):

- `modelsummary` — fixest models → LaTeX/markdown/Word tables
- `sandwich` + `lmtest` — robust/clustered SEs for base `lm`/`glm`
- `kableExtra` — LaTeX table styling on top of knitr
- `arrow` — parquet/feather I/O, interop with the venv's `pyarrow` (compiles its C++ bundle from source on Debian — many minutes — unless installed as a P3M binary, below)
- `car` — regression diagnostics / hypothesis tests
- `marginaleffects` — contrasts/marginal effects, pairs with modelsummary

Skip `plm`/`estimatr` — fixest covers panel FE and clustered SEs. Python side needs nothing.

## The reverted change (interim CRAN-repo approach)

This built cleanly and works; it just tracks CRAN's Debian builds instead of pinning. Kept here for reference / re-application:

```diff
diff --git a/.devcontainer/Dockerfile b/.devcontainer/Dockerfile
index e74d907..5cec918 100644
--- a/.devcontainer/Dockerfile
+++ b/.devcontainer/Dockerfile
@@ -52,6 +52,12 @@ RUN wget -O /tmp/git.tar.gz "https://mirrors.edge.kernel.org/pub/software/scm/gi
   make -C "/tmp/git-${GIT_VERSION}" prefix=/usr/local NO_TCLTK=YesPlease NO_GETTEXT=YesPlease install && \
   rm -rf /tmp/git.tar.gz "/tmp/git-${GIT_VERSION}"
 
+# Use CRAN's Debian repo so r-base installs current R (4.4/4.5) instead of
+# bookworm's stock 4.2.2, which CRAN no longer builds packages for.
+RUN gpg --keyserver keyserver.ubuntu.com --recv-key '95C0FAF38DB3CCAD0C080A7BDC78B2DDEABC47B7' && \
+  gpg --armor --export '95C0FAF38DB3CCAD0C080A7BDC78B2DDEABC47B7' > /etc/apt/trusted.gpg.d/cran-debian.asc && \
+  echo "deb http://cloud.r-project.org/bin/linux/debian bookworm-cran40/" > /etc/apt/sources.list.d/cran.list
+
 # Install heavy workflow toolchains after Git so later workflow changes do not
 # force a Git rebuild.
 RUN apt-get update && apt-get install -y --no-install-recommends \
@@ -243,6 +249,33 @@ RUN pip install --no-cache-dir \
   requests \
   && chown -R node:node /opt/venv
 
+# R packages for mp-rep (Live,Risk-vs-Writing/dev/mp-rep), in late layers so
+# edits here don't invalidate the heavy layers above.
+# Required by mp-rep.R: fixest (regressions) and OpenSourceAP.DownloadR
+# (Chen-Zimmermann data download; GitHub-only package).
+RUN Rscript -e "install.packages(c('fixest','remotes'), repos='https://cloud.r-project.org')"
+RUN Rscript -e "remotes::install_github('tomz23/OpenSourceAP.DownloadR')"
+
+# Optional econometrics/publication helpers:
+#   modelsummary    - fixest models -> LaTeX/markdown/Word tables
+#   sandwich+lmtest - robust/clustered SEs for base lm/glm
+#   kableExtra      - LaTeX table styling on top of knitr
+#   arrow           - parquet/feather I/O, interop with Python pyarrow
+#   car             - regression diagnostics / hypothesis tests
+#   marginaleffects - contrasts/marginal effects, pairs with modelsummary
+RUN Rscript -e "install.packages(c('modelsummary','sandwich','lmtest','kableExtra'), repos='https://cloud.r-project.org')"
+RUN Rscript -e "install.packages(c('arrow','car','marginaleffects'), repos='https://cloud.r-project.org')"
+
+RUN Rscript -e " \
+  pkgs <- c('fixest','OpenSourceAP.DownloadR', \
+            'modelsummary','sandwich','lmtest','kableExtra', \
+            'arrow','car','marginaleffects'); \
+  missing <- pkgs[!vapply(pkgs, requireNamespace, logical(1), quietly=TRUE)]; \
+  if (length(missing)) { cat('MISSING:', paste(missing, collapse=', '), '\n'); q(status=1) }"
+
+# Re-open write access for packages installed after the earlier chmod.
+RUN chmod -R a+w /usr/local/lib/R/site-library
+
 # Copy and set up firewall script
 COPY init-firewall.sh /usr/local/bin/
 RUN chmod +x /usr/local/bin/init-firewall.sh && \
```

## The preferred plan: Posit r-builds + Package Manager snapshot

Goal: **bit-identical R stack on every machine and every rebuild date.** Two pins, both one-line to bump:

### 1. Pin R itself via Posit r-builds

Posit (the RStudio company) hosts pre-compiled R distributions at `cdn.posit.co` (project: `github.com/rstudio/r-builds`). Unlike CRAN's apt repo, **artifacts are immutable and never removed** — verified 2026-07-16 that `debian-12` `.deb`s exist for both `amd64` and `arm64`, and that even ancient versions (4.2.2) are still hosted. Installs to `/opt/R/<version>/` without touching apt's package system; includes headers and recommended packages, so source compiles work with the `build-essential` + `lib*-dev` already in the image. Trust model: HTTPS to Posit's CDN, no package signature.

Replace the `r-base`/`r-base-dev` apt lines with:

```dockerfile
ARG R_VERSION=4.5.3
RUN ARCH=$(dpkg --print-architecture) && \
  wget -O /tmp/r.deb "https://cdn.posit.co/r/debian-12/pkgs/r-${R_VERSION}_1_${ARCH}.deb" && \
  apt-get update && apt-get install -y --no-install-recommends /tmp/r.deb && \
  ln -sf /opt/R/${R_VERSION}/bin/R /usr/local/bin/R && \
  ln -sf /opt/R/${R_VERSION}/bin/Rscript /usr/local/bin/Rscript && \
  rm /tmp/r.deb && apt-get clean && rm -rf /var/lib/apt/lists/*
```

The runtime-write `chmod -R a+w` lines must then target `/opt/R/${R_VERSION}/lib/R/library` instead of `/usr/local/lib/R/site-library`.

### 2. Pin package versions via a P3M date snapshot

Pinning R fixes only half the drift: `repos='https://cloud.r-project.org'` serves *today's* package versions, so two machines building a week apart diverge. Point every `install.packages()` at a dated Posit Package Manager snapshot instead:

```dockerfile
ARG CRAN_SNAPSHOT=https://packagemanager.posit.co/cran/2026-07-15
RUN Rscript -e "install.packages(c('fixest','remotes'), repos='${CRAN_SNAPSHOT}')"
```

Every package resolves to its version as of that date, forever. Bonus: P3M serves pre-compiled Linux binaries (set `HTTPUserAgent` or use the `__linux__/bookworm/` URL form), which turns slow source builds — notably `arrow`'s C++ bundle — into fast downloads.

### Remaining loose ends for implementation

- `OpenSourceAP.DownloadR` comes from GitHub, not CRAN — pin it too (`remotes::install_github('tomz23/OpenSourceAP.DownloadR@<commit-sha>')`) for full reproducibility.
- Migrate the ~10 existing `install.packages` layers to `${CRAN_SNAPSHOT}` in the same pass; the archived-`pryr` special case (line ~130) may become unnecessary if the snapshot date predates its archiving, or can stay as-is.
- Check that `keyring`/`languageserver` and friends behave under `/opt/R` paths (they should; nothing hardcodes `/usr/lib/R`).

## Build-speed improvement: P3M binaries instead of source compiles (added 2026-07-18)

CRAN serves Linux only source tarballs, so every existing `install.packages` layer compiles C/C++/Fortran (`Rcpp`, `data.table`, tidyverse internals; `arrow` would compile the whole Arrow C++ bundle). P3M can serve pre-built per-distro binaries instead, turning those layers into downloads. This is nearly free to adopt because the snapshot URL from step 2 is the same URL that delivers the binaries — two additions:

1. **Splice `__linux__/<distro>/` into the snapshot URL** so P3M knows the target distro:

   ```dockerfile
   ARG CRAN_SNAPSHOT=https://packagemanager.posit.co/cran/__linux__/bookworm/2026-07-15
   ```

2. **Set an R-version-bearing user agent in every `Rscript` install line** — P3M picks a binary compatible with the requesting R version from the UA, and *silently falls back to source* without it:

   ```dockerfile
   RUN Rscript -e "options(HTTPUserAgent = sprintf('R/%s R (%s)', getRversion(), paste(getRversion(), R.version\$platform, R.version\$arch, R.version\$os))); \
     install.packages(c('fixest','remotes'), repos='${CRAN_SNAPSHOT}')"
   ```

Binaries arrive as `.tar.gz` that `install.packages()` just unpacks — no compiler runs. Runtime linking needs are already covered by the image's existing `lib*-dev` packages.

Notes:

- **This pairs with the R upgrade; it doesn't stand alone.** P3M builds binaries against the R versions it currently supports, so a 2026 snapshot's binaries target modern R — against stock 4.2.2 they'd fall back to source or fail. Smoke-test one package early to confirm bookworm binaries exist for the pinned `R_VERSION`.
- The firewall is irrelevant here: it's runtime-only (see `0715a,firewall-fails-open.md`), so build-time `install.packages` already has unrestricted network. The build is slow from compilation, not network policy.
- Expected effect: tidyverse/Rcpp layers drop from minutes to seconds; `arrow` becomes a plain download.

## Build-speed improvement: parallel R compiles (added 2026-07-18)

Independent of the upgrade — works on the current Dockerfile as-is. `install.packages()` builds packages serially by default, and each package's internal `make` runs single-threaded. Two knobs, capped at 2 CPUs for conservatism (parallel C++ jobs can use 1–2 GB each; OOM in a memory-capped Docker VM surfaces as cryptic `g++: fatal error: Killed`):

```dockerfile
ENV MAKEFLAGS=-j2
RUN Rscript -e "options(Ncpus = 2); install.packages(c('tidyverse',...), repos=...)"
```

- `Ncpus` parallelizes across packages within one `install.packages()` call. Safe by design: R generates a Makefile encoding the inter-package dependency graph, so nothing builds before its deps.
- `MAKEFLAGS` parallelizes compilation inside each package.
- Failure logs interleave under parallelism, but the existing verification layer (Dockerfile ~137–147) already catches silent install failures — `install.packages()` never fails the build on compile errors anyway.
- No reproducibility impact; still useful after the P3M switch for packages that fall back to source.
