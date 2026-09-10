# Host setup

`.setup/` is host machine setup and maintenance, `.host/` is session navigation,
and `.devcontainer/` defines the container.

## TeX Live

From the repository root, on the host with Docker running:

```sh
bash .setup/texlive.sh
```

This downloads the full TeX Live 2026 scheme using upstream `install-tl` in a
temporary Ubuntu 24.04 container. It creates `texlive-2026-noble` on the selected
Docker daemon. Allow space for the full distribution. The repository must
still serve 2026; the script refuses a different year before installation.
The temporary builder includes `libfontconfig1`, required by XeTeX during
format generation. Setup checks all enabled formats, font maps, and small
pdfLaTeX and XeLaTeX compilations before reporting success.

The volume is shared across projects on that daemon and mounted read-only in
devcontainers. Its binaries must match the consumer architecture: native amd64
and arm64 are supported by the configuration, one architecture per volume.
Changing the Docker platform requires a matching installation. Opening a
project never downloads TeX.

After installation, rebuild/recreate the devcontainer for the mount and PATH
changes. If the new configuration is already running, run `tex-refresh` as
`node` in each consuming container. Reopen any already-running LyX before its
next export. The helper also runs during normal devcontainer startup, after
the firewall step; missing TeX produces a warning.

The script only installs into an empty volume. It does not update, overwrite,
or delete an existing installation. Do not run concurrent installers. Treat
the successful installation as fixed; updates are separate explicit work and
must happen with TeX/LyX work stopped in every consumer.

If installation fails, its tree and `install.log` remain in the volume. Read
the log without changing the installation:

```sh
docker run --rm --mount type=volume,source=texlive-2026-noble,target=/texlive,readonly \
  ubuntu:24.04 cat /texlive/install.log
```

Failures before installation starts may only have terminal output. Inspect
that output before deciding on manual repair or explicit volume recreation;
rerunning against a nonempty volume intentionally refuses. No automatic
recovery or completion marker is provided.

Before adopting the rebuilt image, test PDF compilation with biber, a LyX
export, and latexindent as `node`, with fresh writable user caches and the TeX
volume read-only. Also check startup with an empty volume. Keep the previous
image until validation passes; pruning is separate work.

For a repeatable check against a separately built image, from the repository root:

```sh
docker build --build-arg TZ=America/New_York -t texlive-check .devcontainer
docker run --rm --cap-add=NET_ADMIN --cap-add=NET_RAW \
  --mount type=volume,source=texlive-2026-noble,target=/usr/local/texlive,readonly \
  --mount "type=bind,source=$PWD/.devcontainer/tests,target=/checks,readonly" \
  texlive-check bash -c 'sudo /usr/local/bin/init-firewall.sh && bash /checks/test-texlive.sh'
```

This uses a fresh container home and checks PDF/bibliography output, LyX
refresh and export, latexindent, and read-only/writable paths. Its fixtures and
logs are in `/tmp/texlive-check` inside the test container; omit `--rm` if you
need to retain them for diagnosis. Run it only after installation has finished.

Installation reference: [upstream installer manual](https://tug.org/texlive/doc/install-tl.html).
