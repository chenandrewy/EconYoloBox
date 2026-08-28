# The photo labeler is a second consumer of the planned container browser

Date: 2026-08-23 (NY)

This entry applies the browser decision already made in
[0731b,scholar-host-browser-test.md](archive/0731b,scholar-host-browser-test.md)
to `Live,Photo-Labeler`. It is confirmation and refinement, not a new decision
to add a browser.

0731b decided to build a real browser engine into the shared devcontainer for
two independent reasons: to investigate Scholar's client-versus-address
behavior, and to let agents inspect rendered interfaces such as ChatRender and
local development servers. A friendly photo-labeling interface is now another
strong consumer of that same container-level capability.

This note concerns the development environment only. It does not choose the
photo labeler's web framework or design the application. Distribution of the
finished tool to a non-technical Windows user is a separate subject and lives
in `Live,Photo-Labeler/windows-delivery.md`; where that constrains an
environment decision, it is noted below.

## Existing environment

The devcontainer already has most of the general web-development foundation:

- Node 24 and npm
- Python 3.12, with the persistent venv at `/opt/venv`
- ESLint and Prettier VS Code extensions
- VS Code Dev Containers port forwarding
- Ubuntu 24.04 on amd64 and arm64

It has no configured `forwardPorts` and contains no Chromium, Chrome, Firefox,
Playwright, Puppeteer, or Selenium.

## How the existing decision applies here

Use two browser paths for two different jobs:

1. **Use the host browser for normal interactive development.** Run the local
   server inside the container, bind it to `0.0.0.0`, and forward a stable port
   through VS Code. This preserves the native macOS browser, file picker, and
   clipboard without adding a Linux desktop.
2. **Use headless Playwright Chromium inside the container for inspection and
   tests.** It can load the application, upload fixtures, click through
   workflows, inspect accessibility labels, test keyboard use, capture
   screenshots, emulate smaller viewports, and report browser-console errors.

There is a second reason to invest in the Playwright suite specifically. The
same tests can later be run on a real Windows machine against a packaged build
of the application, which is the only way to observe the behavior that matters
to a Windows user. That is worth designing for before any tests exist: keep the
suite free of container assumptions, take the base URL and port from
configuration rather than hardcoding them, and refer to fixtures by relative
path rather than through `/workspace`. One suite, two targets.

This reinforces 0731b's headless-first direction. Firefox and WebKit can wait
for a demonstrated cross-browser need. Xvfb plus noVNC remains an escalation
path for Scholar's human-in-the-loop use or difficult headed debugging, rather
than a requirement for the photo labeler.

## Port forwarding

Once the application chooses a port, add a persistent forward and label it. A
FastAPI application on port 8000 would use:

```jsonc
"forwardPorts": [8000],
"portsAttributes": {
  "8000": {
    "label": "Photo Labeler",
    "onAutoForward": "openBrowser"
  }
}
```

Inside the container the application must listen on `0.0.0.0`, not only the
container's loopback interface, or the forwarded port has nothing to reach.
That is a requirement of this development setup, not a property of the
application: a copy running on someone else's machine should bind `127.0.0.1`,
which on Windows also avoids a Defender Firewall prompt. Make the bind address
a setting rather than hardcoding either value. The exact port should follow the
application choice, so this part of `devcontainer.json` should not be added
before then.

## Installation must follow this repo's Python seam

`Live,Photo-Labeler/vibe-code-sesh-01` is currently a pure-Python prototype. It
has no `package.json` or lockfile, so Playwright should not be introduced as an
npm development dependency merely to support it.

The existing seam from 0731b fits the repository:

- add the Python `playwright` package to `PY_PKGS` in
  `.devcontainer/install-packages.sh`, so the library lives in the persistent
  `/opt/venv` volume;
- install the matching Chromium binary and required Linux libraries at build
  time in `.devcontainer/Dockerfile`.

There is one necessary exception to the sandbox's deliberately unpinned Python
policy recorded in [0821c,lessons-learned.md](0821c,lessons-learned.md):
`playwright` must be pinned to an exact version. Each Playwright library release
expects a particular browser revision and fails when the expected executable is
absent. Therefore the version must appear in both places and move atomically:

```text
install-packages.sh:  playwright==X.Y.Z
Dockerfile:           ARG PLAYWRIGHT_VERSION=X.Y.Z
```

The exact version should be selected and verified when implementation is
authorized; this journal entry does not pretend an untested placeholder is a
finished configuration. Comments in both files should point to the other pin.

The Dockerfile installation must run as root because `--with-deps` invokes apt.
The browser should live in a shared path rather than root's cache, and the
non-root runtime user must be able to execute and update files Playwright needs.
A complete implementation will therefore need the existing Dockerfile's
explicit user transition and permissions, conceptually:

```dockerfile
USER root
ARG PLAYWRIGHT_VERSION=X.Y.Z
ENV PLAYWRIGHT_BROWSERS_PATH=/ms-playwright
RUN npx -y playwright@${PLAYWRIGHT_VERSION} install --with-deps chromium && \
    chmod -R 0777 /ms-playwright
USER node
```

`X.Y.Z` above describes the coupling and is not a value to paste into a build.
The real edit must use a tested exact version. The downloaded browser is
architecture-specific, but Docker builds the image separately on each machine;
Playwright supports Ubuntu 24.04 Chromium on both amd64 and arm64.

## Preserve the two traps from 0731b

First, do not install Ubuntu's `chromium` apt package. On Ubuntu 24.04 it is a
transitional snap launcher, and snap does not provide a workable container
browser here. Playwright's own Chromium build avoids that trap.

