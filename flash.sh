#!/usr/bin/env bash
# =============================================================================
# Utility: flash
# Description: Flash a tmux window name as a visual notification
# Dependencies: tmux
# =============================================================================
#
# Why this exists:
#   When Claude Code (or any script) finishes a task and wants to subtly
#   notify the user, it can't send a BEL character to the pane's TTY because
#   it runs as a subprocess, not inside the pane's shell. This script uses
#   tmux's per-window format overrides to temporarily recolour a window's
#   status bar entry, then reverts cleanly to the global (powerkit) formats.
#
# Usage:
#   flash.sh [window_id] [count] [interval] [bg] [fg]
#
# Config (tmux options — all optional):
#   @flash-bg       background colour    (default: #3d5a80)
#   @flash-fg       foreground colour    (default: #e0e0e0)
#   @flash-count    number of flashes    (default: 10)
#   @flash-interval seconds on/off each  (default: 0.3)
#
# Claude Code integration:
#   Add the following to ~/.claude/settings.json under "hooks" to flash
#   the tmux window on events like Notification, Stop, or PermissionRequest.
#   Recommended events: Notification, Stop, PermissionRequest, SessionEnd.
#
#   "Notification": [
#     {
#       "matcher": "",
#       "hooks": [
#         {
#           "type": "command",
#           "command": "/path/to/flash.sh 2>&1",
#           "timeout": 10,
#           "async": true
#         }
#       ]
#     }
#   ]
#
# =============================================================================

WINDOW="${1:-$(tmux display-message -t "${TMUX_PANE}" -p '#{window_id}')}"

COUNT="${2:-$(tmux show-option -gqv @flash-count)}"
COUNT="${COUNT:-6}"

INTERVAL="${3:-$(tmux show-option -gqv @flash-interval)}"
INTERVAL="${INTERVAL:-0.2}"

FLASH_BG="${4:-$(tmux show-option -gqv @flash-bg)}"
FLASH_BG="${FLASH_BG:-#3d5a80}"

FLASH_FG="${5:-$(tmux show-option -gqv @flash-fg)}"
FLASH_FG="${FLASH_FG:-#e0e0e0}"

# Snapshot global formats (powerkit sets these)
INACTIVE_FMT=$(tmux show-options -gv window-status-format)
ACTIVE_FMT=$(tmux show-options -gv window-status-current-format)

# Replace all hex colours with flash colours
recolour() {
    echo "$1" \
        | sed -e "s/bg=#[0-9a-fA-F]\{6\}/bg=$FLASH_BG/g" \
              -e "s/fg=#[0-9a-fA-F]\{6\}/fg=$FLASH_FG/g"
}

FLASH_INACTIVE=$(recolour "$INACTIVE_FMT")
FLASH_ACTIVE=$(recolour "$ACTIVE_FMT")

flash_on() {
    tmux set-window-option -t "$WINDOW" window-status-format "$FLASH_INACTIVE"
    tmux set-window-option -t "$WINDOW" window-status-current-format "$FLASH_ACTIVE"
}

flash_off() {
    tmux set-window-option -u -t "$WINDOW" window-status-format
    tmux set-window-option -u -t "$WINDOW" window-status-current-format
}

# Skip if the window already has focus — the user is already looking at it
if [ "$(tmux display-message -t "$WINDOW" -p '#{window_active}')" = "1" ]; then
    exit 0
fi

# Blink in background so the script returns immediately
(for _ in $(seq 1 "$COUNT"); do
    flash_on
    sleep "$INTERVAL"
    flash_off
    sleep "$INTERVAL"
done) &
