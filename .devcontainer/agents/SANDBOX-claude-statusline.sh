#!/usr/bin/env bash
# SANDBOX-claude-statusline.sh
# How to run: bash .devcontainer/agents/SANDBOX-claude-statusline.sh
# Input:  JSON from Claude Code via stdin
# Output: single-line status string for the Claude Code status bar

input=$(cat)

cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // ""')
dir=$(basename "$cwd")

model=$(echo "$input" | jq -r '.model.display_name // ""')

used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
if [ -n "$used" ]; then
  ctx=$(printf "ctx:%.0f%%" "$used")
else
  ctx=""
fi

five_h=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
seven_d=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
limits=""
if [ -n "$five_h" ]; then
  limits=$(printf "5h:%.0f%%" "$five_h")
fi
if [ -n "$seven_d" ]; then
  limits=$(printf "%s 7d:%.0f%%" "$limits" "$seven_d")
fi

branch=""
if [ -d "${cwd}/.git" ] || git -C "$cwd" rev-parse --git-dir > /dev/null 2>&1; then
  branch=$(git -C "$cwd" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null)
fi

parts=""
parts=$(printf "\033[36m%s\033[0m" "$dir")

if [ -n "$branch" ]; then
  parts=$(printf "%s \033[33m(%s)\033[0m" "$parts" "$branch")
fi

if [ -n "$model" ]; then
  parts=$(printf "%s  \033[90m%s\033[0m" "$parts" "$model")
fi

if [ -n "$ctx" ]; then
  parts=$(printf "%s \033[90m%s\033[0m" "$parts" "$ctx")
fi

if [ -n "$limits" ]; then
  parts=$(printf "%s  \033[90m%s\033[0m" "$parts" "$limits")
fi

printf "%s" "$parts"
