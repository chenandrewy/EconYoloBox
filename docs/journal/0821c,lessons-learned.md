# Lessons from building the sandbox

Brownbag notes. Date: 2026-08-21 (NY)

The design of this box is empirical: something broke, we worked out why, and the
fix became the design. What follows is organised by area, and within each area
the details are written as **lessons** rather than as a log of what happened.
The incident write-ups live in the other journal entries if you want them.

---

## The decisions, in one table

| Area | Decision | Call |
|---|---|---|
| Agents | What keeps an unsupervised agent safe? | The container, not the prompt |
| Network | How much internet does the box get? | Nothing by default; open specific things deliberately |
| Network | Sites that keep changing addresses | Allow by *name*, resolved live |
| Network | Google serves Scholar and Drive from the same addresses | Allow all of Google; the data isn't worth the lock |
| Agents | Can the agent reach our mail, calendar, drive? | Freeze connectors and plugins shut, where the agent can't undo it |
| Agents | Can the agent push to GitHub? | Yes — but ask first. **Least settled decision here** |
| Secrets | How do research passwords get in? | One read-only file, read on demand — not environment variables |
| Image | Which Linux? | Ubuntu, because that's what the R mirror builds for |
| Image | How is the image laid out? | Slow and stable first; fast-changing last |
| Packages | Where do R and Python packages live? | On a persistent disk, not in the image |
| Packages | Do we pin versions? | R yes, deliberately. Python no, deliberately |
| Ergonomics | How do you open a project? | One command from anywhere: `dccode` / `dce` |
| Ergonomics | Do sessions follow you between machines? | Yes, via Dropbox |
| Scope | Windows? | No |
| Scope | Publish it? | Yes, as EconYoloBox, via a scripted release procedure |

---

## 1. Running agents unsupervised: what actually holds the line

**Lesson: if you turn off the permission prompts, something other than the
agent's good behaviour has to be the boundary — and only the container
qualifies.**

The point of the box is that agents run without asking permission for every
command. That's only defensible because the agent is inside a container that can
reach an approved list of sites and nothing else. Instructions in a config file
are preferences. An agent can ignore them, and worse, an instruction that
arrives inside a downloaded paper or a repository can override them.

**Lesson: the container isolates the process, not your disk.**

Files in the project folder are live host files. Whatever the agent writes shows
up on your Mac immediately. This is the single most common misunderstanding of
what a container gives you, and it is worth saying out loud before anyone
copies the setup.

**Lesson: inheriting a security design beats inventing one — but check what the
authors actually claim for it.**

The container descends from Anthropic's own reference setup, deliberately, so
the safety argument doesn't rest on our judgement. Preparing to publish, we went
and read what they say about it: *"a working example rather than a maintained
base image."* That is a weaker warrant than "many people have reviewed this,"
which is what we'd been implying. Their guidance also covers Claude only — we run
Codex in the same box with the same prompts bypassed, and nothing upstream
blesses that half.

**Lesson: the standard protection doesn't apply here.** VS Code asks whether you
trust a repository when you open it. That's a one-time human decision about
code you didn't write. It is never re-checked when a file you already trusted
gets rewritten — which is exactly what an unsupervised agent does all day.

*Written up in: 0821a, 0821b.*

---

## 2. The firewall

**Lesson: a safety measure that fails silently — in the direction of "more
things work" — will never be discovered by using the system.**

The firewall wasn't running for about a day. The rules were installed once when
the container was first built; restart your laptop and the container comes back
with them gone, wide open. Nothing complained, because everything on the network
works *better* without them. The only symptom was a download succeeding that
should have failed.

Two changes followed, and both are the general form of the lesson. The rules are
re-applied on every start, and the container isn't considered ready until they
are. And there's now a script that deliberately tries to reach a blocked site
and complains if it gets through — because the only way to find a silent failure
is to test for it on purpose.

**Lesson: blocked traffic must fail loudly and immediately, or you will lose an
afternoon.**

Originally blocked connections just hung until something timed out. The Python
extension wouldn't install and there was *no error message anywhere* — just
things being slow and never finishing. One extra rule turned silent timeouts
into instant, visible failures and the problem solved itself in seconds.

This generalises well beyond the sandbox: **under this kind of blocking, a
network problem doesn't look like an error, it looks like something being slow.
The absence of an error message is not evidence that the network is fine.**

**Lesson: allowing sites by address doesn't work, and fails in a way that looks
like something else entirely.**

