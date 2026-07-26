#!/usr/bin/env bash
# Deterministic quality ratchet for gc formula step checks.
# Runs the repo's full quality gate (format, compile --warnings-as-errors,
# credo, migrations, full test suite) from the Phoenix app directory.
set -euo pipefail
cd "$(dirname "$0")/../../we_go_next"
exec mix quality
