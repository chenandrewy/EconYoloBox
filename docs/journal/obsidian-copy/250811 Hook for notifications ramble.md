---
title: bug
created: 2025-08-11 22:36:62
tags: []
modified: 2025-08-12, 08:30:06
---
```
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/bin/sh -c '/usr/bin/osascript -e \"display notification \\\"Task completed\\\" with title \\\"Claude Code\\\"\"; afplay /System/Library/Sounds/Glass.aiff'"
          }
        ]
      }
    ]
  }
}
```

older one works
```You’re right: `PostToolUse` fires after **every** tool call, not after the entire run. Anthropic’s docs say to use the **Stop** (and optionally **SubagentStop**) events for “when the main Claude Code agent has finished responding” and “when a subagent (Task tool call) has finished responding.” ([Anthropic](https://docs.anthropic.com/en/docs/claude-code/hooks "Hooks reference - Anthropic"))

Here’s how to wire both “needs input” and “task done” notifications:

```jsonc
{
  "hooks": {
    // Fires when Claude needs permission or has been idle 60s.
    // If you only want the “needs permission” case, call a script that
    // inspects stdin.message and exits unless it matches.
    "Notification": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/usr/bin/osascript -e 'display notification \"Claude needs your input\" with title \"Claude Code\"'"
          }
        ]
      }
    ],

    // Fires once the whole agent response is finished (i.e., task complete).
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/usr/bin/osascript -e 'display notification \"Task completed\" with title \"Claude Code\"'"
          }
        ]
      }
    ],

    // Optional: if you use the Task tool (subagents), this fires when that subtask finishes.
    // Keep or remove depending on whether you want per-subtask completion pings.
    "SubagentStop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/usr/bin/osascript -e 'display notification \"Subtask finished\" with title \"Claude Code\"'"
          }
        ]
      }
    ]
  }
}
```

Why this works:

- `Stop` = whole run complete (not per-tool). ([Anthropic](https://docs.anthropic.com/en/docs/claude-code/hooks "Hooks reference - Anthropic"))
    
- `Notification` = when Claude needs permission or has been waiting for your input; it doesn’t take matchers, but the hook receives `stdin.message` so you can filter in a tiny script if you only want specific messages. ([Anthropic](https://docs.anthropic.com/en/docs/claude-code/hooks "Hooks reference - Anthropic"))
    

If your changes don’t seem to apply, open `/hooks` in Claude Code and accept the changes (hooks are snapshotted per session), or run with `--debug` to see hook execution. ([Anthropic](https://docs.anthropic.com/en/docs/claude-code/hooks "Hooks reference - Anthropic"))

Want me to show a tiny Python filter script so the “Notification” hook only fires on the “needs permission” message?

Fixing the call to osascript
```
osascript -e 'display notification "Claude needs your input" with title "Claude Code"'
```
That works.

Adding the sound:
```
/usr/bin/osascript -e 'display notification "Task completed" with title "Claude Code"' && afplay /System/Library/Sounds/Glass.aiff
```

But the json does not work. 

A json that worked used

```
{
  "permissions": {
    "allow": [
      "Bash(afplay:*)"
    ],
    "deny": [
      "Read(./**/.env*)",
      "Read(./**/.ssh/**)"
    ]
  },
  "model": "claude-3.7-sonnet",
  "hooks": {
    "Notification": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/usr/bin/osascript -e 'display notification \"Claude needs your input\" with title \"Claude Code\"'"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "/usr/bin/osascript -e 'display notification \"Task completed\" with title \"Claude Code\"'"
          }
        ]
      }
    ]
  }
}

```