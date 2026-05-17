#!/usr/bin/env bash
set -u

readonly lx_bin="${LX_BIN:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/zig-out/bin/lx}"
HISTFILE="${LX_HISTFILE:-$HOME/.lx_history}"
HISTSIZE="${LX_HISTSIZE:-1000}"

if [[ ! -x "$lx_bin" ]]; then
    echo "binary not found at $lx_bin (set LX_BIN or run \`just build\`)" >&2
    exit 1
fi

[[ -f "$HISTFILE" ]] && history -r "$HISTFILE"
trap 'history -w "$HISTFILE" 2>/dev/null || true' EXIT

while IFS= read -e -r -p "> " src; do
    [[ -z "${src//[[:space:]]/}" ]] && continue
    history -s "$src"
    "$lx_bin" - <<< "$src"
done
echo
