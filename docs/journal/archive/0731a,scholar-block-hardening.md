# Scholar block after a previously working cited-by tool

Date: 2026-07-31 23:02 EDT

Snapshot of the July 30–31 Scholar failure, the client hardening it prompted,
and the two post-change tests. This follows
[0730a,scholar-captcha.md](0730a,scholar-captcha.md).

## Bottom line

The Google Scholar tool **did work before this block**. The available record is
stronger than recollection alone:

- The Scholar implementation landed July 26 in commit `96c01e1`, whose commit
  message says “works now due to previous firewall updates.”
- [0724b,firewall-exfil-risk.md](0724b,firewall-exfil-risk.md) describes the
  Scholar tool as “built + validated.”
- On July 30, the Kahn–Landsburg–Stockman lookup got successful responses from
  both `q=` and `cluster=` before `cites=` was blocked.

The user's recollection that it worked two days ago, possibly as recently as
yesterday, is therefore consistent with the artifacts. What is directly proven
for July 30 is narrower than “the entire two-step lookup completed”: search and
cluster lookup worked, while the citing-set request failed later that day. There
is no saved transcript proving the last date on which a full `cites=` run
completed, so do not invent one.

The July 31 tests show that Scholar now blocks even an ordinary `q=` search.
That is a change in Scholar's treatment of the current client/IP, not evidence
that the parser or command was always broken.

## Timeline

| Time (EDT) | Observation | What it establishes |
|---|---|---|
| July 24–26 | Scholar tool built and validated; implementation committed July 26 with “works now” in the commit message | Scholar access and parsing worked before the present incident |
| July 30, before 17:55 | `q=kahn landsburg stockman` returned hits; `cluster=5179910145110411934` returned the pinned record | Search and cluster endpoints were still working |
| July 30, about 17:55 | Two `cites=` page-one requests were blocked, the second only about 20 seconds after the first | First observed block in this incident; the immediate retry may have worsened it |
| July 31, 18:25 | After the first hardening implementation, `q=Andrew Chen Mihail Velikov JFQA` was blocked before returning hits | The problem was no longer confined to `cites=` |
| Seconds later | The same command was invoked again, but the new local cooldown refused it without contacting Scholar | Cooldown enforcement worked; this was not a second Scholar request |
| July 31, 23:00 | The same `q=` request was tried after the one-hour cooldown had long expired and was blocked again | Waiting several hours did not clear the restriction |
| July 31, 23:00 | Diagnostics recorded HTTP 200 with `gs_captcha`, no redirect, and no `Retry-After`; `NID` and `GSP` cookies were present | This was a Scholar-layer soft CAPTCHA response, not the firewall, an HTTP 429, or a cookie-free first request |
| July 31, 23:00 | Consecutive block count became 2; local retry time escalated to August 1, 05:00 EDT | Adaptive backoff worked as implemented |

The 05:00 time is a mechanical six-hour minimum, **not** evidence that Scholar
will accept a request then and not a recommendation to probe at that time.

## First interpretation, and why it changed

The July 30 evidence initially suggested that Scholar guarded `cites=` more
aggressively than ordinary search. That was plausible because the successful
`cluster=` and blocked `cites=` requests used the same numeric id only seconds
apart.

The July 31 tests materially update that inference. Both failed on plain `q=`.
The second failure is especially informative because the hardened client sent
persisted `NID` and `GSP` cookies and still received an HTTP 200 CAPTCHA body.
Thus endpoint-specific guarding may exist, but it cannot explain the current
state by itself.

Current best reading (still inference because Scholar publishes no decision
rule): the current IP/session is under a broader Scholar restriction. The
sequence is consistent with a dynamic reputation or request-budget decision:
the tool worked, crossed a threshold or encountered a policy change, and is now
refused even at the search endpoint. It is not consistent with the earlier
claim that “the parameter is what matters” as a complete explanation.

## Client hardening implemented

Commit `63c4340` (`Harden Scholar citation requests and backoff`) changed
`.tools/lit/cited_by.py` and its README:

1. Use a persistent `requests.Session` and retain Scholar cookies under
   `~/.cache/sandbox-lit/`.
2. Send a fuller, internally coherent Chrome navigation header set, including
   a same-origin referrer.
3. Apply the randomized 3–6 second delay before the first citer page as well as
   later pages.
4. Detect `gs_captcha`, `/sorry/`, and HTTP 429 and stop immediately.
5. Persist block diagnostics without retaining the query text: request kind,
   status, signal, redirect target, and `Retry-After`.
6. Escalate consecutive blocks from one hour to six hours to 24 hours, capped
   at 24; only a successful response resets the streak.
7. Add `cited_by.py --status`, which reads cookies and block state without a
   network request.

The implementation also migrated the first timestamp-only cooldown record into
the richer JSON state. Current state immediately after the 23:00 test was:

```text
Cookies: 2 (GSP, NID)
Cooldown: active
Retry at: 2026-08-01 05:00:47 EDT
Consecutive blocks: 2
Last request: q · HTTP 200 · gs_captcha
```

## Validation performed

No validation probe was sent to Scholar. Offline mocked checks covered:

- cookie persistence across client instances;
- navigation referrer and `Sec-Fetch-Site` headers;
- block detection and diagnostic persistence;
- legacy timestamp-state migration;
- zero network calls during an active cooldown;
- one-hour then six-hour escalation;
- `Retry-After` taking precedence when it is longer;
- reset only after a successful response; and
- randomized pacing before citer page one.

Python compilation, CLI `--help`/`--status`, and `git diff --check` also passed.
The two real attempts supplied the missing integration evidence: the state and
backoff machinery work, but the fingerprint changes do not make Scholar accept
the current IP/session.

## What the hardening does and does not fix

The changes fix concrete client defects: stateless cookies, cold referrers,
back-to-back citer requests, reflexive retries, and lack of diagnostics. They
reduce avoidable bot-like behavior and keep an agent from hammering a block.

They do **not** clear an existing CAPTCHA, reset IP reputation, or guarantee
Scholar access. Calling them a CAPTCHA “fix” was too strong. For the current
incident, the protective part worked and the access-restoration part did not.

Do not respond by rotating user agents, deleting block cookies, cycling
proxies, or automating CAPTCHA solving. Those either make the fingerprint less
coherent or cross from polite-client hardening into circumventing an access
control. A homepage warm-up request is also unattractive: it spends another
request against an already refusing endpoint without evidence that it helps.

## Next evidence worth collecting

- Do not probe merely because the six-hour local timer expires. A substantially
  longer quiet period is more prudent given that several hours did not help.
- On the next real Scholar need, make one request and inspect `--status` after
  it. If it blocks again, the backoff will move to 24 hours.
- If a later plain `q=` succeeds, that successful response will reset the block
  streak. Only then is it worth learning whether `cites=` remains independently
  more sensitive.
- Keep Scholar and OpenAlex explicit and separate. In the Chen–Velikov task the
  user prohibited fallbacks, and none were used.

The unresolved operational conclusion is simple: the tool is behaving safely,
but Scholar is presently unavailable from this client/IP. That present outage
should not erase the evidence that the same tool and route worked days earlier.
