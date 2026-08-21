# Devcontainer firewall silently not enforcing (fails open on restart)

2026-07-15, ~14:45 NY time

## How we found it

Downloading Chen-Zimmermann baseline predictor data with the `OpenSourceAP.DownloadR` R package (into `Live,Risk-vs-Writing/dev/mp-rep/`). Two separate things went wrong / looked wrong:

1. R's googledrive/gargle metadata requests failed with `Stream error in the HTTP/2 framing layer ... PROTOCOL_ERROR` from `drive.google.com`. This turned out to be the well-known gargle/Google-frontend HTTP/2 quirk, **not** a container problem. Standard fix, applied in `dev/mp-rep/download-cz-baseline.R`:
   ```r
   httr::set_config(httr::config(http_version = 2))  # 2 = CURL_HTTP_VERSION_1_1
   ```
   (libcurl constant naming: `2` forces HTTP/1.1.) Only affects httr-based calls; the 74MB CSV itself goes through `utils::download.file()` and was fine over HTTP/2.

2. While relating this to the firewall: `drive.google.com` is **not** in the `init-firewall.sh` allowlist, yet the download worked. Probing further: `curl https://example.com` returns **200** from inside the container — the exact check the script's own verification treats as "firewall broken." Confirmed both inside and outside Claude Code's command sandbox. So the iptables allowlist is not in effect at all.

## Root cause

- iptables rules + ipsets live in the container's network namespace, which is destroyed on container stop and recreated **empty (default ACCEPT)** on start.
- `init-firewall.sh` runs only via `postCreateCommand` (`devcontainer.json:78`) — i.e., once at container creation. On restart, only `postStartCommand` runs (`seed-agent-guidelines.sh`), so nothing reinstates the rules.
- This container's PID 1 uptime (~23.7h) matches the VM uptime → Docker/laptop restarted a day ago; firewall evaporated then and failed open.

Secondary weakness: the script is fail-open even at creation. It flushes all rules first (`init-firewall.sh:9-15`) and sets DROP policies only near the end (`:132-134`), with `set -e` and hard exits on any single DNS resolution failure (`:107-108`). A mid-script failure after the flush leaves the container wide open.

## How this started (traced via GitHub)

/workspace/.git got wiped during a vibe-coding session, but the pre-wipe history lives in `chenandrewy/big-ol-sandbox` (last pushed 2026-05-03). Tracing that repo plus upstream `anthropics/claude-code`:

