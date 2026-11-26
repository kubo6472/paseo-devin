ARG BASE_IMAGE=ghcr.io/getpaseo/paseo:latest
FROM ${BASE_IMAGE}

USER root

# Devin CLI. The installer puts the binary in $HOME/.local/bin, which is
# /root/.local/bin during the build. The `paseo` user can't use that, so we
# copy it to /usr/local/bin. The `|| true` is deliberate: the installer can
# exit non-zero after a successful install.
RUN set -eux; \
    curl -fsSL https://cli.devin.ai/install.sh -o /tmp/install.sh; \
    bash /tmp/install.sh </dev/null || true; \
    bin="$(command -v devin || ls "$HOME/.local/bin/devin" /root/.local/bin/devin 2>/dev/null | head -n1)"; \
    test -n "$bin"; \
    install -m 0755 "$(readlink -f "$bin")" /usr/local/bin/devin; \
    devin --version

# GitHub CLI.
ARG GH_VERSION=2.104.0
RUN set -eux; \
    arch="$(uname -m)"; \
    case "$arch" in x86_64) gharch=amd64 ;; aarch64) gharch=arm64 ;; *) echo "unsupported arch: $arch"; exit 1 ;; esac; \
    curl -fsSL "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_${gharch}.tar.gz" -o /tmp/gh.tar.gz; \
    tar -xzf /tmp/gh.tar.gz -C /tmp; \
    install -m 0755 "/tmp/gh_${GH_VERSION}_linux_${gharch}/bin/gh" /usr/local/bin/gh; \
    rm -rf /tmp/gh.tar.gz "/tmp/gh_${GH_VERSION}_linux_${gharch}"; \
    gh --version

# Docker CLI + compose plugin, for talking to the host daemon via the
# mounted socket (see docker-compose.yml). Client only, no dockerd.
RUN set -eux; \
    install -m 0755 -d /etc/apt/keyrings; \
    curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc; \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
        > /etc/apt/sources.list.d/docker.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        docker-ce-cli docker-compose-plugin jq \
        build-essential make \
        python3 python3-pip python3-venv \
        ripgrep fd-find \
        git-lfs \
        unzip zip less file patch sqlite3 rsync tree nano \
        iproute2 iputils-ping dnsutils lsof \
        tmux gettext-base; \
    rm -rf /var/lib/apt/lists/*; \
    docker --version; docker compose version

# fd-find ships as `fdfind` on Debian; agents expect `fd`.
RUN ln -s "$(command -v fdfind)" /usr/local/bin/fd

# pnpm/yarn via Node's bundled corepack; uv for fast python envs;
# CodeRabbit CLI (login skipped: auth happens at first use as paseo user).
RUN corepack enable; \
    curl -fsSL https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh; \
    curl -fsSL https://cli.coderabbit.ai/install.sh | env CODERABBIT_INSTALL_DIR=/usr/local/bin CR_CLI_SKIP_LOGIN=1 sh; \
    uv --version; coderabbit --version

# Put paseo in a group matching the host's docker gid so the mounted socket
# stays accessible after the entrypoint drops privileges (group_add in
# compose doesn't survive the drop). 102 is the host's docker gid.
ARG DOCKER_GID=102
RUN groupadd -g ${DOCKER_GID} dockerhost && usermod -aG dockerhost paseo

# Leave the user as root: the base entrypoint prepares the volumes, then
# drops the daemon and the agents it launches to the `paseo` user.
