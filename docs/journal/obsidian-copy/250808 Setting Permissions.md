---
title: Setting Permissions
created: 2025-08-08 08:56:85
tags: []
modified: 2025-08-08, 08:59:56
---
In general, use `.claude/settings.local.json`: this is project-specific and ignored by git

paths are relative to CC's current folder. So if you want to allow stuff in `pyCode/Debug/`, you can use 

```
{
  "permissions": {
    "allow": [
      "Write(Debug/*.py)",
      "Edit(Debug/*.py)",
	  "Bash(python3 Debug/*.py)",      
```

and then have CC `cd pyCode` and it can write or edit debug stuff form there. 



