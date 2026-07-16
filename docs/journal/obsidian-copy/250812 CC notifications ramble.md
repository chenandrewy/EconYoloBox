---
title: CC notifications
created: 2025-08-12 06:08:23
tags: []
modified: 2025-08-12, 06:36:47
---
why is it so confusing / hard to get this set up?

Officially: https://docs.anthropic.com/en/docs/claude-code/terminal-config

###   
Notification setup

Never miss when Claude completes a task with proper notification configuration:

	#### 
	
	[​
	
	](https://docs.anthropic.com/en/docs/claude-code/terminal-config#terminal-bell-notifications)
	
	Terminal bell notifications
	
	Enable sound alerts when tasks complete:
	
	Copy
	
	```sh
	claude config set --global preferredNotifChannel terminal_bell
	```
	
	**For macOS users**: Don’t forget to enable notification permissions in System Settings → Notifications → [Your Terminal App].
	
	

this seems already to be set up
```
(.venv) ➜  Signals git:(HardPredictorsPt3) ✗ claude config get --global preferredNotifChannel
"terminal_bell"
```

## Finally some progress by using Script Editor

![[Pasted image 20250812063204.png]]

But still the CC notifications dont' show up.