The obvious design is: at startup, look up each approved site's address and
allow those addresses. It works for most things and fails completely for
anything behind a modern content-delivery network. The R package mirror hands
out a different address every couple of minutes, and a different one to
different people asking. So the address we wrote down at startup was already
wrong.

The visible symptom was that **the entire R package stack never installed, while
Python installed perfectly** — both "on the allowed list." The fix is to allow
sites at the moment their address is looked up, so whatever comes back is
automatically permitted. The list is by *name* now, which is what we meant all
along.

**Lesson: a measurement that can only return one answer isn't evidence.**

We convinced ourselves that mirror was stable by checking it five times, one second
apart, and getting identical answers. The address changes every fifteen seconds.
Those five checks were physically incapable of disagreeing. We wrote the wrong
conclusion into the journal, then had to correct it the same day.

**Lesson: some distinctions can't be drawn at the network level at all — and
that's a fact about layers, not a tuning problem.**

Google serves Scholar, Docs, Drive, Forms and Cloud Storage from the *same*
addresses. Which one you get depends on the name you asked for, which the
firewall cannot see. So "allow Scholar but not Drive" isn't a setting; it's
impossible here. Allowing Scholar means allowing Google Forms, which is a
textbook way to quietly ship data out of a machine.

**Lesson: price the asset before you design the lock.**

We spent a day designing an elaborate workaround — a locked-down helper that
would open a hole, fetch from Scholar itself, and slam it shut, with a watchdog
in case it crashed mid-fetch. Good design. Then we asked the question we should
have asked first: *what's in this box that's worth stealing?* Economics
research. The most sensitive artifact is a referee report — an embarrassment if
it leaked, not a catastrophe. And the box already has GitHub, the AI APIs and
error reporting open, so it was never sealed against anyone determined.

So: allow Google, accept the exposure, delete the clever design. A day saved by
one question asked at the start.

**Lesson: say what the control actually buys, not what it sounds like it
buys.** This firewall stops a bad dependency phoning home to some random server.
That's a real and common threat and it's worth having. It does not stop a
determined attacker, and documenting otherwise would be worse than useless.

**Lesson: an inherited design carries inherited holes, and "we got it from
upstream" is not the same as "someone checked it."** Outbound SSH and outbound
DNS are open to anywhere, both inherited verbatim. DNS is close to unavoidable —
block it and nothing can look up any address, including permitted ones. SSH is
harder to defend: nothing here uses it, and it's precisely the kind of opening
you can tunnel everything else through. Still on the list.

*Written up in: 0715a, 0719a, 0720d, 0724b, 0724d, 0725e, 0821a.*

---

## 3. Agent-level controls

The firewall is where nearly all the security lives. Two things it structurally
cannot do have to be handled at the agent level instead.

### 3a. Connectors: the hole the firewall can't close

**Lesson: opening a network destination can open a data channel you didn't
think you were opening.**

Claude and Codex can both connect to outside services on your behalf — Gmail,
Google Calendar, Google Drive, and a catalogue of third-party plugins. Useful
features, exactly wrong here, for two reasons that compound:

1. The agent runs with permissions bypassed. Nobody is reviewing what it reads.
2. **We just opened Google in the firewall.** So the layer that is supposed to
   be the boundary would happily let a connector reach our mail and our Drive.

The firewall can't help — it can't tell a Scholar request from a Gmail request.
So the block has to happen in the agent's own configuration.

**Lesson: settings the agent can write are settings the agent can undo.**

Connectors and plugins are frozen shut by two small files owned by root and
baked into the image: Claude's AI connectors are disabled, with the Gmail,
Calendar and Drive endpoints denied by name as well because the general switch
leaves a gap for connectors passed in on the command line; Codex Apps, Plugins
and remote plugin catalogues are disabled and the marketplace allowlist is
emptied so nothing can be installed from anywhere. Changing any of this now
requires editing the repository and rebuilding — a deliberate, visible act.

**Lesson: a policy file that fails silently needs a behavioural test, not a
presence check.**

Get a key name wrong, or have the vendor rename a flag, and the file sits there
looking perfectly correct while enforcing nothing. So the startup check doesn't
ask "does the file exist." It **actually tries to turn the feature back on** and
confirms it gets refused. Presence is not enforcement.

**Lesson: be precise about what kind of control this is.** It configures the
agent software, not the operating system. It reliably prevents accidents and
casual reaching. It is not the same guarantee as the container itself, and the
documentation says so.

*Written up in: commit a2353e6.*

