---
title: CC container try again
created: 2025-08-17 08:43:74
tags: []
modified: 2026-07-19, 12:11:13
---
based off [[260719 null]]

from official: https://docs.anthropic.com/en/docs/claude-code/devcontainer

you need to reinstall extensions.

##   Getting started in 4 steps

1. Install VS Code and the Remote - Containers extension
2. Clone the [Claude Code reference implementation](https://github.com/anthropics/claude-code/tree/main/.devcontainer) repository
3. Open the repository in VS Code
4. When prompted, click “Reopen in Container” (or use Command Palette: Cmd+Shift+P → “Remote-Containers: Reopen in Container”)

Well, I've done all that. Let me repeat item 4:

Open CC-garage/claude-code-gh/ in Cursor
pop up window -> reopen in container 
close original window
new window does a bunch of stuff
![[Pasted image 20250817084839.png]]

trying to run cc...
it works!

**problem**: none of my apps work in the container. from the terminal, i can't run github, or finder. i can use github and finder outside of the container to edit files in the container though.... ...but isn't this a security issue? i would need to be careful there.

**problem: curl and wget do not work.** i guess that's the whole point of the container!


