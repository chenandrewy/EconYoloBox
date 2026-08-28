# Image vs volumes: where the disk actually goes

Date: 2026-08-21 (NY)

Written because the TeX Live question in [0821c] turned on a claim — "volumes
cost you once per checkout, the image costs you once" — that was asserted
without ever being explained. This entry explains it in plain terms, checks it
against what is actually on this machine, and corrects two stale figures in the
existing docs.

---

## The one-sentence version

**The image is one master copy that every container shares. A volume is private
storage that belongs to one dev container.** So anything baked into the image is
stored once no matter how many dev containers you run, and anything installed
into a volume is stored again for each dev container that has one.

---

## The mental model

Think of the image as a **printed book** and volumes as **notebooks**.

The book is printed once and sits on the shelf. Ten people can read it. There is
still one book. When Docker builds the image, it writes those files to disk one
time; every container started from that image reads the same copy. Starting a
second container does not copy the image.

A notebook is yours. If three people each want a notebook, that is three
notebooks' worth of paper. When you install R packages into a volume, those files
are written into that volume. A second dev container with its own volume gets its
own copy of every one of those packages.

There is a third thing worth naming, because it explains a common surprise. When
a container writes to a file that came from the image, Docker does not modify the
image — it makes a private copy of just that file for that container, in a
**scratch layer** that is thrown away when the container is deleted. That is why
packages installed at runtime used to vanish on rebuild, and why we added volumes
in the first place ([0725f]).

So the three storage locations behave like this:

| Where | Copies on disk | Survives container delete |
|---|---|---|
| Baked into the image | one, shared by everything | yes (it's in the image) |
| Installed into a volume | one **per dev container** | yes |
| Installed at runtime, no volume | one per container | **no** |

---

## The part that was actually confusing: what counts as "a checkout"

This is the bit worth getting straight, because it is easy to assume the
multiplier is your project count. It is not.

Our volumes are named with `${devcontainerId}` on the end. That id comes from the
**path of the folder containing `.devcontainer/`** — so the thing that multiplies
is the number of *dev containers you have opened*, not the number of projects you
work on.

Almost all the projects here — `Live,Risk-vs`, `Live,PriceEarnings`,
`Live,QuantClass`, and the rest — are plain folders inside `/workspace`. They
share one dev container, so they share one set of volumes and cost **nothing
extra**. You could add twenty more and the storage would not move.

What does add a set is a folder carrying its own `.devcontainer/`. There are five
such folders in this tree:

```
/workspace/.devcontainer                                    <- the sandbox itself
Live,AIWorkFlow/econyolobox/.devcontainer                   <- the public release checkout
Live,Singularity/ralph-wiggum-asset-pricing/.devcontainer
Live,Singularity/0-archive/old-ralph-wiggum-asset-pricing/.devcontainer
Live,Singularity/0-archive/old2-ralph/.devcontainer
```

Only the ones you have actually **opened in a container** have volumes; a
`devcontainer.json` sitting on disk unopened costs nothing. But every one you do
open gets a full private set.

Two further multipliers that are easy to forget:

- **Each machine is separate.** The laptop and the desk machine each hold their
  own copy of everything. Dropbox syncs `/workspace`; it does not sync Docker.
- **Renaming or moving a folder starts a new set.** The id is derived from the
  path, so moving a project orphans its old volumes — they stay on disk, taking
  up space, and are no longer identifiable by name.

---

## The numbers on this machine

Measured inside the container, 2026-08-21.

**Per dev container** (a private set, duplicated for each one you open):

| Volume | Size |
|---|---|
| Python venv (`/opt/venv`) | 1.2 GB |
| R site-library | 492 MB |
| npm-global (the AI CLIs) | 591 MB |
| `~/.claude` | 8.4 MB |
| `~/.codex` | 3.7 MB |
| command history | 36 KB |
| **total** | **≈ 2.3 GB** |

**Shared by all of them** — the image, roughly 3.4 GB, of which TeX Live is
about 3.2 GB.

So the arithmetic that settles the TeX Live question:

| Dev containers open | TeX Live in the image | TeX Live in a volume |
|---|---|---|
| 1 | 3.2 GB | 3.2 GB |
| 2 | 3.2 GB | 6.4 GB |
| 4 | 3.2 GB | 12.8 GB |

Whereas the package volumes we *did* choose to duplicate cost 2.3 GB each time.
Two dev containers is 4.6 GB of volumes against a 3.4 GB shared image — the
volumes already outweigh the image, which is not obvious from looking at either
number alone.

---

## Then why put packages in volumes at all?

Because the thing we were buying was **time, not space** ([0725f]).

R and Python packages used to be baked into the image. That made image builds
take twenty-plus minutes, and any edit to an earlier line in the Dockerfile
re-paid the whole bill. It made the image miserable to change and slow for anyone
new to try. Moving packages to a runtime script fixed that — and volumes are what
stop the runtime install from being thrown away every time the container is
recreated.

The trade, stated honestly: we accepted **duplicated storage per dev container**
in exchange for **fast, debuggable image builds** and packages that survive a
rebuild. That is a good trade at two or three dev containers. It would be a bad
one at ten.

The same reasoning put the AI CLIs in a volume. There the point was not even
persistence but *update persistence* — in the image, every rebuild silently
reverted whatever CLI update you had installed.

And `~/.claude` and `~/.codex` genuinely must be per dev container: they hold
login tokens, and sharing them between checkouts is the exact bug this naming
scheme was introduced to fix.

---

## Why TeX Live is the opposite case

Every reason that favoured volumes for packages points the other way for TeX
Live:

- **It is the biggest thing there is**, so duplication hurts most.
- **It causes no build pain.** It is a plain download near the top of the
  Dockerfile, in the most cache-stable position. It essentially never rebuilds,
  so the twenty-minute problem that motivated volumes does not apply.
- **There is nothing to add.** A volume buys "install something later without
  rebuilding," and `texlive-full` already contains everything.

So it stays in the image, and that is not an inconsistency — it is the same rule
producing a different answer because the inputs are different.

---

## The lever, if this ever gets expensive

If the volume total becomes a problem, the fix is **not** to bake packages back
into the image. It is to drop `${devcontainerId}` from the *package* volume names
only, so every dev container shares one Python venv and one R library — the way
they already share one image.

That is cheap to do and it has a real cost, which is why it has not been done:

- **Isolation goes away.** One project installing or upgrading a package changes
  it for every project. Today each dev container's library is its own.
- **It creates a path between projects.** An agent running unsupervised in one
  checkout could write a package into the shared library that a different
  checkout later loads and runs. The image does not have this problem, because
  changing the image requires a rebuild — a deliberate human act — while a shared
  volume is writable at any time by design.

So the honest summary is that per-checkout volumes are buying isolation, and the
duplicated gigabytes are the price. Worth revisiting only if the number of dev
containers grows.

Cheaper housekeeping first: delete the orphaned volumes from renamed folders and
from the pre-Ubuntu era, which are inert but still occupying disk.

---

## How to check on the host

None of this is visible from inside the container — there is no Docker client in
here. From the Mac:

```bash
docker system df -v          # images, volumes, and build cache, itemised
docker volume ls             # one set of names per dev container
docker volume ls -f dangling=true   # orphans, safe to inspect before removing
```

`docker system df -v` is the one that answers "where did my disk go," because it
shows the image once and each volume separately, which is exactly the distinction
this note is about.

---

## Corrections to the existing docs

Two figures in `docs/storage-needs.md` no longer match:

- **`~/.codex` is listed at 613 MB; it measures 3.7 MB now.** Not a shrinking
  volume — `ai-sesh` symlinks the session history out to `/workspace`, so it
  lives on Dropbox-synced host disk instead of in the volume. The old figure was
  measured before that, or by a method that followed the link.
- **The R site-library is listed at 789 MB; it measures 492 MB.**

The root `README.md` is staler still: it says "roughly 5.5 GB for the first
checkout, plus about 2 GB for each additional." Those numbers predate the
2026-08-20 re-measurement and do not agree with `storage-needs.md`'s own table.

One methodological note, since it explains why two tools disagree by a few
hundred megabytes: TeX Live is about 168,000 files. Disk usage rounds every file
up to a block, so `du` reports 3.2 GB while the actual content is 2.8 GB. Docker
reports layer sizes, which is a third number again. When comparing, use one tool
throughout.

[0725f]: 0725f,persistent-package-volumes.md
[0821c]: 0821c,lessons-learned.md