### 3b. GitHub credentials — the decision we're least sure about

Worth real discussion, because we have been round this loop twice and do not think
we have landed.

**Round one.** We removed the saved GitHub login, on the principle that an
unsupervised agent shouldn't be able to publish. Agents prepare commits; the
human reviews and pushes. We wrote it into the guidance as an invariant: *"the
container has no GitHub credentials by design."*

**Round two: that statement was false, and had been the whole time.** VS Code
forwards your GitHub credentials into any dev container by default. Not a
mistake anyone made — it's default behaviour, reinstalled on every connect, and
owned by root inside the container so you can't remove it from in there. The
container could push the entire time we were documenting that it couldn't.

**Lesson: check what your tools do by default before writing an invariant about
it.** We documented a security property for weeks that the platform was quietly
contradicting.

**Round three: we kept it.** The strict stance was an overreaction to one
accidental push, and Anthropic's reference container forwards credentials
deliberately so the agent can push branches and open pull requests. So the
capability exists and the guardrail is a written rule: *get permission before
authenticating to GitHub or pushing anything.*

**And here's why we're uneasy.** A written rule is exactly the sort of protection
that §1 says isn't protection. The entire argument of this box is that
instructions are not a boundary — and here we've made an instruction the boundary
for the one capability that publishes irreversibly to the internet.

Three defensible positions, and we don't think it's obvious which wins:

- **Keep it.** Pushing is useful, mistakes are recoverable, git keeps history.
  The realistic failure is a premature push, not a malicious one.
- **Turn the forwarding off** and push from the Mac. Small friction; removes the
  capability instead of asking nicely.
- **Forward a narrow token** scoped to specific repositories, instead of your
  whole GitHub identity. Probably the actually-correct answer. Not done.

*Written up in: 0724e, 0725a.*

---

## 4. Credentials

**Lesson: environment variables and files are equally readable by anything
already running in the container. The difference is everywhere *else* they end
up.**

WRDS and the API keys have to get from the Mac into a container an unsupervised
agent is running inside. They now live in the macOS Keychain, get pulled out by
a script on the Mac before the container starts, land in one private file, and
are mounted read-only. Scripts ask for one value at a time. Previously they were
passed in as environment variables.

Against an attacker already inside the container this changes nothing — same
user, same access. That's the honest framing. What it does buy:

- **Every program stops seeing them.** As environment variables, your WRDS
  password is handed to *everything* that runs: every `pip install`, every R
  package build script, every tool the agent starts. In a box that routinely
  runs third-party install scripts, that's the part that matters.
- **They stay out of Docker's own records.** Environment variables get copied
  into Docker's metadata, where they persist for the container's life, survive
  restarts, and print out to anyone who asks Docker about the container. A
  second copy in a place you don't manage and wouldn't think to check.
- **Crash reporters collect environment variables.** They don't collect files
  they've never heard of.
- **You can revoke it.** Blank the file and access ends. An environment variable
  is fixed for the life of the program.

**Lesson: an in-container keychain is the obvious idea and it's worthless.**
Worth spelling out, because everyone suggests it:

- **No backend.** It's a front-end over a store, and the store isn't there.
- **It's circular.** Any vault inside the container has to be unlocked by a
  password that has to arrive from outside — which is the problem you started
  with. A vault that unlocks itself at boot is a plaintext file with extra
  steps.
- **Wrong trust model.** The Mac Keychain works because macOS enforces per-app
  permissions and prompts you. Nothing inside a Linux container enforces
  anything equivalent. The store belongs on the host, which is where it is.

**The other alternatives, and why not:**

- **A helper on the Mac the container asks each time.** Architecturally the
  nicest. Awkward to wire through Docker on macOS, needs its own authentication
  (back to the injection problem), and doesn't help anyway — anything in the
  container can just ask the helper.
- **Never let the secret in.** Run WRDS pulls on the Mac, drop the data file in
  the shared folder. Genuinely the safest, and the right answer if pulls are
  occasional. Still available.
- **Send fewer secrets.** Which credentials reach which project is configured
  per-project; a LaTeX project doesn't need the WRDS password. Cheap, and
  usually buys more than any amount of plumbing.

**Lesson: name the tension instead of accepting it quietly.** Anthropic's
guidance says don't mount long-lived host secrets into a bypass-mode container;
prefer short-lived, narrowly-scoped tokens. Our design does what they advise
against. For WRDS there may be no short-lived alternative, which makes it an
accepted risk rather than a fixable defect — but right now it's accepted
*silently*, which is the part to fix.

