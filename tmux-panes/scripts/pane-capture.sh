#!/bin/bash
# Capture the current scrollback content of a tmux pane.
#
# Usage: pane-capture.sh <pane-id> [lines]
# Output: Last N lines of pane content printed to stdout
# Exit:   0=success, 1=error

PANE_ID="${1:-}"
LINES="${2:-100}"

if [ -z "$PANE_ID" ]; then
    echo "Usage: pane-capture.sh <pane-id> [lines]" >&2
    exit 1
fi

if [ -z "${TMUX:-}" ]; then
    echo "Error: not running in a tmux session" >&2
    exit 1
fi

tmux capture-pane -t "$PANE_ID" -p -S "-${LINES}"
