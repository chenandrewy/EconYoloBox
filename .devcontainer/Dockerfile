FROM node:20

ARG TZ
ENV TZ="$TZ"

ARG GIT_VERSION=2.49.0
ARG CLAUDE_CODE_VERSION=latest
ARG CODEX_CLI_VERSION=latest
ARG PANDOC_VERSION=3.9.0.2
ARG PANDOC_CROSSREF_VERSION=v0.3.23a
ARG LYX_VERSION=2.4.3-1~bpo12+1

# Install core system tools and build prerequisites.
RUN apt-get update && apt-get install -y --no-install-recommends \
  less \
  git \
  libexpat1-dev \
  procps \
  sudo \
  fzf \
  zsh \
  man-db \
  unzip \
  gnupg2 \
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
  # Some R packages use native builds that expect cmake/pkg-config toolchains.
  cmake \
  pkg-config \
  xz-utils \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# Pin Git to the host workflow version so worktree behavior matches outside the container.
RUN wget -O /tmp/git.tar.gz "https://mirrors.edge.kernel.org/pub/software/scm/git/git-${GIT_VERSION}.tar.gz" && \
  tar -C /tmp -xzf /tmp/git.tar.gz && \
  make -C "/tmp/git-${GIT_VERSION}" prefix=/usr/local NO_TCLTK=YesPlease NO_GETTEXT=YesPlease -j"$(nproc)" all && \
  make -C "/tmp/git-${GIT_VERSION}" prefix=/usr/local NO_TCLTK=YesPlease NO_GETTEXT=YesPlease install && \
  rm -rf /tmp/git.tar.gz "/tmp/git-${GIT_VERSION}"

# R is pinned via Posit r-builds below, not apt; R_VERSION and the dated P3M
# snapshot are the two knobs that fully determine the R stack on every machine.
# gfortran replaces the compiler r-base-dev used to pull in, for source builds.
ARG R_VERSION=4.5.3
ARG CRAN_SNAPSHOT=https://packagemanager.posit.co/cran/__linux__/bookworm/2026-07-15

# Install heavy workflow toolchains after Git so later workflow changes do not
# force a Git rebuild.
RUN apt-get update && apt-get install -y --no-install-recommends \
  python3 \
  python3-dev \
  python3-pip \
  python3-venv \
  gfortran \
  libcurl4-openssl-dev \
  libssl-dev \
  libxml2-dev \
  libpq-dev \
  libsecret-1-dev \
  libfreetype6-dev \
  libharfbuzz-dev \
  libfribidi-dev \
  libuv1-dev \
  texlive-full \
  biber \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# Pin R itself from Posit r-builds (immutable artifacts, amd64+arm64), installed
# to /opt/R/<version> outside apt. Debian's frozen r-base (4.2.2) is too old for
# current CRAN packages.
RUN ARCH=$(dpkg --print-architecture) && \
  wget -O /tmp/r.deb "https://cdn.posit.co/r/debian-12/pkgs/r-${R_VERSION}_1_${ARCH}.deb" && \
  apt-get update && apt-get install -y --no-install-recommends /tmp/r.deb && \
  ln -sf /opt/R/${R_VERSION}/bin/R /usr/local/bin/R && \
  ln -sf /opt/R/${R_VERSION}/bin/Rscript /usr/local/bin/Rscript && \
  rm /tmp/r.deb && apt-get clean && rm -rf /var/lib/apt/lists/*

# Site-wide defaults for every Rscript below and at runtime: the dated P3M
# snapshot pins package versions; the R-version-bearing user agent makes P3M
# serve pre-built bookworm binaries (without it, it silently falls back to
# source); Ncpus parallelizes across packages for source fallbacks.
RUN cat >> /opt/R/${R_VERSION}/lib/R/etc/Rprofile.site <<EOF
options(repos = c(CRAN = "${CRAN_SNAPSHOT}"))
options(HTTPUserAgent = sprintf("R/%s R (%s)", getRversion(),
  paste(getRversion(), R.version\$platform, R.version\$arch, R.version\$os)))
options(Ncpus = 2)
EOF

# Ensure default node user has access to /usr/local/share
RUN mkdir -p /usr/local/share/npm-global && \
  chown -R node:node /usr/local/share

# Git defaults
RUN git config --system merge.ff false && \
  git config --system pager.branch cat && \
  git config --system core.editor nano

ARG USERNAME=node

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

# Pin LyX to the Debian 12 backports build so export/import behavior stays
# stable even if the base `node:20` tag changes over time.
RUN apt-get update && apt-get install -y --no-install-recommends \
  ca-certificates \
  rsync \
  && echo "deb http://deb.debian.org/debian bookworm-backports main" > /etc/apt/sources.list.d/bookworm-backports.list \
  && apt-get update \
  && apt-get install -y --no-install-recommends \
  lyx=${LYX_VERSION} \
  lyx-common=${LYX_VERSION} \
  && apt-mark hold lyx lyx-common \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

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

# Install AI CLIs
RUN npm install -g \
  @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION} \
  @openai/codex@${CODEX_CLI_VERSION}

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

# Copy and set up firewall script
COPY init-firewall.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/init-firewall.sh && \
  echo "node ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh" > /etc/sudoers.d/node-firewall && \
  chmod 0440 /etc/sudoers.d/node-firewall
USER node
