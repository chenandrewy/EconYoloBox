---
name: pdf-bookmarks
description: Add, repair, reorganize, or validate PDF bookmarks and outline hierarchy while preserving clickable destinations and document contents. Use whenever a task changes a PDF outline, table of contents bookmarks, section bookmarks, or figure and table bookmarks.
---

# PDF Bookmarks

## Decide whether to rebuild

Work through this in order. Stop at the first step that applies.

1. **The user asked.** An explicit request to rebuild from scratch, or to
   preserve what is there, settles it. Do that and skip the rest.
2. **Check the existing outline, cheaply.** One pass, described below. A clean
   outline is kept as is.
3. **Otherwise rebuild** from font metadata, never from raw text patterns or an
   LLM pass over page images.

The cheap check:

```python
doc = fitz.open(src)
pdf = pikepdf.open(src)
toc = doc.get_toc(simple=False)
print(doc.metadata.get("producer"), len(toc))
print("/Outlines" in pdf.Root, "/Names" in pdf.Root)
links_valid = bool(toc) and all(
    d["kind"] == fitz.LINK_GOTO and 0 <= d["page"] < doc.page_count
    for *_, d in toc
)
```

- `links_valid` is only the first half of the test. It says the destinations are
  well formed; it does not say the outline is clean, so never treat it as the
  decision on its own.
- After it passes, inspect the outline itself before keeping it. Required, not
  optional: check that the entry count and depth are plausible for the document,
  and look at where the destinations land. Destinations that all sit on page 1,
  or all at the top of their page, indicate an outline degraded by a later merge
  or page extraction — rebuild.
- An outline counts as clean only when `links_valid` holds *and* that inspection
  finds nothing wrong. Anything else goes to a rebuild.
- The producer usually settles it on its own. A `pdfTeX` producer with
  `/Outlines` and a `/Names` `/Dests` tree means `hyperref` wrote the outline
  from the source `\section` commands: exact named destinations and correctly
  typeset titles, including unnumbered headings and math that font detection
  cannot reconstruct. Keep those.
- A producer such as `iTextSharp`, Ghostscript, or a scanner means the file was
  reassembled or rasterized downstream, and any `hyperref` structure is already
  gone. Journal submission systems that staple a cover page onto a manuscript
  land here, so a submission PDF normally has nothing to preserve and goes
  straight to a rebuild.
- A section outline is incomplete without exhibits. `hyperref` builds its
  outline from sectioning commands only, so even a clean source-generated
  outline normally omits floats. Always scan the full document for table and
  figure captions and add the missing exhibit bookmarks to the outline that was
  kept.
- Report before you discard. When you rebuild over an existing outline, state
  how the result differs — entry count, depth, and any titles that
  disappeared — rather than silently shipping a smaller outline.

## Recover the structure from font metadata

- Build a `(font, size)` histogram over every span, weighted by character
  count. Body text is the largest bucket; heading faces are small buckets at
  distinctly larger sizes. One histogram usually names every heading level in
  the document.

  ```python
  import collections, fitz
  doc = fitz.open(src)
  hist = collections.Counter()
  for page in doc:
      for block in page.get_text("dict")["blocks"]:
          if block["type"] != 0:
              continue
          for line in block["lines"]:
              for span in line["spans"]:
                  hist[(span["font"], round(span["size"], 1))] += len(span["text"])
  ```

  A LaTeX article typically resolves to something like `CMR12 @ 12.0` for body,
  `CMBX12 @ 17.2` for sections, and `CMBX12 @ 14.3` for subsections. Filter
  lines by the heading faces to get candidate headings with their pages and
  `bbox` coordinates.
- Merge spans by line. A numbered heading arrives as separate spans — `"7.6"`
  and `"Time-State Transfer: …"` — that must be joined into one title.
- Rejoin wrapped headings. A long title continues onto a second line at the
  same font and size, sometimes as a fragment as short as `"Match"`. Treat
  consecutive heading-face lines whose vertical gap is about one line height as
  a single heading; a naive extractor emits the tail as its own bookmark.
- Confirm the recovered structure against the document before writing it. Check
  that the level sequence has no gaps and that numbering runs consecutively.

## Always bookmark exhibits

- Scan the full document on every bookmark task, including repairs. A caption
  begins with a table or figure label — `Table`, `Tab.`, `Tbl.`, `Figure`,
  `Fig.` — followed by a number, and the number is not always arabic. Match
  roman numerals (`Table I`, `Table II`, standard in finance journals) and
  appendix or internet-appendix prefixes (`Table A1`, `Figure IA.2`) as well as
  `Table 1`. A pattern that assumes `Table 1` finds nothing in a roman-numeral
  paper and silently drops the appendix in a prefixed one, and the gap check
  below will not catch either, because the sequence it sees looks complete.
- Do not trust an assumed exhibit count; compare the scan with the document and
  report discrepancies.
- When the user scoped the task to sections, still scan, but report the missing
  exhibits rather than adding them unasked.
- Distinguish captions from body references using font, position, surrounding
  lines, and layout. Rejoin wrapped captions before constructing the bookmark.
- Bookmark every detected table and figure exactly once. Check each numbering
  sequence for gaps, but do not invent bookmarks for exhibits that are absent.
- Use concise, caption-derived titles: retain the label and number as the
  document prints them — `Table 1:`, `Table I:`, `Figure A2:` — plus the
  identifying caption title or first sentence; omit caption notes and extended
  interpretation.
