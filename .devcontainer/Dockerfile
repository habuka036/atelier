# atelier — general-purpose AI software development environment image.
#
# Linux (arm64/amd64) container intended to be opened from an Apple Silicon host
# via VS Code DevContainers. Provides: bubblewrap (for NAVETTE's sandbox), Go
# 1.26.0 via mise (matching navette/millefeuille go.mod), and the Kiro CLI.
#
# Security posture:
#   - Runs as a non-root user (developer, uid 1000).
#   - No --privileged, no --cap-add, no Docker socket.
#   - Unprivileged user namespaces (used by bubblewrap) are available in the
#     container; only seccomp=unconfined is relaxed (set in devcontainer.json),
#     which does NOT grant privilege escalation.
FROM debian:bookworm-slim

ARG USERNAME=developer
ARG USER_UID=1000
ARG USER_GID=${USER_UID}

# Pinned tool versions for reproducibility. mise is pinned via MISE_VERSION.
# The Kiro CLI upstream installer does not accept a version argument, so the
# installed version is RECORDED (not pinned) and surfaced in logs; see README
# "Reproducibility" for the associated risk.
ARG MISE_VERSION=v2026.8.12

RUN groupadd --gid "${USER_GID}" "${USERNAME}" \
    && useradd --uid "${USER_UID}" --gid "${USER_GID}" -m "${USERNAME}" \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        bubblewrap \
        ca-certificates \
        curl \
        gcc \
        g++ \
        git \
        libc6-dev \
        libstdc++-12-dev \
        make \
        sudo \
        unzip \
        util-linux \
    && rm -rf /var/lib/apt/lists/*

# Named volumes are created root-owned and mounted at /workspace/state and
# /workspace/artifacts. The container runs as non-root `developer`, so it cannot
# write there until the mount points are chowned at startup. Install a fixed
# root-owned helper that performs ONLY those two chowns, after VERIFYING each
# target is the expected path AND is a mount point (so the helper can only ever
# affect the intended durable volumes, never an arbitrary directory). Grant
# `developer` a passwordless sudo entry limited to exactly that helper with no
# arguments. This is far narrower than --privileged and cannot be repurposed.
RUN printf '%s\n' \
    '#!/bin/sh' \
    '# Fix ownership of the atelier durable volume mount points ONLY.' \
    '# Hardcoded targets; verifies each is the expected path and a mount point.' \
    'set -eu' \
    'for d in /workspace/state /workspace/artifacts; do' \
    '  case "$d" in' \
    '    /workspace/state|/workspace/artifacts) : ;;' \
    '    *) echo "refusing unexpected target: $d" >&2; exit 2 ;;' \
    '  esac' \
    '  if [ ! -d "$d" ]; then echo "target missing: $d" >&2; exit 3; fi' \
    '  if ! mountpoint -q "$d"; then' \
    '    echo "refusing: $d is not a mount point (expected a named volume)" >&2' \
    '    exit 4' \
    '  fi' \
    '  chown developer:developer "$d"' \
    'done' \
    > /usr/local/sbin/atelier-fix-volumes \
    && chmod 0755 /usr/local/sbin/atelier-fix-volumes \
    && echo 'developer ALL=(root) NOPASSWD: /usr/local/sbin/atelier-fix-volumes' \
    > /etc/sudoers.d/atelier-volume-chown \
    && chmod 0440 /etc/sudoers.d/atelier-volume-chown \
    && visudo -cf /etc/sudoers.d/atelier-volume-chown

USER ${USERNAME}

ENV PATH="/home/${USERNAME}/.local/bin:/home/${USERNAME}/.local/share/mise/shims:${PATH}"

# mise provides the Go toolchain pinned to go.mod's version. mise itself is
# pinned via MISE_VERSION for reproducibility.
RUN curl -fsSL https://mise.run | MISE_VERSION="${MISE_VERSION}" sh \
    && echo 'eval "$(mise activate bash)"' >> "/home/${USERNAME}/.bashrc"

COPY --chown=${USERNAME}:${USERNAME} mise.toml /home/${USERNAME}/.config/mise/config.toml

RUN mise trust /home/${USERNAME}/.config/mise/config.toml \
    && mise install \
    && mise reshim

# Kiro CLI installs into ~/.local/bin with embedded bun/node under
# ~/.local/share/kiro-cli (which NAVETTE's sandbox mounts read-only). The
# normal profile dir (~/.kiro, ~/.local/share/kiro-cli/data.sqlite3) is NOT
# used by experiments; experiments authenticate a dedicated HOME under
# /workspace/state/kiro-home instead.
#
# NOTE: the Kiro CLI installer does not accept a version pin; the installed
# version is recorded below and printed by post-create/smoke. Treat upstream
# installer drift as a reproducibility risk (see README "Reproducibility").
RUN curl -fsSL https://cli.kiro.dev/install | bash

# Record the actual installed tool versions into an image-baked file so every
# run can log a reproducible provenance record (surfaced by post-create.sh).
RUN set -eu; \
    { \
      echo "recorded_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"; \
      echo "mise_requested=${MISE_VERSION}"; \
      echo "mise=$(mise --version 2>/dev/null | head -n1 || echo unknown)"; \
      echo "go=$(mise exec -- go version 2>/dev/null || echo unknown)"; \
      echo "kiro_cli=$(kiro-cli --version 2>/dev/null || echo unknown)"; \
      echo "bwrap=$(bwrap --version 2>/dev/null || echo unknown)"; \
    } > /home/${USERNAME}/.atelier-versions

WORKDIR /workspace