- **Upstream context.** Anthropic's reference devcontainer shipped the firewall on `postCreateCommand` from its initial release (`bd5ca70`, 2025-02-22) — restart-fragile — and fixed it on **2025-08-20** (`6d79459`, "fix: ensure firewall rules are re-applied on every DevContainer start"), changing to `"postStartCommand": "sudo /usr/local/bin/init-firewall.sh"` + `"waitFor": "postStartCommand"`, and the same day added an explicit REJECT rule (`c58a7da`/`2b46e47`).
- **The base is a mid-2025 (pre-fix) vintage of the upstream template — established by four independent markers.** The earliest surviving snapshot ([`4f1ccc4`](https://github.com/chenandrewy/FinRep/commit/4f1ccc4f247e868c5503c017cd61b4fec83f59bb), 2026-03-04, root commit shared by `FinRep` and `HumanxAI-ChenAY`, "copy over .devcontainer from ralph-wiggum-asset-pricing") matches upstream's **Jul 30 – Aug 15, 2025** state on every trait that discriminates versions: (1) `postCreateCommand` wiring with no `waitFor` (upstream switched to postStart+waitFor Aug 20); (2) no explicit-REJECT block (added Aug 20); (3) `ENV EDITOR nano` space-form Dockerfile syntax (changed to `=` form Aug 25, never reverted); (4) DNS handling whose base predates the Aug 15 CNAME fix, while the Docker-DNS-restore block (Jul 30) and `CLAUDE_CODE_VERSION` arg (Jul 28) are present. No mix of local regressions plausibly reproduces all four; conversely the one *post*-fix marker — `anthropic.claude-code` in extensions (upstream added it Aug 27) — is exactly what a Claude Code user would add locally, and it sits beside clearly-local additions (`tomoki1207.pdf`, `james-yu.latex-workshop`). An earlier draft of this note flipped to "descends from post-fix upstream" on the strength of that extension marker alone; the Dockerfile ENV form refuted that. Notably, the traits in our file **never coexisted in any upstream commit**, ruling out a clean pull of upstream main at any date.
- **Local edits on that base, all consistent with vibe-debugging:** research/AI domains added to the allowlist; `dig +short | grep -E` + `-exist` + validation-loop removal — and here's the kicker: `scholar.google.com`, one of the added domains, resolves via a CNAME (`scholar.l.google.com`), which in the pre-Aug-15 script causes exactly the "Invalid IP from DNS" hard exit that these edits fix. So whoever added the domains hit the same CNAME bug upstream fixed on Aug 15, 2025, and fixed it independently, unaware upstream had already done so.
- **The conduit is unresolved.** Andrew distinctly recalls pulling from `anthropics/` — but `anthropics/claude-code` main was post-fix from Aug 20, 2025 onward, so a Feb 2026 clone of main is ruled out by the four markers. Possibilities: (a) an old pinned tag/release or commit link (repo has 171 version tags; unverified); (b) a stale fork/tutorial copy; (c) the "pull" was AI-mediated and the assistant reproduced a mid-2025 version from its training data while describing it as coming from anthropics/ — in which case the recollection is of what the session *reported*, not what happened. Feb 2026 chat logs, if any survive, could settle this.
- **Lineage:** mid-2025 template (conduit unknown) → ralph-wiggum-asset-pricing (repo created **2026-02-11** = first contact with containers; pre-Mar-21 history force-push-wiped, no backup predates Mar 21) → FinRep/HumanxAI-ChenAY (`4f1ccc4`, Mar 4) → [ralph-wiggum re-init "based on FinRep", `0accc2e`, Mar 20 — circular copy-back after a .git wipe, not evidence FinRep was first] → big-ol-sandbox (`5c314dc`, Apr 23; `seed-agent-guidelines.sh` added as a *new* postStart line, did **not** displace the firewall) → `/workspace` re-init (`510716f`, Jun 28, post-.git-wipe).
- **Trigger:** ~23.7h before discovery (≈ July 14), Docker/the machine restarted (container PID 1 uptime matches VM uptime). Network namespace came back empty, only `seed-agent-guidelines.sh` re-ran, firewall gone. Silent because everything on the network *works better* with the firewall off; only noticed because a download succeeded that the allowlist should have blocked.

Timeline: Feb 2025 upstream ships bug → Aug 20, 2025 upstream fixes it (postStart + waitFor + REJECT) → Feb 11, 2026 ralph-wiggum-asset-pricing built on a Jul 30–Aug 15, 2025 vintage of the template (conduit unknown — old tag, stale copy, or AI-reproduced; the fix never arrives) → Mar 4, 2026 earliest surviving snapshot (`4f1ccc4`) already carries the bug plus local CNAME debugging → Apr 23, 2026 big-ol-sandbox → Jun 28, 2026 /workspace re-init → Jul 14, 2026 restart fails open → Jul 15, 2026 found.

## Fixes (not yet applied)

1. Re-arm now: `sudo /usr/local/bin/init-firewall.sh` (node has NOPASSWD sudo scoped to exactly this script). Caveat: this cuts off `drive.google.com`, so add `drive.google.com` + `drive.usercontent.google.com` to the domain list first if OpenAP downloads should keep working.
2. Persistence: run the firewall script on every start, e.g. `postStartCommand: "sudo /usr/local/bin/init-firewall.sh && bash .devcontainer/seed-agent-guidelines.sh"`, plus `"waitFor": "postStartCommand"`. This matches upstream's own fix (`6d79459`). Also worth porting upstream's Aug 20, 2025 explicit-REJECT changes (`c58a7da`, `2b46e47`) while at it.
3. Fail closed: set default DROP policies at the top of the script, before the flush and the fallible DNS/GitHub-meta steps.

## Misc observations

- Google IP-snapshot caveat: the script resolves each domain once at creation; Google front-end IPs rotate with short TTLs, so even an allowlisted Google domain can break intermittently later. (Today `scholar.google.com` → `64.233.180.x` but `drive.google.com` → `142.250.31.x`; no overlap, so scholar's entry never covered Drive.)
- An iptables DROP looks like a connect timeout/hang, not an application-layer error — useful for telling firewall blocks apart from server-side quirks like the HTTP/2 PROTOCOL_ERROR above.

Related: `0706a-container-breaking.md`, `0426T17-devcontainer-secrets.md`