- Default exhibits to one level below the nearest preceding main section
  (typically level 2 when sections are level 1). Interleave them with sections
  and subsections by their actual page and vertical position. Follow a
  user-specified level or grouping when provided.
- Preserve existing exhibit destinations when reorganizing a clean outline;
  create caption-position destinations for newly detected captions, using the
  technique in the next section with the caption line in place of the heading.

## Build destinations that land on the heading

A page-only destination scrolls to the top of the page, which is wrong whenever
a heading sits mid-page. Target the heading itself.

```python
toc = [
    [level, title, page,
     {"kind": fitz.LINK_GOTO, "page": page - 1,
      "to": fitz.Point(72, max(y - 12, 0))}]
    for level, title, page, y in entries
]
doc.set_toc(toc)
```

- `page` in the entry is 1-based; `page` inside the destination dict is
  0-based. Assert they agree.
- `y` is the heading line's `bbox[1]`. Subtract a small offset (about 12pt) so
  the heading is not flush against the viewport edge, and clamp at 0.

## Preserve outline behavior

These rules govern the preserve-and-reorganize case, when the user has asked to
keep the existing outline rather than rebuild it.

- Preserve either `/Dest` or a valid `/A` `/GoTo` action for every retained
  outline item. A title and hierarchy position alone do not make a bookmark
  clickable.
- When attaching children, do not recreate an existing
  `pikepdf.OutlineItem` using only its title. Retain the original destination or
  action.

## Order the outline

These rules apply to any outline, rebuilt or preserved.

- Follow logical and document order within each subtree. A theorem or
  proposition appearing before the next section heading belongs under the
  preceding section, even when both occur on the same page.
- Use a top-level `Tables and Figures` index only when the user requests it or
  the document's own structure calls for one. Collect every exhibit once and
  order entries within the group by document position.

## Protect the source PDF

- Write every bookmark edit to a temporary PDF and validate that file before
  replacing the project PDF.
- Naming a target file is the request. "Add bookmarks to `paper.pdf`" asks for
  that file to be modified, so replacement is authorized. Ask first only when
  the target is genuinely unclear, or when the edit would touch a PDF the user
  did not name.
- Replace only after validation passes on the temporary file, and keep a
  recoverable copy of the prior PDF until it does.
- Mention that an open PDF viewer may need a reload to pick up a new outline.

## Validate the completed PDF

- Inspect the outline with PyMuPDF using `doc.get_toc(simple=False)`.
- Require every entry to have a `LINK_GOTO` destination and a zero-based target
  page within the document.
- Check PDF syntax with `pikepdf.Pdf.check_pdf_syntax()`.
- Verify the expected outline count, hierarchy, and ordering.
- Verify that the caption scan and final outline contain the same tables and
  figures, each exactly once, at the intended hierarchy level. Account for
  numbering gaps explicitly.
- Confirm that the page count and per-page geometry are unchanged, and that
  each page's extracted text is identical to the original page for page. A
  whole-document text comparison hides content that moved between pages.
- Treat visible bookmark titles as insufficient evidence; confirm that every
  bookmark is clickable and reaches its intended page. Assert that each title's
  text actually appears on its target page — the cheap automated form of this
  check, and the one that catches off-by-one page errors.
- Validate the vertical position too, not just the page. A destination with the
  right page and the wrong `to.y` scrolls to the wrong part of the page and
  passes every page-level check. Locate the title on the page and require the
  destination to sit just above it.

```python
import re

TOL = (-2, 36)  # destination sits at, or slightly above, the heading

for level, title, page, dest in out.get_toc(simple=False):
    assert dest["kind"] == fitz.LINK_GOTO, title
    assert 0 <= dest["page"] < out.page_count, title
    assert page == dest["page"] + 1, title
    key = re.sub(r"^[A-Z0-9.]+\s+", "", title).split(":")[0].strip()[:28]
    hits = out[page - 1].search_for(key) if key else []
    if not hits:
        print("UNRESOLVED", page, title)
    elif not any(TOL[0] <= r.y0 - dest["to"].y <= TOL[1] for r in hits):
        print("CHECK", page, title, [round(r.y0 - dest["to"].y, 1) for r in hits])
```

- Accept any occurrence within tolerance, not the topmost one. A section title
  is often quoted in the body text above its own heading — `7.4 Stock Connect:
  Foreign Institutional Access` was mentioned earlier on the same page — and
  taking `min(r.y0)` reports a false failure against that mention.
- `to.y` round-trips through `set_toc` and `get_toc` in the same top-left
  coordinate space that `bbox` uses. No page-height flip is needed. Confirm
  this on the file at hand before trusting a tolerance, since a silent
  coordinate flip turns every gap into `page_height - gap`.
- Correct destinations cluster at exactly the offset that was written, so the
  observed gaps should be near-identical across entries. A spread of values is
  itself the signal, whatever the tolerance admits.
- Prove the check can fail. Move one destination to an arbitrary `y`, confirm
  the check reports it, and discard the corrupted file. A validator that
  reports nothing on a broken file is reporting nothing on a good one.
- Synthetic titles that describe a page rather than quote it — `Abstract`,
  `Tables and Figures` — resolve to no hits. Confirm those by reading the
  target page, and account for every one rather than dismissing the failures as
  a group.
