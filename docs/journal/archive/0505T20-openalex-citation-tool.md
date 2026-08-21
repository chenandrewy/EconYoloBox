# OpenAlex follow-up-citations tool — sketch review

Reviewed a draft of `cited_by.py`: takes a DOI, looks up the OpenAlex work,
then fetches papers that cite it, sorted by their own citation counts.

## Findings

### Blocker: wrong auth scheme
The sketch sends `Authorization: Bearer <key>`. OpenAlex doesn't accept
Bearer auth — the key must be passed as an `api_key` query parameter
(`?api_key=...`).
Source: <https://docs.openalex.org/how-to-use-the-api/rate-limits-and-authentication>

**Correction (post-codex review):** earlier I claimed the Bearer header
was "silently ignored". A live curl on 2026-05-06 returns
`401 {"error":"Invalid or missing API key"}` whenever any Bearer header
is present — even an obviously bogus one. So the script doesn't fall
back to the anonymous pool; it hard-fails. With the env var unset it
sends literal `Bearer YOUR_KEY_HERE` and 401s on the very first call.

### Env var name doesn't match credential map
`.credentials/credentials-map.json` (added in 4732403) exposes the key as
`OPENALEX_API_KEY`. The sketch reads `OPENALEX_KEY`, so the credential
injection wiring is bypassed.

### Input mismatch: title vs DOI
The stated UX is "pass in the name of a paper", but the script takes a DOI.
Title lookup needs a separate `?search=<title>&per-page=1` call before the
`cites:` filter.

### No error handling on the lookup
Bad DOI / rate-limit / network error makes `work["id"]` raise `KeyError`
with no useful message. Needs `raise_for_status()` plus a guard that the
work was actually returned.

### Minor
- `work_id.split("/")[-1]` is unnecessary — `cites:` accepts the full URL.
- `a["author"]["display_name"]` can hit `None` authors on rare records.
- Consider adding `id` to `select` so output can link back to OpenAlex
  when DOI is missing.
- 25 results is fine for "top-cited"; cursor pagination only matters past
  ~200.

## Plan to fix

1. **Auth + env var.** Drop the `headers=` kwarg on both calls; pass
   `api_key` via `params=`. Read the key from `OPENALEX_API_KEY`.
2. **CLI shape.** Default arg = DOI (current behavior). Add `--title "..."`
   flag that does a `search` lookup and uses the top hit. Print the
   resolved work (title + DOI + year) to stderr so the user can confirm
   the right paper was matched.
3. **Error handling.** `raise_for_status()` on both requests; if the work
   lookup returns no `id`, print a clear "not found" message and exit 1.
4. **Output safety.** Guard `a.get("author", {}).get("display_name")`
   against `None`. Add `id` to `select` and fall back to the OpenAlex URL
   when DOI is absent.
5. **No-key behavior.** If `OPENALEX_API_KEY` is unset, just omit the
   `api_key` param and `Authorization` header entirely — anonymous calls
   work (verified: bare GET returns 200). Drop the earlier "polite pool
   `mailto` fallback" idea; current docs no longer describe `mailto` as
   the auth mechanism.
6. **Location.** Workspace-level tool (general-purpose, not tied to
   any single project). Put it under `/workspace/.tools/cited_by.py` next to
   `sync-lyx.sh`.

## Codex review (2026-05-06, additions)

Codex did real curls and flagged extras worth folding into the plan:

- Use the documented `per_page` (underscore), not `per-page`. The API
  currently accepts both, but underscore is the documented form.
- Add `timeout=` to both `requests.get` calls.
- Normalize the DOI input: accept raw `10.x/yyy`, `doi:10.x/yyy`, and
  `https://doi.org/10.x/yyy`. URL-encode before path interpolation;
  unescaped DOIs are brittle.
- Title lookup is risky — `search=<title>&per_page=1` can grab the wrong
  paper. Default to printing the top 3 candidates and require a `--doi`
  for exact match, or at minimum echo resolved title/year/DOI/OpenAlex ID
  to stderr before printing citers.
- Cursor-pagination concern was over-engineered. `per_page` goes up to
  100 and basic paging up to 10,000 — fine for any sensible top-cited
  list. Drop the "past ~200" footnote.
