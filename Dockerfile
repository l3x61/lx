FROM debian:bookworm-slim

ARG ZIG_VERSION=0.16.0
ARG JUST_VERSION=1.40.0

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates curl xz-utils git bat \
    && ln -s /usr/bin/batcat /usr/local/bin/bat \
    && rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    arch="$(uname -m)"; \
    case "$arch" in \
        x86_64)  zig_arch="x86_64"  ;; \
        aarch64) zig_arch="aarch64" ;; \
        *) echo "unsupported architecture: $arch" >&2; exit 1 ;; \
    esac; \
    curl -fsSL "https://ziglang.org/download/${ZIG_VERSION}/zig-${zig_arch}-linux-${ZIG_VERSION}.tar.xz" \
        | tar -xJ -C /opt; \
    ln -s "/opt/zig-${zig_arch}-linux-${ZIG_VERSION}/zig" /usr/local/bin/zig

RUN set -eux; \
    arch="$(uname -m)"; \
    case "$arch" in \
        x86_64)  just_arch="x86_64-unknown-linux-musl"  ;; \
        aarch64) just_arch="aarch64-unknown-linux-musl" ;; \
        *) echo "unsupported architecture: $arch" >&2; exit 1 ;; \
    esac; \
    curl -fsSL "https://github.com/casey/just/releases/download/${JUST_VERSION}/just-${JUST_VERSION}-${just_arch}.tar.gz" \
        | tar -xz -C /usr/local/bin just

WORKDIR /work
COPY . /work

RUN zig build

ENTRYPOINT ["/work/docker-entry.sh"]