Second, the browser artifact host is `cdn.playwright.dev`, which is absent from
`.devcontainer/init-firewall.sh`. The firewall is raised by
`postStartCommand`, so the browser should be downloaded during the image build,
when the build network is open. Adding a runtime firewall exception merely to
download a reproducible build artifact is unnecessary.

The remaining unresolved issue from 0731b must stay explicit:
`playwright install --with-deps chromium` asks apt for several dozen runtime
libraries. Their exact list and installed size should be obtained with the
Playwright dry-run option and reviewed before changing the image. This is a
rebuild plus new system packages and still requires explicit user
authorization.

## Browser state and storage

0731b also called for a named volume holding the browser profile, following the
existing `${devcontainerId}`-keyed volume pattern. That remains appropriate for
the persistent, human-used browser profile needed by the Scholar investigation.
Its target should be a dedicated path passed explicitly as Playwright's
`user_data_dir`; it should not silently capture every disposable test context.

Photo-labeler end-to-end tests should normally use isolated, throwaway browser
contexts. They do not need cookies or profile state to survive. The distinction
is:

- browser executable and Linux libraries: bake into the shared image;
- Python Playwright library: persistent per-devcontainer venv volume;
- human browser profile: persistent per-devcontainer named volume;
- automated test profiles: disposable.

This follows the image-versus-volume framework in
[0821d,image-vs-volume-storage.md](0821d,image-vs-volume-storage.md): immutable,
large, shared tooling belongs in the image; mutable state requiring isolation
belongs in a `${devcontainerId}`-keyed volume. Playwright's documentation gives
rough illustrative cache sizes of about 281 MB for Chromium, 187 MB for Firefox,
and 180 MB for WebKit. Linux dependencies and architecture change the actual
figure, so the implemented image should be measured rather than treating those
examples as local measurements. Installing only Chromium avoids multiplying
that cost.

## Runtime options and optional UI

Playwright recommends `--ipc=host` for Chromium in Docker to reduce shared-memory
crashes. If local tests show instability, it belongs in the existing `runArgs`
array in `.devcontainer/devcontainer.json`, alongside the current capability and
environment-file arguments. It should not be added speculatively.

A lightweight desktop and noVNC can expose a headed container browser on port
6080. That is useful for selector recording or a human solving a presented
Scholar challenge, but it adds another service, packages, memory use, and an
inferior clipboard/file-picker experience. The host browser plus headless
Playwright covers the photo-labeler workflow.

The Playwright VS Code extension is optional too. It improves test discovery but
is not required, and adding its publisher may require a new Gallery CDN entry in
the firewall allowlist.

## Application-level implications

The likely browser application should keep the existing Python labeling logic
behind a local server and use the browser as its interface. This supports local
previews and progress while preserving the current rule that only resized image
data is sent to OpenRouter. Web framework packages and frontend dependencies
should be declared inside `Live,Photo-Labeler`, not added globally to the shared
analysis stack.

Two constraints follow from the intent to distribute this to a Windows user,
and both bear on choices that would otherwise look purely local. Anything
requiring a Node runtime at execution time, or a build step that would have to
be reproduced on Windows, works against packaging the application as a single
self-contained executable; server-rendered HTML or a small committed static
bundle keeps the shipped artifact to one bundled interpreter. And the API key
cannot keep coming from `/workspace/.credentials`, which exists only in this
sandbox, so key entry becomes part of the interface and therefore part of the
tested surface.

Important end-to-end cases for Playwright will include:

- selecting or dropping several images
- selecting a ZIP archive
- HEIC success and missing-decoder failure messages
- preview orientation and transparency handling
- progress, cancellation, retry, and resume behavior
- editing generated titles, descriptions, and tags
- keyboard-only labeling and visible focus states
- export of JSONL, CSV, and the informative-filename ZIP
- explicit disclosure that resized photo pixels leave the machine
- entering and storing an API key through the interface

Several cases only fail on Windows and are therefore reserved for a run of the
same suite there:

- non-ASCII and long filenames, and backslash path handling
- the exported CSV opening correctly in Excel, which requires a UTF-8 BOM
- windowed operation with no console: errors must reach a log file beside the
  application rather than a terminal nobody is watching

Use synthetic or deliberately approved fixture images in automated tests; do
not put the personal Banff album into browser-test artifacts, screenshots, or
traces.

## Refined decision and open work

The browser itself is not a new photo-labeler-specific proposal. It is an
already-decided shared container investment with a second concrete consumer.
When implementation is explicitly authorized:

- dry-run and review the Chromium system dependency set and image-size cost;
- choose one tested Playwright version and pin it in both the Dockerfile and
  `install-packages.sh`;
- bake only the matching Chromium browser into the image with permissions for
  `node`;
- add the `${devcontainerId}`-scoped human-profile volume planned in 0731b;
- start headless-only and defer noVNC;
- add the photo labeler's forwarded port only after its server port is chosen.

No environment changes were made in this investigation. The rebuild, browser
download, and new apt libraries still require explicit user authorization.

## References

- [0731b: Host browser is clean while the tool is blocked](archive/0731b,scholar-host-browser-test.md)
- [0821c: Lessons from building the sandbox](0821c,lessons-learned.md)
- [0821d: Image vs volumes](0821d,image-vs-volume-storage.md)
- `Live,Photo-Labeler/windows-delivery.md` (packaging and distribution)
- [VS Code: Developing inside a Container](https://code.visualstudio.com/docs/devcontainers/containers)
- [Playwright: Installation](https://playwright.dev/docs/intro)
- [Playwright: Browsers](https://playwright.dev/docs/browsers)
- [Playwright: Docker](https://playwright.dev/docs/docker)
- [Playwright: Best Practices](https://playwright.dev/docs/best-practices)
