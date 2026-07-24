# Windows container assessment

2026-07-23 20:29 EDT

Considered whether the current devcontainer setup was worth supporting on a
Windows machine.

The Linux image itself should behave well under Docker Desktop, but the
host-side setup is not natively Windows-portable. The main problems are:

- `initializeCommand` assumes Bash and Unix `/tmp` paths. Git Bash, Windows
  Python, and Docker can interpret those paths differently.
- WSL2 solves most shell and path problems, but the credential loader then
  identifies the host as Linux and does not read Windows Credential Manager.
  Native Windows retrieval also requires the optional PowerShell
  `CredentialManager` module.
- A Dropbox-backed workspace on NTFS would add bind-mount performance,
  filesystem-watching, and file-hydration friction. Putting the workspace in
  WSL would be faster but would undermine the current Dropbox-based session
  sync arrangement.
- Windows checkouts need explicit LF enforcement for shell scripts and
  Developer Mode/Git configuration to preserve the repository's symlinks.
- The large TeX/R/Python image would impose significant build time, disk use,
  and WSL/Docker memory overhead.
- The in-container firewall would probably work in Linux-container mode, but
  adds another brittle layer around Docker Desktop DNS, VPNs, and host-network
  detection.

Decision: Windows support is probably not worth pursuing. Continue treating
macOS/Linux as the supported host environment rather than adding and
maintaining a separate Windows/WSL startup and credential path.
