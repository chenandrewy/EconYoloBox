# Public release procedure

Publish the sandbox infrastructure as `EconYoloBox`: a snapshot carrying no
private projects, journal notes, host paths, or private history.

Three rules make the rest routine:

- The public checkout lives at `/workspace/Live/EconYoloBox/`, ignored by the
  private repository and holding its own `.git`. Never add a public remote to
  the private repository.
- Export with `git archive` from a commit, never by copying the working tree.
- Scrub the export only. The private tree keeps its real values, so the scrubs
  are redone on every release.

## 1. Export

The release is always `HEAD`. Pin it so every later step reads one tree.

```bash
release_commit="$(git rev-parse HEAD)"
release_dir="/workspace/Live/EconYoloBox"

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
  the real private folders (`Live/` and friends). Replace that block with a
  single `My-Project/`.
- **Examples** — replace real project names and hostnames with `My-Project` and
  a generic host, wherever they appear in prose or comments.
- **Journal references** — the journal is excluded, not scrubbed, so every link
  or path pointing into it dangles in the export. Reword them to state the fact
  without the citation; an entry's filename can name private work by itself.
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
      | sed -n 's#^\([A-Za-z][^#[:space:]]*\)/$#\1#p'
    ls -1 /workspace/Live | grep -vx EconYoloBox   # the release names itself
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
as projects come and go: the ignored top-level folders come from `.gitignore`,
and the individual project names come from listing `Live/`. The second source
matters — a folder name can be revealing on its own, and nothing in
`.gitignore` spells those names out. Confirm the printed list is non-empty and
looks right before trusting a quiet result. Judge each hit on context —
generic Dropbox references are fine, and a short name can occur in ordinary
English — but do not publish with an unexplained match. Confirm
`credentials-map.json` still holds only slug-to-environment-variable mappings.

## 4. Test

AIChatRender is maintained and tested in its own repository; it is not part of
this release audit.

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
release_dir="/workspace/Live/EconYoloBox"
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
