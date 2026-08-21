FROM ubuntu:24.04

ARG TZ
ENV TZ="$TZ"

ARG GIT_VERSION=2.49.0
ARG NODE_MAJOR=24
ARG NODE_VERSION=24.18.0-1nodesource1
ARG PANDOC_VERSION=3.9.0.2
ARG PANDOC_CROSSREF_VERSION=v0.3.23a
ARG LYX_VERSION=2.4.5
ARG LYX_SHA256=4667f2759ae6070198c6f25606950a6374fd54863ac3dbf4fdcc05d01fa4bff4

ARG USERNAME=node

# ubuntu:24.04 ships a default `ubuntu` user at uid 1000, which collides with
# the `node` user this workspace is built around. Delete it and take the uid:
# /home/node/... is hardcoded in devcontainer.json, the ai-sesh tooling, and the
# agent config paths, so renaming to `ubuntu` instead would be the larger edit.
# (userdel warns about the absent mail spool and still exits 0.)
RUN userdel -r ubuntu && \
  groupadd --gid 1000 ${USERNAME} && \
  useradd --uid 1000 --gid 1000 --create-home --shell /bin/bash ${USERNAME}

# ubuntu:24.04 ships /etc/dpkg/dpkg.cfg.d/excludes, which path-excludes
# /usr/share/doc/* to slim the image. Debian's fzf package ships its shell
# integration (key-bindings.zsh, completion.zsh) under that path, so those files
# never get unpacked and every zsh startup errors on the `source` lines added by
# zsh-in-docker below. node:20 had no such exclude, hence the regression.
# dpkg reads dpkg.cfg.d in alphabetical order and last match wins, so this
# fragment must sort after `excludes` -- and must exist before fzf is unpacked.
RUN printf 'path-include=/usr/share/doc/fzf/examples/*\n' \
  > /etc/dpkg/dpkg.cfg.d/zz-keep-fzf-examples

# Install core system tools and build prerequisites.
# wget/curl/ca-certificates/gnupg2 are explicit here: the old `node:20` base
# provided them, `ubuntu:24.04` does not, and every download below needs them.
RUN apt-get update && apt-get install -y --no-install-recommends \
  wget \
  curl \
  ca-certificates \
  gnupg2 \
  # openssh-client came free with node:20 and does not exist on a bare Ubuntu.
  # Without it every git@github.com:/ssh:// remote fails. init-firewall.sh
  # deliberately ACCEPTs outbound tcp/22, so SSH is expected to work here.
  openssh-client \
  # rsync was installed by the old LyX layer, which this rewrite replaced.
  # node:20 never carried it; the previous Dockerfile added it on purpose.
  rsync \
  less \
  git \
  libexpat1-dev \
  procps \
  # GNU time, i.e. /usr/bin/time. zsh's builtin `time` only applies to commands
  # typed at an interactive prompt, so it gives nothing inside Rscript, a
  # python3 subprocess chain, or anything run via `sh -c`. `/usr/bin/time -v`
  # works anywhere and reports max RSS, page faults, and I/O in one block -
  # what you want when a pandas/polars job or an R source build gets OOM-killed.
  # (The builtin's TIMEFMT %M is also mislabelled: it prints MB, not KB.)
  time \
  sudo \
  fzf \
  zsh \
  man-db \
  unzip \
  gh \
  bubblewrap \
  iptables \
  ipset \
  iproute2 \
  dnsutils \
  # dnsmasq-base: resolve-time allowlisting of CDN-fronted hosts (init-firewall.sh)
  dnsmasq-base \
  aggregate \
  jq \
  nano \
  vim \
  ripgrep \
  fd-find \
  bat \
  shellcheck \
  poppler-utils \
  build-essential \
  zlib1g-dev \
  # libssl-dev and libcurl4-openssl-dev must be HERE, above the Git build, not
  # with the other -dev libraries further down: node:20 happened to ship them,
  # ubuntu:24.04 does not. Without libssl-dev Git fails to compile at all;
  # without libcurl4-openssl-dev it compiles fine but omits git-remote-http, so
  # the breakage would surface much later as `git clone https://...` failing
  # with "Unable to find remote helper for 'https'".
  libssl-dev \
  libcurl4-openssl-dev \
  # Some R packages use native builds that expect cmake/pkg-config toolchains.
  cmake \
  pkg-config \
  xz-utils \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# Node is ours to pin now that the base image no longer supplies it. NodeSource
