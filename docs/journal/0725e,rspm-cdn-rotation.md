# Why the R stack won't install: `rspm-sync` is CloudFront, and pinning can't work

Date: 2026-07-25 (NY)

The allowlist entry added in [0725b] is correct and installed, and it still
doesn't work. `rspm-sync.rstudio.com` rotates IPs faster than a start-time
`dig` can pin them. This entry records the evidence, corrects a wrong
measurement, and lays out the options in detail. **Decision recorded at the
end, later the same day: option 2 (dnsmasq).**

## The evidence

The firewall resolves each domain once, at container start, and pins those IPs
into the ipset. Sampled properly, the answer for `rspm-sync.rstudio.com` is:

```
13:52   18.160.10.29  18.160.10.31  18.160.10.74  18.160.10.78
13:58   13.35.107.11  13.35.107.13  13.35.107.38  13.35.107.64
14:00   18.160.10.29  18.160.10.31  18.160.10.74  18.160.10.78
```

Different `/16`s, flipping on a minutes timescale. TTL is **15–77 seconds**, and
answers differ *by resolver* — at one moment the container's resolver said
`13.35.107.x` while both `8.8.8.8` and `1.1.1.1` said `18.160.10.x`. Both
prefixes are AWS CloudFront.

Every currently-resolved IP is refused:

```
18.160.10.29: BLOCKED   (No route to host)
```

`No route to host` is EHOSTUNREACH, which is what our own
`--reject-with icmp-admin-prohibited` produces — so this is definitely our rule,
not a dead edge. The container pinned whatever was current at 13:46 and those
edges were gone by the time the script ran.

## Correction to [0725b]

I reported there that five `dig`s a second apart returned identical answers, and
concluded start-time pinning was "stable enough in the short run." Five samples
one second apart all fall inside a single 15-second TTL window — that
measurement could not have returned anything else. The conclusion was wrong, and
[0725b] now carries a correction banner.

## Why every other host in the list is fine

The `dig`-and-pin design assumes anycast. PyPI is the contrast:

| host | TTL | answers | behavior |
|---|---|---|---|
| `pypi.org` | 4502 | `151.101.{0,64,128,192}.223` | Fastly anycast — fixed set |
| `files.pythonhosted.org` | 77 | same four | Fastly anycast — fixed set |
| `rspm-sync.rstudio.com` | 15–77 | rotates across `/16`s | CloudFront — DNS edge selection |

Fastly answers with the same handful of anycast addresses forever; the TTL is
irrelevant because the addresses don't move. CloudFront hands out different edge
IPs per query, per resolver, per few minutes. Pinning works for the first and
cannot work for the second. This is why pip installs flawlessly and R never gets
a single package.

## Two things that are *not* the fix

**Turning off P3M binaries.** The site `Rprofile` sets an R-version user agent so
P3M serves prebuilt binaries; the obvious guess is that the binary payload is
what lives on the CDN. It isn't — the redirect is unconditional:

```
with R user agent:  307 -> rspm-sync.rstudio.com/v4/1/packages/8fcdb7....tar.gz
plain curl:         307 -> rspm-sync.rstudio.com/v4/1/packages/8fcdb7....tar.gz
```

Same artifact hash either way. Every P3M package download goes through that host,
source or binary. Metadata is served from `packagemanager.posit.co` directly,
which is why the batch *starts* and then every single download fails.

**Adding more names to the allowlist.** The name is already there. The mechanism,
not the list, is what's broken.

## What this explains

The R stack has never installed — not in the 11:43 run, not since. That is
independent of the container-lifetime question from earlier today: the venv was
populated successfully at 13:53 (220 entries) while R got zero packages in the
same run.

## The options

### 1. Refresher loop into an expiring ipset

`init-firewall.sh` already runs as root, so it can leave behind a background loop
that re-resolves a short list of volatile names every ~20s and adds whatever it
finds to a **second** ipset created with `timeout`, so entries expire on their
own:

