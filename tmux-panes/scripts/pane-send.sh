#!/bin/bash
# Send a command to a tmux pane and wait for it to complete.
# Uses a unique sentinel marker to detect completion.
#
# Usage: pane-send.sh <pane-id> "<command>" [timeout-seconds]
# Output: Command output printed to stdout
# Exit:   0=success, 1=not in tmux or bad args, 2=timeout

PANE_ID="${1:-}"
COMMAND="${2:-}"
TIMEOUT="${3:-30}"

if [ -z "$PANE_ID" ] || [ -z "$COMMAND" ]; then
    echo "Usage: pane-send.sh <pane-id> <command> [timeout-seconds]" >&2
    exit 1
fi

if [ -z "${TMUX:-}" ]; then
    echo "Error: not running in a tmux session" >&2
    exit 1
fi

# Unique sentinel — random enough to avoid collisions
SENTINEL="__CLAUDE_PANE_DONE_${$}_${RANDOM}__"

# Send command; append sentinel echo so we know when it finishes
tmux send-keys -t "$PANE_ID" "${COMMAND}; echo ${SENTINEL}" Enter

# Poll for the sentinel to appear in the pane's scrollback
END_TIME=$((SECONDS + TIMEOUT))
while [ $SECONDS -lt $END_TIME ]; do
    CAPTURED=$(tmux capture-pane -t "$PANE_ID" -p -S -1000 2>/dev/null || true)
    if echo "$CAPTURED" | grep -qF "$SENTINEL"; then
        # Print captured output with sentinel line stripped
        echo "$CAPTURED" | grep -vF "$SENTINEL"
        exit 0
    fi
    sleep 0.3
done

echo "Timeout: command did not complete within ${TIMEOUT}s" >&2
exit 2
