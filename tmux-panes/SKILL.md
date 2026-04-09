---
name: tmux Pane Control
description: This skill should be used when the user asks to "run a command in a new pane", "create a terminal pane", "use a separate tmux pane", "run tests in another pane", "open a shell split", "send a command to the terminal", "read output from that pane", "open a repl in a pane", "watch logs in a split", or wants Claude to execute commands, monitor output, or maintain a persistent shell workspace in a tmux pane alongside the conversation.
version: 0.1.0
---

# tmux Pane Control

Control tmux panes in the window Claude is running in — list existing panes, create new splits, send commands, and capture output. This skill lets Claude use a dedicated terminal pane as a persistent workspace for running commands and reading their results.

**Requirement:** Claude must be running inside a tmux session. Check first:

```bash
echo "${TMUX:-not-in-tmux}"
```

If `$TMUX` is unset, pane operations will not work — inform the user and stop.

---

## Listing Panes

To see all panes in the current window:

```bash
tmux list-panes -F "#{pane_id} idx=#{pane_index} active=#{pane_active} #{pane_width}x#{pane_height} cmd=#{pane_current_command} title=#{pane_title}"
```

Key fields:
- `pane_id` — unique ID like `%0`, `%1`, `%3`; always use this when targeting a pane with `-t`
- `pane_active` — `1` = the pane the user is currently in; **do not send keys to this pane** without explicit permission
- `pane_current_command` — what process is running (e.g. `zsh`, `node`, `vim`)
- `pane_title` — can be set to label panes (e.g. `claude-workspace`)

To list all panes across all windows in the session, add `-a`. Default scope (no `-a`) is current window only — prefer this.

---

## Creating a New Pane

Split the current pane and capture the new pane's ID:

```bash
# Horizontal split — new pane to the right
NEW_PANE=$(tmux split-window -h -P -F "#{pane_id}")

# Vertical split — new pane below
NEW_PANE=$(tmux split-window -v -P -F "#{pane_id}")

# Vertical split taking 30% of the height
NEW_PANE=$(tmux split-window -v -p 30 -P -F "#{pane_id}")
```

Always save the returned pane ID. Then optionally label it:

```bash
tmux select-pane -t "$NEW_PANE" -T "claude-workspace"
```

Return focus to the original pane (the one Claude's conversation is in) after splitting:

```bash
tmux select-pane -t "$ORIGINAL_PANE"
```

The original pane ID can be obtained before splitting:

```bash
ORIGINAL_PANE=$(tmux display-message -p "#{pane_id}")
```

---

## Sending a Command to a Pane

For quick, simple sends (no output needed back):

```bash
tmux send-keys -t %3 "ls -la" Enter
```

For commands where Claude needs to read the output — use the bundled `pane-send.sh` script. It appends a unique sentinel, waits for it to appear in the scrollback, then returns the captured output:

```bash
bash ~/.claude/skills/tmux-panes/scripts/pane-send.sh %3 "npm test" 60
```

Arguments: `<pane-id>` `<command>` `[timeout-seconds, default 30]`

Exit codes: `0`=success with output, `2`=timed out.

**Avoid** sending keys to `pane_active=1` (the user's focused pane) unless explicitly instructed. Check before sending.

### Sending Multi-line or Complex Commands

For commands with pipes, redirects, or quotes, prefer wrapping in a temporary script:

```bash
# Write the command to a temp file, then source it in the pane
cat > /tmp/claude-cmd.sh << 'EOF'
cd /some/path && npm run build 2>&1 | tee /tmp/build-out.txt
EOF
bash ~/.claude/skills/tmux-panes/scripts/pane-send.sh %3 "bash /tmp/claude-cmd.sh" 120
```

### Sending Ctrl+C or Special Keys

```bash
tmux send-keys -t %3 C-c        # Ctrl+C — interrupt current process
tmux send-keys -t %3 q Enter    # send 'q' then Enter (e.g. quit less)
tmux send-keys -t %3 ""        # Ctrl+D — EOF / logout
```

---

## Capturing Pane Output

To read the current content of a pane without sending a command:

```bash
bash ~/.claude/skills/tmux-panes/scripts/pane-capture.sh %3 200
```

Arguments: `<pane-id>` `[lines, default 100]`

Capture directly with tmux for quick reads:

```bash
tmux capture-pane -t %3 -p -S -100   # last 100 lines
tmux capture-pane -t %3 -p            # visible area only
```

Use `pane-capture.sh` for anything needing more than ~50 lines — it returns clean output.

---

## Killing a Pane

When the workspace pane is no longer needed:

```bash
tmux kill-pane -t %3
```

Always kill Claude-created panes when a task is done unless the user explicitly wants to keep them. Ask if unsure.

---

## Standard Workflow: Command + Output

1. Get current pane ID (to restore focus later):
   ```bash
   ORIGINAL=$(tmux display-message -p "#{pane_id}")
   ```

2. Check if a `claude-workspace` pane already exists:
   ```bash
   tmux list-panes -F "#{pane_id} #{pane_title}" | grep "claude-workspace"
   ```

3. If not found, create one:
   ```bash
   WORK_PANE=$(tmux split-window -v -p 30 -P -F "#{pane_id}")
   tmux select-pane -t "$WORK_PANE" -T "claude-workspace"
   tmux select-pane -t "$ORIGINAL"
   ```

4. Run a command and read its output:
   ```bash
   bash ~/.claude/skills/tmux-panes/scripts/pane-send.sh "$WORK_PANE" "your command here" 30
   ```

5. Report output back in the conversation, then kill or keep the pane.

---

## Best Practices

- **Never send keys to `pane_active=1`** without the user's explicit request — that is their focused terminal.
- **Announce creation**: Tell the user "Creating a new pane below for this..." before splitting.
- **Capture at least 200 lines**: Short captures miss output. Default to `-S -200` or higher for commands that produce output.
- **Restore focus**: After splitting, return focus with `tmux select-pane -t "$ORIGINAL"` so the user's cursor isn't yanked away.
- **Respect the pane title**: Check `pane_title` for `claude-workspace` before creating a new one — reuse it if present.
- **Interactive commands**: For commands that prompt for input (passwords, confirmations), warn the user rather than sending blindly.
- **Long-running commands**: Use a generous timeout (120s+). If a command might run indefinitely (server, watcher), use `pane-capture.sh` to periodically read output instead of `pane-send.sh`.

---

## Additional Resources

- **`scripts/pane-send.sh`** — Send a command and wait for completion via sentinel pattern
- **`scripts/pane-capture.sh`** — Capture N lines of scrollback from any pane