```bash
ipset create allowed-volatile hash:ip timeout 3600
iptables -A OUTPUT -m set --match-set allowed-volatile dst -j ACCEPT   # before the REJECT
# then, backgrounded as root:
while :; do
  for d in "${VOLATILE[@]}"; do
    dig +short A "$d" | grep -E '^[0-9.]+$' |
      while read -r ip; do ipset add allowed-volatile "$ip" -exist timeout 3600; done
  done
  sleep 20
done
```

*Why it works well:* it is **additive with expiry**, so during a rotation the old
edges are still allowed while the new ones are added — no gap where an in-flight
install breaks. Over an hour the set holds only the edges this host actually
resolved to, which is a far smaller and more meaningful surface than "all of
CloudFront." It generalizes to the next CDN-fronted host by adding one name to
`VOLATILE`. No new packages: `dig` and `ipset` are both present.

*Costs and failure modes:* an orphaned root loop with no supervisor — if it dies,
installs start failing again silently, so it wants a log line or a liveness
check. Re-running `init-firewall.sh` must kill the previous loop (marker in the
process name, `pkill -f`). The `hash:ip` set has to be created with `timeout`
support up front, since existing sets can't gain it retroactively.

*Effort:* ~25 lines in one file. No permission needed.

### 2. dnsmasq with `ipset=`

The textbook answer. dnsmasq has a native option that adds every resolved address
for a name straight into an ipset:

```
server=127.0.0.11                              # upstream: Docker's embedded DNS
ipset=/rspm-sync.rstudio.com/allowed-domains
```

Point `/etc/resolv.conf` at it and any lookup for that name is allowlisted at the
moment it resolves. No polling, no window, exact by construction. It also scales
to wildcards (`/rstudio.com/`) if more Posit hosts surface.

*Why it's attractive:* it makes the firewall genuinely **name-based** rather than
address-based, which is the actual intent of the whole allowlist. The set
contains exactly the addresses that names we approved resolved to.

*Costs:* a new system package (needs permission), plus resolver plumbing —
Docker rewrites `/etc/resolv.conf` at container start, so `init-firewall.sh`
would have to rewrite it and keep `127.0.0.11` as upstream so Docker-internal
names still resolve. Worse failure mode than option 1: if dnsmasq doesn't come
up, *all* DNS breaks, not just R installs.

*Effort:* small, but it touches DNS for the whole container.

### 3. Point R at CRAN directly instead of P3M

`cran.r-project.org` is not a CDN. Measured: a single address, `137.208.57.37`
(WU Vienna), TTL 377s, identical across five samples spanning multiple TTL
windows. Pinning works by construction, it is already in the allowlist, and it is
already proven in practice — the `pryr` archive tarball downloads fine while
every P3M payload fails. A direct test downloaded `tictoc`, `Rcpp` and `fixest`
in **5 seconds** total.

*Cost 1 — the snapshot pin.* CRAN serves current versions only; there is no dated
CRAN. The Dockerfile calls `R_VERSION` and `CRAN_SNAPSHOT` "the two knobs that
fully determine the R stack on every machine," and this option gives up the
second one. Measured drift **today** is small — 2 of 36 packages differ from the
2026-07-15 snapshot (`lme4` 2.0-1 → 2.0-6, `arrow` 24.0.0 → 25.0.0) — but that
is an artifact of the snapshot being 10 days old. The number grows with time,
and worse, the stack becomes *date-of-install* dependent, so two machines built a
month apart diverge. That is exactly what [0716a] adopted the snapshot to stop.
Recoverable with an `renv` lockfile or explicit Archive-URL pins, at the cost of
maintaining one.

*Cost 2 — source builds, cheaper than expected.* CRAN serves Linux source only,
so everything compiles. I assumed this was prohibitive; measured, it mostly isn't:
`Rcpp` (C++, no dependencies) built in **12s**, `tictoc` in **2s**, with
`Ncpus=2` already set. For most of the stack this is a non-issue.

*Cost 3 — `arrow` is the exception, and it's a real one.* Under P3M `arrow`
arrives prebuilt so nothing compiles. From CRAN, `tools/nixlibs.R` first tries to
download a prebuilt libarrow from `apache.jfrog.io`, falling back to
`nightlies.apache.org` — **both verified blocked** — and otherwise compiles the
bundled Arrow C++ tree, which is slow and pulls third-party dependencies. So this
option needs an explicit decision on `arrow`: drop it, allowlist yet another
CDN-fronted host (the same trap again), or force `LIBARROW_MINIMAL` / a bundled
source build and accept the build time.

