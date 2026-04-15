---
name: pane
description: Run a command in a tmux pane. Usage - /pane [name] "<command>" [processing instructions]
version: 0.4.0
---

Script: `bash ~/.claude/skills/pane/scripts/pane-run.sh [flags] "<command>"`

Flags: `--capture` (capture output), `-t <name>` (named pane), `--dir=v` (split below instead of right)

Args: bare word = pane name, quoted string = command, remaining text = processing instructions.

No name → auto-finds an idle pane or creates one. Add `--capture` only when processing instructions are present. Without processing instructions, respond only "Sent." No confirmations, no announcements.