*Written up in: 0426T17, 0725c, 0821b.*

---

## 5. The image and the base

**Lesson: the base Linux distribution is not a matter of taste — it decides
whether your statistical packages arrive ready to use or get rebuilt from
source on your laptop.**

The container originally ran Debian. On an Apple Silicon Mac that meant **every
single R package compiled from source**, because the Posit mirror we get R
packages from publishes ready-built packages for Ubuntu but not for Debian on
ARM chips. Everything downstream traced to that one fact: first-time setup took
about an hour, and `arrow` (Parquet files) tried to build a large C++ library
from scratch, which kept failing on downloads from hosts that weren't on the
allowed list.

Switching to Ubuntu fixed the category rather than the symptom:

```
Before:  ~1 hour of compiling
After:   1m13s — 189 packages downloaded ready-built, 2 compiled
```

The two that still compile are meant to: one is pinned to an archived version,
one comes from GitHub.

**Lesson: put slow, stable things at the top of the Dockerfile and
fast-changing things at the bottom.**

The recipe is layered and each layer is cached. Change something at line 50 and
everything after it rebuilds; change something at line 250 and nothing else
does. LaTeX, R and LyX are enormous and almost never change, so they go early.
The firewall configuration and the agent policy files change constantly and are
tiny, so they go last — where editing them costs seconds instead of twenty
minutes.

Two ways we got this wrong, both instructive:

- We compile LyX from source, and immediately afterwards a command adjusted file
  permissions across the folder LyX had just filled with 40MB of data. That
  rewrote all 40MB into a fresh layer for no benefit. Moving one line up fixed
  it.
- LyX sits *above* the R section deliberately. The R snapshot date gets bumped
  fairly often and everything below it rebuilds when it does. LyX below that
  line would mean recompiling LyX every time we updated R packages.

**Lesson: when you swap a base image, the danger isn't what you install — it's
what the old base was installing for you without being asked.**

Five packages vanished in the Ubuntu move. Four failed loudly. One didn't: Git
built perfectly, just silently without the ability to talk to `https://`. The
build went green and the failure surfaced days later as a baffling error on the
first `git clone`. There's now a check that confirms tools actually *work*
rather than that the build succeeded.

*Written up in: 0716a, 0720b, 0725g, 0726a.*

---

## 6. Packages and reproducibility

**Lesson: packages belong on a persistent disk, not baked into the image.**

Originally every R and Python package was built into the image. Two costs, and
they compounded: rebuilding took twenty-plus minutes, which made the image
painful to change and painful to debug (a failed build starts over from
scratch); and trying the box for the first time meant sitting through that
build, which is a bad first impression for anyone we'd like to actually use it.

So packages moved out into a re-runnable script — which created a new problem,
because rebuilding the container then silently threw them all away and you'd sit
through the install again.

The fix is a persistent disk (Docker calls it a volume) that lives outside the
container and survives rebuilding it. First install fills it; every rebuild
after that finds it full and skips the work. Compiling becomes a
once-per-machine cost instead of once-per-rebuild, **and the image build gets
faster rather than slower.**

Same trick, same reason, for two other things:

- **The AI command-line tools.** They used to be in the image, which meant every
  rebuild silently reverted whatever update you'd installed. Now updates stick.
- **Your Claude and Codex logins**, so you don't re-authenticate after every
  rebuild.

**Lesson: label the disk with the versions it was built for.** Packages are
compiled against a specific Linux and a specific R. Mixing them doesn't degrade
gracefully, it crashes. The names carry the version, so upgrading R
automatically starts a clean disk instead of mounting an incompatible one.

**Lesson: and make them unique per project.** They weren't, briefly. Two
checkouts with the same folder name shared one disk — which meant sharing Claude
and Codex login tokens between them. It turns out to be the same bug Anthropic
had fixed upstream a year earlier.

**Lesson: what belongs on a volume is decided by build pain and per-checkout
cost — not by size.**

The obvious follow-up is why TeX Live didn't move out too. It is 3.2GB, easily
the largest thing in the image, and on size alone it looks like the best
candidate of all. It stayed, and the reasoning is the general rule.

Volumes are keyed per checkout, because that is what stops two projects sharing
login tokens. The image is shared across all of them. So the trade isn't 3.2GB
either way — it's 3.2GB once, against 3.2GB *times the number of projects you
have checked out*. And the thing that moved R was compile pain, not size: R
packages built from source for twenty minutes and every edit above them re-paid
the bill, whereas TeX Live is a plain download sitting near the top of the
recipe, in the most cache-stable position, which essentially never rebuilds.

