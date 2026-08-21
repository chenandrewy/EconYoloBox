# 0720a — PDF→markdown via Claude Code's Read tool

2026-07-20 (NY)

Context: building a higher-fidelity alternative to the Mistral OCR converter,
aimed at **math symbols** specifically. Goal was a tool that reads page renders
through Claude Code's Read tool instead of shipping the PDF to Mistral OCR.

Status: **working but over-built** (699 lines vs Mistral's 146). Shelved
pending a decision on whether to trim it or rewrite it against the API directly.

## State of the tree (uncommitted)

- `.tools/pdf/pdf2md.py` — the Mistral tool, left exactly as it was. It was
  briefly renamed to `pdf2md_mistral.py` during this work; that was reverted,
  so the Mistral tool keeps the primary name and the default workflow is
  unchanged.
- `.tools/pdf/pdf2md-cc.py` — new Claude Code version, untracked. Runs as
  `pdf2md-cc.py` (it's on `PATH`); note the hyphen means it can't be `import`ed
  as a module, so testing its internals needs `importlib`.
- `dev/*.pdf` — test corpus: Fama French 1993 (scanned JSTOR, math-heavy),
  McLean Pontiff 2016, "risk vs 2025 12" (our own arXiv paper, modern LaTeX).

Architecture: PyMuPDF renders pages at 200 dpi → text layer extracted alongside
→ chunks of 3 pages fanned out to `claude -p --allowed-tools Read,Write`
subprocesses via ThreadPoolExecutor → stitched. Output uses `$...$` inline,
`$$...$$` display, `\tag{}` for source equation numbers.

## Findings (priority order)

1. **10-page batching fails outright — output tokens are the binding
   constraint.** Tested `--chunk-size 10` on Fama French pp. 12–21: the batch
   ran ~8 min and wrote *nothing* (`out_012-021.md` never created), then
   degraded to per-page retries and was still going at 9 min on work that
   takes ~3 min at `--chunk-size 3`. Ten pages of markdown is ~15–20k output
   tokens in one response and the worker never gets there. Batching up is
   strictly worse on both cost and time: you pay for all ten page images, get
   nothing, then pay again for the retries. **Do not revisit larger chunks
   as a cost lever.** Input-side batching saves only per-session overhead;
   image tokens are identical whether in 1 request or 4.

2. **The API content filter fires deterministically on some page renders.**
   Fama French pdf p. 7 returned `400 Output blocked by content filtering
   policy` 3/3 times on Opus and also on Sonnet — retries and model swaps are
   both useless. Re-cropping the page into bands *does* recover it. But the
   band that actually tripped the filter turned out to be **blank white
   space** — so the real fix was detecting blank regions before dispatching a
   worker at all, not the recursive splitting. Worth remembering that "blocked"
   can mean "there was nothing there."

3. **Scanned PDFs are stored as horizontal image strips, not pages.** Naive
   `get_images()` extraction produced **80 "figures" from 4 pages** of Fama
   French — 1860×138 slices of the scan. Filtered by aspect ratio (>4:1) and
   per-page count (>8 ⇒ treat page as a scan, extract nothing). Now yields 0
   on Fama French, correctly.

4. **Modern LaTeX papers draw figures as vector graphics, so `get_images()`
   finds nothing.** "risk vs 2025 12" has zero extractable rasters despite
   having real figures; McLean Pontiff has 3. Figure extraction as built only
   covers embedded bitmaps. Proper fix is cropping figure regions out of the
   high-dpi page render, but region detection risks capturing ruled tables as
   figures — a lot of false positives in econ papers. **Deferred.**

5. **Printed-page offset is constant per document; detect it once, not per
   page.** Per-page folio reading was unreliable (worked on odd pages, failed
   on even). Taking the modal `folio - pdf_index` across sampled pages is
   robust — running heads and stray statistics wash out. Measured: Fama French
   `+2` (journal pp. 3–56 ✓), McLean Pontiff `+4`, risk vs 2025 `−1` (title
   page unnumbered). Markers render as `[p. 8 | pdf 6]` when they differ,
   `[p. 8]` when they don't, `[pdf 1]` for unnumbered front matter.

6. **Transcription quality is genuinely good.** Correct `[^n]` footnote
   references, callout boxes as blockquotes, markdown tables, `$BE/ME$`,
   `$t-1$`, and it reached for `\text{...}` in display math unprompted. This
   part of the premise holds up — it is better than OCR on structure, not just
   on math.

7. **Speed: ~1 min/page.** A 54-page paper is ~15–20 min at concurrency 4.
   This is the main thing making it feel heavy next to Mistral's seconds.

8. **`--verify` is untested where it matters.** The math-recheck pass reported
   0 corrections on "risk vs 2025 12", but that document has one display
   equation. Needs a run against Fama French's regression sections before we
   believe anything about it.

## Open decision

Two ways forward, not yet chosen:

- **(a) Rewrite against the Anthropic API directly.** Drops the `claude -p`
  subprocess layer entirely — no session boot per chunk, no tool definitions,
  no file round-trip. Lands near Mistral's size (~200 lines) and kills the
  slowest part of the design. Cost: abandons the "uses Claude Code's Read
  tool" premise the tool started from.
- **(b) Keep the harness, trim hard.** Drop band-splitting (finding 2) and
  figure extraction (finding 4) — ~130 lines — plus drop dpi 200→150 (~40% off
  image tokens) and run the bulk on Sonnet with Opus reserved for `--verify`.
  Gets to ~450 lines and materially cheaper without a rewrite.

Leaning (a) + the deletions from (b).

## Loose end

`container_mode()` in `pdf2md-cc.py` still detects the container via
`/.dockerenv` / `REMOTE_CONTAINERS`. CLAUDE.md now specifies `$DEVCONTAINER`.
Fix whichever direction we go.
