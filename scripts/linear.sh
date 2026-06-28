#!/usr/bin/env bash
#
# Linear API helper for we_go_next.
#
# This project's board lives in the `we-go-next` workspace (team WE). The
# `mcp__linear__*` MCP tools are authed to a DIFFERENT workspace
# (`wow-ui-o-matic`) and must NOT be used here — they silently write to the
# wrong team. Always drive Linear through this script (the per-session
# LINEAR_API_KEY personal key selects the correct workspace).
#
# Usage:
#   echo '{"query":"{ viewer { name } }"}' | scripts/linear.sh
#   scripts/linear.sh path/to/body.json
#
# Body is a GraphQL request object: {"query": "...", "variables": {...}}.
set -euo pipefail

if [ -z "${LINEAR_API_KEY:-}" ]; then
  echo "LINEAR_API_KEY is not set in this shell. Export the we-go-next key before using Linear here." >&2
  exit 1
fi

curl -s -X POST https://api.linear.app/graphql \
  -H "Authorization: $LINEAR_API_KEY" \
  -H "Content-Type: application/json" \
  --data @"${1:-/dev/stdin}"
