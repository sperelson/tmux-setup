# tmux-powerkit Custom Plugins

Custom tmux-powerkit plugins for the tmux status bar.

## Plugins

| Plugin | Description |
|--------|-------------|
| **[Claude Code](#claude-code-plugin)** | Displays Claude Code rate limit usage (5h/7d) |
| **[CPU AS](#cpu-apple-silicon-plugin)** | Accurate CPU usage for Apple Silicon macOS |
| **[RAM](#ram-plugin)** | Accurate memory usage for Apple Silicon macOS |

## Files

| File | Description |
|------|-------------|
| `claude_code.sh` | Claude Code rate limit plugin |
| `cpuas.sh` | Accurate CPU usage plugin (replaces built-in `cpu`) |
| `ram.sh` | Accurate RAM usage plugin (replaces built-in `memory`) |
| `statusline.sh` | Claude Code status line script (bridges data to the plugin) |
| `.tmux.conf` | Full tmux configuration with all plugins enabled |
| `tmux-panes/` | Claude Code skill for controlling tmux panes from Claude |

## Installation

### 1. Copy the plugins

```bash
cp claude_code.sh ~/.tmux/plugins/tmux-powerkit/src/plugins/claude_code.sh
cp cpuas.sh ~/.tmux/plugins/tmux-powerkit/src/plugins/cpuas.sh
cp ram.sh ~/.tmux/plugins/tmux-powerkit/src/plugins/ram.sh
```

### 2. Copy the status line script

```bash
cp statusline.sh ~/.claude/statusline.sh
chmod +x ~/.claude/statusline.sh
```

### 3. Enable in tmux.conf

Add the plugins to your `@powerkit_plugins` list in `~/.tmux.conf`:

```bash
set -g @powerkit_plugins "group(datetime,cpuas,ram),claude_code,git"
```

> **Note:** Use `cpuas` instead of `cpu` and `ram` instead of `memory` for accurate Apple Silicon readings.

### 4. Ensure Claude Code statusLine is configured

In `~/.claude/settings.json`, the `statusLine` entry should exist:

```json
{
  "statusLine": {
    "type": "command",
    "command": "input=$(cat); echo \"$(echo \"$input\" | ~/.claude/statusline.sh)\""
  }
}
```

### 5. Reload tmux

```
prefix + r
```

Or from the terminal:

```bash
tmux source-file ~/.tmux.conf
```

---

## CPU Apple Silicon Plugin

A drop-in replacement for the built-in `cpu` plugin that provides accurate CPU readings on Apple Silicon macOS.

### Why not the built-in cpu plugin?

The built-in `cpu` plugin uses `top -l 1` on macOS, which returns the **cumulative-since-boot** CPU average — not a live snapshot. This inflates readings significantly, often showing 2x the actual load compared to Activity Monitor.

### How it calculates

The `cpuas` plugin uses `iostat -c 2 -w 1` and discards the first sample (cumulative). The second sample is a true 1-second delta of user + system time, matching Activity Monitor.

On Linux it uses `/proc/stat` delta calculations between refresh cycles.

### Settings

All settings use the `@powerkit_plugin_cpuas_` prefix in `.tmux.conf`:

```bash
# Health thresholds (controls powerkit theme coloring)
set -g @powerkit_plugin_cpuas_warning_threshold "70"
set -g @powerkit_plugin_cpuas_critical_threshold "90"

# Custom icon (Nerd Font glyph)
set -g @powerkit_plugin_cpuas_icon "󰻠"
```

### Health coloring (via powerkit theme)

- **ok**: Usage below 70%
- **warning**: Usage 70-90%
- **error**: Usage above 90%

---

## RAM Plugin

A drop-in replacement for the built-in `memory` plugin that provides accurate memory readings on Apple Silicon macOS (Tahoe+).

### Why not the built-in memory plugin?

The built-in `memory` plugin has two accuracy problems on Apple Silicon:

1. **`memory_pressure`** reports a coarse "free percentage" that doesn't match Activity Monitor
2. **`vm_stat` fallback** only counts active + wired pages, ignoring **compressor-occupied pages** — a significant category on Apple Silicon where memory compression is aggressive

### How it calculates

The `ram` plugin matches Activity Monitor's "Memory Used" breakdown:

| Component | Source (`vm_stat`) |
|-----------|--------------------|
| App Memory | Anonymous pages - Purgeable pages |
| Wired | Pages wired down |
| Compressed | Pages occupied by compressor |
| **Used** | **App + Wired + Compressed** |

### Settings

All settings use the `@powerkit_plugin_ram_` prefix in `.tmux.conf`:

```bash
# Display format: "percent" (default), "usage" (used/total), or "used" (used only)
set -g @powerkit_plugin_ram_format "percent"     # e.g.  54%
set -g @powerkit_plugin_ram_format "usage"       # e.g.  17.3G/32.0G
set -g @powerkit_plugin_ram_format "used"        # e.g.  17.3G

# Health thresholds (controls powerkit theme coloring)
set -g @powerkit_plugin_ram_warning_threshold "75"
set -g @powerkit_plugin_ram_critical_threshold "90"

# Custom icon (Nerd Font glyph)
set -g @powerkit_plugin_ram_icon "󰍛"
```

### Health coloring (via powerkit theme)

- **ok**: Usage below 75%
- **warning**: Usage 75-90%
- **error**: Usage above 90%

---

## Claude Code Plugin

Displays Claude Code rate limit usage in the tmux status bar. Shows two percentages: **5-hour window usage / 7-day reset usage**, with a dynamic icon that changes based on the 5-hour rate limit level.

## How it works

Claude Code pipes JSON to the `statusLine` command on each update. The JSON includes rate limit data:

```json
{
  "rate_limits": {
    "five_hour": {
      "used_percentage": 23,
      "resets_at": 1738425600
    },
    "seven_day": {
      "used_percentage": 41,
      "resets_at": 1738857600
    }
  }
}
```

### Data flow

1. **Claude Code** pipes JSON to `statusline.sh` via the `statusLine` setting
2. **`statusline.sh`** extracts both rate limit percentages and writes them to `/tmp/claude-code-ctx`
3. **`claude_code.sh`** (powerkit plugin) reads `/tmp/claude-code-ctx` and renders the values

### Changes made to statusline.sh

The following lines were added to extract rate limit data and write it to a temp file:

```bash
# Extract rate limit percentages for tmux-powerkit plugin
five_h=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // ""' | cut -d. -f1)
seven_d=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // ""' | cut -d. -f1)

# Export for tmux-powerkit claude_code plugin
printf '%s %s\n' "${five_h:-}" "${seven_d:-}" > /tmp/claude-code-ctx 2>/dev/null
```

## Display

The plugin renders as: `<icon> XX%/XX%` (5h usage / 7d usage)

### Icons (based on 5-hour window percentage)

| Range | Icon |
|-------|------|
| 0-5%  | 󱚣 |
| 5-40% | 󱜙 |
| 40-60% | 󰚩 |
| 60-80% | 󱚝 |
| 80-95% | 󱚟 |
| 95%+  | 󱚡 |

### Health coloring (via powerkit theme)

- **ok**: 5h usage below 40%
- **warning**: 5h usage 40-60%
- **error**: 5h usage above 60%

Thresholds are configurable in `.tmux.conf`:

```bash
set -g @powerkit_plugin_claude_code_warning_threshold "40"
set -g @powerkit_plugin_claude_code_critical_threshold "60"
```

## Notes

- Rate limit data is only available for **Claude Pro/Max subscribers**
- Data only appears after the **first API response** in a Claude Code session
- The plugin hides automatically when the data file is stale (default: 10 minutes)
- Stale timeout is configurable: `set -g @powerkit_plugin_claude_code_stale_seconds "600"`

---

---

## tmux Pane Control Skill

A Claude Code skill that lets Claude control tmux panes — create splits, send commands, and capture output — directly from a conversation.

### Files

| File | Description |
|------|-------------|
| `tmux-panes/SKILL.md` | Full skill documentation (loaded by Claude when invoked) |
| `tmux-panes/scripts/pane-send.sh` | Send a command to a pane and wait for completion via sentinel |
| `tmux-panes/scripts/pane-capture.sh` | Capture N lines of scrollback from a pane |

### Installation

Copy the skill to your Claude skills directory:

```bash
cp -r tmux-panes ~/.claude/skills/tmux-panes
```

Claude will pick it up automatically — invoke it by asking Claude to run something in a tmux pane.

### How it works

`pane-send.sh` appends a unique sentinel string after the command, then polls the pane's scrollback until the sentinel appears. This reliably detects when a command has finished without requiring any shell integration or modification to the target pane.

`pane-capture.sh` is a thin wrapper around `tmux capture-pane -S -N` for reading pane output without sending a command.

---

## tmux-resurrect: Tilde Expansion Bug Fix

tmux-resurrect has a bug where restored panes open in `~` instead of the saved working directory. The `new_window()` function in `restore.sh` correctly expands `~` to `$HOME`, but `new_session()` and `new_pane()` do not.

**Fix:** In `~/.tmux/plugins/tmux-resurrect/scripts/restore.sh`, add this line to both the `new_session()` and `new_pane()` functions, right after the local variable declarations (before the `if` statement):

```bash
dir="${dir/#\~/$HOME}"
```

This matches the existing fix already present in `new_window()` (around line 132). **Reapply after any tmux-resurrect plugin update** (`prefix + U`).

---

## Useful Shell Aliases

Add these to your `~/.zshrc` for convenient tmux management:

```bash
# Smart attach: reattach to existing session, or start a new one and restore via tmux-resurrect
alias mux='tmux attach 2>/dev/null || { tmux new-session -d && tmux run-shell ~/.tmux/plugins/tmux-resurrect/scripts/restore.sh && tmux attach; }'

# List all tmux sessions
alias tls="tmux ls"

# Kill the tmux server (all sessions)
alias tk="tmux kill-server"
```