# publishes arm64 for the `nodistro` suite, and keeps every past release in the
# major, so an exact version pin is stable rather than a build-breaking bet.
#
# 24, not the 20 the old base carried: node:20 was already past end of life
# (2026-04-30) when this image was built on it. The migration did not cause
# that, it just moved the pin somewhere we control, which made it fixable.
# 24 is LTS through 2028-04-30.
RUN mkdir -p /etc/apt/keyrings && \
  curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
  | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg && \
  echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_MAJOR}.x nodistro main" \
  > /etc/apt/sources.list.d/nodesource.list && \
  apt-get update && apt-get install -y --no-install-recommends \
  nodejs=${NODE_VERSION} \
  && apt-mark hold nodejs \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# Pin Git to the host workflow version so worktree behavior matches outside the container.
RUN wget -O /tmp/git.tar.gz "https://mirrors.edge.kernel.org/pub/software/scm/git/git-${GIT_VERSION}.tar.gz" && \
  tar -C /tmp -xzf /tmp/git.tar.gz && \
  make -C "/tmp/git-${GIT_VERSION}" prefix=/usr/local NO_TCLTK=YesPlease NO_GETTEXT=YesPlease -j"$(nproc)" all && \
  make -C "/tmp/git-${GIT_VERSION}" prefix=/usr/local NO_TCLTK=YesPlease NO_GETTEXT=YesPlease install && \
  rm -rf /tmp/git.tar.gz "/tmp/git-${GIT_VERSION}"

# Install heavy workflow toolchains after Git so later workflow changes do not
# force a Git rebuild.
RUN apt-get update && apt-get install -y --no-install-recommends \
  python3 \
  python3-dev \
  python3-pip \
  python3-venv \
  gfortran \
  # libcurl4-openssl-dev / libssl-dev are installed above, before the Git build.
  libxml2-dev \
  libpq-dev \
  libsecret-1-dev \
  # noble renamed libfreetype6-dev; the old name is now only a Provides:.
  libfreetype-dev \
  libharfbuzz-dev \
  libfribidi-dev \
  libuv1-dev \
  texlive-full \
  biber \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# Ensure default node user has access to /usr/local/share.
# npm-global is now a volume mountpoint, which makes this load-bearing beyond
# the chown: Docker seeds a fresh named volume from the image directory at that
# path, ownership included. The directory must therefore exist and be
# node-owned here, or the new volume comes up root-owned and `npm install -g`
# fails as node with EACCES.
# Must run BEFORE the LyX build below, not after: `make install` drops ~40MB of
# LyX data files into /usr/local/share/lyx, and a recursive chown crossing them
# would rewrite every one of those inodes into a new layer for no benefit.
RUN mkdir -p /usr/local/share/npm-global && \
  chown -R node:node /usr/local/share

