---
title: CC Container
created: 2025-08-07 07:39:57
tags: []
modified: 2025-08-08, 09:50:48
---
Web resources:
- o4-mini guide
	- https://chatgpt.com/g/g-p-67e5a37babd0819184da8c8c39fc932f-tech-support/c/6894901b-ecf0-8323-9880-12cd42ee64d3
- Official 
	- https://docs.anthropic.com/en/docs/claude-code/devcontainer?utm_source=chatgpt.com
	- https://www.anthropic.com/engineering/claude-code-best-practices?utm_source=chatgpt.com
- reddit example: https://www.reddit.com/r/ClaudeAI/comments/1kxdxcf/claude_code_dev_containers/?utm_source=chatgpt.com
	- why do they need to type continue every 30 min?


My version, based off anthropic guide
1. Cursor: Install Anyshere Dev Containers extension
2. Clone the [Claude Code reference implementation](https://github.com/anthropics/claude-code/tree/main/.devcontainer) repository
	1. actually, clone the whole anthropics/claude-code repo with `gh repo clone anthropics/claude-code`. the reference implementation is a subfolder of `claude-code`
	2. actually, actually, i needed to use `brew install gh` first, as well as log in
3. Open the `.devcontainer` subfolder in Cursor
4. Cmd+Shift+P -> dev container: reopen in container
	1. Actually, need to install docker first?
	2. ![[Pasted image 20250808062857.png]]
5. Install Docker Desktop
	1. Go to https://docs.docker.com/desktop/setup/install/mac-install/
	2. Install dmg
6. Try again to reopen in container
	1. fail
	2. ![[Pasted image 20250808094153.png]]

this is strange because devcontainer.json exists. 

![[Pasted image 20250808094255.png]]


oh i should open one folder up. 

hey then i get the popup 

![[Pasted image 20250808094514.png|400]]

it's setting up...
![[Pasted image 20250808094840.png|400]]

it did a bunch of stuff

now what?