#!/usr/bin/env bash
set -euo pipefail

PROMPT='$'

step() {
    echo "$PROMPT $*"
    "$@"
    echo
}

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

step git rev-parse HEAD
step zig version
step just clean
step just build
step just test
step just examples
