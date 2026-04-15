#!/bin/bash
# Run a command in a tmux pane. Combines ensure + send into one call.
#
# Usage:
#   pane-run.sh <command> [timeout]                        # auto-find pane
#   pane-run.sh -t <pane-name> <command> [timeout]         # named pane
#   pane-run.sh --capture <command> [timeout]               # capture output
#   pane-run.sh --capture -t <pane-name> <command> [timeout]
#   pane-run.sh --dir=h|v <command> [timeout]               # split direction
#
# Options:
#   --capture    Use pane-send.sh to capture and return output
#   --dir=h      Split horizontally / to the right (default)
#   --dir=v      Split vertically / below
#   -t NAME      Target a named pane (find or create by title)
#
# Without -t: finds any non-active pane in the current window,
#             only creates a new pane if none exist.
#
# Exit: 0=success, 1=error, 2=timeout (capture mode only)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CAPTURE=false
DIRECTION="-h"
PANE_NAME=""

# Parse flags
while [ $# -gt 0 ]; do
    case "$1" in
        --capture) CAPTURE=true; shift ;;
        --dir=h)   DIRECTION="-h"; shift ;;
        --dir=v)   DIRECTION="-v"; shift ;;
        -t)        PANE_NAME="$2"; shift 2 ;;
        -*)        echo "Unknown option: $1" >&2; exit 1 ;;
        *)         break ;;
    esac
done

COMMAND="${1:-}"
TIMEOUT="${2:-30}"

if [ -z "$COMMAND" ]; then
    echo "Usage: pane-run.sh [--capture] [--dir=h|v] [-t pane-name] <command> [timeout]" >&2
    exit 1
fi

# Build ensure args
ENSURE_ARGS=("$DIRECTION")
if [ -n "$PANE_NAME" ]; then
    ENSURE_ARGS+=(-t "$PANE_NAME")
fi

WORK_PANE=$("$SCRIPT_DIR/pane-ensure.sh" "${ENSURE_ARGS[@]}")
if [ $? -ne 0 ] || [ -z "$WORK_PANE" ]; then
    echo "Error: failed to ensure pane" >&2
    exit 1
fi

if [ "$CAPTURE" = true ]; then
    exec "$SCRIPT_DIR/pane-send.sh" "$WORK_PANE" "$COMMAND" "$TIMEOUT"
else
    tmux send-keys -t "$WORK_PANE" "$COMMAND" Enter
fi
