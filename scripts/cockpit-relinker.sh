#!/usr/bin/env bash

# Keep Gas City agent windows linked into the wgn-factory cockpit. This runs
# inside the cockpit, on the same tmux server as the agents, so plain `tmux`
# intentionally targets that server through $TMUX.
#
# Ported from ui-o-matic's cockpit-relinker.sh; keep fixes in sync.

set -u

SESSION="${WGN_COCKPIT_SESSION:-wgn-factory}"
INTERVAL="${WGN_COCKPIT_RELINK_INTERVAL:-3}"

# Cockpit window slot -> Gas City session. Airmux owns slots 1-5.
# Add worker sessions here as they get stable names (gc session list).
declare -A SLOTS=(
  [6]="mayor"
)

log() {
  printf '[relinker] %s\n' "$*"
}

window_id_at_slot() {
  local wanted_slot="$1"
  local listed_slot listed_id

  while read -r listed_slot listed_id; do
    if [ "$listed_slot" = "$wanted_slot" ]; then
      printf '%s\n' "$listed_id"
      return
    fi
  done < <(tmux list-windows -t "$SESSION" -F '#{window_index} #{window_id}' 2>/dev/null)
}

unlink_slot() {
  local slot="$1"

  # -k is required: a killed source session leaves its window linked only to
  # the cockpit, and plain unlink-window refuses to remove a window's last
  # link ("window only linked to one session").
  tmux unlink-window -k -t "${SESSION}:${slot}" 2>/dev/null \
    && log "unlinked stale ${SESSION}:${slot}"
}

relink_slot() {
  local slot="$1"
  local agent="${SLOTS[$slot]}"
  local idx source_id target_id current_name

  idx=$(tmux list-windows -t "$agent" -F '#{window_index}' 2>/dev/null | head -1)
  # Do not probe a possibly absent slot through display-message: tmux 3.4 can
  # fall back to an unrelated current window. Enumerate and compare indices.
  target_id=$(window_id_at_slot "$slot")

  if [ -z "$idx" ]; then
    [ -n "$target_id" ] && unlink_slot "$slot"
    return
  fi

  source_id=$(tmux display-message -p -t "${agent}:${idx}" '#{window_id}' 2>/dev/null)
  if [ -z "$source_id" ]; then
    return
  fi

  # A killed source session can leave its shared window alive in the cockpit.
  # Compare object IDs so a recreated source replaces that stale link.
  if [ -n "$target_id" ] && [ "$target_id" != "$source_id" ]; then
    unlink_slot "$slot"
    target_id=""
  fi

  if [ -z "$target_id" ]; then
    tmux link-window -d -s "${agent}:${idx}" -t "${SESSION}:${slot}" 2>/dev/null \
      && log "linked ${agent}:${idx} -> ${SESSION}:${slot}"
  fi

  current_name=$(tmux display-message -p -t "${SESSION}:${slot}" '#{window_name}' 2>/dev/null)
  if [ -n "$current_name" ] && [ "$current_name" != "$agent" ]; then
    tmux rename-window -t "${SESSION}:${slot}" "$agent" 2>/dev/null || true
  fi
}

run_pass() {
  local slot

  # Make wheel/copy-mode behavior survive a cold server start even when the
  # operator has no ~/.tmux.conf.
  tmux set-option -g mouse on 2>/dev/null || true
  # Dedicated numeric slots must not collapse when an agent window disappears.
  tmux set-option -t "$SESSION" renumber-windows off 2>/dev/null || true
  for slot in "${!SLOTS[@]}"; do
    relink_slot "$slot"
  done
}

if [ "${1:-}" = "--once" ]; then
  run_pass
  exit
fi

while true; do
  run_pass
  sleep "$INTERVAL"
done
