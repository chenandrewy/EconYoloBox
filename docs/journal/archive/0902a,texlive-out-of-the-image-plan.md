# Plan: move TeX Live out of the image, into an externally built volume

Date: 2026-09-02 (NY)

Reverses the decision recorded in `0821c,lessons-learned.md` ("sometimes the
crude bulk install is the right answer"), and corrects a premise in
`0821d,image-vs-volume-storage.md`. Nothing has been implemented. This is the
plan plus the measurements that motivated it.

## The trigger

`texlive-full` on `ubuntu:24.04` is **TeX Live 2023, permanently**. Ubuntu
freezes its archive at release and an LTS never advances it, so that apt line
can only ever install 2023 — today, and in 2029. Verified in the built image:

```
pdfTeX 3.141592653-2.6-1.40.25 (TeX Live 2023/Debian)
kpathsea version 6.3.5
tlmgr ... TeX Live (https://tug.org/texlive) version 2023
biber version: 2.19
```

And `tlmgr` — the escape hatch you would reach for — is disabled by Debian's
packaging:

```
$ tlmgr install pgfplots
(running on Debian, switching to user mode!)
TLPDB: not a directory, not loading: /home/node/texmf
tlmgr: user mode not initialized, please read the documentation!
```

So the version is frozen *and* unfixable in place. The only remedy apt offers
is changing the base image, which drags python3, the distro libraries, and
every `noble` volume token along with it.

**The irony:** `0821c` argues at length that Debian's R 4.2.2 was "from October
2022, frozen forever," and that this justified pinning R from Posit with a
dated CRAN snapshot. That is the identical argument, and it was never applied
to TeX. TeX is currently the only major toolchain in this image with no version
knob at all — Node, R, LyX, pandoc, git all have ARGs.

## What `install-tl` actually is

Same product, different packaging. Debian repackages upstream TUG source into
~100 apt packages; `texlive-full` is the metapackage. Not a fork.

Upstream `install-tl` puts everything under **one prefix**,
`/usr/local/texlive/<year>/`, with binaries in `bin/<arch>-linux`. That single
property is what makes a volume possible — apt scatters TeX across
`/usr/share/texlive`, `/usr/share/texmf`, `/usr/bin/*`, `/etc/texmf`, and the
dpkg database, none of which a volume can hold.

It is **not** a build. `install-tl` downloads pre-built binaries for the
platform it detects. The "builder container" is doing the work of `wget`.

## The plan

### 1. Build the volume from outside the devcontainer entirely

A throwaway `docker run` on the host, no devcontainer involved:

```bash
ARCH=$(docker run --rm ubuntu:24.04 dpkg --print-architecture)
VOLUME="texlive-2026-noble-$ARCH"
docker volume create "$VOLUME"
docker run --rm -v "$VOLUME":/usr/local/texlive ubuntu:24.04 \
  bash -c '... install-tl ...'
```

The firewall lives *inside* the devcontainer, applied by `init-firewall.sh` at
startup. A separate container never runs it. **The firewall problem does not
get solved; it never arises.** This is the main reason to prefer this shape.

Derive `$ARCH` rather than hardcode it — same script then works on x86 Linux,
where `install-tl` fetches `x86_64-linux` without being told.

### 2. Mount it read-only, with a fixed name

```
"source=texlive-2026-noble-arm64,target=/usr/local/texlive,type=volume,readonly"
```

Deliberately **not** keyed to `${devcontainerId}`. That key exists to stop two
projects sharing auth tokens and swappable executables. TeX Live is public,
identical for everyone, and holds no secrets — and `readonly` closes the
executable-swapping hole directly. So sharing one copy across projects is a
feature.

Devcontainer passes `mounts` strings straight to Docker's `--mount`, and you
already use this exact syntax one line above, on the credentials bind
(`type=bind,readonly`). Verified today that it behaves the same for a volume:

```
$ docker run --mount 'source=demo-ro,target=/data,type=volume,readonly' ...
hello                                    # read works
touch: cannot touch '/data/nope': Read-only file system
```

and — the part that matters — **the same volume still mounts read-write for the
builder**. `readonly` is a property of the mount, not of the volume, so the
builder is unaffected.

Read-only works because TeX's scratch files go to `~/.texlive<year>/`, not into
the tree. `install-tl` runs `mktexlsr` at install time, so `ls-R` is already
built. The thing that stops working is `tlmgr install` and `mktexlsr` from
inside the container — which is the point: updates come from the builder.

The fixed global name is safe **only because of `readonly`**. If the read-only
mount turns out not to work (see Open/unverified), the fix is dropping
`readonly` — and then the name has to go back to being `${devcontainerId}`-keyed
and the shared-single-copy benefit disappears with it.

### 3. Verified: a pre-filled volume is not clobbered by the image

Docker copies image content into a volume **only when the volume is empty**.
Tested directly today: volume pre-filled with `marker.txt` = "built-outside",
mounted over an image whose own `/data` had `marker.txt` = "from-image" plus an
`other.txt`. Container saw `built-outside` and no `other.txt` at all. The image
side is fully hidden.

So the Dockerfile does not need to seed anything at that path.

### 4. Builder script lives in a new `.setup/` folder

Not `.host/`. Both run on the host, so the split is not host-vs-container — it
is **lifecycle**:

- `.host/` — stateless helpers you source every session (navigation).
- `.setup/` — stateful things you run **once per machine**.

This also leaves `.host/`'s README honest. It says its scope is "deliberately
narrow: **navigation only**," and a volume builder plainly is not navigation. A
new folder preserves that sentence instead of watering it down.

Caveat: both READMEs must state the axis out loud, or the obvious guess in six
months is that `.setup/` means container setup — which is `.devcontainer/`.
`.setup/README.md` should say "runs on the host, once per machine." Per the
script-header convention, the script header says the same.

### 5. Dockerfile / devcontainer changes

- Drop `texlive-full` and `biber` from the Dockerfile (upstream TL bundles
  biber; keeping the apt one risks a biber/biblatex version mismatch).
- Keep the latexindent Perl modules and `librsvg2-bin` — unrelated to TL.
- No `mkdir` needed for the mount point — Docker creates it — and no seeding,
  per section 3.
- `ENV PATH` must include `/usr/local/texlive/<year>/bin/<arch>-linux`, which is
  arch-specific and `ENV` cannot compute. Fix: build a symlink using the same
  `case $(dpkg --print-architecture)` pattern already used for pandoc and
  git-delta, then put the *symlink* on PATH:

  ```dockerfile
  ARG TEXLIVE_YEAR=2026
  RUN ARCH=$(dpkg --print-architecture) && \
      case "$ARCH" in \
        amd64) TL_ARCH=x86_64-linux ;; \
        arm64) TL_ARCH=aarch64-linux ;; \
        *) echo "Unsupported: $ARCH" >&2; exit 1 ;; \
      esac && \
      ln -s "/usr/local/texlive/${TEXLIVE_YEAR}/bin/${TL_ARCH}" /usr/local/texlive-bin
  ENV PATH="/usr/local/texlive-bin:$PATH"
  ```

  The symlink **dangles at build time** — the volume is not mounted yet — and
  resolves at runtime once it is. That is fine, and it keeps `ENV PATH` static
  and arch-agnostic. It also avoids the drift problem: the symlink points *into*
  the volume rather than copying binaries out to `/usr/local/bin`, so there is
  no image-state copy to go stale.
- **Move the LyX `configure.py` scan to runtime.** It is the last Dockerfile
  step and only finds tools already installed. With TeX out of the image it
  would bake in a LyX that believes it cannot export PDF. This is the real cost
  of the change. If it lands in `postStartCommand`, it must not fail hard — see
  section 6.
- `shellrc.sh` should warn on an empty/missing TeX volume, like it does for
  `npm-global`. Not to prevent breakage (see section 6 — there is none) but
  because the first symptom is otherwise a confusing `pdflatex: not found`
  mid-draft.
- `initializeCommand` could *check* for the volume and warn — but must not
  silently start a 30-minute download on folder open.

### 6. Verified: a missing volume does NOT break the container

Tested today with a deliberately absent volume, mounted `readonly`, against an
image carrying the dangling-symlink PATH from section 5:

```
container started OK
/usr/local/texlive-bin -> /usr/local/texlive/2026/bin/aarch64-linux   (dangling)
ls works
pdflatex not found (expected)
shell exit status: 0
```

Three things make that work:

- Docker **auto-creates a missing named volume** and mounts it empty, even with
  `readonly`. No "volume not found" startup failure.
- A **dangling symlink on `PATH` is silently ignored** by shell lookups. No
  error, no warning, no effect on other entries.
- Nothing in `postStartCommand` touches TeX — `init-firewall.sh`,
  `seed-agent-guidelines.sh`, `test-agent-policy.sh` are all unrelated.

So the failure mode is exactly the wanted one: `pdflatex: not found`, and
nothing else. **This is what makes the whole approach low-risk** — and it
retires the "empty volume is silent breakage" objection that was listed against
the volume idea.

**Also verified: filling the volume needs no container restart.** Started a
container with the empty volume, populated it from a *separate* builder
container, and the already-running container saw the new binary immediately.
Recovery is "run the builder, keep working" — better than the R/venv volumes.

**The one thing that could still break startup:** moving the LyX
`configure.py` scan into `postStartCommand`. The scan itself runs fine with no
TeX, but `postStartCommand` is an `&&` chain, so a non-zero exit takes the whole
chain down — including the firewall. Needs `|| true`, or it belongs in the
install script rather than at startup.

## Measurements taken today

- `/usr/share/texlive` 3.2G + `/usr/share/texmf` 346M in the image.
- 3 images, 19.43GB. 22 volumes, 34.93GB. **Build cache 43.61GB, 33.15GB
  reclaimable** — worth pruning before adding a multi-GB volume, since Docker
  Desktop's VM disk is fixed-size.
- Host `arm64`; a plain no-flags `docker run ubuntu:24.04` is already
  `aarch64`. No cross-build, no emulation, no `--platform`.
- Non-texlive packages depending on `texlive*`: asymptote, cm-super, context,
  dvipng, feynmf, fragmaster, latex-cjk-*, latexmk, prerex, purifyeps, tipa.
  All are part of the TL family itself — **nothing outside the TeX world breaks
  when the line is removed.**

## Correction to 0821d / 0821c

`0821c` argued the trade is "3.2GB once, against 3.2GB *times the number of
projects you have checked out*," resting on `0821d`'s "the image is one master
copy that every container shares."

That is true of one image and many containers. It is **false across separate
projects**, which is the case being compared. `1-sandbox` and `econyolobox` are
distinct images (10.5GB each) and share only **6 of 33 layers**. TeX Live is
already stored twice.

So the accounting inverts: the image costs 3.2GB × projects, and a fixed-name
read-only volume costs 3.2GB **once, globally**. The "volumes are keyed per
checkout" premise was a property of how *these* volumes were keyed for secret
isolation, not a law about volumes.

## What of 0821c survives

Its central lesson holds and is not being discarded: **the deciding factor
isn't disk, it's your attention.** A missing `.sty` mid-draft costs an
interruption, and paying disk to make LaTeX always work is a good trade.

That argument is untouched — this plan keeps a full scheme. What changed is
that `0821c` never priced in the *freeze*. Its stated failure mode was "missing
`.sty` from a minimal scheme"; the actual failure mode is "package is three
years old," which `texlive-full` does not protect against and offers no remedy
for.

Honest cost, and it cuts against this plan: with a read-only externally built
volume, an agent still cannot fix a missing package — it now needs a *host-side*
action outside the container, which is a **worse** interruption than
`apt-get`. The mitigation is that a full scheme plus a working `tlmgr` should
make it rare, but the interruption argument survives intact.

## Also considered, not chosen

**Pin a single CTAN mirror and allowlist it** (`install-tl --repository`,
`tlmgr --repository`), adding one hostname to the `for domain in \` list in
`init-firewall.sh` beside `cran.r-project.org`. Would allow `tlmgr install`
from *inside* the container with the firewall up, and would restore
reproducibility via a dated snapshot URL. Rejected for now only because the
external-volume route removes the need entirely; **revisit if the read-only
interruption cost above turns out to bite.**

## Open / unverified

- Read-only mount not tested against a real LaTeX build, LyX export, or
  `latexindent`. Something may want to write into the tree.
- Whether upstream TL's `latexindent` needs a different Perl module set than
  the apt one.
- Which TeX Live edition is current — assumed 2026, not checked. Affects the
  path, the PATH entry, and the volume name.
- Whether to pin a dated snapshot for reproducibility. Frozen-at-2023 is stale
  but *is* reproducible; "whatever is current the day you run it" is not. This
  is a real regression against the `CRAN_SNAPSHOT` discipline and has not been
  decided.
- Codespaces / remote devcontainers: the technique does not fit — the Docker
  daemon is not on a machine you have a host shell on. Boundary, not a blocker.
