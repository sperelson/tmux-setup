#!/bin/bash

# Read JSON input once
input=$(cat)

# Extract current directory
cwd=$(echo "$input" | jq -r '.workspace.current_dir')

# Extract model display name
model=$(echo "$input" | jq -r '.model.display_name // ""')

# Extract context percentage
ctx_pct=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)

# Extract rate limit percentages for tmux-powerkit plugin
five_h=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // ""' | cut -d. -f1)
seven_d=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // ""' | cut -d. -f1)

# Export for tmux-powerkit claude_code plugin
printf '%s %s\n' "${five_h:-}" "${seven_d:-}" > /tmp/claude-code-ctx 2>/dev/null

# Pick context-level icon based on context usage
if [ "$ctx_pct" -ge 95 ]; then
  ctx_icon='󱚡'
elif [ "$ctx_pct" -ge 80 ]; then
  ctx_icon='󱚟'
elif [ "$ctx_pct" -ge 60 ]; then
  ctx_icon='󱚝'
elif [ "$ctx_pct" -ge 40 ]; then
  ctx_icon='󰚩'
elif [ "$ctx_pct" -ge 5 ]; then
  ctx_icon='󱜙'
else
  ctx_icon='󱚣'
fi

# Color the context percentage based on usage
if [ "$ctx_pct" -ge 60 ]; then
  ctx_color='\033[01;31m' # red
elif [ "$ctx_pct" -ge 40 ]; then
  ctx_color='\033[01;33m' # yellow
else
  ctx_color='\033[01;32m' # green
fi

# Format rate limit info
rate_info=""
if [ -n "$five_h" ] && [ -n "$seven_d" ]; then
  rate_info=" (${five_h}%/${seven_d}%)"
fi

# Memory used by all Claude Code instances (RSS in KB → human-readable)
claude_mem_kb=$(ps -eo rss,command 2>/dev/null | awk '/[c]laude$/ {sum+=$1} END {print sum+0}')
if [ "$claude_mem_kb" -gt 1048576 ]; then
  claude_mem=$(awk -v kb="$claude_mem_kb" 'BEGIN {printf "%.1fG", kb/1048576}')
elif [ "$claude_mem_kb" -gt 1024 ]; then
  claude_mem=$(awk -v kb="$claude_mem_kb" 'BEGIN {printf "%.0fM", kb/1024}')
else
  claude_mem="${claude_mem_kb}K"
fi

# Git information
if git -C "$cwd" rev-parse --git-dir > /dev/null 2>&1; then
  repo_name=$(basename "$cwd")

  printf '\033[01;36m%s\033[00m | %s | %b%s %s%%%s\033[00m 󰍛 %s' \
    "$repo_name" "$model" "$ctx_color" "$ctx_icon" "$ctx_pct" "$rate_info" "$claude_mem"
else
  printf '\033[01;36m%s\033[00m | %s | %b%s %s%%%s\033[00m 󰍛 %s' \
    "$cwd" "$model" "$ctx_color" "$ctx_icon" "$ctx_pct" "$rate_info" "$claude_mem"
fi