*Effort:* one line — change `options(repos=)` in `Rprofile.site` — plus whatever
`arrow` ends up needing. No daemon, no new packages, no policy widening.

### 4. Allowlist AWS's published CloudFront ranges

Mechanically the easiest — copy the `goog.json` block, point it at
`https://ip-ranges.amazonaws.com/ip-ranges.json`, filter `service == "CLOUDFRONT"`,
add the prefixes. Self-healing, no daemon, no polling.

*Why I'd avoid it:* this is precisely the `cloud.json` category that [0724d]
drew a line against. CloudFront is a *customer-facing* CDN: anyone can stand up a
distribution for a few dollars and get an endpoint inside those ranges. Allowing
them is functionally "allow a rentable egress endpoint," which is the rent-a-C2
shape, not the `goog.json` shape (Google's own fleet). It is also large — a
significant fraction of the web sits behind CloudFront.

If the posture is "match control cost to data value" ([0724d]) you could argue
for it anyway, given GitHub, Google, Sentry and the LLM APIs are already open.
But it is a **policy widening dressed as a bug fix**, and worth naming as such
rather than sliding it in.

### 5. Install at `postCreateCommand`, before the firewall exists

`postCreateCommand` runs before `postStartCommand`, and the firewall is applied in
`postStartCommand` — so at that moment the network is wide open and the install
just works, exactly as it did during `docker build`.

*Why it's a trap:* it re-creates the build-vs-runtime asymmetry that [0725a] item
3 identified as the source of this whole problem — "it worked in the Dockerfile"
was never evidence a command works in flight. Installs would succeed at creation
and fail whenever re-run later, which is the confusing failure we just spent an
afternoon on. It also silently un-tests the allowlist: hosts could drop off it
without anyone noticing.

*Where it's defensible:* combined with persistent volumes, re-runs become rare
enough that the asymmetry rarely bites. Cheap: one line in `devcontainer.json`.

### 6. Put the R stack back in the image

The honest option, and a partial revert of `f12d37c`. `docker build` has an open
network, which is why 30+ R packages installed fine for months and one fails now.
Baking R back in makes the problem disappear without any new machinery, and it
also disposes of the volume/persistence question for R specifically.

*Costs:* back to a rebuild for every R stack change — the thing [0725a] set out
to fix. Worth asking how often that actually happens; if it's twice a year, the
runtime-install machinery is buying very little.

*A useful middle:* keep **Python** at runtime (PyPI is anycast, works perfectly,
and pip is the stack that changes more often) and bake **R** back into the image.
That splits along the exact line the evidence draws.

### 7. Local package cache

Vendor the tarballs into a volume (miniCRAN / `renv` cache) and install from
`repos = NULL` against local files. Fully offline after the first fill, immune to
CDN behavior, and reproducible.

*Costs:* the first fill still has to get through the CDN, so it doesn't solve
anything on its own — it needs one of the options above to bootstrap, then makes
subsequent installs independent. Real maintenance burden. Only worth it if
offline reproducibility becomes a goal in its own right.

## Recommendation

The choice turns on **one question: does the dated snapshot pin still matter?**

*If yes* — **option 1 (refresher)**. It is the smallest change that makes runtime
R installs genuinely work while keeping both the snapshot and the name-based
boundary. No new packages, no permission, and it generalizes to the next
CDN-fronted host. Its weakness is supervision, which a log line largely covers.
**Option 2 (dnsmasq)** is the more principled version of the same idea if a
system package and DNS plumbing are acceptable.

*If no* — **option 3 (CRAN direct)** is the least machinery of anything here: one
line in `Rprofile.site`, a host that is already allowlisted and demonstrably
works, and compile times that measurement showed to be far lower than assumed.
The bill is reproducibility (recoverable via `renv`) plus a decision about
`arrow`.

**Option 6's middle path** (Python at runtime, R baked into the image) is the
answer if the preference is fewer moving parts over flexibility. It is a real
retreat from [0725a], but an evidence-driven one.

I'd avoid **4** on consistency grounds — it is a policy widening dressed as a bug
fix — and **5** because it hides exactly the failure class we just spent an
afternoon debugging.

## Decision: option 2 (dnsmasq)

Chosen later the same day, and implemented.

The question the recommendation turned on — does the snapshot pin still
matter? — resolved to **yes**, which ruled out 3. Its "one line" is
front-loaded laziness: the real bill (an `renv` lockfile to keep the pin, an
unresolved `arrow` decision whose escape hatches are blocked hosts or bundled
C++ builds) arrives later, distributed. Under dnsmasq, P3M keeps serving
prebuilt binaries and the `arrow` question never comes up.

Between 1 and 2, dnsmasq wins on correctness and failure mode:

- The evidence above shows answers differ *by resolver*. A 20s polling loop
  against a 15s TTL leaves a window where the client's own resolution returns
  an edge the loop hasn't seen yet — widest at container start, exactly when
  `install-packages.sh` runs against a nearly-empty set. dnsmasq inserts the
  address into the ipset *before* returning the DNS answer, so no client can
  connect to an address that isn't already allowed. No window, by
  construction.
- Option 1 fails silently (the loop dies, installs mysteriously break weeks
  later). dnsmasq fails loudly (no DNS at all), and cutover-after-verification
  caps even that: `resolv.conf` is pointed at `127.0.0.1` only after dnsmasq
  demonstrably answers queries *and* populates the ipset; otherwise it stays
  at the upstream and only R installs remain broken — which is where we
  already were.

### Corrections and traps found while implementing

- The option-2 sketch above says `server=127.0.0.11`. **Wrong for this
  container**: `/etc/resolv.conf` points at `192.168.65.7`, Docker Desktop's
  host-side resolver — there is no embedded-DNS NAT in play. The script
  harvests the upstream from `resolv.conf` instead of hardcoding, and stashes
  it in `/etc/dnsmasq-upstream.conf`, because on re-runs `resolv.conf` already
  says `127.0.0.1` and harvesting *that* would make dnsmasq forward to itself.
- Re-run hazard: the script kills the previous dnsmasq early, so every
  `dig`/`curl` later in the script would hit a dead `127.0.0.1`. The teardown
  restores the stashed upstream into `resolv.conf` immediately after the kill.
- Pre-rebuild hazard: `postStartCommand` runs on every container start. If the
  script hard-failed on a missing dnsmasq binary, the EXIT trap would slam
  policies to DROP and brick all networking. A missing binary is a
  warning-and-skip instead: everything else works, R installs stay broken
  loudly until the rebuild.
- `allowed-volatile` is `hash:ip` with **no timeout**: dnsmasq only ever
  inserts addresses that approved names actually resolved to, so the set stays
  small, and expiry could drop an edge a client still holds in its own DNS
  cache.
- AAAA answers can't go into an inet-family ipset; dnsmasq logs and skips
  them. Irrelevant here (no v6 routing in the container), noted in case a
  future dual-stack setup resurfaces it.

### What changed

- `Dockerfile`: `dnsmasq-base` (binary only, no init scripts — the script
  launches it explicitly). Image-time because Debian's apt mirrors are not
  allowlisted at runtime. **Rebuild required.**
- `init-firewall.sh`: teardown (kill dnsmasq, restore upstream, destroy set);
  `allowed-volatile` ipset; an ACCEPT rule for it ahead of the REJECT; and a
  launch/verify/cutover block at the end. `rspm-sync.rstudio.com` is removed
  from the static pin list — volatile hosts now go in `VOLATILE_DOMAINS`,
  where the next CDN-fronted redirect host is a one-line addition.
- `test-firewall.sh`: probes `https://rspm-sync.rstudio.com/`, exercising the
  full resolve → ipset-insert → connect chain — the regression test for
  exactly the failure documented above.

### Postscript: it worked, and then `arrow` failed differently

First run after the rebuild: **35 of 36 installed, every download through the
dnsmasq path succeeded** — including `arrow`'s own tarball. The rotation bug is
dead.

`arrow` then failed at *build* time, which surfaces a correction to Cost 3
above: "under P3M `arrow` arrives prebuilt" is only true on x86_64. **This
container is aarch64**, and P3M has no arm64 Debian binaries — so everything
here compiles from source (consistent with the Cost-2 timings, which were
measured on this machine), and `arrow` alone needs Arrow C++. Its bundled
build fetched Boost and Snappy fine (GitHub), then died downloading Thrift
from `www.apache.org` / `dlcdn.apache.org`.

Unlike last time, these hosts are pinnable: both resolve to `151.101.2.132`
(Fastly anycast, TTL ~370s, stable across samples). Added, together with
`nightlies.apache.org` (single IP), to the **static** list. `apache.jfrog.io`
— the first host `nixlibs.R` tries for a prebuilt libarrow — is an AWS load
balancer with a 73s TTL, so it went into `VOLATILE_DOMAINS` instead; whether
it serves an arm64 binary is unknown (it was blocked), but if it does the
whole compile is skipped, and if not it falls through to the source build.
This is the generalization paying off: the next CDN-fronted host was, as
predicted, a one-line addition.

Open question, deliberately deferred until this run reports timing: **baking
tricky packages (i.e. `arrow`) into the image at build time.** The case for:
runtime installs live in the container filesystem, so every container
*recreate* pays the full ARM compile again — if the bundled Arrow C++ build
takes 30+ minutes, that bill recurs. The case against: it re-creates the
build-vs-runtime asymmetry from [0725a] for exactly the package most likely
to break, and the runtime path for it would go permanently untested. Decision
rule: if `apache.jfrog.io` serves an arm64 libarrow, runtime install is fast
and nothing moves; if we're stuck with a long bundled build, `arrow` (alone)
goes into the Dockerfile.

**Resolved — and the decision rule above was wrongly framed.** The goals
clarification in [0725f] (fast debuggable builds and low adoption barrier;
runtime install speed was never a goal) rejects baking in every form —
`arrow` is precisely the compile that made builds painful. Recreate cost is
handled by persistent package volumes instead. See [0725f].

### Postscript 2: round two, and the full host list this time

The rebuilt firewall connected to `www.apache.org` fine — and `closer.lua`
redirected to `archive.apache.org`, blocked. Mechanism, confirmed by a direct
probe: **Apache mirrors carry only current releases.** `dlcdn.apache.org`
answers 404 for thrift 0.22.0 (rotated off the mirrors), and `closer.lua`
sends archived versions to `archive.apache.org` — a single stable Hetzner IP,
TTL ~30 min. So dlcdn was never going to serve this file; archive is the host
that matters.

Rather than discover the remaining hosts one failed build at a time,
downloaded the `arrow` source tarball through the (working) dnsmasq path and
enumerated `cpp/thirdparty/versions.txt`: 43 of 48 dependency URLs are
`github.com` (covered by the GitHub ranges); the rest are the apache
closer.lua pair (thrift, orc), `zlib.net` (only hit if system zlib isn't
found), and `sourceware.org` (bzip2). All stable, all added to the static
list. That should be the complete surface for this arrow version.

The root cause under all of this — no P3M arm64 binaries for Debian, hence
source builds, hence the chase — has a structural fix: an Ubuntu base image.
Direction decided, timing deferred; see [0725g].

## Also fixed today

`install-packages.sh` reported this failure terribly: `install.packages()` only
*warns* on download failure, so the script cascaded into `pryr`'s missing
dependencies and then died on `loadNamespace('remotes')` — a hard error that
halted R before the verification block that would have named the problem. It now
checks the batch immediately, stops with one summary naming the failed packages
and pointing at the firewall and CDN rotation, and wraps the archive/GitHub steps
so the summary is always reached. Committed as `031deae`.

[0716a]: 0716a,r-upgrade-shelved.md
[0724d]: 0724d,google-firewall-open.md
[0725a]: 0725a,firewall-plan-update.md
[0725b]: 0725b,firewall-plan-implemented.md
[0725f]: 0725f,persistent-package-volumes.md
[0725g]: 0725g,ubuntu-base-migration.md
