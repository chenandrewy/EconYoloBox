# Public release procedure

Publish the sandbox infrastructure as `EconYoloBox`: a snapshot carrying no
private projects, journal notes, host paths, or private history.

Three rules make the rest routine:

- The public checkout lives outside the private repository's tracked tree,
  ignored by it and holding its own `.git`. Its path is defined once below and
  referenced as `$release_dir` everywhere after. Never add a public remote to
  the private repository.
- Export with `git archive` from a commit, never by copying the working tree.
- Scrub the export only. The private tree keeps its real values, so the scrubs
  are redone on every release.

## 0. Where the release lives

Set this before any other step; every block below assumes it. This is the one
place the path appears, so moving the checkout is a one-line change here.

```bash
release_dir="/workspace/Live,AIWorkFlow/EconYoloBox"
```

## 1. Export

The release is always `HEAD`. Pin it so every later step reads one tree.

```bash
release_commit="$(git rev-parse HEAD)"

test -z "$(git status --porcelain)"
test ! -e "$release_dir"
mkdir -p "$release_dir"

git archive "$release_commit" -- \
  . \
  ':(exclude)docs/journal' \
  ':(exclude)docs/journal/**' \
  ':(exclude)docs/public-release.md' \
  | tar -x -C "$release_dir"

test ! -e "$release_dir/docs/journal"
test ! -e "$release_dir/docs/public-release.md"
```

Everything `.gitignore` covers is excluded automatically, because `git archive`
reads the committed tree. The journal and this file are tracked, so they need
the explicit exclusions above.

Do not assume `HEAD` is already clean because `3218e05 "Initial public release
of the sandbox setup"` sits in the history. That cleanup was done in a copy that
was not kept, and its scrubs are not in this tree.

## 2. Scrub the export

Edit only under `$release_dir`.

- **README** — name it `EconYoloBox`, keep the setup instructions that apply to
  public users, drop private-workspace commentary, and link `docs/features.md`
  for the feature tour.
- **`.gitignore`** — the project-folder block, marked by its comments, lists
  the real private prefixes. Replace them with `My-Project/`.
- **Examples** — replace real project names and hostnames with `My-Project` and
  a generic host, wherever they appear in prose or comments.
- **Journal references** — nothing to do here as long as the private tree stays
  clean; the links and paths pointing into `docs/journal/` were reworded
  upstream. The journal is excluded rather than scrubbed, so any new one dangles
  in the export, and an entry's filename can name private work by itself. The
  audit in step 3 greps for `docs/journal`; if a hit turns up, reword it upstream
  rather than scrubbing it here.
- **Private commit hashes** — the public repository is a fresh snapshot, so a
  short hash cited in prose resolves to nothing there. Reword to state the change
  without the citation.
- **Google Scholar** — nothing to do here as long as the private tree stays
  clean; the Scholar scraper and every mention of it were removed upstream. The
  audit in step 3 greps for its fingerprints so a reintroduced mention cannot
  reach the export unnoticed. If one turns up, remove it upstream rather than
  scrubbing it here.
- **Keep** the author's name in `LICENSE` and the README byline. The repository
  is published under it deliberately.

## 3. Audit

Stage the snapshot so it can be reviewed as a diff, then search it.

```bash
git -C "$release_dir" init -b main
git -C "$release_dir" add -A

git -C "$release_dir" grep --cached -n -i -F \
  -e 'chen1678' -e '/Users/' -e 'Dropbox' -e 'MacBook' -e 'docs/journal' \
  -e 'scholar' -e 'gs_captcha' -e 'cites=' -e 'as_sdt' -e 'cluster=' \
  -e '--cluster' -- .

private_names="$(
  { git show "$release_commit:.gitignore" \
      | sed -n 's#^\([^#[:space:]]*\)\*/$#\1#p'
    ls -d1 /workspace/Live,*/ | sed 's#^.*/Live,##; s#/$##'
  } | sort -u
)"
test -n "$private_names"
printf '%s\n' "$private_names"          # eyeball before trusting a quiet result

printf '%s\n' "$private_names" | while IFS= read -r name; do
    printf '\n== %s ==\n' "$name"
    git -C "$release_dir" grep --cached -n -F -e "$name" -- .
done

git -C "$release_dir" ls-files
git -C "$release_dir" diff --cached
```

Private names are derived rather than listed here, so the audit stays correct
as projects come and go. Two sources: the prefixes come from `.gitignore`,
which enumerates them by design, and the bare project names come from globbing
`Live,*/`. The second matters because a name is revealing without its prefix —
a document that says "GoogleScholar" and never says "Live," would otherwise
pass. Confirm the printed list is non-empty and looks right before trusting a
quiet result. Judge each hit on context —
generic Dropbox references are fine, and a short name can occur in ordinary
English — but do not publish with an unexplained match. Confirm
`credentials-map.json` still holds only slug-to-environment-variable mappings.

## 4. Test

The AIChatRender extension is out of scope. Nothing in this snapshot builds or
bundles it — `docs/features.md` only points at its own repository, and the
devcontainer installs it from the Marketplace — so it is tested there, not
here.

Add whatever else the changes warrant, and rebuild the exported devcontainer if
its configuration moved.

## 5. Publish

Create an empty public `EconYoloBox` repository, with no generated README,
license, or `.gitignore`. Then, from the public checkout only:

```bash
git -C "$release_dir" commit -m "Initial EconYoloBox release"
git -C "$release_dir" remote add origin <PUBLIC-REPOSITORY-URL>
git -C "$release_dir" remote -v   # must show only the public repository
git -C "$release_dir" push -u origin main
```

## 6. Later snapshots

Reuse the same checkout. Export the new commit to a temporary directory, scrub
and audit and test it there, then swap it in.

```bash
release_commit="$(git -C /workspace rev-parse HEAD)"
next_snapshot="$(mktemp -d)"

test "$(git -C "$release_dir" rev-parse --show-toplevel)" = "$release_dir"
git -C "$release_dir" remote -v
test -z "$(git -C "$release_dir" status --porcelain)"

git -C /workspace archive "$release_commit" -- \
  . \
  ':(exclude)docs/journal' \
  ':(exclude)docs/journal/**' \
  ':(exclude)docs/public-release.md' \
  | tar -x -C "$next_snapshot"

# Scrub, audit, and test $next_snapshot before going further.

git -C "$release_dir" rm -r .
git -C "$release_dir" clean -fdx
cp -a "$next_snapshot"/. "$release_dir"/
git -C "$release_dir" add -A
git -C "$release_dir" diff --cached
```

The `clean -fdx` matters: `git rm` leaves untracked and ignored files behind,
and `add -A` would sweep them into the snapshot.

Review the staged deletions and additions, commit as one snapshot, and push.
Never force-push, and never use the private repository as the public checkout.

Re-export only when there is something worth publishing. A dated snapshot that
goes stale is a fine outcome.
