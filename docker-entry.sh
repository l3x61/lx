#!/usr/bin/env bash
# Container entry point.
set -eu

if [[ $# -eq 0 ]]; then
    exec /work/transcript.sh
fi

exec /work/zig-out/bin/lx "$@"
