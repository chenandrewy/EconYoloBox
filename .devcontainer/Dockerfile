FROM node:20

ARG TZ
ENV TZ="$TZ"

ARG GIT_VERSION=2.49.0
ARG CLAUDE_CODE_VERSION=latest
ARG CODEX_CLI_VERSION=latest
ARG PANDOC_VERSION=3.9.0.2
ARG PANDOC_CROSSREF_VERSION=v0.3.23a

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
  aggregate \
  jq \
  nano \
  vim \
  ripgrep \
  fd-find \
  bat \
  poppler-utils \
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
  python3-pip \
  python3-venv \
  r-base \
  r-base-dev \
  libcurl4-openssl-dev \
  libssl-dev \
  libxml2-dev \
  libpq-dev \
  libsecret-1-dev \
  libuv1-dev \
  texlive-latex-recommended \
  texlive-latex-extra \
  texlive-fonts-recommended \
  texlive-bibtex-extra \
  cm-super \
  biber \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# Ensure default node user has access to /usr/local/share
RUN mkdir -p /usr/local/share/npm-global && \
  chown -R node:node /usr/local/share

# Git defaults
RUN git config --system merge.ff false

ARG USERNAME=node

# Persist bash history.
RUN SNIPPET="export PROMPT_COMMAND='history -a' && export HISTFILE=/commandhistory/.bash_history" \
  && mkdir /commandhistory \
  && touch /commandhistory/.bash_history \
  && chown -R $USERNAME /commandhistory

# Set `DEVCONTAINER` environment variable to help with orientation
ENV DEVCONTAINER=true

WORKDIR /workspace

# Set up Python virtual environment with data analysis packages
RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
RUN pip install --no-cache-dir \
  numpy \
  pandas \
  matplotlib \
  statsmodels \
  scipy \
  linearmodels \
  scikit-learn \
  openpyxl \
  wrds \
  mistralai \
  polars \
  sas7bdat \
  beautifulsoup4 \
  lxml \
  pyarrow \
  pyfixest
RUN chown -R node:node /opt/venv

# Keep libuv headers available so future R packages such as fs compile without extra debugging.
# Install core R data and WRDS tooling.
RUN Rscript -e "install.packages(c('DBI','RPostgres','dplyr','data.table','keyring'), repos='https://cloud.r-project.org')"

# Allow non-root user to install R packages at runtime.
RUN chmod -R a+w /usr/local/lib/R/site-library

ARG GIT_DELTA_VERSION=0.18.2
RUN ARCH=$(dpkg --print-architecture) && \
  wget "https://github.com/dandavison/delta/releases/download/${GIT_DELTA_VERSION}/git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" && \
  sudo dpkg -i "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" && \
  rm "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb"

# Install lmodern explicitly so kpsewhich resolves lmodern.sty in the container.
RUN apt-get update && apt-get install -y --no-install-recommends lmodern \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# Create node-owned workspace and config directories before switching users.
# Pre-creating the gh config path avoids Docker creating it as root during volume mount.
RUN mkdir -p /workspace /home/node/.claude /home/node/.codex /home/node/.config/gh && \
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
  -a "source /workspace/.devcontainer/aliases.sh" \
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

# xz-utils is needed to extract the pandoc-crossref .tar.xz archive.
USER root
RUN apt-get update && apt-get install -y --no-install-recommends xz-utils \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

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

# Copy and set up firewall script
COPY init-firewall.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/init-firewall.sh && \
  echo "node ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh" > /etc/sudoers.d/node-firewall && \
  chmod 0440 /etc/sudoers.d/node-firewall
USER node