# LyX built from upstream source, replacing the Debian 12 backports pin this
# image used to carry. Noble's archive LyX is 2.4.0~RC3 - a release candidate -
# and Ubuntu has no backports pocket offering a stable 2.4, so there is no
# apt equivalent of the old pin. Building 2.4.5 also makes the version an
# explicit knob rather than a property of whichever suite we happen to track.
#
# Qt5 (not Qt6) to match what the Debian build linked against, so export/import
# behavior stays comparable. The -dev packages stay in the image: they pull the
# Qt runtime LyX links against, and purging them cleanly would mean naming
# noble's t64-renamed runtime libs by hand for no meaningful size win.
#
# ftp.lyx.org is a CNAME to ftp.lip6.fr whose certificate covers only the
# latter, so fetch by the mirror's own name and let the sha256 pin - not the
# hostname - be what guarantees the artifact.
#
# Placed BEFORE the R block on purpose: CRAN_SNAPSHOT below is bumped far more
# often than LYX_VERSION, and a layer here would otherwise turn every snapshot
# bump into a full LyX recompile.
RUN apt-get update && apt-get install -y --no-install-recommends \
  qtbase5-dev \
  qtbase5-dev-tools \
  qttools5-dev-tools \
  libqt5svg5-dev \
  libmagic-dev \
  libenchant-2-dev \
  && wget -O /tmp/lyx.tar.xz "https://ftp.lip6.fr/pub/lyx/stable/2.4.x/lyx-${LYX_VERSION}.tar.xz" && \
  echo "${LYX_SHA256}  /tmp/lyx.tar.xz" | sha256sum -c - && \
  tar -C /tmp -xJf /tmp/lyx.tar.xz && \
  cd "/tmp/lyx-${LYX_VERSION}" && \
  ./configure --prefix=/usr/local --enable-build-type=release --disable-static && \
  make -j"$(nproc)" && \
  make install-strip && \
  cd / && rm -rf /tmp/lyx.tar.xz "/tmp/lyx-${LYX_VERSION}" && \
  apt-get clean && rm -rf /var/lib/apt/lists/*

# R is pinned via Posit r-builds below, not apt; R_VERSION and the dated P3M
# snapshot are the two knobs that fully determine the R stack on every machine.
# gfortran replaces the compiler r-base-dev used to pull in, for source builds.
ARG R_VERSION=4.5.3
ARG CRAN_SNAPSHOT=https://packagemanager.posit.co/cran/__linux__/noble/2026-07-15

# Pin R itself from Posit r-builds (immutable artifacts, amd64+arm64), installed
# to /opt/R/<version> outside apt. Ubuntu's archive r-base is too old for
# current CRAN packages.
RUN ARCH=$(dpkg --print-architecture) && \
  wget -O /tmp/r.deb "https://cdn.posit.co/r/ubuntu-2404/pkgs/r-${R_VERSION}_1_${ARCH}.deb" && \
  apt-get update && apt-get install -y --no-install-recommends /tmp/r.deb && \
  ln -sf /opt/R/${R_VERSION}/bin/R /usr/local/bin/R && \
  ln -sf /opt/R/${R_VERSION}/bin/Rscript /usr/local/bin/Rscript && \
  rm /tmp/r.deb && apt-get clean && rm -rf /var/lib/apt/lists/*

# Site-wide defaults for every Rscript below and at runtime: the dated P3M
# snapshot pins package versions; the R-version-bearing user agent makes P3M
# serve pre-built noble binaries (without it, it silently falls back to
# source); Ncpus parallelizes across packages for source fallbacks.
#
# This is the payoff of the Ubuntu base: P3M publishes arm64 binaries for noble
# but not for bookworm, so on Apple Silicon the whole stack - arrow included,
# with libarrow already inside - now arrives prebuilt instead of compiling.
RUN cat >> /opt/R/${R_VERSION}/lib/R/etc/Rprofile.site <<EOF
options(repos = c(CRAN = "${CRAN_SNAPSHOT}"))
options(HTTPUserAgent = sprintf("R/%s R (%s)", getRversion(),
  paste(getRversion(), R.version\$platform, R.version\$arch, R.version\$os)))
options(Ncpus = 2)
EOF

# Git defaults
RUN git config --system merge.ff false && \
  git config --system pager.branch cat && \
  git config --system core.editor nano

# Persist bash history.
RUN SNIPPET="export PROMPT_COMMAND='history -a' && export HISTFILE=/commandhistory/.bash_history" \
  && mkdir /commandhistory \
  && touch /commandhistory/.bash_history \
  && chown -R $USERNAME /commandhistory

# Set `DEVCONTAINER` environment variable to help with orientation
ENV DEVCONTAINER=true

WORKDIR /workspace

# The Python and R analysis stacks are NOT baked into the image. They live in
# .devcontainer/install-packages.sh, run on demand inside a started container.
# Rationale: baked-in layers meant every package change cost a full rebuild, and
# a broken package was unrecoverable without one. Version reproducibility is
# unaffected (the dated P3M snapshot still pins R; pip still resolves PyPI) -
# only *state* becomes opt-in.
#
# What stays here is what needs root or the build's open network: the system
# -dev libraries above, R itself, the venv, and the write permissions below.

# Empty venv, owned by node so the install script can populate it at runtime.
# noble's python3 is 3.12, so the venv volume name in devcontainer.json carries
# py3.12 - a 3.11 volume from the bookworm image must not be mounted here.
RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
RUN chown -R node:node /opt/venv

# Allow non-root user to install R packages at runtime - this is now the normal
# path for the whole R stack, not just late additions. Packages land in
# site-library (R's default first library whenever the directory exists), which
# devcontainer.json mounts as a named volume so compiles survive container
# recreation. The empty volume inherits this directory's node ownership on
# first mount (Docker copy-on-first-use), so no chown at container setup.
RUN chmod -R a+w /opt/R/${R_VERSION}/lib/R/library && \
  mkdir -p /opt/R/${R_VERSION}/lib/R/site-library && \
  chown node:node /opt/R/${R_VERSION}/lib/R/site-library

ARG GIT_DELTA_VERSION=0.18.2
RUN ARCH=$(dpkg --print-architecture) && \
  wget "https://github.com/dandavison/delta/releases/download/${GIT_DELTA_VERSION}/git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" && \
  sudo dpkg -i "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" && \
  rm "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb"

# Create node-owned workspace and config directories before switching users.
RUN mkdir -p /workspace /home/node/.claude /home/node/.codex /home/node/.config && \
  chown -R node:node /workspace /home/node/.claude /home/node/.codex /home/node/.config

# Set up non-root user
USER node

# Install global packages
ENV NPM_CONFIG_PREFIX=/usr/local/share/npm-global
ENV PATH=$PATH:/usr/local/share/npm-global/bin

# Set the default shell to zsh rather than sh
ENV SHELL=/bin/zsh

# Set the default editor and visual
ENV EDITOR nano
ENV VISUAL nano

# Default powerline10k theme
ARG ZSH_IN_DOCKER_VERSION=1.2.0
RUN sh -c "$(wget -O- https://github.com/deluan/zsh-in-docker/releases/download/v${ZSH_IN_DOCKER_VERSION}/zsh-in-docker.sh)" -- \
  -p git \
  -p fzf \
  -a "source /usr/share/doc/fzf/examples/key-bindings.zsh" \
  -a "source /usr/share/doc/fzf/examples/completion.zsh" \
  -a "export PROMPT_COMMAND='history -a' && export HISTFILE=/commandhistory/.bash_history" \
  -a "source /workspace/.devcontainer/shellrc.sh" \
  -x

# zsh-in-docker defaults to en_US.UTF-8, which is not generated in this image.
# Pin to C.UTF-8 (available by default) to avoid locale warnings in child shells.
RUN sed -i "s/^export LANG=.*/export LANG='C.UTF-8'/" /home/node/.zshrc && \
  sed -i "s/^export LANGUAGE=.*/export LANGUAGE='C.UTF-8'/" /home/node/.zshrc && \
  sed -i "s/^export LC_ALL=.*/export LC_ALL='C.UTF-8'/" /home/node/.zshrc

