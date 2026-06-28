#!/bin/sh
set -eu

# Elixir release scripts use MODE internally. Preserve the operator-facing
# MODE=public/parser setting before the release script rewrites it.
if [ -n "${MODE:-}" ] && [ -z "${WE_GO_NEXT_MODE:-}" ]; then
  export WE_GO_NEXT_MODE="$MODE"
fi

exec "$@"
