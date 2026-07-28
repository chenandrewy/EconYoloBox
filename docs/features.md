# Sandbox Features

1. **One-command project opening (`.host/`)** — source `devcontainer.zsh` in your
   `~/.zshrc` and any project folder is one command away: `dccode [dir]` walks up
   from any subfolder to the enclosing devcontainer and opens that exact
   subfolder in VS Code inside the container; `dce [dir]` does the same but drops
   you into an in-container zsh. No manual "Reopen in Container" and no
   navigating after attach. The toolkit takes no configuration and names no
   personal paths, so it works against any repo with a devcontainer and ports
   across machines unchanged.

2. **Self-naming Claude sessions (`cchat-yolo`)** — inside the container,
   `cchat-yolo` starts Claude always under `--remote-control`, deriving the
   session name from the working directory and numbering it
   (`Live,Risk-vs-Writing#1`), so `dce <dir>` then `cchat-yolo` is the whole
   workflow and every session is identifiable without being named by hand.
   Permissions are skipped in the container, where the firewall is the blast
   radius. Because every session is remote-controlled, host-side tooling can
   list them all across running containers and terminate them in one command.

3. **Ready-to-use analysis stacks** — everything you need to do economics
   research: a full Python venv and R site-library installed by one script
   (`install-packages.sh`) into version-named persistent volumes, so rebuilds are
   fast and packages survive container recreation. R resolves against a dated
   P3M snapshot for reproducibility. Note that installs run *behind the
   firewall*, which makes them tricky: package hosts and their redirect mirrors
   must be allowlisted, and `docker build` having open network is no evidence a
   command works in a running container.

4. **Research document tooling (`.tools/`)** — PDF-to-Markdown OCR with figure
   extraction (`pdf2md.py`), PDF section-bookmark regeneration
   (`rebookmark.py`), two-way LyX/TeX sync with PDF rebuild (`sync-lyx.sh`), and
   citation lookup from Google Scholar (`cited_by.py`, fresh but scraped) and
   the OpenAlex API (`openalex_cited_by.py`, stable and structured).

5. **Fail-closed network firewall, tuned for econ research** — every container
   start arms a default-DROP iptables + ipset domain allowlist with its own
   dnsmasq; any setup failure drops all traffic rather than leaving the
   container open. The allowlist is curated for research: FRED, OpenAlex, arXiv,
   SSRN, WRDS, the Ken French data library, global-q, and JKP factor data are
   reachable alongside package registries and agent APIs — little else is.

6. **Keychain-based credential mounting (`.credentials/`)** — secrets stay in
   the host credential store (macOS Keychain / Windows Credential Manager),
   mapped by `credentials-map.json`, and exposed on demand through a read-only
   host-side file. They do not enter Docker metadata or the global container
   environment. The same resolver works inside and outside the container, so
   scripts never change.

7. **Cross-machine AI session sync (`ai-sesh`)** — Claude/Codex session stores
   are symlinked into the Dropbox-synced workspace per machine, so sessions
   follow you between desks; `sesh-push` installs another machine's sessions
   when you switch, with fork and wipe helpers.

8. **MathPanel VS Code extension** — a live transcript panel for the current
   Claude/Codex session with KaTeX-rendered math, auto-following whichever
   session wrote most recently. Deliberately hookless, serverless, and
   HTML-inert; auto-installed on container start.

9. **Agent config as code (`.devcontainer/agents/`)** — the single source of
   truth for Claude/Codex guidance and settings, re-seeded on every container
   start: guidance is symlinked so edits apply live; settings are copied so
   drift resets to canonical.

10. **Persistent agent auth** — named volumes keep Claude and Codex login state
    across rebuilds; VS Code forwards host Git credentials so in-container work
    can push branches and open PRs.

11. **Reproducible devcontainer** — pinned tool versions (git, delta, Claude
    Code, Codex CLI), curated VS Code extensions, and cache-conscious Dockerfile
    layering.