# The Claude Code and Codex CLIs are NOT baked into the image, for the same
# reason as the analysis stacks above: a baked `npm install -g ...@latest` layer
# pins itself to whenever it was first cached, so rebuilds kept serving whatever
# was current on that day. They are installed at runtime by
# install-packages.sh into NPM_CONFIG_PREFIX, which is a volume - so an update
# made in a running container survives rebuilds instead of being reverted by
# them. A fresh volume starts empty; shellrc.sh says so, and test-agent-policy.sh
# skips rather than fails when a CLI is absent.

USER root

# Install matching upstream pandoc and pandoc-crossref binaries.
RUN ARCH=$(dpkg --print-architecture) && \
  case "$ARCH" in \
    amd64) PANDOC_ARCH=amd64; CROSSREF_ARCH=X64 ;; \
    arm64) PANDOC_ARCH=arm64; CROSSREF_ARCH=ARM64 ;; \
    *) echo "Unsupported architecture: $ARCH" >&2; exit 1 ;; \
  esac && \
  wget -O /tmp/pandoc.tar.gz "https://github.com/jgm/pandoc/releases/download/${PANDOC_VERSION}/pandoc-${PANDOC_VERSION}-linux-${PANDOC_ARCH}.tar.gz" && \
  tar -C /tmp -xzf /tmp/pandoc.tar.gz && \
  install -m 0755 /tmp/pandoc-${PANDOC_VERSION}/bin/pandoc /usr/local/bin/pandoc && \
  wget -O /tmp/pandoc-crossref.tar.xz "https://github.com/lierdakil/pandoc-crossref/releases/download/${PANDOC_CROSSREF_VERSION}/pandoc-crossref-Linux-${CROSSREF_ARCH}.tar.xz" && \
  tar -C /tmp -xJf /tmp/pandoc-crossref.tar.xz && \
  install -m 0755 /tmp/pandoc-crossref /usr/local/bin/pandoc-crossref && \
  rm -rf /tmp/pandoc.tar.gz /tmp/pandoc-crossref.tar.xz /tmp/pandoc-${PANDOC_VERSION} /tmp/pandoc-crossref

