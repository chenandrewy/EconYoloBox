# .tools/lit

Literature tools. Each one's docstring (`--help`) is the usage reference; this
file holds the background that would otherwise bloat it.

## Citation lookup

`cited_by.py` answers "what has cited this paper?" from OpenAlex. A "follow-up"
is any work citing the seed paper.

### `cited_by.py` (OpenAlex)

Takes a DOI (raw, `doi:` form, or `https://doi.org/...` URL) and sorts citers by
citation count. Reads `OPENALEX_API_KEY` through the shared credential resolver
when present, anonymous otherwise; OpenAlex authenticates via `?api_key=`,
**not** a Bearer header — sending `Authorization: Bearer` hard-fails with 401.

```
cited_by.py "the positive economics of methodology"   # browse
cited_by.py 10.1006/jeth.1996.0004                    # rank its citers
```

Preprints work the same way, each platform minting its own DOI. The preprint and
the published version are usually separate OpenAlex records with separate
citation counts. See the script's docstring for the per-platform DOI patterns
(SSRN, NBER, arXiv).

**No DOI in hand?** Pass a title and it browses: the hit list carries the DOI or
OpenAlex W-id that pins each record, and you re-run with that. Browsing is the
default rather than an auto-pick because the top hit is regularly the wrong
paper. A title query for the Kahn-Landsburg-Stockman JET paper returns Friedman's
*The Methodology of Positive Economics* and two of its reprints above it, purely
on citation weight.

The W-id seed also covers records that carry no DOI at all — older articles,
book chapters, some working papers.

**Coverage caveat.** OpenAlex trails on working papers: SSRN/NBER/arXiv drafts
and their citations are indexed later than the versions of record. For a recent
or unpublished paper, treat an OpenAlex count as a floor and check the paper's
own SSRN/NBER page.