There's also nothing to gain. A volume buys "add a package without rebuilding,"
and with the full TeX Live distribution installed there is nothing left to add.

**Lesson: sometimes the crude bulk install is the right answer, and the deciding
factor isn't disk.**

We spent real effort trying to install LaTeX *nicely* — a minimal scheme
carrying just the packages we actually use — and gave up. `texlive-full` is
unsubtle and it is roughly 94% of the image.

What settled it wasn't storage, it was the failure mode. A missing `.sty` file
produces a cryptic error, and fixing it means `apt-get`, which means root, which
under our own rules means the agent has to stop and ask a human. So the tidy
install doesn't fail on disk, it fails on *your attention*, at whatever moment
you were mid-draft. Paying about 2.5GB once, on a shared image, to make LaTeX
simply always work is a good trade.

The general form: an optimisation that converts a rare storage cost into an
occasional interruption is usually a bad deal, and the accounting won't show it
because interruptions aren't measured in gigabytes.

**Lesson: pin R deliberately, and know that Python isn't pinned.**

Debian's built-in R was 4.2.2, from October 2022, frozen forever, and current
CRAN packages increasingly refuse to install on it. So we install a specific R
version from Posit, whose builds are permanent and never deleted, and point
every `install.packages()` at a **dated snapshot** of CRAN rather than at live
CRAN.

The argument is replication, and it's the one to make to economists: without the
snapshot, two machines built a month apart get different package versions, and
so do you and your coauthor, and so does you-in-two-years. With it, the R
environment is fixed by two numbers in one file — an R version and a date.
Rebuild next year, get the same stack. The cost is that you bump the date
deliberately and are never accidentally on the newest thing. That's the point.

Python deliberately installs whatever's current from PyPI. It's convenient and
it is *not* reproducible, and that inconsistency is real. If replicating the
Python side ever matters, that's the thing to fix.

**Lesson: watch for the one-line fix that quietly sells the thing you built the
setup for.** During the address-rotation mess in §2, pointing R at live CRAN
would have made the problem vanish in one line. It would also have thrown away
reproducibility — the entire reason for the arrangement — and the real bill (a
lockfile to maintain, plus an unresolved `arrow` problem) would have arrived
later and in pieces.

*Written up in: 0716a, 0725e, 0725f.*

---

## 7. Ergonomics

The largest share of the actual work, and the part people notice.

**Lesson: if getting into the environment takes five steps, you will avoid the
environment.**

Opening a project inside a container normally means: open VS Code, open the
outer folder, run "Reopen in Container," wait, then navigate down to the
subfolder you actually wanted. Every time. So:

```
dccode My-Project      # opens that exact folder, in the container, in VS Code
dce    My-Project      # same, but drops you into a terminal there
dcu                    # starts the container
```

They walk *upward* from wherever you are to find the enclosing container, then
open the exact subfolder you asked for. No "Reopen in Container," no navigating
afterwards.

**Lesson: tooling that names your personal paths can't be shared.** These take
no configuration and name no personal folders, so they work against any
repository with a dev container, on any machine, unchanged. The setup originally
mixed generic container navigation together with launchers pointed at our own
folders; splitting them by owner is what made the whole thing publishable.

**Lesson: name things automatically or they won't get named.** `cchat-yolo`
starts Claude with prompts off, names the session after the folder you're in,
numbers it, and puts every session under remote control. So `dce <project>` then
`cchat-yolo` is the entire workflow, and every session is identifiable
afterwards without anyone naming one by hand — which is what makes running
several at once tractable.

**Lesson: sync sessions between machines by machine, and never resolve conflicts
by timestamp.** Claude and Codex histories are symlinked into the Dropbox folder
per machine, so you can start something on the laptop and resume at the desk.
The operating rule is quit, let Dropbox settle, resume. When two versions
disagree the tool keeps both and warns — a timestamp cannot tell "newer" apart
from "conflicting," and guessing wrong silently destroys work.

*Written up in: 0708T08, commits f19c812, d11c149.*

---

## 8. Research tooling

**Lesson: never let a search tool pick the paper for you.**

Both citation tools hit this independently. Asked for "The Positive Economics of
Methodology," the top hit is *Friedman's* "The Methodology of Positive
Economics" — word order flipped. Taking the top hit silently returns the wrong
paper's citations, with nothing in the output to say so. Both tools now show the
candidates and make you choose, then echo back the paper they pinned.