# latexindent is installed by TeX Live, but --no-install-recommends can omit
# Perl modules it needs at runtime.
RUN apt-get update && apt-get install -y --no-install-recommends \
  libyaml-tiny-perl \
  libfile-homedir-perl \
  liblog-log4perl-perl \
  liblog-dispatch-perl \
  libunicode-linebreak-perl \
  librsvg2-bin \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# Headers for the R graphics-device stack that install-packages.sh compiles at
# runtime: systemfonts needs fontconfig, and ragg needs jpeg and tiff on top of
# it. (libpng-dev, ragg's fourth requirement, already arrives as a dependency.)
#
# Their natural home is the freetype/harfbuzz/fribidi group far above, but that
# block also carries texlive-full and sits above the LyX source build, so
# touching it costs a ~30-minute rebuild. Nothing in this Dockerfile links
# against these - only runtime R installs do - so a late layer is equivalent.
# Fold them upward whenever something else forces a full rebuild anyway.
RUN apt-get update && apt-get install -y --no-install-recommends \
  libfontconfig-dev \
  libjpeg-dev \
  libtiff-dev \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# Detect converters (latex, pdflatex, pandoc, ...) once, system-wide. LyX would
# otherwise run this itself on first export, per user, writing into ~/.lyx -
# slower, noisier, and lost whenever the home volume is recreated. Runs here,
# last, because the scan only finds tools already installed: TeX Live above and
# pandoc immediately preceding it.
RUN cd /usr/local/share/lyx && python3 ./configure.py

# Copy and set up firewall script
COPY init-firewall.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/init-firewall.sh && \
  echo "node ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh" > /etc/sudoers.d/node-firewall && \
  chmod 0440 /etc/sudoers.d/node-firewall

# Keep frequently edited, baked-in agent policy at the end of the Dockerfile so
# changing it does not invalidate the expensive installation layers above.

# Claude Code policy. `disableClaudeAiConnectors` has any-source-true semantics,
# so user- and project-level settings cannot override this file. The companion
# denylist covers the gap it leaves: connectors passed via `--mcp-config`.
COPY agents/SANDBOX-claude-managed-settings.json /etc/claude-code/managed-settings.json

# Codex requirements are admin-enforced and outrank user config, profiles, and
# CLI --config / --enable overrides. The ordinary ~/.codex/config.toml remains
# node-owned so Codex can persist user preferences.
COPY agents/SANDBOX-codex-requirements.toml /etc/codex/requirements.toml

# COPY already lands these root-owned, since this stage runs as root; the chmod
# is what makes them read-only to `node`.
RUN chmod 0444 /etc/claude-code/managed-settings.json /etc/codex/requirements.toml

# Policy verification, run manually or from postStartCommand. Copied rather than
# invoked from /workspace so a check of the policy is not itself node-writable.
COPY test-agent-policy.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/test-agent-policy.sh

# Debian installs fd as fdfind to avoid a package-name collision. Provide the
# conventional command name after all expensive build layers are complete.
RUN ln -s /usr/bin/fdfind /usr/local/bin/fd

USER node
