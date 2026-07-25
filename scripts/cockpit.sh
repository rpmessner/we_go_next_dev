#!/usr/bin/env bash

# Start the Airmux cockpit on the same named tmux server Gas City uses
# (~/gc city.toml sets [session] socket = "default"), so agent windows —
# mayor, workers — can be linked natively into the cockpit instead of
# attaching nested tmux clients. Pattern ported from ui-o-matic.

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd)
SOCK="${WGN_COCKPIT_SOCKET:-default}"

if [[ ! "$SOCK" =~ ^[A-Za-z0-9_.-]+$ ]]; then
  printf 'Invalid tmux socket name: %s\n' "$SOCK" >&2
  exit 2
fi

exec airmux start \
  -f "${PROJECT_ROOT}/.airmux.yml" \
  -t "tmux -L ${SOCK}" \
  "$@"
