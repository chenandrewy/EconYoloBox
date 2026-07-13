# Devcontainer Secrets and YOLO Agents

We noticed that a devcontainer rebuild log exposed injected credentials during VS Code's `loginInteractiveShell` environment probe. The immediate mitigation was to add `"userEnvProbe": "none"` to `.devcontainer/devcontainer.json`, which should stop that particular environment dump.

The larger issue is the threat model. This sandbox is meant for running agents in YOLO-style modes, so the main risk is not only accidental logging. If an attacker or agent has arbitrary code execution inside the container as the normal user, then any credential the container can use non-interactively can also be stolen by that attacker. This is true whether the credential is exposed as an environment variable, stored in a `0600` file, mounted under `/run/secrets`, or held by an in-container keychain that the same user can query.

Environment variables are still worse for accidental exposure: they are inherited by subprocesses and can appear in logs, shell probes, process environments, and crash/debug output. A file-based secret system, preferably using a temporary `0600` file under `/run` or `/tmp`, would reduce this accidental leakage and better match common Docker/Kubernetes secret patterns. It would not protect against a compromised container user.

Installing a keychain-like service inside the container would add complexity and a second secret store. Since the host OS keychain is already the source of truth via `.credentials/setup.py`, the more pragmatic eventual design is:

1. Keep long-lived credentials in the host keychain.
2. Materialize needed credentials at container startup into a short-lived, user-readable `0600` secret file.
3. Mount or place that file somewhere like `/run/secrets`.
4. Update `.credentials/get-credentials.py` to read that file on demand.
5. Stop injecting credentials into the global container environment by default.

For the current threat model, the highest-value controls remain scoped, low-value credentials; opt-in credential injection only when needed; short-lived or easily rotated keys where possible; and the existing egress firewall. The file-based system is worth doing eventually to reduce accidental leaks, but it should not be mistaken for isolation from a malicious process already running inside the sandbox.