**Lesson: sort by relevance, not by citation count.** We originally sorted
candidates by citations, with a comment justifying it. That buried the target
paper (11 citations) under Friedman's 1,573 and two reprints, off the first page
entirely. The counterexample now lives in the code comment so nobody tidies it
back.

**Lesson: know where the line is between hardening a client and circumventing a
control.**

Google Scholar worked for about four days, then began showing our tool a CAPTCHA
and never stopped — while the same site loaded fine in a browser on the same
machine, from the same address. So it is the *tool* being refused, not the
address being blocked. We hardened the client properly (cookies, coherent
headers, real pacing, backing off instead of retrying) and it did not help.
Explicitly ruled out: rotating fake browser identities, CAPTCHA-solving
services, proxy cycling. We use OpenAlex instead, and the tool says plainly that
OpenAlex undercounts recent working papers.

**Lesson: retire a broken tool from the documentation, not just from the
workflow.** Leaving it described invites an agent to reach for it as a fallback,
which is the opposite of the intent.

**Lesson: think twice about anything shaped "agent transcript → local web server
→ editor panel."**

The extension we used to render equations from agent chats had a flaw that let
*any website open in any browser tab* read the full text of our agent
conversations — including, at the time, an in-progress referee report on a paper
under confidential review. Not malicious; a one-line mistake. But that shape is
proliferating, and it is worth three questions before installing one: does it
listen on the network, can other websites read it, and does any endpoint return
conversation text? Our replacement has no server and no network at all.

**Lesson: with document conversion, the output side is the binding constraint.**
Sending ten PDF pages per request to be converted ran for eight minutes and
produced *nothing*, then fell back to retrying page by page. Ten pages of output
is more than a single response can produce. Batching up is strictly worse on
both cost and time — you pay for all ten page images, get nothing, then pay
again.

*Written up in: 0505T20, 0720a, 0721a, 0730a, 0731a, 0731b.*

---

## 9. Decisions we reversed

The reversals are better calibration than the decisions. Every row is something
we were confident about.

| Decision | What changed our mind |
|---|---|
| Build a locked-down Scholar fetching helper | Priced the asset honestly: referee reports, not crown jewels |
| Keep Google access narrow to stay safe | Narrow bought *no* safety — same addresses serve Drive and Forms — only maintenance |
| Remove GitHub credentials entirely | Overreaction to one accidental push; upstream forwards them on purpose so agents can open PRs |
| Point R at live CRAN to dodge the CDN problem | The "one line" fix sells reproducibility and bills you later |
| Bake the slow packages back into the image | Those are precisely the compiles that made the image painful to build |
| Store only formulas, not full transcripts | The property that mattered was *unreachable*, not *minimal* |
| Reorganise projects into nested folders | A comma is a word boundary to shell completion; a slash isn't |
| Ship project templates | They were real work instances, not templates — a promise the docs couldn't cash |
| Pin the Ubuntu base to a fixed dated build | Kept floating instead |
| Support Windows | Assessed and declined outright |
| Fall back from Scholar to OpenAlex automatically | Silently switching source yields a list you can't attribute |

---

## 10. What we'd put to the room

1. **GitHub credentials (§3b).** Is a written rule an acceptable guardrail on
   the one capability that publishes irreversibly? Or should we forward a narrow,
   repository-scoped token instead of our whole identity?
2. **The Python reproducibility gap (§6).** R is pinned, Python isn't. Does that
   matter for the work we do, or is it fine?
3. **Where's the line on data?** The posture is "don't put anything in here whose
   leak would be a real problem" — a judgement made per-project by a human, which
   works right up until it doesn't. WRDS is licensed data. Does that change the
   answer?
4. **Is the maintenance worth it?** Honest question. This is a few months of
   evenings. The counterfactual is approving every command by hand: slower, but
   zero maintenance.

### Still open

- Close the two inherited network doors, outbound SSH especially (§2).
- Flip the ignore file to hide-everything-by-default now the repo is public;
  today a new project folder would be published by one careless `git add`.
- Write down the credential tension in §4 rather than accepting it quietly.
- Decide whether the telemetry and error-reporting sites stay on the allowed
  list, and say so either way.
- Run a real WRDS query in the rebuilt container — the drivers load and the host
  is reachable, but nobody has logged in since the Ubuntu move.
