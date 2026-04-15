#!/bin/bash
# Ensure a target pane exists and return its ID.
# Combines tmux check, existing pane lookup, creation, and focus restore
# into a single call.
#
# Usage: pane-ensure.sh [-h|-v] [-p SIZE] [-t TITLE]
#   -h         Split horizontally (new pane to the right, default)
#   -v         Split vertically (new pane below)
#   -p SIZE    Percentage of space for the new pane (default: none/tmux default)
#   -t TITLE   Pane title to find or create
#
# Output: Prints the pane ID (e.g. %5) to stdout
# Exit:   0=success, 1=error (not in tmux, creation failed)
#
# With -t TITLE: finds a pane with that title, or creates one with that label.
# Without -t:    finds any idle, non-active pane in the current window.
#                A pane is idle if its current command is a shell (bash, zsh, sh, fish).
#                Panes running other processes are skipped.
#                Only creates a new pane if no idle pane exists.
# Focus is always restored to the originating pane.

DIRECTION="-h"
SIZE=""
TITLE=""

while [ $# -gt 0 ]; do
    case "$1" in
        -h) DIRECTION="-h"; shift ;;
        -v) DIRECTION="-v"; shift ;;
        -p) SIZE="$2"; shift 2 ;;
        -t) TITLE="$2"; shift 2 ;;
        *)  echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

# Must be inside tmux
if [ -z "${TMUX:-}" ]; then
    echo "Error: not running in a tmux session" >&2
    exit 1
fi

# Remember where we are so we can restore focus
ORIGINAL=$(tmux display-message -p "#{pane_id}")

if [ -n "$TITLE" ]; then
    # Named mode: find pane by title
    EXISTING=$(tmux list-panes -s -F "#{pane_id} #{pane_title}" | grep "$TITLE" | head -1 | awk '{print $1}')
else
    # Auto mode: find a non-active pane that is idle (running a shell).
    # Panes running other processes (node, python, vim, etc.) are busy — skip them.
    EXISTING=$(tmux list-panes -F "#{pane_id} #{pane_active} #{pane_current_command}" \
        | awk '$2 == 0 && ($3 == "zsh" || $3 == "bash" || $3 == "sh" || $3 == "fish") {print $1; exit}')
fi

if [ -n "$EXISTING" ]; then
    echo "$EXISTING"
    exit 0
fi

# Build the split-window command
SPLIT_ARGS=("$DIRECTION" -P -F "#{pane_id}")
if [ -n "$SIZE" ]; then
    SPLIT_ARGS+=(-p "$SIZE")
fi

WORK_PANE=$(tmux split-window "${SPLIT_ARGS[@]}")
if [ -z "$WORK_PANE" ]; then
    echo "Error: failed to create pane" >&2
    exit 1
fi

# Label and restore focus
tmux select-pane -t "$WORK_PANE" -T "$TITLE"
tmux select-pane -t "$ORIGINAL"

# Brief pause so the shell in the new pane is ready to accept commands.
# Without this, a chained pane-send.sh can fire before the prompt appears.
sleep 0.3

echo "$WORK_PANE"
